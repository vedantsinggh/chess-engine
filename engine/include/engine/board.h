#pragma once

#include <string>
#include <vector>

#include "engine/types.h"

namespace engine {

namespace nnue {
struct AccStack;
}

struct MoveList {
    Move moves[256];
    int scores[256];
    int size = 0;
    void push(Move m) { moves[size++] = m; }
};

// Precomputed attack tables (initialised by initTables()).
void initTables();

namespace detail {
// "Fancy" magic bitboards: magics are found at startup with a fixed seed.
struct Magic {
    Bitboard mask;
    Bitboard magic;
    const Bitboard* attacks;
    unsigned shift;
    unsigned index(Bitboard occ) const { return unsigned(((occ & mask) * magic) >> shift); }
};
extern Magic ROOK_MAGICS[64];
extern Magic BISHOP_MAGICS[64];
extern Bitboard KNIGHT_ATT[64];
extern Bitboard KING_ATT[64];
extern Bitboard PAWN_ATT[2][64];
// Incremental evaluation tables (filled by initEvalTables() in eval.cpp):
// material + piece-square value, positive for white pieces, negative for black.
extern int PSQ_MG[12][64];
extern int PSQ_EG[12][64];
extern int PHASE_INC[12];
} // namespace detail
void initEvalTables();

inline Bitboard knightAttacks(int sq) { return detail::KNIGHT_ATT[sq]; }
inline Bitboard kingAttacks(int sq) { return detail::KING_ATT[sq]; }
inline Bitboard pawnAttacks(Color c, int sq) { return detail::PAWN_ATT[c][sq]; }
inline Bitboard bishopAttacks(int sq, Bitboard occ) {
    const detail::Magic& m = detail::BISHOP_MAGICS[sq];
    return m.attacks[m.index(occ)];
}
inline Bitboard rookAttacks(int sq, Bitboard occ) {
    const detail::Magic& m = detail::ROOK_MAGICS[sq];
    return m.attacks[m.index(occ)];
}

class Board {
public:
    static const char* START_FEN;

    Board();

    bool setFen(const std::string& fen);
    std::string fen() const;
    std::string pretty() const;

    // Applies a pseudo-legal move. Returns false (and leaves the board
    // unchanged) if the move would leave the mover's king in check.
    bool makeMove(Move m);
    void unmakeMove();
    void makeNullMove();
    void unmakeNullMove();

    void generatePseudo(MoveList& list, bool capturesOnly = false) const;
    void generateLegal(MoveList& list);

    bool isAttacked(int sq, Color by) const;
    bool inCheck() const { return isAttacked(kingSquare(side), ~side); }
    int kingSquare(Color c) const { return lsb(pieces[makePiece(c, KING)]); }

    bool isRepetition() const;        // any earlier occurrence (used inside search)
    int repetitionCount() const;      // number of earlier occurrences
    bool isInsufficientMaterial() const;
    bool hasNonPawnMaterial(Color c) const;

    uint64_t perft(int depth);

    std::string moveToUci(Move m) const;
    Move parseUciMove(const std::string& s);  // NULL_MOVE if illegal
    // True if `m` (e.g. from the hash table) is in this position's pseudo-legal move list.
    bool isPseudoLegal(Move m) const;
    // Legality of a pseudo-legal move without making it.
    bool isLegal(Move m) const;

    Key computeKey() const;

    // NNUE accumulator stack (per search thread). While attached, make/unmake (and the
    // null-move variants) push/pop entries describing the pieces that changed. The link
    // is not copied with the board: copies start detached.
    void attachAcc(nnue::AccStack* st);
    nnue::AccStack* accStack() const { return acc_.p; }

    Bitboard pieces[12];
    Bitboard occ[3];  // white, black, all
    Piece squares[64];
    Color side = WHITE;
    int castling = 0;
    int ep = NO_SQ;
    int halfmove = 0;
    int fullmove = 1;
    Key key = 0;
    // Incrementally updated material + piece-square sums (white - black) and
    // raw game phase (sum of piece phase weights, unclamped).
    int psqMg = 0, psqEg = 0, phaseRaw = 0;

private:
    struct Undo {
        Move move;
        Piece captured;
        int castling;
        int ep;
        int halfmove;
        Key key;
    };
    std::vector<Undo> history_;

    struct AccLink {
        nnue::AccStack* p = nullptr;
        AccLink() = default;
        AccLink(const AccLink&) {}
        AccLink& operator=(const AccLink&) {
            p = nullptr;
            return *this;
        }
    };
    AccLink acc_;

    void clear();
    void addPiece(int sq, Piece p);
    void removePiece(int sq);
    void movePiece(int from, int to);
};

} // namespace engine
