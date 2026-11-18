#pragma once

#include "engine/board.h"

namespace engine {

// Small direct-mapped cache of pawn-structure scores (one per search thread).
struct PawnCache {
    static constexpr int SIZE = 1 << 14;
    struct Entry {
        Bitboard wp = ~Bitboard(0), bp = ~Bitboard(0);
        int mg = 0, eg = 0;
    };
    Entry entries[SIZE];
};

// Static evaluation in centipawns from the side to move's perspective.
// `cache` (optional, not thread-safe) memoises the pawn-structure terms.
// Uses the NNUE network when one is loaded and enabled, the hand-crafted eval otherwise.
int evaluate(const Board& b, PawnCache* cache = nullptr);
// Hand-crafted (tapered PeSTO) evaluation only.
int evaluateHce(const Board& b, PawnCache* cache = nullptr);

// Game phase in [0, 24]: 24 = all non-pawn material present, 0 = bare kings/pawns.
int gamePhase(const Board& b);

} // namespace engine
