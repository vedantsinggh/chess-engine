#pragma once

#include <atomic>
#include <chrono>
#include <cstdint>
#include <functional>
#include <memory>
#include <random>
#include <string>
#include <vector>

#include "engine/board.h"
#include "engine/eval.h"
#include "engine/nnue.h"

namespace engine {

struct SearchLimits {
    int depth = 0;           // 0 = no depth limit
    int64_t movetime = 0;    // ms, 0 = unset
    int64_t time[2] = {-1, -1};
    int64_t inc[2] = {0, 0};
    int movestogo = 0;
    uint64_t nodes = 0;      // 0 = unlimited
    bool infinite = false;
    bool ponder = false;     // `go ponder`: search until ponderhit/stop
};

struct Strength {
    // Elo in [400, 2400]; >= 2400 means full strength.
    int elo = 2400;
};

// Shared, lock-free transposition table. Each entry is two 64-bit atomics:
// the packed data word and (key ^ data). A torn read from a concurrent write
// fails the key check and is treated as a miss.
struct TTData {
    Move move = NULL_MOVE;
    int score = 0;
    int depth = 0;
    uint8_t flag = 0;
};

class TranspositionTable {
public:
    enum Flag : uint8_t { NONE = 0, EXACT = 1, LOWER = 2, UPPER = 3 };
    static constexpr int BUCKET = 4;

    void resize(size_t mb);
    void clear();
    void newSearch() { age_ = (age_ + 1) & 63; }
    bool probe(Key key, TTData& out) const;
    void store(Key key, Move move, int score, int depth, Flag flag, int ply);
    static int scoreFromTT(int score, int ply);
    int hashfull() const;

private:
    struct Entry {
        std::atomic<uint64_t> key;
        std::atomic<uint64_t> data;
    };
    struct alignas(64) Bucket {
        Entry e[BUCKET];
    };
    std::unique_ptr<Bucket[]> table_;
    size_t buckets_ = 0;
    uint8_t age_ = 0;

    Bucket& bucketFor(Key key) const { return table_[key & (buckets_ - 1)]; }
};

class Searcher;

// Per-thread search state (Lazy SMP: every thread searches the same root
// position and shares only the transposition table).
class SearchWorker {
public:
    SearchWorker(Searcher& owner, int id);
    void clearHistory();

private:
    friend class Searcher;

    struct RootMove {
        Move move;
        int score;
        int prevScore;
        uint64_t nodes;
    };

    int negamax(int alpha, int beta, int depth, int ply, bool pvNode, bool allowNull);
    int quiesce(int alpha, int beta, int ply);
    int rootSearch(int depth, int alpha, int beta);
    int staticEval();
    void scoreMoves(MoveList& list, Move ttMove, int ply);
    static void pickMove(MoveList& list, int i);
    bool checkStop();
    void iterativeDeepening();
    void updatePv(int ply, Move m);
    void updateHistory(Color us, Move m, int bonus);
    std::string pvString();

    Searcher& s_;
    const int id_;
    Board board_;
    std::atomic<uint64_t> nodes_{0};
    int seldepth_ = 0;
    bool aborted_ = false;

    Move killers_[MAX_PLY][2];
    int history_[2][64][64];
    int evalStack_[MAX_PLY + 1];
    std::unique_ptr<PawnCache> pawnCache_{new PawnCache()};
    std::unique_ptr<nnue::AccStack> acc_{new nnue::AccStack()};
    Move pv_[MAX_PLY + 1][MAX_PLY + 1];
    int pvLen_[MAX_PLY + 1];

    std::vector<RootMove> rootMoves_;
    Move iterBest_ = NULL_MOVE;
    int iterBestScore_ = 0;
    Move bestMove_ = NULL_MOVE;
    int bestScore_ = 0;
    int completedDepth_ = 0;
    int maxDepth_ = MAX_PLY - 8;
    bool exactRoot_ = false;
};

class Searcher {
public:
    using Output = std::function<void(const std::string&)>;

    Searcher();
    ~Searcher();
    void setHashMb(size_t mb) { tt_.resize(mb); }
    void setThreads(int n);
    int threads() const { return int(workers_.size()); }
    void setMoveOverhead(int ms) { moveOverhead_ = ms; }
    void newGame();

    // Runs a full search and returns the move to play (NULL_MOVE if none).
    // Emits `info` lines through `out` but not `bestmove`.
    Move think(const Board& board, const SearchLimits& limits, const Strength& strength, const Output& out);
    // Expected reply to the last returned move (NULL_MOVE if unknown).
    Move ponderMove() const { return ponderMove_; }
    // Score (side to move, centipawns or mate score) of the last think() result.
    int lastScore() const { return lastScore_; }

    // Thread-safe controls, called from the UCI thread while think() runs.
    void ponderhit();
    std::atomic<bool> stop{false};

private:
    friend class SearchWorker;

    int64_t elapsedMs() const;
    uint64_t totalNodes() const;
    bool timeUp();  // hard limit / node limit (main thread only)
    void setupTime(const SearchLimits& limits, Color us);
    bool shouldStopIteration(SearchWorker& w, int depth, int score);
    Move chooseWeakMove(SearchWorker& w);
    Move findPonderMove(SearchWorker& w, Move best);
    void report(SearchWorker& w, int depth, int score);

    TranspositionTable tt_;
    std::vector<std::unique_ptr<SearchWorker>> workers_;
    SearchLimits limits_;
    Strength strength_;
    Output out_;
    Board rootBoard_;
    int moveOverhead_ = 30;

    std::atomic<int64_t> startNs_{0};
    std::atomic<bool> abortAll_{false};   // tells helpers to finish
    std::atomic<bool> pondering_{false};
    std::atomic<bool> stopOnPonderhit_{false};
    int64_t optimumMs_ = 0, hardMs_ = 0;  // 0 = none
    bool timeManaged_ = false;
    int activeThreads_ = 1;

    // Time-management state (main thread)
    Move lastBest_ = NULL_MOVE;
    int stability_ = 0;
    int prevScores_[4] = {0, 0, 0, 0};

    Move ponderMove_ = NULL_MOVE;
    int lastScore_ = 0;

    // Strength limiting
    int noiseAmp_ = 0;
    uint64_t noiseSeed_ = 0;
    std::mt19937_64 rng_;
};

std::string scoreToUci(int score);
// Static exchange evaluation: does `m` gain at least `threshold` centipawns?
bool see(const Board& b, Move m, int threshold);

} // namespace engine
