#include "engine/search.h"

#include <algorithm>
#include <climits>
#include <cmath>
#include <cstring>
#include <sstream>
#include <thread>

#include "engine/eval.h"

namespace engine {

// ---------------------------------------------------------------------------
// Transposition table
// ---------------------------------------------------------------------------
namespace {

// Packed entry layout: move 20 bits | score 16 | depth+1 8 | flag 2 | age 6.
inline uint64_t packTT(Move move, int score, int depth, int flag, int age) {
    return uint64_t(move & 0xFFFFF) | (uint64_t(uint16_t(int16_t(score))) << 20) |
           (uint64_t(uint8_t(depth + 1)) << 36) | (uint64_t(flag & 3) << 44) | (uint64_t(age & 63) << 46);
}
inline Move ttMove(uint64_t d) { return Move(d & 0xFFFFF); }
inline int ttScore(uint64_t d) { return int(int16_t(uint16_t((d >> 20) & 0xFFFF))); }
inline int ttDepth(uint64_t d) { return int((d >> 36) & 0xFF) - 1; }
inline int ttFlag(uint64_t d) { return int((d >> 44) & 3); }
inline int ttAge(uint64_t d) { return int((d >> 46) & 63); }

} // namespace

void TranspositionTable::resize(size_t mb) {
    if (mb < 1) mb = 1;
    size_t bytes = mb * 1024 * 1024;
    size_t n = 1;
    while (n * 2 * sizeof(Bucket) <= bytes) n *= 2;
    if (n != buckets_) {
        table_.reset();
        table_.reset(new Bucket[n]);
        buckets_ = n;
    }
    clear();
}

void TranspositionTable::clear() {
    for (size_t i = 0; i < buckets_; ++i)
        for (Entry& e : table_[i].e) {
            e.key.store(0, std::memory_order_relaxed);
            e.data.store(0, std::memory_order_relaxed);
        }
    age_ = 0;
}

bool TranspositionTable::probe(Key key, TTData& out) const {
    Bucket& b = bucketFor(key);
    for (const Entry& e : b.e) {
        uint64_t d = e.data.load(std::memory_order_relaxed);
        uint64_t k = e.key.load(std::memory_order_relaxed);
        if ((k ^ d) == key && ttFlag(d) != NONE) {
            out.move = ttMove(d);
            out.score = ttScore(d);
            out.depth = ttDepth(d);
            out.flag = uint8_t(ttFlag(d));
            return true;
        }
    }
    return false;
}

void TranspositionTable::store(Key key, Move move, int score, int depth, Flag flag, int ply) {
    Bucket& b = bucketFor(key);
    Entry* target = nullptr;
    uint64_t old = 0;
    bool same = false;
    int worst = INT_MAX;
    for (Entry& e : b.e) {
        uint64_t d = e.data.load(std::memory_order_relaxed);
        uint64_t k = e.key.load(std::memory_order_relaxed);
        if ((k ^ d) == key && ttFlag(d) != NONE) {
            target = &e;
            old = d;
            same = true;
            break;
        }
        int value = ttFlag(d) == NONE ? INT_MIN : ttDepth(d) - 8 * ((age_ - ttAge(d)) & 63);
        if (value < worst) {
            worst = value;
            target = &e;
        }
    }
    if (same) {
        if (depth < ttDepth(old) - 2 && flag != EXACT && ttAge(old) == age_) return;
        if (move == NULL_MOVE) move = ttMove(old);
    }
    // Mate scores are stored relative to this node, not the root.
    if (score >= MATE_BOUND) score += ply;
    else if (score <= -MATE_BOUND) score -= ply;
    uint64_t d = packTT(move, score, std::max(-1, std::min(depth, 127)), flag, age_);
    target->data.store(d, std::memory_order_relaxed);
    target->key.store(key ^ d, std::memory_order_relaxed);
}

int TranspositionTable::scoreFromTT(int score, int ply) {
    if (score >= MATE_BOUND) return score - ply;
    if (score <= -MATE_BOUND) return score + ply;
    return score;
}

int TranspositionTable::hashfull() const {
    size_t n = std::min<size_t>(1000 / BUCKET, buckets_);
    int used = 0;
    for (size_t i = 0; i < n; ++i)
        for (const Entry& e : table_[i].e) {
            uint64_t d = e.data.load(std::memory_order_relaxed);
            used += ttFlag(d) != NONE && ttAge(d) == age_;
        }
    return int(used * 1000 / (n * BUCKET));
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
namespace {

const int ORDER_VALUE[6] = {100, 320, 330, 500, 900, 20000};
constexpr int HISTORY_MAX = 16384;

uint64_t splitmix(uint64_t x) {
    x += 0x9E3779B97F4A7C15ULL;
    x = (x ^ (x >> 30)) * 0xBF58476D1CE4E5B9ULL;
    x = (x ^ (x >> 27)) * 0x94D049BB133111EBULL;
    return x ^ (x >> 31);
}

// Lazy SMP depth skipping for helper threads (pattern from Stockfish 9).
const int SKIP_SIZE[] = {1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 3, 3, 4, 4, 4, 4, 4, 4, 4, 4};
const int SKIP_PHASE[] = {0, 1, 0, 1, 2, 3, 0, 1, 2, 3, 4, 5, 0, 1, 2, 3, 4, 5, 6, 7};

// Late-move reduction table.
struct LmrTable {
    int r[64][64];
    LmrTable() {
        for (int d = 0; d < 64; ++d)
            for (int m = 0; m < 64; ++m)
                r[d][m] = (d && m) ? int(0.75 + std::log(double(d)) * std::log(double(m)) / 2.25) : 0;
    }
};
const LmrTable LMR_TABLE;

int64_t nowNs() {
    return std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now().time_since_epoch())
        .count();
}

} // namespace

const int SEE_VALUE[7] = {100, 320, 330, 500, 900, 20000, 0};

// Static exchange evaluation: true if the move wins at least `threshold`
// centipawns after the best sequence of recaptures on its target square.
bool see(const Board& b, Move m, int threshold) {
    if (flagsOf(m) & F_CASTLE) return 0 >= threshold;
    const int from = fromSq(m), to = toSq(m);
    int victim = (flagsOf(m) & F_EP) ? PAWN : (b.squares[to] == NO_PIECE ? 6 : typeOf(b.squares[to]));
    int balance = SEE_VALUE[victim] - threshold;
    int next = typeOf(b.squares[from]);
    if (promoOf(m)) {
        balance += SEE_VALUE[promoOf(m)] - SEE_VALUE[PAWN];
        next = promoOf(m);
    }
    if (balance < 0) return false;
    balance -= SEE_VALUE[next];
    if (balance >= 0) return true;

    Bitboard occ = b.occ[2] ^ bit(from) ^ bit(to);
    if (flagsOf(m) & F_EP) occ ^= bit(to + (b.side == WHITE ? -8 : 8));
    const Bitboard bishops = b.pieces[WB] | b.pieces[BB] | b.pieces[WQ] | b.pieces[BQ];
    const Bitboard rooks = b.pieces[WR] | b.pieces[BR] | b.pieces[WQ] | b.pieces[BQ];
    Bitboard attackers = (pawnAttacks(BLACK, to) & b.pieces[WP]) | (pawnAttacks(WHITE, to) & b.pieces[BP]) |
                         (knightAttacks(to) & (b.pieces[WN] | b.pieces[BN])) |
                         (kingAttacks(to) & (b.pieces[WK] | b.pieces[BK])) | (bishopAttacks(to, occ) & bishops) |
                         (rookAttacks(to, occ) & rooks);
    Color side = ~b.side;
    for (;;) {
        attackers &= occ;
        Bitboard mine = attackers & b.occ[side];
        if (!mine) break;
        int pt = PAWN;
        for (; pt <= KING; ++pt)
            if (mine & b.pieces[makePiece(side, PieceType(pt))]) break;
        side = ~side;
        balance = -balance - 1 - SEE_VALUE[pt];
        if (balance >= 0) {
            // A king cannot capture into a defended square.
            if (pt == KING && (attackers & b.occ[side])) side = ~side;
            break;
        }
        occ ^= bit(lsb(mine & b.pieces[makePiece(~side, PieceType(pt))]));
        if (pt == PAWN || pt == BISHOP || pt == QUEEN) attackers |= bishopAttacks(to, occ) & bishops;
        if (pt == ROOK || pt == QUEEN) attackers |= rookAttacks(to, occ) & rooks;
    }
    return side != b.side;
}

std::string scoreToUci(int score) {
    if (score >= MATE_BOUND) return "mate " + std::to_string((MATE_SCORE - score + 1) / 2);
    if (score <= -MATE_BOUND) return "mate " + std::to_string(-(MATE_SCORE + score) / 2);
    return "cp " + std::to_string(score);
}

// ---------------------------------------------------------------------------
// SearchWorker
// ---------------------------------------------------------------------------
SearchWorker::SearchWorker(Searcher& owner, int id) : s_(owner), id_(id) { clearHistory(); }

void SearchWorker::clearHistory() {
    std::memset(killers_, 0, sizeof(killers_));
    std::memset(history_, 0, sizeof(history_));
}

bool SearchWorker::checkStop() {
    if (s_.stop.load(std::memory_order_relaxed) || s_.abortAll_.load(std::memory_order_relaxed)) aborted_ = true;
    else if (id_ == 0 && s_.timeUp()) aborted_ = true;
    return aborted_;
}

int SearchWorker::staticEval() {
    int e = evaluate(board_, pawnCache_.get());
    if (s_.noiseAmp_ > 0) {
        uint64_t h = splitmix(board_.key ^ s_.noiseSeed_);
        e += int(h % uint64_t(2 * s_.noiseAmp_ + 1)) - s_.noiseAmp_;
    }
    return e;
}

void SearchWorker::scoreMoves(MoveList& list, Move ttMove, int ply) {
    const Color us = board_.side;
    for (int i = 0; i < list.size; ++i) {
        Move m = list.moves[i];
        int s;
        if (m == ttMove) {
            s = 10000000;
        } else if (isCapture(m)) {
            int victim = (flagsOf(m) & F_EP) ? PAWN : typeOf(board_.squares[toSq(m)]);
            int attacker = typeOf(board_.squares[fromSq(m)]);
            s = 2000000 + ORDER_VALUE[victim] * 10 - attacker;
            if (promoOf(m) == QUEEN) s += 5000;
            // Losing captures go after the quiet moves.
            if (ORDER_VALUE[attacker] > ORDER_VALUE[victim] && !see(board_, m, 0)) s -= 2400000;
        } else if (promoOf(m)) {
            s = promoOf(m) == QUEEN ? 1900000 : -1000000;
        } else if (m == killers_[ply][0]) {
            s = 1500000;
        } else if (m == killers_[ply][1]) {
            s = 1400000;
        } else {
            s = history_[us][fromSq(m)][toSq(m)];
        }
        list.scores[i] = s;
    }
}

void SearchWorker::pickMove(MoveList& list, int i) {
    int best = i;
    for (int j = i + 1; j < list.size; ++j)
        if (list.scores[j] > list.scores[best]) best = j;
    if (best != i) {
        std::swap(list.moves[i], list.moves[best]);
        std::swap(list.scores[i], list.scores[best]);
    }
}

void SearchWorker::updatePv(int ply, Move m) {
    pv_[ply][ply] = m;
    for (int j = ply + 1; j < pvLen_[ply + 1]; ++j) pv_[ply][j] = pv_[ply + 1][j];
    pvLen_[ply] = std::max(ply + 1, pvLen_[ply + 1]);
}

void SearchWorker::updateHistory(Color us, Move m, int bonus) {
    int& h = history_[us][fromSq(m)][toSq(m)];
    h += bonus - h * std::abs(bonus) / HISTORY_MAX;
}

// ---------------------------------------------------------------------------
// Quiescence
// ---------------------------------------------------------------------------
int SearchWorker::quiesce(int alpha, int beta, int ply) {
    pvLen_[ply] = ply;
    uint64_t n = nodes_.load(std::memory_order_relaxed) + 1;
    nodes_.store(n, std::memory_order_relaxed);
    if ((n & 1023) == 0 && checkStop()) return 0;
    if (aborted_) return 0;
    if (ply > seldepth_) seldepth_ = ply;
    if (ply >= MAX_PLY - 1) return staticEval();
    if (board_.isInsufficientMaterial()) return 0;

    TTData tte;
    const bool found = s_.tt_.probe(board_.key, tte);
    if (found) {
        int s = TranspositionTable::scoreFromTT(tte.score, ply);
        if (tte.flag == TranspositionTable::EXACT || (tte.flag == TranspositionTable::LOWER && s >= beta) ||
            (tte.flag == TranspositionTable::UPPER && s <= alpha))
            return s;
    }

    const bool inCheck = board_.inCheck();
    const int origAlpha = alpha;
    int best = -INF_SCORE;
    int standPat = 0;
    if (!inCheck) {
        standPat = staticEval();
        if (standPat >= beta) return standPat;
        if (standPat > alpha) alpha = standPat;
        best = standPat;
    }

    MoveList list;
    board_.generatePseudo(list, !inCheck);
    scoreMoves(list, found ? tte.move : NULL_MOVE, ply);
    int legal = 0;
    Move bestMove = NULL_MOVE;
    for (int i = 0; i < list.size; ++i) {
        pickMove(list, i);
        Move m = list.moves[i];
        if (!inCheck) {
            if (!promoOf(m)) {
                // Delta pruning: skip captures that cannot raise alpha.
                int victim = (flagsOf(m) & F_EP) ? PAWN : typeOf(board_.squares[toSq(m)]);
                if (standPat + ORDER_VALUE[victim] + 200 < alpha) continue;
            }
            // Skip captures that lose material.
            if (!see(board_, m, 0)) continue;
        }
        if (!board_.makeMove(m)) continue;
        ++legal;
        int s = -quiesce(-beta, -alpha, ply + 1);
        board_.unmakeMove();
        if (aborted_) return 0;
        if (s > best) {
            best = s;
            if (s > alpha) {
                alpha = s;
                bestMove = m;
                if (s >= beta) break;
            }
        }
    }
    if (inCheck && legal == 0) return -MATE_SCORE + ply;
    TranspositionTable::Flag flag = best >= beta        ? TranspositionTable::LOWER
                                    : best > origAlpha ? TranspositionTable::EXACT
                                                       : TranspositionTable::UPPER;
    s_.tt_.store(board_.key, bestMove, best, 0, flag, ply);
    return best;
}

// ---------------------------------------------------------------------------
// Main search
// ---------------------------------------------------------------------------
int SearchWorker::negamax(int alpha, int beta, int depth, int ply, bool pvNode, bool allowNull) {
    pvLen_[ply] = ply;
    if (ply >= MAX_PLY - 1) return staticEval();

    const bool inCheck = board_.inCheck();

    // Draws
    if (board_.isRepetition() || board_.isInsufficientMaterial()) return 0;
    if (board_.halfmove >= 100) {
        if (!inCheck) return 0;
        MoveList legalMoves;
        board_.generateLegal(legalMoves);
        return legalMoves.size ? 0 : -MATE_SCORE + ply;
    }

    // Mate distance pruning
    alpha = std::max(alpha, -MATE_SCORE + ply);
    beta = std::min(beta, MATE_SCORE - ply - 1);
    if (alpha >= beta) return alpha;

    if (inCheck) ++depth;
    if (depth <= 0) return quiesce(alpha, beta, ply);

    uint64_t n = nodes_.load(std::memory_order_relaxed) + 1;
    nodes_.store(n, std::memory_order_relaxed);
    if ((n & 1023) == 0 && checkStop()) return 0;
    if (aborted_) return 0;
    if (ply > seldepth_) seldepth_ = ply;

    TTData tte;
    const bool found = s_.tt_.probe(board_.key, tte);
    const Move ttMove = found ? tte.move : NULL_MOVE;
    if (found && !pvNode && tte.depth >= depth) {
        int s = TranspositionTable::scoreFromTT(tte.score, ply);
        if (tte.flag == TranspositionTable::EXACT) return s;
        if (tte.flag == TranspositionTable::LOWER && s >= beta) return s;
        if (tte.flag == TranspositionTable::UPPER && s <= alpha) return s;
    }

    const int staticE = inCheck ? -INF_SCORE : staticEval();
    evalStack_[ply] = staticE;
    const bool improving =
        !inCheck && (ply < 2 || evalStack_[ply - 2] == -INF_SCORE || staticE > evalStack_[ply - 2]);

    if (!pvNode && !inCheck) {
        // Reverse futility pruning
        if (depth <= 6 && std::abs(beta) < MATE_BOUND && staticE - 80 * (depth - improving) >= beta)
            return staticE;

        // Null-move pruning
        if (allowNull && depth >= 3 && staticE >= beta && board_.hasNonPawnMaterial(board_.side)) {
            int R = 3 + depth / 4 + std::min(3, (staticE - beta) / 200);
            board_.makeNullMove();
            int s = -negamax(-beta, -beta + 1, depth - 1 - R, ply + 1, false, false);
            board_.unmakeNullMove();
            if (aborted_) return 0;
            if (s >= beta) return s >= MATE_BOUND ? beta : s;
        }
    }

    // Internal iterative reduction: no hash move, search shallower first.
    if (depth >= 4 && ttMove == NULL_MOVE) --depth;

    // The hash move is tried before any moves are generated.
    const bool ttValid = ttMove != NULL_MOVE && board_.isPseudoLegal(ttMove);
    bool generated = false;
    MoveList list;
    list.size = 0;

    const int origAlpha = alpha;
    const Color us = board_.side;
    int best = -INF_SCORE;
    Move bestMove = NULL_MOVE;
    int legal = 0;
    Move quiets[64];
    int quietCount = 0;

    for (int i = ttValid ? -1 : 0;; ++i) {
        Move m;
        if (i < 0) {
            m = ttMove;
        } else {
            if (!generated) {
                board_.generatePseudo(list);
                scoreMoves(list, ttMove, ply);
                generated = true;
            }
            if (i >= list.size) break;
            pickMove(list, i);
            m = list.moves[i];
            if (ttValid && m == ttMove) continue;
        }
        const bool quiet = !isCapture(m) && !promoOf(m);

        // Move-count based pruning (never before a legal move has been searched).
        if (!pvNode && !inCheck && legal > 0 && best > -MATE_BOUND) {
            if (quiet) {
                if (depth <= 4 && quietCount >= (3 + depth * depth) / (improving ? 1 : 2)) continue;
                if (depth <= 5 && staticE + 100 + 90 * depth <= alpha && m != killers_[ply][0] &&
                    m != killers_[ply][1])
                    continue;
            } else if (depth <= 5 && !see(board_, m, -100 * depth)) {
                continue;
            }
        }

        if (!board_.makeMove(m)) continue;
        ++legal;
        if (quiet && quietCount < 64) quiets[quietCount++] = m;
        const bool givesCheck = board_.inCheck();
        const int newDepth = depth - 1;
        int s;
        if (legal == 1) {
            s = -negamax(-beta, -alpha, newDepth, ply + 1, pvNode, true);
        } else {
            int r = 0;
            if (depth >= 3 && legal > 2 && quiet) {
                r = LMR_TABLE.r[std::min(depth, 63)][std::min(legal, 63)];
                if (pvNode) --r;
                if (!improving) ++r;
                if (givesCheck || inCheck) --r;
                if (m == killers_[ply][0] || m == killers_[ply][1]) --r;
                r -= history_[us][fromSq(m)][toSq(m)] / 6000;
                r = std::clamp(r, 0, newDepth - 1);
            }
            s = -negamax(-alpha - 1, -alpha, newDepth - r, ply + 1, false, true);
            if (s > alpha && r > 0) s = -negamax(-alpha - 1, -alpha, newDepth, ply + 1, false, true);
            if (s > alpha && s < beta && pvNode) s = -negamax(-beta, -alpha, newDepth, ply + 1, true, true);
        }
        board_.unmakeMove();
        if (aborted_) return 0;

        if (s > best) {
            best = s;
            bestMove = m;
            if (s > alpha) {
                alpha = s;
                updatePv(ply, m);
                if (alpha >= beta) {
                    if (quiet) {
                        if (killers_[ply][0] != m) {
                            killers_[ply][1] = killers_[ply][0];
                            killers_[ply][0] = m;
                        }
                        const int bonus = std::min(depth * depth * 16, 1600);
                        updateHistory(us, m, bonus);
                        for (int q = 0; q < quietCount - 1; ++q) updateHistory(us, quiets[q], -bonus);
                    }
                    break;
                }
            }
        }
    }

    if (legal == 0) return inCheck ? -MATE_SCORE + ply : 0;

    TranspositionTable::Flag flag = best >= beta        ? TranspositionTable::LOWER
                                    : best > origAlpha ? TranspositionTable::EXACT
                                                       : TranspositionTable::UPPER;
    s_.tt_.store(board_.key, bestMove, best, depth, flag, ply);
    return best;
}

int SearchWorker::rootSearch(int depth, int alpha, int beta) {
    pvLen_[0] = 0;
    iterBest_ = NULL_MOVE;
    evalStack_[0] = board_.inCheck() ? -INF_SCORE : staticEval();
    const int origAlpha = alpha;
    int best = -INF_SCORE;
    for (size_t i = 0; i < rootMoves_.size(); ++i) {
        RootMove& rm = rootMoves_[i];
        const uint64_t before = nodes_.load(std::memory_order_relaxed);
        board_.makeMove(rm.move);
        nodes_.store(before + 1, std::memory_order_relaxed);
        int s;
        if (i == 0 || exactRoot_) {
            s = -negamax(exactRoot_ ? -INF_SCORE : -beta, exactRoot_ ? INF_SCORE : -alpha, depth - 1, 1, true,
                         true);
        } else {
            s = -negamax(-alpha - 1, -alpha, depth - 1, 1, false, true);
            if (s > alpha && s < beta) s = -negamax(-beta, -alpha, depth - 1, 1, true, true);
        }
        board_.unmakeMove();
        rm.nodes += nodes_.load(std::memory_order_relaxed) - before;
        if (aborted_) return best;
        rm.score = s;
        if (s > best) {
            best = s;
            iterBest_ = rm.move;
            iterBestScore_ = s;
            pv_[0][0] = rm.move;
            for (int j = 1; j < pvLen_[1]; ++j) pv_[0][j] = pv_[1][j];
            pvLen_[0] = std::max(1, pvLen_[1]);
            if (s > alpha) alpha = s;
            if (s >= beta && !exactRoot_) break;  // aspiration fail-high
        }
    }
    if (best > origAlpha && best < beta && iterBest_ != NULL_MOVE)
        s_.tt_.store(board_.key, iterBest_, best, depth, TranspositionTable::EXACT, 0);
    return best;
}

std::string SearchWorker::pvString() {
    // Validate the PV by playing it out; stop at the first illegal move.
    std::string s;
    int played = 0;
    for (int i = 0; i < pvLen_[0]; ++i) {
        Move m = pv_[0][i];
        MoveList legal;
        board_.generateLegal(legal);
        bool ok = false;
        for (int j = 0; j < legal.size; ++j) ok |= legal.moves[j] == m;
        if (!ok) break;
        if (!s.empty()) s += ' ';
        s += board_.moveToUci(m);
        board_.makeMove(m);
        ++played;
    }
    while (played--) board_.unmakeMove();
    return s;
}

void SearchWorker::iterativeDeepening() {
    const bool main = id_ == 0;
    for (int depth = 1; depth <= maxDepth_; ++depth) {
        // Helper threads skip some depths so threads spread over different depths.
        if (!main) {
            int i = (id_ - 1) % 20;
            if (((depth + SKIP_PHASE[i]) / SKIP_SIZE[i]) % 2) continue;
        }
        seldepth_ = 0;
        for (RootMove& rm : rootMoves_) rm.nodes = 0;
        // Before depth 1 completes the main thread only stops on an explicit `stop`.
        // (timeManaged_ is only touched by the main thread.)
        bool savedTm = false;
        if (main) {
            savedTm = s_.timeManaged_;
            if (completedDepth_ == 0) s_.timeManaged_ = false;
        }
        int score;
        if (depth >= 5 && !exactRoot_ && std::abs(bestScore_) < MATE_BOUND) {
            // Aspiration window around the previous score, widened on failure.
            int delta = 20;
            int alpha = std::max(bestScore_ - delta, -INF_SCORE), beta = std::min(bestScore_ + delta, INF_SCORE);
            for (;;) {
                score = rootSearch(depth, alpha, beta);
                if (aborted_) break;
                if (score <= alpha) {
                    beta = (alpha + beta) / 2;
                    alpha = std::max(score - delta, -INF_SCORE);
                } else if (score >= beta) {
                    bestMove_ = iterBest_;  // a fail-high move is at least as good
                    beta = std::min(score + delta, INF_SCORE);
                } else {
                    break;
                }
                delta += delta / 2 + 10;
                if (delta > 1000) {
                    alpha = -INF_SCORE;
                    beta = INF_SCORE;
                }
            }
        } else {
            score = rootSearch(depth, -INF_SCORE, INF_SCORE);
        }
        if (main) s_.timeManaged_ = savedTm;

        if (aborted_) {
            if (iterBest_ != NULL_MOVE && !exactRoot_) {
                bestMove_ = iterBest_;
                bestScore_ = iterBestScore_;
            }
            break;
        }
        completedDepth_ = depth;
        bestMove_ = iterBest_;
        bestScore_ = score;
        for (RootMove& rm : rootMoves_) rm.prevScore = rm.score;
        // Best move first, then the rest by score.
        const Move bm = bestMove_;
        std::stable_sort(rootMoves_.begin(), rootMoves_.end(), [&](const RootMove& a, const RootMove& b) {
            if (a.move == bm) return b.move != bm;
            if (b.move == bm) return false;
            return a.score > b.score;
        });

        if (!main) {
            if (s_.stop.load(std::memory_order_relaxed) || s_.abortAll_.load(std::memory_order_relaxed)) break;
            continue;
        }
        s_.report(*this, depth, score);
        if (s_.shouldStopIteration(*this, depth, score)) break;
        if (s_.stop.load()) break;
    }
}

// ---------------------------------------------------------------------------
// Searcher
// ---------------------------------------------------------------------------
Searcher::Searcher() : rng_(std::random_device{}()) {
    tt_.resize(16);
    setThreads(1);
    newGame();
}

Searcher::~Searcher() = default;

void Searcher::setThreads(int n) {
    n = std::max(1, n);
    while (int(workers_.size()) > n) workers_.pop_back();
    while (int(workers_.size()) < n) workers_.push_back(std::make_unique<SearchWorker>(*this, int(workers_.size())));
}

void Searcher::newGame() {
    tt_.clear();
    for (auto& w : workers_) w->clearHistory();
}

int64_t Searcher::elapsedMs() const {
    return (nowNs() - startNs_.load(std::memory_order_relaxed)) / 1000000;
}

uint64_t Searcher::totalNodes() const {
    uint64_t n = 0;
    for (int i = 0; i < activeThreads_; ++i) n += workers_[size_t(i)]->nodes_.load(std::memory_order_relaxed);
    return n;
}

bool Searcher::timeUp() {
    if (limits_.nodes && totalNodes() >= limits_.nodes) return true;
    if (!timeManaged_ || pondering_.load(std::memory_order_relaxed)) return false;
    return hardMs_ > 0 && elapsedMs() >= hardMs_;
}

void Searcher::ponderhit() {
    // The opponent played the expected move: our clock starts now.
    startNs_.store(nowNs());
    if (stopOnPonderhit_.load()) stop = true;
    pondering_ = false;
}

void Searcher::setupTime(const SearchLimits& limits, Color us) {
    optimumMs_ = hardMs_ = 0;
    timeManaged_ = false;
    if (limits.movetime > 0) {
        optimumMs_ = hardMs_ = std::max<int64_t>(1, limits.movetime - moveOverhead_ / 3 - 5);
        timeManaged_ = true;
    } else if (!limits.infinite && limits.time[us] >= 0) {
        const int64_t time = limits.time[us], inc = limits.inc[us];
        const int64_t avail = std::max<int64_t>(1, time - moveOverhead_);
        const int mtg = limits.movestogo > 0 ? std::min(limits.movestogo, 40) : 26;
        int64_t opt = avail / mtg + inc * 3 / 4;
        // Never plan to spend most of the clock on one move; the hard cap
        // keeps a reserve so increments can rebuild the clock.
        const double cap = mtg == 1 ? 0.8 : limits.movestogo > 0 ? 0.6 : 0.4;
        int64_t hard = std::min<int64_t>(opt * 5, int64_t(double(avail) * cap));
        opt = std::min(opt, hard);
        optimumMs_ = std::max<int64_t>(1, opt);
        hardMs_ = std::max<int64_t>(1, hard);
        timeManaged_ = true;
    }
}

bool Searcher::shouldStopIteration(SearchWorker& w, int depth, int score) {
    // Best-move stability and score trend, used to scale the optimum time.
    if (w.bestMove_ == lastBest_) stability_ = std::min(stability_ + 1, 10);
    else stability_ = 0;
    lastBest_ = w.bestMove_;
    const int prev = prevScores_[(depth + 2) % 4];  // score two iterations ago
    prevScores_[depth % 4] = score;

    if (limits_.infinite) return false;
    if (std::abs(score) >= MATE_BOUND && MATE_SCORE - std::abs(score) <= depth) {
        if (!pondering_.load()) return true;
        stopOnPonderhit_ = true;
        return false;
    }
    if (limits_.nodes && totalNodes() >= limits_.nodes) return true;
    if (!timeManaged_ || limits_.movetime > 0) return false;

    const int64_t t = elapsedMs();
    // A single legal move: answer immediately (after a short search for a score).
    if (w.rootMoves_.size() == 1 && depth >= 2) {
        if (!pondering_.load()) return true;
        stopOnPonderhit_ = true;
        return false;
    }
    double scale = 1.0;
    if (depth >= 5) {
        static const double STAB[] = {1.8, 1.4, 1.15, 1.0, 0.9, 0.82, 0.76, 0.72, 0.7, 0.68, 0.66};
        scale *= STAB[stability_];
        if (score < prev - 20) scale *= std::min(1.8, 1.0 + double(prev - score) / 120.0);
        uint64_t total = 0, bestNodes = 0;
        for (auto& rm : w.rootMoves_) {
            total += rm.nodes;
            if (rm.move == w.bestMove_) bestNodes = rm.nodes;
        }
        if (total > 0) {
            double frac = double(bestNodes) / double(total);
            scale *= std::clamp((1.6 - frac) * 1.2, 0.6, 1.8);
        }
    }
    const double limit = std::min(double(hardMs_), double(optimumMs_) * scale);
    if (t >= limit * 0.6) {
        // The next iteration would very likely not finish before the limit.
        if (!pondering_.load()) return true;
        stopOnPonderhit_ = true;
    }
    return false;
}

void Searcher::report(SearchWorker& w, int depth, int score) {
    int64_t t = elapsedMs();
    uint64_t nodes = totalNodes();
    std::ostringstream os;
    os << "info depth " << depth << " seldepth " << std::max(w.seldepth_, depth) << " score " << scoreToUci(score)
       << " nodes " << nodes << " nps " << (nodes * 1000 / uint64_t(std::max<int64_t>(1, t))) << " hashfull "
       << tt_.hashfull() << " time " << t << " pv " << w.pvString();
    out_(os.str());
}

Move Searcher::chooseWeakMove(SearchWorker& w) {
    const auto& rootMoves = w.rootMoves_;
    if (rootMoves.size() < 2) return rootMoves.empty() ? NULL_MOVE : rootMoves[0].move;
    std::vector<SearchWorker::RootMove> sorted = rootMoves;
    std::stable_sort(sorted.begin(), sorted.end(),
                     [](const SearchWorker::RootMove& a, const SearchWorker::RootMove& b) {
                         return a.prevScore > b.prevScore;
                     });
    const int elo = strength_.elo;
    const int margin = (2400 - elo) / 6;  // 400 Elo: ~333cp
    const int bestScore = sorted[0].prevScore;
    std::vector<Move> candidates;
    for (const auto& rm : sorted) {
        if (candidates.size() >= 4) break;
        if (rm.prevScore < bestScore - margin) break;
        if (rm.prevScore <= -MATE_BOUND && bestScore > -MATE_BOUND) break;  // never walk into a forced mate
        candidates.push_back(rm.move);
    }
    std::uniform_real_distribution<double> u(0.0, 1.0);
    // Occasional outright blunder for low ratings (400 Elo: 20%, >= 1600 Elo: never):
    // pick any move from the better half that does not walk into a forced mate.
    double pBlunder = std::max(0, 1600 - elo) / 1200.0 * 0.2;
    if (u(rng_) < pBlunder) {
        std::vector<Move> pool;
        for (size_t i = 0; i < (sorted.size() + 1) / 2; ++i)
            if (sorted[i].prevScore > -MATE_BOUND || bestScore <= -MATE_BOUND) pool.push_back(sorted[i].move);
        if (!pool.empty()) {
            std::uniform_int_distribution<size_t> pick(0, pool.size() - 1);
            return pool[pick(rng_)];
        }
    }
    double pDeviate = (2400.0 - elo) / 2000.0 * 0.6;  // 400 Elo: 60%, 2200 Elo: 6%
    if (candidates.size() > 1 && u(rng_) < pDeviate) {
        std::uniform_int_distribution<size_t> pick(1, candidates.size() - 1);
        return candidates[pick(rng_)];
    }
    return sorted[0].move;
}

Move Searcher::findPonderMove(SearchWorker& w, Move best) {
    if (best == NULL_MOVE) return NULL_MOVE;
    Board b = rootBoard_;
    if (!b.makeMove(best)) return NULL_MOVE;
    MoveList legal;
    b.generateLegal(legal);
    Move cand = NULL_MOVE;
    if (w.pvLen_[0] >= 2 && w.pv_[0][0] == best) cand = w.pv_[0][1];
    if (cand == NULL_MOVE) {
        TTData tte;
        if (tt_.probe(b.key, tte)) cand = tte.move;
    }
    for (int i = 0; i < legal.size; ++i)
        if (legal.moves[i] == cand) return cand;
    return NULL_MOVE;
}

Move Searcher::think(const Board& board, const SearchLimits& limits, const Strength& strength, const Output& out) {
    startNs_.store(nowNs());
    rootBoard_ = board;
    limits_ = limits;
    strength_ = strength;
    out_ = out;
    abortAll_ = false;
    pondering_ = limits.ponder;
    stopOnPonderhit_ = false;
    ponderMove_ = NULL_MOVE;
    lastBest_ = NULL_MOVE;
    stability_ = 0;
    for (int& s : prevScores_) s = 0;
    tt_.newSearch();
    setupTime(limits, board.side);

    auto waitForRelease = [&]() {
        // UCI: in infinite/ponder mode bestmove may only be sent after stop/ponderhit.
        while ((limits.infinite || pondering_.load()) && !stop.load())
            std::this_thread::sleep_for(std::chrono::milliseconds(1));
    };

    // Root moves
    Board rb = board;
    MoveList legal;
    rb.generateLegal(legal);
    if (legal.size == 0) {
        out(std::string("info depth 0 score ") + (rb.inCheck() ? "mate 0" : "cp 0"));
        waitForRelease();
        return NULL_MOVE;
    }

    // Strength limiting (single-threaded, depth-capped, noisy evaluation).
    const bool weak = strength.elo < 2400;
    int maxDepth = MAX_PLY - 8;
    noiseAmp_ = 0;
    if (weak) {
        int elo = std::max(400, strength.elo);
        maxDepth = 1 + (elo - 400) / 200;  // 400 -> 1 ply, 2200 -> 10 plies
        noiseAmp_ = (2400 - elo) / 8;      // 400 -> +-250cp
        noiseSeed_ = rng_();
    }
    if (limits.depth > 0) maxDepth = std::min(maxDepth, limits.depth);
    activeThreads_ = weak ? 1 : int(workers_.size());

    for (int i = 0; i < activeThreads_; ++i) {
        SearchWorker& w = *workers_[size_t(i)];
        w.board_ = board;
        if (nnue::enabled()) w.board_.attachAcc(w.acc_.get());
        w.nodes_.store(0);
        w.aborted_ = false;
        w.iterBest_ = w.bestMove_ = NULL_MOVE;
        w.bestScore_ = 0;
        w.completedDepth_ = 0;
        w.maxDepth_ = maxDepth;
        w.exactRoot_ = weak;
        std::memset(w.killers_, 0, sizeof(w.killers_));
        for (auto& a : w.history_)
            for (auto& b : a)
                for (auto& c : b) c /= 2;
        TTData tte;
        MoveList l = legal;
        w.scoreMoves(l, tt_.probe(board.key, tte) ? tte.move : NULL_MOVE, 0);
        w.rootMoves_.clear();
        for (int j = 0; j < l.size; ++j) {
            SearchWorker::pickMove(l, j);
            w.rootMoves_.push_back(SearchWorker::RootMove{l.moves[j], -INF_SCORE, -INF_SCORE, 0});
        }
    }
    SearchWorker& main = *workers_[0];
    main.bestMove_ = main.rootMoves_[0].move;  // fallback if stopped before depth 1 completes

    std::vector<std::thread> helpers;
    for (int i = 1; i < activeThreads_; ++i)
        helpers.emplace_back([this, i]() { workers_[size_t(i)]->iterativeDeepening(); });
    main.iterativeDeepening();
    abortAll_ = true;
    for (auto& t : helpers) t.join();

    Move bestMove = main.bestMove_;
    lastScore_ = main.bestScore_;
    if (weak && main.completedDepth_ > 0) bestMove = chooseWeakMove(main);
    ponderMove_ = findPonderMove(main, bestMove);

    waitForRelease();
    return bestMove;
}

} // namespace engine
