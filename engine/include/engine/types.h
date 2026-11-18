#pragma once

#include <cstdint>

#if defined(_MSC_VER)
#include <intrin.h>
#endif

namespace engine {

using Bitboard = uint64_t;
using Key = uint64_t;

enum Color : int { WHITE = 0, BLACK = 1 };
inline Color operator~(Color c) { return Color(c ^ 1); }

enum PieceType : int { PAWN = 0, KNIGHT, BISHOP, ROOK, QUEEN, KING, NO_TYPE };

enum Piece : int { WP = 0, WN, WB, WR, WQ, WK, BP, BN, BB, BR, BQ, BK, NO_PIECE };

inline Piece makePiece(Color c, PieceType t) { return Piece(int(c) * 6 + int(t)); }
inline PieceType typeOf(Piece p) { return PieceType(int(p) % 6); }
inline Color colorOf(Piece p) { return Color(int(p) / 6); }

// Squares: 0 = a1, 7 = h1, 56 = a8, 63 = h8.
constexpr int NO_SQ = -1;
inline int fileOf(int sq) { return sq & 7; }
inline int rankOf(int sq) { return sq >> 3; }
inline int makeSquare(int file, int rank) { return rank * 8 + file; }

enum CastlingRight : int { WHITE_OO = 1, WHITE_OOO = 2, BLACK_OO = 4, BLACK_OOO = 8 };

// Move encoding: bits 0-5 from, 6-11 to, 12-14 promotion piece type (0 = none),
// bits 16+ flags.
using Move = uint32_t;
constexpr Move NULL_MOVE = 0;
enum MoveFlag : uint32_t { F_NONE = 0, F_CAPTURE = 1, F_EP = 2, F_CASTLE = 4, F_DOUBLE = 8 };

inline Move encodeMove(int from, int to, int promo = 0, uint32_t flags = 0) {
    return Move(from) | (Move(to) << 6) | (Move(promo) << 12) | (flags << 16);
}
inline int fromSq(Move m) { return int(m & 63); }
inline int toSq(Move m) { return int((m >> 6) & 63); }
inline int promoOf(Move m) { return int((m >> 12) & 7); }
inline uint32_t flagsOf(Move m) { return m >> 16; }
inline bool isCapture(Move m) { return (flagsOf(m) & (F_CAPTURE | F_EP)) != 0; }

inline Bitboard bit(int sq) { return Bitboard(1) << sq; }

inline int popcount(Bitboard b) {
#if defined(_MSC_VER)
    return int(__popcnt64(b));
#else
    return __builtin_popcountll(b);
#endif
}

inline int lsb(Bitboard b) {
#if defined(_MSC_VER)
    unsigned long idx;
    _BitScanForward64(&idx, b);
    return int(idx);
#else
    return __builtin_ctzll(b);
#endif
}

inline int msb(Bitboard b) {
#if defined(_MSC_VER)
    unsigned long idx;
    _BitScanReverse64(&idx, b);
    return int(idx);
#else
    return 63 - __builtin_clzll(b);
#endif
}

inline int popLsb(Bitboard& b) {
    int s = lsb(b);
    b &= b - 1;
    return s;
}

constexpr int MAX_PLY = 128;
constexpr int INF_SCORE = 32001;
constexpr int MATE_SCORE = 32000;
constexpr int MATE_BOUND = MATE_SCORE - MAX_PLY;

} // namespace engine
