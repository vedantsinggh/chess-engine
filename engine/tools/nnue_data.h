// Packed training position shared by `datagen` (writer) and `train` (reader).
//
// 32 bytes, little-endian, no padding:
//   occ       u64   occupied squares (a1 = bit 0)
//   pieces    u8[16] one nibble per occupied square in ascending square order
//                    (low nibble first), value = engine::Piece (0..11: WP..BK)
//   score     i16   search score in centipawns from WHITE's point of view
//   result    u8    game result: 0 = black won, 1 = draw, 2 = white won
//   stm       u8    side to move (0 = white, 1 = black)
//   halfmove  u8    fifty-move counter (saturated at 255)
//   reserved  u8
//   fullmove  u16
#pragma once

#include <cstdint>
#include <cstring>

#include "engine/board.h"

namespace nnuedata {

struct PackedPos {
    uint64_t occ;
    uint8_t pieces[16];
    int16_t score;
    uint8_t result;
    uint8_t stm;
    uint8_t halfmove;
    uint8_t reserved;
    uint16_t fullmove;
};
static_assert(sizeof(PackedPos) == 32, "PackedPos must be 32 bytes");

inline PackedPos pack(const engine::Board& b, int whiteScore, int result) {
    PackedPos p;
    std::memset(&p, 0, sizeof(p));
    p.occ = b.occ[2];
    engine::Bitboard bb = p.occ;
    int i = 0;
    while (bb) {
        int sq = engine::popLsb(bb);
        uint8_t v = uint8_t(b.squares[sq]);
        p.pieces[i / 2] |= uint8_t((i & 1) ? v << 4 : v);
        ++i;
    }
    p.score = int16_t(whiteScore);
    p.result = uint8_t(result);
    p.stm = uint8_t(b.side);
    p.halfmove = uint8_t(b.halfmove > 255 ? 255 : b.halfmove);
    p.fullmove = uint16_t(b.fullmove > 65535 ? 65535 : b.fullmove);
    return p;
}

// Calls f(square, piece) for every piece of the packed position.
template <class F>
inline void forEachPiece(const PackedPos& p, F&& f) {
    engine::Bitboard bb = p.occ;
    int i = 0;
    while (bb) {
        int sq = engine::popLsb(bb);
        int v = (p.pieces[i / 2] >> ((i & 1) * 4)) & 15;
        f(sq, v);
        ++i;
    }
}

} // namespace nnuedata
