// datagen: multi-threaded fixed-node self-play producing NNUE training data.
//
// Every game starts from a few random legal plies (unbalanced starts are rejected by a
// quick search), then the engine plays itself at a fixed node budget per move. Quiet
// positions (not in check, best move not a capture/promotion, no mate score) are stored
// with the search score (white POV) and, once the game is over, its result. Output is
// appended to the file (see nnue_data.h for the 32-byte record), so runs can be resumed
// or extended by simply running the tool again with the same -out file.
#include <atomic>
#include <chrono>
#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <mutex>
#include <random>
#include <string>
#include <thread>
#include <vector>

#include "engine/board.h"
#include "engine/nnue.h"
#include "engine/search.h"
#include "nnue_data.h"

using namespace engine;

namespace {

std::atomic<bool> gStop{false};
void onSignal(int) { gStop = true; }

struct Config {
    std::string out;
    int threads = 4;
    uint64_t nodes = 5000;
    int randomPlies = 8;
    int maxOpenScore = 300;
    uint64_t maxPositions = 0;  // 0 = unlimited
    double hours = 0;           // 0 = unlimited
    uint64_t seed = 0;
    int hashMb = 8;
    bool useNnue = false;
    std::string net;
    // adjudication
    int winScore = 2000, winPlies = 4;
    int drawScore = 10, drawPlies = 12, drawMinPly = 80;
    int maxPlies = 400;
};

std::atomic<uint64_t> gPositions{0}, gGames{0}, gWhiteWins{0}, gBlackWins{0}, gDraws{0}, gRejected{0};
std::mutex gFileMutex;
FILE* gFile = nullptr;

struct NullOut {
    void operator()(const std::string&) const {}
};

// Plays `n` random legal plies; false if the game ended on the way.
bool randomOpening(Board& b, int n, std::mt19937_64& rng) {
    for (int i = 0; i < n; ++i) {
        MoveList list;
        b.generateLegal(list);
        if (list.size == 0) return false;
        std::uniform_int_distribution<int> pick(0, list.size - 1);
        b.makeMove(list.moves[pick(rng)]);
    }
    MoveList list;
    b.generateLegal(list);
    return list.size > 0;
}

void worker(const Config& cfg, int id) {
    std::mt19937_64 rng(cfg.seed * 0x9E3779B97F4A7C15ULL + uint64_t(id) * 7919 + 1);
    Searcher searcher;
    searcher.setHashMb(size_t(cfg.hashMb));
    searcher.setThreads(1);
    const NullOut out;
    SearchLimits limits;
    limits.nodes = cfg.nodes;
    std::vector<nnuedata::PackedPos> game;
    std::vector<int> whiteScores;

    while (!gStop.load()) {
        Board b;
        b.setFen(Board::START_FEN);
        // Alternate between n and n+1 random plies so both colours start to move.
        int plies = cfg.randomPlies + int(rng() & 1);
        if (!randomOpening(b, plies, rng)) continue;
        searcher.newGame();
        searcher.stop = false;
        Move first = searcher.think(b, limits, Strength{}, out);
        if (first == NULL_MOVE || std::abs(searcher.lastScore()) > cfg.maxOpenScore) {
            ++gRejected;
            continue;
        }

        game.clear();
        whiteScores.clear();
        int result = -1;  // 0 black win, 1 draw, 2 white win
        for (int ply = 0; result < 0; ++ply) {
            MoveList legal;
            b.generateLegal(legal);
            if (legal.size == 0) {
                result = b.inCheck() ? (b.side == WHITE ? 0 : 2) : 1;
                break;
            }
            if (b.halfmove >= 100 || b.repetitionCount() >= 2 || b.isInsufficientMaterial() ||
                ply >= cfg.maxPlies) {
                result = 1;
                break;
            }
            searcher.stop = false;
            Move m = searcher.think(b, limits, Strength{}, out);
            if (m == NULL_MOVE) {  // cannot happen with legal moves, but stay safe
                result = 1;
                break;
            }
            const int score = searcher.lastScore();
            const int ws = b.side == WHITE ? score : -score;
            whiteScores.push_back(ws);

            const bool quiet = !isCapture(m) && !promoOf(m);
            if (quiet && !b.inCheck() && std::abs(score) < MATE_BOUND) game.push_back(nnuedata::pack(b, ws, 0));

            // Adjudication
            const int n = int(whiteScores.size());
            if (n >= cfg.winPlies) {
                bool w = true, l = true;
                for (int i = n - cfg.winPlies; i < n; ++i) {
                    w &= whiteScores[size_t(i)] >= cfg.winScore;
                    l &= whiteScores[size_t(i)] <= -cfg.winScore;
                }
                if (w) result = 2;
                if (l) result = 0;
            }
            if (result < 0 && ply >= cfg.drawMinPly && n >= cfg.drawPlies) {
                bool d = true;
                for (int i = n - cfg.drawPlies; i < n; ++i) d &= std::abs(whiteScores[size_t(i)]) <= cfg.drawScore;
                if (d) result = 1;
            }
            b.makeMove(m);
        }

        for (auto& p : game) p.result = uint8_t(result);
        {
            std::lock_guard<std::mutex> lock(gFileMutex);
            if (!game.empty()) {
                std::fwrite(game.data(), sizeof(nnuedata::PackedPos), game.size(), gFile);
                std::fflush(gFile);
            }
        }
        gPositions += game.size();
        ++gGames;
        (result == 2 ? gWhiteWins : result == 0 ? gBlackWins : gDraws)++;
        if (cfg.maxPositions && gPositions.load() >= cfg.maxPositions) gStop = true;
    }
}

void usage() {
    std::cerr << "usage: datagen -out FILE [-threads N] [-nodes N] [-plies N] [-positions N] [-hours H]\n"
                 "               [-seed S] [-hash MB] [-openscore CP] [-nnue] [-net FILE]\n";
}

} // namespace

int main(int argc, char** argv) {
    initTables();
    Config cfg;
    cfg.seed = uint64_t(std::chrono::steady_clock::now().time_since_epoch().count());
    for (int i = 1; i < argc; ++i) {
        std::string a = argv[i];
        auto next = [&]() -> std::string {
            if (i + 1 >= argc) {
                usage();
                std::exit(2);
            }
            return argv[++i];
        };
        if (a == "-out") cfg.out = next();
        else if (a == "-threads") cfg.threads = std::max(1, std::atoi(next().c_str()));
        else if (a == "-nodes") cfg.nodes = std::strtoull(next().c_str(), nullptr, 10);
        else if (a == "-plies") cfg.randomPlies = std::atoi(next().c_str());
        else if (a == "-positions") cfg.maxPositions = std::strtoull(next().c_str(), nullptr, 10);
        else if (a == "-hours") cfg.hours = std::atof(next().c_str());
        else if (a == "-seed") cfg.seed = std::strtoull(next().c_str(), nullptr, 10);
        else if (a == "-hash") cfg.hashMb = std::max(1, std::atoi(next().c_str()));
        else if (a == "-openscore") cfg.maxOpenScore = std::atoi(next().c_str());
        else if (a == "-nnue") cfg.useNnue = true;
        else if (a == "-net") cfg.net = next();
        else {
            usage();
            return 2;
        }
    }
    if (cfg.out.empty()) {
        usage();
        return 2;
    }
    if (!cfg.net.empty()) {
        std::string err;
        if (!nnue::loadFile(cfg.net, err)) {
            std::cerr << "cannot load net: " << err << "\n";
            return 1;
        }
        cfg.useNnue = true;
    }
    if (cfg.useNnue && !nnue::available()) {
        std::cerr << "no NNUE network available\n";
        return 1;
    }
    nnue::setEnabled(cfg.useNnue);

    gFile = std::fopen(cfg.out.c_str(), "ab");
    if (!gFile) {
        std::perror(cfg.out.c_str());
        return 1;
    }
    std::signal(SIGINT, onSignal);
    std::signal(SIGTERM, onSignal);

    std::cout << "datagen: " << cfg.threads << " threads, " << cfg.nodes << " nodes/move, " << cfg.randomPlies
              << "(+1) random plies, eval " << (cfg.useNnue ? "NNUE" : "HCE") << ", appending to " << cfg.out
              << std::endl;
    std::vector<std::thread> threads;
    for (int i = 0; i < cfg.threads; ++i) threads.emplace_back(worker, std::cref(cfg), i);

    const auto t0 = std::chrono::steady_clock::now();
    auto lastReport = t0;
    while (!gStop.load()) {
        std::this_thread::sleep_for(std::chrono::milliseconds(200));
        auto now = std::chrono::steady_clock::now();
        double secs = std::chrono::duration<double>(now - t0).count();
        if (cfg.hours > 0 && secs >= cfg.hours * 3600) gStop = true;
        if (std::chrono::duration<double>(now - lastReport).count() >= 60 || gStop.load()) {
            lastReport = now;
            uint64_t g = gGames.load();
            std::printf("[%7.0fs] games %llu  positions %llu  (%.0f pos/s)  W/D/L %llu/%llu/%llu  rejected %llu\n",
                        secs, (unsigned long long)g, (unsigned long long)gPositions.load(),
                        gPositions.load() / std::max(1e-9, secs), (unsigned long long)gWhiteWins.load(),
                        (unsigned long long)gDraws.load(), (unsigned long long)gBlackWins.load(),
                        (unsigned long long)gRejected.load());
            std::fflush(stdout);
        }
    }
    std::cout << "stopping: finishing games in progress..." << std::endl;
    for (auto& t : threads) t.join();
    double secs = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
    std::printf("done: %llu games, %llu positions in %.0f s (%.0f pos/s)\n", (unsigned long long)gGames.load(),
                (unsigned long long)gPositions.load(), secs, gPositions.load() / std::max(1e-9, secs));
    std::fclose(gFile);
    return 0;
}
