// match: plays games between two UCI engines and reports W/D/L, Elo and SPRT.
//
// POSIX only (fork/exec + pipes). Uses the engine's Board for move legality
// and game-end rules. See tools/README.md for usage.
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <sys/wait.h>
#include <unistd.h>
#if defined(__linux__)
#include <sys/prctl.h>
#endif

#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cmath>
#include <condition_variable>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iostream>
#include <map>
#include <memory>
#include <mutex>
#include <random>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

#include "engine/board.h"
#include "engine/eval.h"

using namespace engine;
using Clock = std::chrono::steady_clock;

namespace {

// ---------------------------------------------------------------------------
// Child process registry (so SIGINT/SIGTERM can kill every engine).
// ---------------------------------------------------------------------------
constexpr int MAX_CHILDREN = 1024;
std::array<std::atomic<pid_t>, MAX_CHILDREN> gChildren{};
std::atomic<bool> gInterrupted{false};

void registerChild(pid_t pid) {
    for (auto& c : gChildren) {
        pid_t expected = 0;
        if (c.compare_exchange_strong(expected, pid)) return;
    }
}
void unregisterChild(pid_t pid) {
    for (auto& c : gChildren) {
        pid_t expected = pid;
        if (c.compare_exchange_strong(expected, 0)) return;
    }
}

void onSignal(int) {
    for (auto& c : gChildren) {
        pid_t p = c.load();
        if (p > 0) ::kill(p, SIGKILL);
    }
    gInterrupted = true;
    const char msg[] = "\nInterrupted: engines killed.\n";
    ssize_t r = ::write(2, msg, sizeof(msg) - 1);
    (void)r;
    _exit(130);
}

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------
struct EngineConfig {
    std::string name;
    std::string cmd;
    std::string dir;
    std::vector<std::pair<std::string, std::string>> options;
    bool ponder = false;
};

struct TimeControl {
    int64_t baseMs = 0;  // 0 = no clock
    int64_t incMs = 0;
    int64_t movetimeMs = 0;
    uint64_t nodes = 0;
    int depth = 0;
};

struct Config {
    EngineConfig eng[2];
    TimeControl tc;
    int games = 100;  // total games (rounded up to even when using pairs)
    int concurrency = 1;
    int64_t timeMarginMs = 0;
    std::string openings = "builtin";  // builtin | random | file path
    int randomPlies = 8;
    int maxOpeningEval = 120;          // for random openings
    uint64_t seed = 0;
    bool seedSet = false;
    // Adjudication
    int resignMoves = 0, resignScore = 0;  // 0 = off
    int drawMoveNumber = 0, drawMoves = 0, drawScore = 0;
    int maxMoves = 0;  // 0 = off: adjudicate draw after N full moves
    // SPRT
    bool sprt = false;
    double elo0 = 0, elo1 = 5, alpha = 0.05, beta = 0.05;
    bool normalized = false;
    std::string pgnOut;
    int ratingInterval = 10;
    bool recover = false;
    bool verbose = false;
};

// ---------------------------------------------------------------------------
// Built-in balanced opening lines (UCI notation).
// ---------------------------------------------------------------------------
const char* BUILTIN_OPENINGS[] = {
    "e2e4 e7e5 g1f3 b8c6 f1b5 a7a6",
    "e2e4 e7e5 g1f3 b8c6 f1b5 g8f6",
    "e2e4 e7e5 g1f3 b8c6 f1c4 f8c5",
    "e2e4 e7e5 g1f3 b8c6 f1c4 g8f6",
    "e2e4 e7e5 g1f3 b8c6 f1c4 f8e7",
    "e2e4 e7e5 g1f3 b8c6 d2d4 e5d4",
    "e2e4 e7e5 g1f3 g8f6 f3e5 d7d6",
    "e2e4 e7e5 g1f3 d7d6 d2d4 g8f6",
    "e2e4 e7e5 b1c3 g8f6 g2g3 d7d5",
    "e2e4 e7e5 g1f3 b8c6 b1c3 g8f6",
    "e2e4 c7c5 g1f3 d7d6 d2d4 c5d4 f3d4 g8f6",
    "e2e4 c7c5 g1f3 b8c6 d2d4 c5d4 f3d4 g8f6",
    "e2e4 c7c5 g1f3 e7e6 d2d4 c5d4 f3d4 a7a6",
    "e2e4 c7c5 g1f3 g7g6 d2d4 c5d4 f3d4 b8c6",
    "e2e4 c7c5 g1f3 d7d6 f1b5 c8d7",
    "e2e4 c7c5 g1f3 b8c6 f1b5 g7g6",
    "e2e4 c7c5 b1c3 b8c6 g2g3 g7g6",
    "e2e4 c7c5 c2c3 g8f6 e4e5 f6d5",
    "e2e4 e7e6 d2d4 d7d5 b1c3 g8f6",
    "e2e4 e7e6 d2d4 d7d5 b1c3 f8b4",
    "e2e4 e7e6 d2d4 d7d5 b1d2 c7c5",
    "e2e4 e7e6 d2d4 d7d5 e4e5 c7c5",
    "e2e4 c7c6 d2d4 d7d5 b1c3 d5e4 c3e4 c8f5",
    "e2e4 c7c6 d2d4 d7d5 e4e5 c8f5",
    "e2e4 c7c6 d2d4 d7d5 e4d5 c6d5 c2c4 g8f6",
    "e2e4 d7d6 d2d4 g8f6 b1c3 g7g6",
    "e2e4 d7d6 d2d4 g8f6 b1c3 e7e5",
    "e2e4 g7g6 d2d4 f8g7 b1c3 d7d6",
    "e2e4 d7d5 e4d5 d8d5 b1c3 d5a5",
    "e2e4 g8f6 e4e5 f6d5 d2d4 d7d6",
    "d2d4 d7d5 c2c4 e7e6 b1c3 g8f6",
    "d2d4 d7d5 c2c4 e7e6 g1f3 c7c5",
    "d2d4 d7d5 c2c4 c7c6 g1f3 g8f6",
    "d2d4 d7d5 c2c4 d5c4 g1f3 g8f6",
    "d2d4 d7d5 c2c4 c7c6 b1c3 g8f6 e2e3 e7e6",
    "d2d4 d7d5 g1f3 g8f6 c1f4 e7e6",
    "d2d4 d7d5 c1f4 g8f6 e2e3 c7c5",
    "d2d4 g8f6 c2c4 e7e6 b1c3 f8b4",
    "d2d4 g8f6 c2c4 e7e6 g1f3 b7b6",
    "d2d4 g8f6 c2c4 e7e6 g1f3 d7d5 b1c3 f8e7",
    "d2d4 g8f6 c2c4 g7g6 b1c3 f8g7 e2e4 d7d6",
    "d2d4 g8f6 c2c4 g7g6 b1c3 d7d5",
    "d2d4 g8f6 c2c4 c7c5 d4d5 e7e6",
    "d2d4 g8f6 c2c4 e7e6 g2g3 d7d5",
    "d2d4 g8f6 c1g5 e7e6 e2e4 h7h6",
    "d2d4 g8f6 g1f3 e7e6 c1g5 c7c5",
    "d2d4 f7f5 g2g3 g8f6 f1g2 e7e6",
    "d2d4 e7e6 c2c4 f8b4 c1d2 d8e7",
    "d2d4 c7c5 d4d5 e7e5 e2e4 d7d6",
    "c2c4 e7e5 b1c3 g8f6 g1f3 b8c6",
    "c2c4 e7e5 g2g3 g8f6 f1g2 d7d5",
    "c2c4 c7c5 b1c3 b8c6 g2g3 g7g6",
    "c2c4 g8f6 g1f3 e7e6 g2g3 d7d5",
    "c2c4 e7e6 b1c3 d7d5 d2d4 f8e7",
    "g1f3 d7d5 g2g3 g8f6 f1g2 e7e6",
    "g1f3 g8f6 c2c4 g7g6 b1c3 f8g7",
    "g1f3 d7d5 c2c4 e7e6 g2g3 g8f6",
    "g2g3 d7d5 f1g2 e7e5 d2d3 g8f6",
    "b2b3 e7e5 c1b2 b8c6 e2e3 g8f6",
    "e2e4 e7e5 g1f3 b8c6 f1b5 f8c5",
};

struct Opening {
    std::string fen;                 // starting FEN ("" = standard start position)
    std::vector<std::string> moves;  // UCI moves played from fen
};

// ---------------------------------------------------------------------------
// Engine subprocess
// ---------------------------------------------------------------------------
class EngineProcess {
public:
    ~EngineProcess() { stop(); }

    bool running() const { return pid_ > 0; }

    bool start(const EngineConfig& cfg) {
        stop();
        int toChild[2], fromChild[2];
        if (pipe2(toChild, O_CLOEXEC) != 0) return false;
        if (pipe2(fromChild, O_CLOEXEC) != 0) {
            close(toChild[0]);
            close(toChild[1]);
            return false;
        }
        // Everything the child needs is prepared before fork(): only async-signal-safe
        // calls are allowed between fork() and exec() in a multi-threaded process.
        const std::string shellCmd = "exec " + cfg.cmd;
        const char* dir = cfg.dir.empty() ? nullptr : cfg.dir.c_str();
        pid_t pid = fork();
        if (pid < 0) return false;
        if (pid == 0) {
#if defined(__linux__)
            prctl(PR_SET_PDEATHSIG, SIGKILL);
#endif
            dup2(toChild[0], 0);
            dup2(fromChild[1], 1);
            int devnull = open("/dev/null", O_WRONLY);
            if (devnull >= 0) dup2(devnull, 2);
            if (dir && chdir(dir) != 0) _exit(127);
            execl("/bin/sh", "sh", "-c", shellCmd.c_str(), (char*)nullptr);
            _exit(127);
        }
        close(toChild[0]);
        close(fromChild[1]);
        pid_ = pid;
        in_ = toChild[1];
        out_ = fromChild[0];
        buf_.clear();
        registerChild(pid);
        return true;
    }

    bool send(const std::string& s) {
        if (in_ < 0) return false;
        std::string line = s + "\n";
        const char* p = line.data();
        size_t left = line.size();
        while (left) {
            ssize_t n = ::write(in_, p, left);
            if (n < 0) {
                if (errno == EINTR) continue;
                return false;
            }
            p += n;
            left -= size_t(n);
        }
        return true;
    }

    // 1 = got a line, 0 = deadline passed, -1 = EOF / error.
    int readLine(std::string& line, Clock::time_point deadline) {
        for (;;) {
            size_t nl = buf_.find('\n');
            if (nl != std::string::npos) {
                line = buf_.substr(0, nl);
                buf_.erase(0, nl + 1);
                if (!line.empty() && line.back() == '\r') line.pop_back();
                return 1;
            }
            if (out_ < 0) return -1;
            auto now = Clock::now();
            if (now >= deadline) return 0;
            int ms = int(std::min<int64_t>(
                1000, std::chrono::duration_cast<std::chrono::milliseconds>(deadline - now).count() + 1));
            pollfd pfd{out_, POLLIN, 0};
            int r = poll(&pfd, 1, ms);
            if (r < 0) {
                if (errno == EINTR) continue;
                return -1;
            }
            if (r == 0) continue;
            char tmp[4096];
            ssize_t n = ::read(out_, tmp, sizeof(tmp));
            if (n < 0 && errno == EINTR) continue;
            if (n <= 0) return -1;
            buf_.append(tmp, size_t(n));
        }
    }

    // Waits for a line starting with `token`. Returns false on timeout/EOF.
    bool waitFor(const std::string& token, int timeoutMs) {
        auto deadline = Clock::now() + std::chrono::milliseconds(timeoutMs);
        std::string line;
        for (;;) {
            int r = readLine(line, deadline);
            if (r <= 0) return false;
            if (line.compare(0, token.size(), token) == 0) return true;
        }
    }

    void stop() {
        if (pid_ <= 0) return;
        send("quit");
        if (in_ >= 0) close(in_);
        in_ = -1;
        // Give the engine a moment to exit, then kill it.
        int status = 0;
        bool exited = false;
        for (int i = 0; i < 100; ++i) {
            pid_t r = waitpid(pid_, &status, WNOHANG);
            if (r == pid_ || r < 0) {
                exited = true;
                break;
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
        }
        if (!exited) {
            ::kill(pid_, SIGKILL);
            waitpid(pid_, &status, 0);
        }
        unregisterChild(pid_);
        if (out_ >= 0) close(out_);
        out_ = -1;
        pid_ = -1;
    }

    void killNow() {
        if (pid_ <= 0) return;
        ::kill(pid_, SIGKILL);
        int status = 0;
        waitpid(pid_, &status, 0);
        unregisterChild(pid_);
        if (in_ >= 0) close(in_);
        if (out_ >= 0) close(out_);
        in_ = out_ = -1;
        pid_ = -1;
    }

private:
    pid_t pid_ = -1;
    int in_ = -1, out_ = -1;
    std::string buf_;
};

bool initEngine(EngineProcess& p, const EngineConfig& cfg, std::string& err) {
    if (!p.start(cfg)) {
        err = "cannot start " + cfg.cmd;
        return false;
    }
    p.send("uci");
    if (!p.waitFor("uciok", 10000)) {
        err = cfg.name + ": no uciok";
        p.killNow();
        return false;
    }
    for (auto& o : cfg.options) p.send("setoption name " + o.first + " value " + o.second);
    if (cfg.ponder) p.send("setoption name Ponder value true");
    p.send("isready");
    if (!p.waitFor("readyok", 30000)) {
        err = cfg.name + ": no readyok";
        p.killNow();
        return false;
    }
    return true;
}

// ---------------------------------------------------------------------------
// SAN for PGN output
// ---------------------------------------------------------------------------
std::string toSan(Board& b, Move m) {
    if (flagsOf(m) & F_CASTLE) {
        std::string s = fileOf(toSq(m)) == 6 ? "O-O" : "O-O-O";
        b.makeMove(m);
        MoveList l;
        b.generateLegal(l);
        if (b.inCheck()) s += l.size ? "+" : "#";
        b.unmakeMove();
        return s;
    }
    const int from = fromSq(m), to = toSq(m);
    const PieceType pt = typeOf(b.squares[from]);
    std::string s;
    auto sqName = [](int sq) {
        return std::string{char('a' + fileOf(sq)), char('1' + rankOf(sq))};
    };
    if (pt == PAWN) {
        if (isCapture(m)) {
            s += char('a' + fileOf(from));
            s += 'x';
        }
        s += sqName(to);
        if (promoOf(m)) {
            s += '=';
            s += "PNBRQK"[promoOf(m)];
        }
    } else {
        s += "PNBRQK"[pt];
        MoveList l;
        b.generateLegal(l);
        bool ambig = false, sameFile = false, sameRank = false;
        for (int i = 0; i < l.size; ++i) {
            Move o = l.moves[i];
            if (o == m || toSq(o) != to || fromSq(o) == from) continue;
            if (typeOf(b.squares[fromSq(o)]) != pt) continue;
            ambig = true;
            if (fileOf(fromSq(o)) == fileOf(from)) sameFile = true;
            if (rankOf(fromSq(o)) == rankOf(from)) sameRank = true;
        }
        if (ambig) {
            if (!sameFile) s += char('a' + fileOf(from));
            else if (!sameRank) s += char('1' + rankOf(from));
            else s += sqName(from);
        }
        if (isCapture(m)) s += 'x';
        s += sqName(to);
    }
    b.makeMove(m);
    if (b.inCheck()) {
        MoveList l;
        b.generateLegal(l);
        s += l.size ? "+" : "#";
    }
    b.unmakeMove();
    return s;
}

// ---------------------------------------------------------------------------
// Statistics
// ---------------------------------------------------------------------------
struct Stats {
    int w = 0, d = 0, l = 0;     // from engine 1's point of view
    int penta[5] = {0, 0, 0, 0, 0};  // pair score in half points: 0..4
    int timeLosses[2] = {0, 0};
    int crashes[2] = {0, 0};
    int illegal[2] = {0, 0};
    std::map<std::string, int> reasons;
};

double eloFromScore(double s) {
    s = std::clamp(s, 1e-6, 1 - 1e-6);
    return -400.0 * std::log10(1.0 / s - 1.0);
}
double scoreFromElo(double e) { return 1.0 / (1.0 + std::pow(10.0, -e / 400.0)); }

struct Summary {
    double elo = 0, eloLo = 0, eloHi = 0, nelo = 0, neloErr = 0, los = 0.5, llr = 0;
    double lower = 0, upper = 0;
    bool pentaUsed = false;
};

// Pentanomial (game-pair) statistics when pairs exist, trinomial otherwise.
// Returns per-unit mean score, variance and unit count (with zero buckets
// regularised so the variance never collapses).
void unitStats(const Stats& st, bool& penta, double& n, double& mu, double& var) {
    int pairs = 0;
    for (int c : st.penta) pairs += c;
    penta = pairs >= 2;
    std::vector<double> cnt, val;
    if (penta) {
        for (int i = 0; i < 5; ++i) {
            cnt.push_back(st.penta[i] ? st.penta[i] : 1e-3);
            val.push_back(i / 4.0);
        }
    } else {
        cnt = {st.l ? double(st.l) : 1e-3, st.d ? double(st.d) : 1e-3, st.w ? double(st.w) : 1e-3};
        val = {0.0, 0.5, 1.0};
    }
    n = 0;
    for (double c : cnt) n += c;
    mu = 0;
    for (size_t i = 0; i < cnt.size(); ++i) mu += cnt[i] * val[i];
    mu /= n;
    var = 0;
    for (size_t i = 0; i < cnt.size(); ++i) var += cnt[i] * (val[i] - mu) * (val[i] - mu);
    var /= n;
}

Summary summarize(const Stats& st, const Config& cfg) {
    Summary s;
    int games = st.w + st.d + st.l;
    if (games == 0) return s;
    bool penta;
    double n, mu, var;
    unitStats(st, penta, n, mu, var);
    s.pentaUsed = penta;
    // Score per game from all games (includes unpaired games).
    double score = (st.w + 0.5 * st.d) / games;
    double se = std::sqrt(var / n);
    s.elo = eloFromScore(score);
    s.eloLo = eloFromScore(score - 1.959964 * se);
    s.eloHi = eloFromScore(score + 1.959964 * se);
    s.los = 0.5 * (1.0 + std::erf((mu - 0.5) / (se * std::sqrt(2.0))));
    // Normalised Elo: per-game standard deviation.
    double sigmaPg = penta ? std::sqrt(2.0 * var) : std::sqrt(var);
    const double NT = 800.0 / std::log(10.0);
    if (sigmaPg > 0) {
        s.nelo = (mu - 0.5) / sigmaPg * NT;
        s.neloErr = 1.959964 * se / sigmaPg * NT;
    }
    if (cfg.sprt) {
        double mu0, mu1;
        if (cfg.normalized) {
            mu0 = 0.5 + cfg.elo0 / NT * sigmaPg;
            mu1 = 0.5 + cfg.elo1 / NT * sigmaPg;
        } else {
            mu0 = scoreFromElo(cfg.elo0);
            mu1 = scoreFromElo(cfg.elo1);
        }
        s.llr = var > 0 ? n * (mu1 - mu0) * (2 * mu - mu0 - mu1) / (2 * var) : 0;
        s.lower = std::log(cfg.beta / (1 - cfg.alpha));
        s.upper = std::log((1 - cfg.beta) / cfg.alpha);
    }
    return s;
}

std::string fmt(double v, int prec = 2) {
    char b[64];
    std::snprintf(b, sizeof(b), "%.*f", prec, v);
    return b;
}

std::string report(const Stats& st, const Config& cfg) {
    Summary s = summarize(st, cfg);
    int games = st.w + st.d + st.l;
    std::ostringstream os;
    double score = games ? (st.w + 0.5 * st.d) / games : 0;
    os << "Score of " << cfg.eng[0].name << " vs " << cfg.eng[1].name << ": " << st.w << " - " << st.l
       << " - " << st.d << "  [" << fmt(score, 3) << "] " << games << "\n";
    os << "Elo: " << fmt(s.elo) << " +/- " << fmt((s.eloHi - s.eloLo) / 2) << " (95%: " << fmt(s.eloLo)
       << " .. " << fmt(s.eloHi) << "), nElo: " << fmt(s.nelo) << " +/- " << fmt(s.neloErr)
       << ", LOS: " << fmt(100 * s.los) << "%";
    if (s.pentaUsed)
        os << "\nPenta [0-2]: [" << st.penta[0] << ", " << st.penta[1] << ", " << st.penta[2] << ", "
           << st.penta[3] << ", " << st.penta[4] << "]";
    if (cfg.sprt)
        os << "\nSPRT (" << (cfg.normalized ? "normalized" : "logistic") << ", elo0=" << fmt(cfg.elo0)
           << " elo1=" << fmt(cfg.elo1) << "): LLR " << fmt(s.llr) << " (" << fmt(s.lower) << ", "
           << fmt(s.upper) << ")";
    return os.str();
}

// ---------------------------------------------------------------------------
// Game playing
// ---------------------------------------------------------------------------
enum class Outcome { WHITE_WINS, BLACK_WINS, DRAW, NONE };

struct GameRecord {
    Outcome outcome = Outcome::NONE;
    std::string reason;
    std::vector<std::string> san;
    std::string startFen;
    int whiteEngine = 0;
    int timeLoser = -1, crashLoser = -1, illegalLoser = -1;  // engine index
    bool fatal = false;  // could not (re)start an engine
};

struct Worker {
    EngineProcess proc[2];
    bool ready[2] = {false, false};
};

int parseScore(const std::string& line, bool& has) {
    std::istringstream is(line);
    std::string tok;
    has = false;
    int score = 0;
    while (is >> tok) {
        if (tok == "score") {
            std::string kind;
            int v = 0;
            if (is >> kind >> v) {
                has = true;
                if (kind == "cp") score = v;
                else if (kind == "mate") score = v > 0 ? 30000 - v : -30000 - v;
            }
        }
    }
    return score;
}

GameRecord playGame(Worker& wk, const Config& cfg, const Opening& op, int whiteEngine) {
    GameRecord rec;
    rec.whiteEngine = whiteEngine;
    for (int i = 0; i < 2; ++i) {
        if (!wk.proc[i].running()) wk.ready[i] = false;
        if (!wk.ready[i]) {
            std::string err;
            if (!initEngine(wk.proc[i], cfg.eng[i], err)) {
                std::cerr << "Error: " << err << "\n";
                rec.fatal = true;
                return rec;
            }
            wk.ready[i] = true;
        }
        wk.proc[i].send("ucinewgame");
        wk.proc[i].send("isready");
        if (!wk.proc[i].waitFor("readyok", 30000)) {
            wk.proc[i].killNow();
            wk.ready[i] = false;
            std::string err;
            if (!initEngine(wk.proc[i], cfg.eng[i], err)) {
                std::cerr << "Error: " << err << "\n";
                rec.fatal = true;
                return rec;
            }
            wk.ready[i] = true;
        }
    }

    Board b;
    if (!op.fen.empty()) b.setFen(op.fen);
    rec.startFen = b.fen();
    std::string posBase = op.fen.empty() ? "position startpos" : "position fen " + op.fen;
    std::vector<std::string> moves;
    for (const auto& ms : op.moves) {
        Move m = b.parseUciMove(ms);
        if (m == NULL_MOVE) break;
        rec.san.push_back(toSan(b, m));
        b.makeMove(m);
        moves.push_back(ms);
    }

    int64_t clock[2] = {cfg.tc.baseMs, cfg.tc.baseMs};  // indexed by colour
    int lastScore[2] = {0, 0};                           // indexed by colour, from mover's view
    bool haveScore[2] = {false, false};
    int resignCount[2] = {0, 0};
    int drawCount = 0;
    std::string ponderMove[2];  // per engine index: move it is pondering on

    auto finish = [&](Outcome o, const std::string& why) {
        rec.outcome = o;
        rec.reason = why;
    };
    auto lossFor = [&](Color c) { return c == WHITE ? Outcome::BLACK_WINS : Outcome::WHITE_WINS; };

    for (;;) {
        // Game-end rules.
        MoveList legal;
        b.generateLegal(legal);
        if (legal.size == 0) {
            if (b.inCheck()) finish(lossFor(b.side), "checkmate");
            else finish(Outcome::DRAW, "stalemate");
            break;
        }
        if (b.halfmove >= 100) {
            finish(Outcome::DRAW, "fifty-move rule");
            break;
        }
        if (b.repetitionCount() >= 2) {
            finish(Outcome::DRAW, "3-fold repetition");
            break;
        }
        if (b.isInsufficientMaterial()) {
            finish(Outcome::DRAW, "insufficient material");
            break;
        }
        if (cfg.maxMoves > 0 && b.fullmove > cfg.maxMoves) {
            finish(Outcome::DRAW, "max moves adjudication");
            break;
        }

        const Color us = b.side;
        const int ei = us == WHITE ? whiteEngine : 1 - whiteEngine;
        EngineProcess& p = wk.proc[ei];

        std::string pos = posBase;
        if (!moves.empty()) {
            pos += " moves";
            for (auto& m : moves) pos += " " + m;
        }

        std::string goCmd = "go";
        if (cfg.tc.baseMs > 0) {
            goCmd += " wtime " + std::to_string(std::max<int64_t>(clock[WHITE], 1)) + " btime " +
                     std::to_string(std::max<int64_t>(clock[BLACK], 1));
            goCmd += " winc " + std::to_string(cfg.tc.incMs) + " binc " + std::to_string(cfg.tc.incMs);
        }
        if (cfg.tc.movetimeMs > 0) goCmd += " movetime " + std::to_string(cfg.tc.movetimeMs);
        if (cfg.tc.nodes > 0) goCmd += " nodes " + std::to_string(cfg.tc.nodes);
        if (cfg.tc.depth > 0) goCmd += " depth " + std::to_string(cfg.tc.depth);

        Clock::time_point start;
        bool ponderHit = false;
        const std::string lastMove = moves.empty() ? "" : moves.back();
        if (!ponderMove[ei].empty()) {
            if (ponderMove[ei] == lastMove) {
                start = Clock::now();
                p.send("ponderhit");
                ponderHit = true;
            } else {
                p.send("stop");
                // Discard the ponder search's bestmove.
                if (!p.waitFor("bestmove", 10000)) {
                    rec.crashLoser = ei;
                    finish(lossFor(us), cfg.eng[ei].name + " unresponsive after stop");
                    p.killNow();
                    wk.ready[ei] = false;
                    break;
                }
            }
            ponderMove[ei].clear();
        }
        if (!ponderHit) {
            p.send(pos);
            start = Clock::now();
            p.send(goCmd);
        }

        Clock::time_point deadline;
        if (cfg.tc.baseMs > 0) deadline = start + std::chrono::milliseconds(clock[us] + cfg.timeMarginMs);
        else if (cfg.tc.movetimeMs > 0)
            deadline = start + std::chrono::milliseconds(cfg.tc.movetimeMs + std::max<int64_t>(cfg.timeMarginMs, 100));
        else deadline = start + std::chrono::seconds(600);

        std::string line, best, ponder;
        std::vector<std::string> transcript;  // engine output for this move (for error reports)
        bool gotScore = false;
        int score = 0;
        int r;
        for (;;) {
            r = p.readLine(line, deadline);
            if (r <= 0) break;
            if (cfg.verbose) std::cerr << cfg.eng[ei].name << " > " << line << "\n";
            if (transcript.size() < 200) transcript.push_back(line);
            if (line.compare(0, 5, "info ") == 0) {
                bool has;
                int s = parseScore(line, has);
                if (has) {
                    score = s;
                    gotScore = true;
                }
            } else if (line.compare(0, 9, "bestmove ") == 0) {
                std::istringstream is(line.substr(9));
                is >> best;
                std::string t;
                if (is >> t && t == "ponder") is >> ponder;
                break;
            }
        }
        auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(Clock::now() - start).count();
        if (r == 0) {
            rec.timeLoser = ei;
            finish(lossFor(us), cfg.eng[ei].name + " loses on time (no bestmove)");
            p.killNow();
            wk.ready[ei] = false;
            break;
        }
        if (r < 0) {
            rec.crashLoser = ei;
            finish(lossFor(us), cfg.eng[ei].name + " disconnects");
            p.killNow();
            wk.ready[ei] = false;
            break;
        }
        if (cfg.tc.baseMs > 0) {
            clock[us] -= elapsed;
            if (clock[us] + cfg.timeMarginMs < 0) {
                rec.timeLoser = ei;
                finish(lossFor(us), cfg.eng[ei].name + " loses on time");
                break;
            }
            clock[us] += cfg.tc.incMs;
        }
        Move m = b.parseUciMove(best);
        if (m == NULL_MOVE) {
            rec.illegalLoser = ei;
            {
                std::ostringstream os;
                os << "Illegal move by " << cfg.eng[ei].name << ": " << best << "\n  fen: " << b.fen()
                   << "\n  sent: " << (ponderHit ? "(ponderhit) " : "") << pos << "\n  " << goCmd << "\n";
                for (auto& t : transcript) os << "  < " << t << "\n";
                std::cerr << os.str();
            }
            finish(lossFor(us), cfg.eng[ei].name + " makes an illegal move: " + best);
            break;
        }
        rec.san.push_back(toSan(b, m));
        b.makeMove(m);
        moves.push_back(best);

        // Start pondering on the predicted reply.
        if (cfg.eng[ei].ponder && !ponder.empty() && b.parseUciMove(ponder) != NULL_MOVE) {
            Board tmp = b;
            Move pm = tmp.parseUciMove(ponder);
            tmp.makeMove(pm);
            MoveList l2;
            tmp.generateLegal(l2);
            if (l2.size > 0) {
                std::string ppos = posBase + " moves";
                for (auto& mv : moves) ppos += " " + mv;
                ppos += " " + ponder;
                int64_t wt = clock[WHITE], bt = clock[BLACK];
                std::string pgo = "go ponder";
                if (cfg.tc.baseMs > 0)
                    pgo += " wtime " + std::to_string(std::max<int64_t>(wt, 1)) + " btime " +
                           std::to_string(std::max<int64_t>(bt, 1)) + " winc " + std::to_string(cfg.tc.incMs) +
                           " binc " + std::to_string(cfg.tc.incMs);
                if (cfg.tc.movetimeMs > 0) pgo += " movetime " + std::to_string(cfg.tc.movetimeMs);
                if (cfg.tc.nodes > 0) pgo += " nodes " + std::to_string(cfg.tc.nodes);
                if (cfg.tc.depth > 0) pgo += " depth " + std::to_string(cfg.tc.depth);
                p.send(ppos);
                p.send(pgo);
                ponderMove[ei] = ponder;
            }
        }

        // Score-based adjudication.
        if (gotScore) {
            lastScore[us] = score;
            haveScore[us] = true;
        } else {
            haveScore[us] = false;
        }
        if (cfg.resignMoves > 0 && haveScore[us]) {
            if (lastScore[us] <= -cfg.resignScore && haveScore[~us] && lastScore[~us] >= cfg.resignScore)
                ++resignCount[us];
            else
                resignCount[us] = 0;
            if (resignCount[us] >= cfg.resignMoves) {
                finish(lossFor(us), "resign adjudication");
                break;
            }
        }
        if (cfg.drawMoves > 0) {
            if (b.fullmove >= cfg.drawMoveNumber && haveScore[us] && std::abs(lastScore[us]) <= cfg.drawScore)
                ++drawCount;
            else
                drawCount = 0;
            if (drawCount >= 2 * cfg.drawMoves) {
                finish(Outcome::DRAW, "draw adjudication");
                break;
            }
        }
    }
    // Make sure no engine is left pondering.
    for (int i = 0; i < 2; ++i) {
        if (!ponderMove[i].empty() && wk.proc[i].running()) {
            wk.proc[i].send("stop");
            if (!wk.proc[i].waitFor("bestmove", 10000)) {
                wk.proc[i].killNow();
                wk.ready[i] = false;
            }
        }
    }
    return rec;
}

std::string pgnFor(const GameRecord& rec, const Config& cfg, int round) {
    std::ostringstream os;
    const char* res = rec.outcome == Outcome::WHITE_WINS   ? "1-0"
                      : rec.outcome == Outcome::BLACK_WINS ? "0-1"
                                                           : "1/2-1/2";
    os << "[Event \"match\"]\n[Site \"local\"]\n[Round \"" << round << "\"]\n";
    os << "[White \"" << cfg.eng[rec.whiteEngine].name << "\"]\n";
    os << "[Black \"" << cfg.eng[1 - rec.whiteEngine].name << "\"]\n";
    os << "[Result \"" << res << "\"]\n";
    os << "[FEN \"" << rec.startFen << "\"]\n[SetUp \"1\"]\n";
    os << "[Termination \"" << rec.reason << "\"]\n\n";
    Board b;
    b.setFen(rec.startFen);
    int moveNo = b.fullmove;
    bool white = b.side == WHITE;
    std::string body;
    for (size_t i = 0; i < rec.san.size(); ++i) {
        if (white) body += std::to_string(moveNo) + ". ";
        else if (i == 0) body += std::to_string(moveNo) + "... ";
        body += rec.san[i] + " ";
        if (!white) ++moveNo;
        white = !white;
    }
    body += res;
    // Wrap at ~80 columns.
    std::string line;
    std::istringstream is(body);
    std::string tok;
    while (is >> tok) {
        if (line.size() + tok.size() + 1 > 80) {
            os << line << "\n";
            line.clear();
        }
        if (!line.empty()) line += ' ';
        line += tok;
    }
    os << line << "\n\n";
    return os.str();
}

// ---------------------------------------------------------------------------
// Openings
// ---------------------------------------------------------------------------
std::vector<std::string> splitWs(const std::string& s) {
    std::istringstream is(s);
    std::vector<std::string> v;
    std::string t;
    while (is >> t) v.push_back(t);
    return v;
}

bool validateOpening(const Opening& op) {
    Board b;
    if (!op.fen.empty() && !b.setFen(op.fen)) return false;
    for (auto& m : op.moves) {
        Move mv = b.parseUciMove(m);
        if (mv == NULL_MOVE) return false;
        b.makeMove(mv);
    }
    MoveList l;
    b.generateLegal(l);
    return l.size > 0;
}

std::vector<Opening> loadOpenings(const Config& cfg, std::mt19937_64& rng, int needed) {
    std::vector<Opening> ops;
    if (cfg.openings == "builtin") {
        for (const char* s : BUILTIN_OPENINGS) {
            Opening op{"", splitWs(s)};
            if (!validateOpening(op)) {
                std::cerr << "Warning: invalid builtin opening skipped: " << s << "\n";
                continue;
            }
            ops.push_back(op);
        }
        std::shuffle(ops.begin(), ops.end(), rng);
    } else if (cfg.openings == "random") {
        while (int(ops.size()) < needed) {
            Board b;
            Opening op;
            bool ok = true;
            for (int ply = 0; ply < cfg.randomPlies; ++ply) {
                MoveList l;
                b.generateLegal(l);
                if (l.size == 0) {
                    ok = false;
                    break;
                }
                std::uniform_int_distribution<int> d(0, l.size - 1);
                Move m = l.moves[d(rng)];
                op.moves.push_back(b.moveToUci(m));
                b.makeMove(m);
            }
            if (!ok) continue;
            MoveList l;
            b.generateLegal(l);
            if (l.size == 0 || b.inCheck()) continue;
            if (std::abs(evaluate(b)) > cfg.maxOpeningEval) continue;
            ops.push_back(op);
        }
    } else {
        std::ifstream f(cfg.openings);
        if (!f) {
            std::cerr << "Error: cannot open openings file " << cfg.openings << "\n";
            std::exit(2);
        }
        // Each line: a FEN/EPD (fields separated by spaces, contains '/') optionally
        // followed by "moves ...", or a list of UCI moves from the start position.
        std::string line;
        while (std::getline(f, line)) {
            if (!line.empty() && line.back() == '\r') line.pop_back();
            if (line.empty() || line[0] == '#') continue;
            Opening op;
            auto toks = splitWs(line);
            if (!toks.empty() && toks[0].find('/') != std::string::npos) {
                size_t i = 0;
                std::string fen;
                for (; i < toks.size() && i < 6 && toks[i] != "moves" && toks[i].find(';') == std::string::npos;
                     ++i)
                    fen += (fen.empty() ? "" : " ") + toks[i];
                op.fen = fen;
                if (i < toks.size() && toks[i] == "moves")
                    for (++i; i < toks.size(); ++i) op.moves.push_back(toks[i]);
            } else {
                op.moves = toks;
            }
            if (validateOpening(op)) ops.push_back(op);
            else std::cerr << "Warning: invalid opening skipped: " << line << "\n";
        }
        std::shuffle(ops.begin(), ops.end(), rng);
    }
    if (ops.empty()) {
        std::cerr << "Error: no valid openings\n";
        std::exit(2);
    }
    return ops;
}

// ---------------------------------------------------------------------------
// Command line
// ---------------------------------------------------------------------------
void usage() {
    std::cerr <<
        R"(Usage: match -engine cmd=PATH [name=N] [dir=D] [option.NAME=VALUE ...] [ponder]
             -engine cmd=PATH ...
             [-each option.NAME=VALUE ... | ponder]
             [-tc BASE+INC] [-movetime MS] [-nodes N] [-depth D]
             [-games N] [-concurrency N] [-openings builtin|random|FILE] [-plies N]
             [-sprt elo0=0 elo1=5 alpha=0.05 beta=0.05 [model=logistic|normalized]]
             [-resign movecount=3 score=600] [-draw movenumber=40 movecount=8 score=10]
             [-maxmoves N] [-timemargin MS] [-pgnout FILE] [-seed N] [-ratinginterval N] [-verbose]
)";
}

bool parseTc(const std::string& s, TimeControl& tc) {
    size_t plus = s.find('+');
    try {
        double base = std::stod(s.substr(0, plus));
        double inc = plus == std::string::npos ? 0.0 : std::stod(s.substr(plus + 1));
        tc.baseMs = int64_t(base * 1000 + 0.5);
        tc.incMs = int64_t(inc * 1000 + 0.5);
    } catch (...) {
        return false;
    }
    return tc.baseMs > 0;
}

void applyEngineArg(EngineConfig& e, const std::string& a) {
    size_t eq = a.find('=');
    std::string k = a.substr(0, eq), v = eq == std::string::npos ? "" : a.substr(eq + 1);
    if (k == "cmd") e.cmd = v;
    else if (k == "name") e.name = v;
    else if (k == "dir") e.dir = v;
    else if (k == "ponder") e.ponder = true;
    else if (k.compare(0, 7, "option.") == 0) e.options.emplace_back(k.substr(7), v);
    else {
        std::cerr << "Unknown engine argument: " << a << "\n";
        std::exit(2);
    }
}

Config parseArgs(int argc, char** argv) {
    Config cfg;
    int nEngines = 0;
    std::vector<std::string> each;
    auto kv = [](const std::string& a, std::string& k, std::string& v) {
        size_t eq = a.find('=');
        k = a.substr(0, eq);
        v = eq == std::string::npos ? "" : a.substr(eq + 1);
    };
    for (int i = 1; i < argc; ++i) {
        std::string a = argv[i];
        auto next = [&]() -> std::string {
            if (i + 1 >= argc) {
                usage();
                std::exit(2);
            }
            return argv[++i];
        };
        auto isVal = [&]() { return i + 1 < argc && argv[i + 1][0] != '-'; };
        if (a == "-engine") {
            if (nEngines >= 2) {
                std::cerr << "Only two engines are supported\n";
                std::exit(2);
            }
            EngineConfig& e = cfg.eng[nEngines++];
            while (isVal()) applyEngineArg(e, argv[++i]);
        } else if (a == "-each") {
            while (isVal()) each.push_back(argv[++i]);
        } else if (a == "-tc") {
            if (!parseTc(next(), cfg.tc)) {
                std::cerr << "Bad -tc\n";
                std::exit(2);
            }
        } else if (a == "-movetime") cfg.tc.movetimeMs = std::stoll(next());
        else if (a == "-nodes") cfg.tc.nodes = std::stoull(next());
        else if (a == "-depth") cfg.tc.depth = std::stoi(next());
        else if (a == "-games") cfg.games = std::stoi(next());
        else if (a == "-concurrency") cfg.concurrency = std::max(1, std::stoi(next()));
        else if (a == "-openings") cfg.openings = next();
        else if (a == "-plies") cfg.randomPlies = std::stoi(next());
        else if (a == "-timemargin") cfg.timeMarginMs = std::stoll(next());
        else if (a == "-pgnout") cfg.pgnOut = next();
        else if (a == "-maxmoves") cfg.maxMoves = std::stoi(next());
        else if (a == "-ratinginterval") cfg.ratingInterval = std::max(1, std::stoi(next()));
        else if (a == "-verbose") cfg.verbose = true;
        else if (a == "-seed") {
            cfg.seed = std::stoull(next());
            cfg.seedSet = true;
        } else if (a == "-sprt") {
            cfg.sprt = true;
            while (isVal()) {
                std::string k, v;
                kv(argv[++i], k, v);
                if (k == "elo0") cfg.elo0 = std::stod(v);
                else if (k == "elo1") cfg.elo1 = std::stod(v);
                else if (k == "alpha") cfg.alpha = std::stod(v);
                else if (k == "beta") cfg.beta = std::stod(v);
                else if (k == "model") cfg.normalized = v == "normalized";
            }
        } else if (a == "-resign") {
            cfg.resignMoves = 3;
            cfg.resignScore = 600;
            while (isVal()) {
                std::string k, v;
                kv(argv[++i], k, v);
                if (k == "movecount") cfg.resignMoves = std::stoi(v);
                else if (k == "score") cfg.resignScore = std::stoi(v);
            }
        } else if (a == "-draw") {
            cfg.drawMoveNumber = 40;
            cfg.drawMoves = 8;
            cfg.drawScore = 10;
            while (isVal()) {
                std::string k, v;
                kv(argv[++i], k, v);
                if (k == "movenumber") cfg.drawMoveNumber = std::stoi(v);
                else if (k == "movecount") cfg.drawMoves = std::stoi(v);
                else if (k == "score") cfg.drawScore = std::stoi(v);
            }
        } else if (a == "-h" || a == "-help" || a == "--help") {
            usage();
            std::exit(0);
        } else {
            std::cerr << "Unknown argument: " << a << "\n";
            usage();
            std::exit(2);
        }
    }
    if (nEngines != 2) {
        usage();
        std::exit(2);
    }
    for (int k = 0; k < 2; ++k) {
        for (auto& a : each) {
            // -each options apply unless the engine set the same option itself.
            EngineConfig tmp;
            applyEngineArg(tmp, a);
            if (tmp.ponder) cfg.eng[k].ponder = true;
            for (auto& o : tmp.options) {
                bool has = false;
                for (auto& eo : cfg.eng[k].options) has |= eo.first == o.first;
                if (!has) cfg.eng[k].options.push_back(o);
            }
        }
        if (cfg.eng[k].cmd.empty()) {
            std::cerr << "Engine " << k + 1 << " has no cmd=\n";
            std::exit(2);
        }
        if (cfg.eng[k].name.empty()) {
            std::string c = cfg.eng[k].cmd;
            size_t sl = c.find_last_of('/');
            cfg.eng[k].name = sl == std::string::npos ? c : c.substr(sl + 1);
        }
    }
    if (cfg.eng[0].name == cfg.eng[1].name) {
        cfg.eng[0].name += "-1";
        cfg.eng[1].name += "-2";
    }
    if (!cfg.tc.baseMs && !cfg.tc.movetimeMs && !cfg.tc.nodes && !cfg.tc.depth) {
        std::cerr << "No time control given (-tc, -movetime, -nodes or -depth)\n";
        std::exit(2);
    }
    if (cfg.games < 1) cfg.games = 1;
    if (cfg.games % 2) ++cfg.games;  // every opening is played with both colours
    return cfg;
}

} // namespace

int main(int argc, char** argv) {
    initTables();
    Config cfg = parseArgs(argc, argv);

    struct sigaction sa {};
    sa.sa_handler = onSignal;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGINT, &sa, nullptr);
    sigaction(SIGTERM, &sa, nullptr);
    signal(SIGPIPE, SIG_IGN);

    if (!cfg.seedSet) cfg.seed = std::random_device{}();
    std::mt19937_64 rng(cfg.seed);
    std::vector<Opening> openings = loadOpenings(cfg, rng, cfg.games / 2);

    std::ofstream pgn;
    if (!cfg.pgnOut.empty()) pgn.open(cfg.pgnOut, std::ios::app);

    std::cout << "Match: " << cfg.eng[0].name << " vs " << cfg.eng[1].name << ", " << cfg.games
              << " games, concurrency " << cfg.concurrency << ", openings " << cfg.openings << " ("
              << openings.size() << "), seed " << cfg.seed << "\n"
              << std::flush;

    std::mutex mtx;
    Stats st;
    std::map<int, std::pair<int, int>> pairs;  // pair -> (games done, half-points of engine 1)
    std::atomic<int> nextGame{0};
    std::atomic<bool> stopScheduling{false};
    bool fatal = false;
    int finished = 0;
    std::string sprtVerdict;

    auto worker = [&]() {
        Worker wk;
        for (;;) {
            if (stopScheduling) break;
            int g = nextGame.fetch_add(1);
            if (g >= cfg.games) break;
            const Opening& op = openings[size_t(g / 2) % openings.size()];
            int whiteEngine = g % 2;  // even games: engine 1 white
            GameRecord rec = playGame(wk, cfg, op, whiteEngine);
            std::lock_guard<std::mutex> lock(mtx);
            if (rec.fatal) {
                fatal = true;
                stopScheduling = true;
                break;
            }
            int e1Points;  // half points for engine 1
            if (rec.outcome == Outcome::DRAW) {
                ++st.d;
                e1Points = 1;
            } else {
                bool whiteWon = rec.outcome == Outcome::WHITE_WINS;
                bool e1Won = whiteWon == (whiteEngine == 0);
                if (e1Won) ++st.w;
                else ++st.l;
                e1Points = e1Won ? 2 : 0;
            }
            if (rec.timeLoser >= 0) ++st.timeLosses[rec.timeLoser];
            if (rec.crashLoser >= 0) ++st.crashes[rec.crashLoser];
            if (rec.illegalLoser >= 0) ++st.illegal[rec.illegalLoser];
            ++st.reasons[rec.reason];
            auto& pr = pairs[g / 2];
            pr.first++;
            pr.second += e1Points;
            if (pr.first == 2) st.penta[pr.second]++;
            ++finished;
            if (pgn.is_open()) pgn << pgnFor(rec, cfg, g + 1) << std::flush;
            const char* res = rec.outcome == Outcome::WHITE_WINS   ? "1-0"
                              : rec.outcome == Outcome::BLACK_WINS ? "0-1"
                                                                   : "1/2-1/2";
            std::cout << "Finished game " << g + 1 << " (" << cfg.eng[whiteEngine].name << " vs "
                      << cfg.eng[1 - whiteEngine].name << "): " << res << " {" << rec.reason << "}\n";
            if (finished % cfg.ratingInterval == 0) std::cout << report(st, cfg) << "\n";
            std::cout << std::flush;
            int pairsDone = 0;
            for (int c : st.penta) pairsDone += c;
            // Variance estimates from a handful of pairs are meaningless: require a minimum sample.
            if (cfg.sprt && sprtVerdict.empty() && pairsDone >= 20) {
                Summary s = summarize(st, cfg);
                if (s.llr >= s.upper) sprtVerdict = "H1 accepted";
                else if (s.llr <= s.lower) sprtVerdict = "H0 accepted";
                if (!sprtVerdict.empty()) {
                    std::cout << "SPRT: " << sprtVerdict << " (LLR " << fmt(s.llr) << ")\n" << std::flush;
                    stopScheduling = true;
                }
            }
        }
    };

    std::vector<std::thread> threads;
    for (int i = 0; i < cfg.concurrency; ++i) threads.emplace_back(worker);
    for (auto& t : threads) t.join();

    std::cout << "\n=== Final ===\n" << report(st, cfg) << "\n";
    if (cfg.sprt) std::cout << "SPRT verdict: " << (sprtVerdict.empty() ? "inconclusive" : sprtVerdict) << "\n";
    std::cout << "Time losses: " << cfg.eng[0].name << " " << st.timeLosses[0] << ", " << cfg.eng[1].name << " "
              << st.timeLosses[1] << "; crashes: " << st.crashes[0] << "/" << st.crashes[1]
              << "; illegal moves: " << st.illegal[0] << "/" << st.illegal[1] << "\n";
    std::cout << "Terminations:";
    for (auto& r : st.reasons) std::cout << "\n  " << r.second << " x " << r.first;
    std::cout << "\n";
    return fatal ? 1 : 0;
}
