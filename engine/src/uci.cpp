#include "engine/uci.h"

#include <algorithm>
#include <chrono>
#include <iostream>
#include <mutex>
#include <sstream>
#include <thread>

#include "engine/board.h"
#include "engine/eval.h"
#include "engine/nnue.h"
#include "engine/search.h"

namespace engine {

namespace {

std::mutex outMutex;

void send(const std::string& s) {
    std::lock_guard<std::mutex> lock(outMutex);
    std::cout << s << '\n' << std::flush;
}

std::string lower(std::string s) {
    std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c) { return char(std::tolower(c)); });
    return s;
}

class UciEngine {
public:
    UciEngine() { searcher_.setHashMb(hashMb_); }
    ~UciEngine() { stopSearch(); }

    void loop(std::istream& in) {
        std::string line;
        while (std::getline(in, line)) {
            if (!line.empty() && line.back() == '\r') line.pop_back();
            if (!handle(line)) return;
        }
        // EOF: let a finite search finish (and print bestmove), stop an infinite one.
        if (searchInfinite_ || searchPonder_) searcher_.stop = true;
        waitSearch();
    }

private:
    Board board_;
    Searcher searcher_;
    std::thread thread_;
    bool searchInfinite_ = false;
    bool searchPonder_ = false;

    int hashMb_ = 16;
    bool limitStrength_ = false;
    int uciElo_ = 1500;
    int skillLevel_ = 20;
    int threads_ = 1;
    int moveOverhead_ = 30;

    void waitSearch() {
        if (thread_.joinable()) thread_.join();
        searchInfinite_ = false;
        searchPonder_ = false;
    }

    void stopSearch() {
        searcher_.stop = true;
        waitSearch();
    }

    bool handle(const std::string& line) {
        std::istringstream is(line);
        std::string cmd;
        if (!(is >> cmd)) return true;

        if (cmd == "uci") {
            send("id name Rank");
            send("id author vedantsinggh");
            send("");
            send("option name Hash type spin default 16 min 1 max 1024");
            send("option name Threads type spin default 1 min 1 max 64");
            send("option name Ponder type check default false");
            send("option name Move Overhead type spin default 30 min 0 max 5000");
            send("option name UCI_LimitStrength type check default false");
            send("option name UCI_Elo type spin default 1500 min 400 max 2400");
            send("option name Skill Level type spin default 20 min 0 max 20");
            send(std::string("option name EvalFile type string default ") +
                 (*nnue::embeddedName() ? nnue::embeddedName() : "<empty>"));
            send(std::string("option name Use NNUE type check default ") +
                 (nnue::defaultEnabled() ? "true" : "false"));
            send("uciok");
        } else if (cmd == "isready") {
            send("readyok");
        } else if (cmd == "ucinewgame") {
            stopSearch();
            searcher_.newGame();
            board_.setFen(Board::START_FEN);
        } else if (cmd == "position") {
            stopSearch();
            position(is);
        } else if (cmd == "go") {
            stopSearch();
            go(is);
        } else if (cmd == "stop") {
            stopSearch();
        } else if (cmd == "ponderhit") {
            if (thread_.joinable() && searchPonder_) {
                searchPonder_ = false;
                searcher_.ponderhit();
            }
        } else if (cmd == "setoption") {
            stopSearch();
            setOption(line);
        } else if (cmd == "quit") {
            stopSearch();
            return false;
        } else if (cmd == "d") {
            send(board_.pretty());
        } else if (cmd == "eval") {
            auto line = [&](const char* what, int s) {
                send(std::string(what) + std::to_string(s) + " cp (side to move), " +
                     std::to_string(board_.side == WHITE ? s : -s) + " cp (white)");
            };
            line("HCE eval:    ", evaluateHce(board_));
            if (nnue::available()) line("NNUE eval:   ", nnue::evaluate(board_));
            line("Static eval: ", evaluate(board_));
            send(std::string("Evaluation: ") + (nnue::enabled() ? "NNUE (" + nnue::currentName() + ")" : "HCE") +
                 ", phase " + std::to_string(gamePhase(board_)) + "/24");
        } else if (cmd == "bench") {
            stopSearch();
            int depth = 13;
            is >> depth;
            bench(std::max(1, depth));
        } else if (cmd == "perft") {
            stopSearch();
            int depth = 1;
            is >> depth;
            perft(std::max(1, depth));
        } else {
            send("info string Unknown command: " + line);
        }
        return true;
    }

    void position(std::istringstream& is) {
        std::string token;
        is >> token;
        Board b;
        if (token == "startpos") {
            b.setFen(Board::START_FEN);
            is >> token;  // "moves" (optional)
        } else if (token == "fen") {
            std::string fen;
            while (is >> token && token != "moves") fen += (fen.empty() ? "" : " ") + token;
            if (!b.setFen(fen)) {
                send("info string Invalid FEN: " + fen);
                return;
            }
        } else {
            return;
        }
        if (token == "moves") {
            while (is >> token) {
                Move m = b.parseUciMove(token);
                if (m == NULL_MOVE) {
                    send("info string Illegal move ignored: " + token);
                    break;
                }
                b.makeMove(m);
            }
        }
        board_ = b;
    }

    void go(std::istringstream& is) {
        SearchLimits limits;
        std::string token;
        auto readInt = [&](int64_t& v) {
            int64_t x;
            if (is >> x) v = x;
        };
        while (is >> token) {
            if (token == "wtime") readInt(limits.time[WHITE]);
            else if (token == "btime") readInt(limits.time[BLACK]);
            else if (token == "winc") readInt(limits.inc[WHITE]);
            else if (token == "binc") readInt(limits.inc[BLACK]);
            else if (token == "movestogo") { int64_t v = 0; readInt(v); limits.movestogo = int(v); }
            else if (token == "depth") { int64_t v = 0; readInt(v); limits.depth = int(v); }
            else if (token == "nodes") { int64_t v = 0; readInt(v); limits.nodes = uint64_t(std::max<int64_t>(0, v)); }
            else if (token == "movetime") readInt(limits.movetime);
            else if (token == "infinite") limits.infinite = true;
            else if (token == "ponder") limits.ponder = true;
        }
        // Clamp negative clock values sent by some GUIs.
        for (auto& t : limits.time)
            if (t < -1) t = 0;

        Strength strength;
        if (limitStrength_) strength.elo = uciElo_;
        else if (skillLevel_ < 20) strength.elo = 400 + skillLevel_ * 100;
        else strength.elo = 2400;

        searcher_.stop = false;
        searchInfinite_ = limits.infinite;
        searchPonder_ = limits.ponder;
        Board b = board_;
        thread_ = std::thread([this, b, limits, strength]() {
            Move best = searcher_.think(b, limits, strength, send);
            std::string msg = "bestmove " + b.moveToUci(best);
            Move pm = searcher_.ponderMove();
            if (best != NULL_MOVE && pm != NULL_MOVE) {
                Board after = b;
                after.makeMove(best);
                msg += " ponder " + after.moveToUci(pm);
            }
            send(msg);
        });
    }

    void setOption(const std::string& line) {
        // setoption name <id> [value <x>]
        std::string l = line;
        size_t namePos = l.find(" name ");
        if (namePos == std::string::npos) return;
        size_t valuePos = l.find(" value ", namePos);
        std::string name = l.substr(namePos + 6, valuePos == std::string::npos ? std::string::npos
                                                                               : valuePos - (namePos + 6));
        std::string value = valuePos == std::string::npos ? "" : l.substr(valuePos + 7);
        while (!name.empty() && name.back() == ' ') name.pop_back();
        while (!value.empty() && value.front() == ' ') value.erase(value.begin());
        while (!value.empty() && value.back() == ' ') value.pop_back();
        name = lower(name);

        auto toInt = [&](int def) {
            try {
                return std::stoi(value);
            } catch (...) {
                return def;
            }
        };
        if (name == "hash") {
            hashMb_ = std::clamp(toInt(hashMb_), 1, 1024);
            searcher_.setHashMb(size_t(hashMb_));
        } else if (name == "threads") {
            threads_ = std::clamp(toInt(threads_), 1, 64);
            searcher_.setThreads(threads_);
        } else if (name == "ponder") {
            // Informational only: the GUI decides when to send `go ponder`.
        } else if (name == "move overhead") {
            moveOverhead_ = std::clamp(toInt(moveOverhead_), 0, 5000);
            searcher_.setMoveOverhead(moveOverhead_);
        } else if (name == "uci_limitstrength") {
            limitStrength_ = lower(value) == "true";
        } else if (name == "uci_elo") {
            uciElo_ = std::clamp(toInt(uciElo_), 400, 2400);
        } else if (name == "skill level") {
            skillLevel_ = std::clamp(toInt(skillLevel_), 0, 20);
        } else if (name == "evalfile") {
            std::string err;
            if (value.empty() || value == "<empty>" || value == nnue::embeddedName()) {
                if (nnue::loadEmbedded()) send("info string NNUE: using embedded network " + nnue::currentName());
                else send("info string NNUE: no embedded network, using HCE");
            } else if (nnue::loadFile(value, err)) {
                send("info string NNUE: loaded " + value);
            } else {
                send("info string NNUE: failed to load " + err +
                     (nnue::available() ? ", keeping " + nnue::currentName() : ", using HCE"));
            }
        } else if (name == "use nnue") {
            nnue::setEnabled(lower(value) == "true");
            if (lower(value) == "true" && !nnue::available())
                send("info string NNUE: no network available, using HCE");
        } else {
            send("info string Unknown option: " + name);
        }
    }

    void bench(int depth) {
        static const char* FENS[] = {
            "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
            "r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4",
            "r2q1rk1/pp2bppp/2n1pn2/3p4/2PP4/2N2N2/PP2BPPP/R2Q1RK1 w - - 0 10",
            "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1",
            "r1bq1rk1/pp3ppp/2nbpn2/3p4/2PP4/2NBPN2/PP3PPP/R1BQ1RK1 b - - 2 9",
            "6k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1",
            "r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10",
            "2r3k1/pp3ppp/2n1b3/3p4/3P4/2PB1N2/P4PPP/2R3K1 w - - 0 20",
            "8/8/4k3/3p4/3P1K2/8/8/8 w - - 0 1",
            "r1b2rk1/2q1bppp/p2p1n2/np2p3/3PP3/5N1P/PPB2PP1/RNBQR1K1 w - - 0 12",
            "3r2k1/5ppp/8/8/1b6/8/2B2PPP/3R2K1 b - - 0 30",
        };
        Searcher s;
        s.setHashMb(16);
        uint64_t nodes = 0;
        auto start = std::chrono::steady_clock::now();
        for (const char* fen : FENS) {
            Board b;
            b.setFen(fen);
            s.newGame();
            SearchLimits limits;
            limits.depth = depth;
            uint64_t last = 0;
            s.stop = false;
            s.think(b, limits, Strength{}, [&](const std::string& line) {
                size_t p = line.find(" nodes ");
                if (p != std::string::npos) last = std::stoull(line.substr(p + 7));
            });
            nodes += last;
        }
        auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - start)
                      .count();
        send("Nodes searched: " + std::to_string(nodes));
        send("Time: " + std::to_string(ms) + " ms");
        send("Nodes/second: " + std::to_string(nodes * 1000 / uint64_t(std::max<int64_t>(1, ms))));
    }

    void perft(int depth) {
        auto start = std::chrono::steady_clock::now();
        MoveList list;
        board_.generateLegal(list);
        uint64_t total = 0;
        for (int i = 0; i < list.size; ++i) {
            board_.makeMove(list.moves[i]);
            uint64_t n = board_.perft(depth - 1);
            board_.unmakeMove();
            total += n;
            send(board_.moveToUci(list.moves[i]) + ": " + std::to_string(n));
        }
        auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - start)
                      .count();
        send("");
        send("Nodes searched: " + std::to_string(total));
        send("Time: " + std::to_string(ms) + " ms");
    }
};

} // namespace

int runUci(std::istream& in) {
    std::ios::sync_with_stdio(false);
    UciEngine eng;
    eng.loop(in);
    return 0;
}

} // namespace engine
