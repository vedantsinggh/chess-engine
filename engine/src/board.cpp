#include "engine/board.h"

#include "engine/nnue.h"

#include <cctype>
#include <cstring>
#include <mutex>
#include <random>
#include <sstream>

namespace engine {

// ---------------------------------------------------------------------------
// Attack tables
// ---------------------------------------------------------------------------
namespace detail {
Bitboard KNIGHT_ATT[64];
Bitboard KING_ATT[64];
Bitboard PAWN_ATT[2][64];
Magic ROOK_MAGICS[64];
Magic BISHOP_MAGICS[64];
} // namespace detail

namespace {

using detail::KING_ATT;
using detail::KNIGHT_ATT;
using detail::PAWN_ATT;

Bitboard ROOK_TABLE[0x19000];
Bitboard BISHOP_TABLE[0x1480];

// Directions: 0 N, 1 NE, 2 E, 3 SE, 4 S, 5 SW, 6 W, 7 NW
Bitboard RAYS[8][64];
const int DIR_DF[8] = {0, 1, 1, 1, 0, -1, -1, -1};
const int DIR_DR[8] = {1, 1, 0, -1, -1, -1, 0, 1};
// Rays pointing towards higher square indices use lsb for the first blocker.
const bool DIR_POSITIVE[8] = {true, true, true, false, false, false, false, true};

struct Zobrist {
    Key psq[12][64];
    Key castling[16];
    Key epFile[8];
    Key side;
} Z;

// castlingMask[sq]: rights that survive a move touching sq (from or to).
int CASTLE_MASK[64];


bool onBoard(int f, int r) { return f >= 0 && f < 8 && r >= 0 && r < 8; }

Bitboard rayAttack(int dir, int sq, Bitboard occ) {
    Bitboard a = RAYS[dir][sq];
    Bitboard blockers = a & occ;
    if (blockers) {
        int b = DIR_POSITIVE[dir] ? lsb(blockers) : msb(blockers);
        a ^= RAYS[dir][b];
    }
    return a;
}

Bitboard slowAttacks(const int* dirs, int sq, Bitboard occ) {
    Bitboard a = 0;
    for (int i = 0; i < 4; ++i) a |= rayAttack(dirs[i], sq, occ);
    return a;
}

// xorshift64* generator (deterministic magic search).
struct Prng {
    uint64_t s;
    uint64_t next() {
        s ^= s >> 12;
        s ^= s << 25;
        s ^= s >> 27;
        return s * 2685821657736338717ULL;
    }
    uint64_t sparse() { return next() & next() & next(); }
};

void initMagics(detail::Magic* magics, Bitboard* table, const int* dirs) {
    // Seeds per rank known to find magics quickly.
    static const uint64_t SEEDS[8] = {728, 10316, 55013, 32803, 12281, 15100, 16645, 255};
    static Bitboard occupancy[4096], reference[4096];
    static int epoch[4096];
    int cnt = 0;
    Bitboard* next = table;
    for (int sq = 0; sq < 64; ++sq) {
        detail::Magic& m = magics[sq];
        const int f = fileOf(sq), r = rankOf(sq);
        Bitboard edges = ((0xFFULL | 0xFF00000000000000ULL) & ~(0xFFULL << (8 * r))) |
                         ((0x0101010101010101ULL | 0x8080808080808080ULL) & ~(0x0101010101010101ULL << f));
        m.mask = slowAttacks(dirs, sq, 0) & ~edges;
        m.shift = unsigned(64 - popcount(m.mask));
        m.attacks = next;
        int size = 0;
        Bitboard b = 0;
        do {
            occupancy[size] = b;
            reference[size] = slowAttacks(dirs, sq, b);
            ++size;
            b = (b - m.mask) & m.mask;
        } while (b);
        for (int i = 0; i < size; ++i) epoch[i] = 0;
        Prng rng{SEEDS[r]};
        for (int i = 0; i < size;) {
            for (m.magic = 0; popcount((m.magic * m.mask) >> 56) < 6;) m.magic = rng.sparse();
            ++cnt;
            for (i = 0; i < size; ++i) {
                unsigned idx = m.index(occupancy[i]);
                if (epoch[idx] < cnt) {
                    epoch[idx] = cnt;
                    next[idx] = reference[i];
                } else if (next[idx] != reference[i]) {
                    break;
                }
            }
        }
        next += size;
    }
}

void initTablesOnce() {
    for (int sq = 0; sq < 64; ++sq) {
        int f = fileOf(sq), r = rankOf(sq);
        const int kn[8][2] = {{1, 2}, {2, 1}, {2, -1}, {1, -2}, {-1, -2}, {-2, -1}, {-2, 1}, {-1, 2}};
        KNIGHT_ATT[sq] = 0;
        for (auto& d : kn)
            if (onBoard(f + d[0], r + d[1])) KNIGHT_ATT[sq] |= bit(makeSquare(f + d[0], r + d[1]));
        KING_ATT[sq] = 0;
        for (int df = -1; df <= 1; ++df)
            for (int dr = -1; dr <= 1; ++dr)
                if ((df || dr) && onBoard(f + df, r + dr)) KING_ATT[sq] |= bit(makeSquare(f + df, r + dr));
        PAWN_ATT[WHITE][sq] = PAWN_ATT[BLACK][sq] = 0;
        for (int df : {-1, 1}) {
            if (onBoard(f + df, r + 1)) PAWN_ATT[WHITE][sq] |= bit(makeSquare(f + df, r + 1));
            if (onBoard(f + df, r - 1)) PAWN_ATT[BLACK][sq] |= bit(makeSquare(f + df, r - 1));
        }
        for (int d = 0; d < 8; ++d) {
            RAYS[d][sq] = 0;
            int ff = f + DIR_DF[d], rr = r + DIR_DR[d];
            while (onBoard(ff, rr)) {
                RAYS[d][sq] |= bit(makeSquare(ff, rr));
                ff += DIR_DF[d];
                rr += DIR_DR[d];
            }
        }
        CASTLE_MASK[sq] = 15;
    }
    static const int ROOK_DIRS[4] = {0, 2, 4, 6};
    static const int BISHOP_DIRS[4] = {1, 3, 5, 7};
    initMagics(detail::ROOK_MAGICS, ROOK_TABLE, ROOK_DIRS);
    initMagics(detail::BISHOP_MAGICS, BISHOP_TABLE, BISHOP_DIRS);
    CASTLE_MASK[4] &= ~(WHITE_OO | WHITE_OOO);   // e1
    CASTLE_MASK[0] &= ~WHITE_OOO;                // a1
    CASTLE_MASK[7] &= ~WHITE_OO;                 // h1
    CASTLE_MASK[60] &= ~(BLACK_OO | BLACK_OOO);  // e8
    CASTLE_MASK[56] &= ~BLACK_OOO;               // a8
    CASTLE_MASK[63] &= ~BLACK_OO;                // h8

    std::mt19937_64 rng(0x9E3779B97F4A7C15ULL);
    for (auto& p : Z.psq)
        for (auto& k : p) k = rng();
    for (auto& k : Z.castling) k = rng();
    for (auto& k : Z.epFile) k = rng();
    Z.side = rng();
    initEvalTables();
    nnue::init();
}

} // namespace

void initTables() {
    static std::once_flag once;
    std::call_once(once, initTablesOnce);
}

void Board::attachAcc(nnue::AccStack* st) {
    acc_.p = st;
    if (!st) return;
    st->top = 0;
    st->overflow = 0;
    st->acc[0].computed = false;
    nnue::refresh(*this, *st);
}


// ---------------------------------------------------------------------------
// Board basics
// ---------------------------------------------------------------------------
const char* Board::START_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";

static const char PIECE_CHARS[] = "PNBRQKpnbrqk";

Board::Board() {
    initTables();
    setFen(START_FEN);
}

void Board::clear() {
    for (auto& b : pieces) b = 0;
    for (auto& b : occ) b = 0;
    for (auto& s : squares) s = NO_PIECE;
    side = WHITE;
    castling = 0;
    ep = NO_SQ;
    halfmove = 0;
    fullmove = 1;
    key = 0;
    psqMg = psqEg = phaseRaw = 0;
    history_.clear();
}

void Board::addPiece(int sq, Piece p) {
    Bitboard b = bit(sq);
    pieces[p] |= b;
    occ[colorOf(p)] |= b;
    occ[2] |= b;
    squares[sq] = p;
    key ^= Z.psq[p][sq];
    psqMg += detail::PSQ_MG[p][sq];
    psqEg += detail::PSQ_EG[p][sq];
    phaseRaw += detail::PHASE_INC[p];
}

void Board::removePiece(int sq) {
    Piece p = squares[sq];
    Bitboard b = bit(sq);
    pieces[p] &= ~b;
    occ[colorOf(p)] &= ~b;
    occ[2] &= ~b;
    squares[sq] = NO_PIECE;
    key ^= Z.psq[p][sq];
    psqMg -= detail::PSQ_MG[p][sq];
    psqEg -= detail::PSQ_EG[p][sq];
    phaseRaw -= detail::PHASE_INC[p];
}

void Board::movePiece(int from, int to) {
    Piece p = squares[from];
    Bitboard fb = bit(from) | bit(to);
    pieces[p] ^= fb;
    occ[colorOf(p)] ^= fb;
    occ[2] ^= fb;
    squares[from] = NO_PIECE;
    squares[to] = p;
    key ^= Z.psq[p][from] ^ Z.psq[p][to];
    psqMg += detail::PSQ_MG[p][to] - detail::PSQ_MG[p][from];
    psqEg += detail::PSQ_EG[p][to] - detail::PSQ_EG[p][from];
}

Key Board::computeKey() const {
    Key k = 0;
    for (int sq = 0; sq < 64; ++sq)
        if (squares[sq] != NO_PIECE) k ^= Z.psq[squares[sq]][sq];
    k ^= Z.castling[castling];
    if (ep != NO_SQ) k ^= Z.epFile[fileOf(ep)];
    if (side == BLACK) k ^= Z.side;
    return k;
}

// ---------------------------------------------------------------------------
// FEN
// ---------------------------------------------------------------------------
bool Board::setFen(const std::string& fenStr) {
    std::istringstream ss(fenStr);
    std::string placement, stm, cast = "-", eps = "-";
    int hm = 0, fm = 1;
    if (!(ss >> placement >> stm)) return false;
    ss >> cast >> eps;
    if (!(ss >> hm)) hm = 0;
    if (!(ss >> fm)) fm = 1;

    // Validate placement before touching state.
    {
        int rank = 7, file = 0;
        int kings[2] = {0, 0};
        for (char c : placement) {
            if (c == '/') {
                if (file != 8 || rank == 0) return false;
                --rank;
                file = 0;
            } else if (std::isdigit(static_cast<unsigned char>(c))) {
                file += c - '0';
                if (file > 8) return false;
            } else {
                const char* p = std::strchr(PIECE_CHARS, c);
                if (!p || !*p || file >= 8) return false;
                int idx = int(p - PIECE_CHARS);
                if (idx == WK) ++kings[0];
                if (idx == BK) ++kings[1];
                ++file;
            }
        }
        if (rank != 0 || file != 8 || kings[0] != 1 || kings[1] != 1) return false;
        if (stm != "w" && stm != "b") return false;
    }

    clear();
    int rank = 7, file = 0;
    for (char c : placement) {
        if (c == '/') {
            --rank;
            file = 0;
        } else if (std::isdigit(static_cast<unsigned char>(c))) {
            file += c - '0';
        } else {
            int idx = int(std::strchr(PIECE_CHARS, c) - PIECE_CHARS);
            addPiece(makeSquare(file, rank), Piece(idx));
            ++file;
        }
    }
    side = stm == "w" ? WHITE : BLACK;
    for (char c : cast) {
        if (c == 'K' && squares[4] == WK && squares[7] == WR) castling |= WHITE_OO;
        if (c == 'Q' && squares[4] == WK && squares[0] == WR) castling |= WHITE_OOO;
        if (c == 'k' && squares[60] == BK && squares[63] == BR) castling |= BLACK_OO;
        if (c == 'q' && squares[60] == BK && squares[56] == BR) castling |= BLACK_OOO;
    }
    ep = NO_SQ;
    if (eps.size() == 2 && eps[0] >= 'a' && eps[0] <= 'h' && (eps[1] == '3' || eps[1] == '6')) {
        int sq = makeSquare(eps[0] - 'a', eps[1] - '1');
        // Only keep the square if a pawn of the side to move can actually capture there.
        if (pawnAttacks(~side, sq) & pieces[makePiece(side, PAWN)]) ep = sq;
    }
    halfmove = hm < 0 ? 0 : hm;
    fullmove = fm < 1 ? 1 : fm;
    key = computeKey();
    if (acc_.p) attachAcc(acc_.p);
    return true;
}

std::string Board::fen() const {
    std::string s;
    for (int r = 7; r >= 0; --r) {
        int empty = 0;
        for (int f = 0; f < 8; ++f) {
            Piece p = squares[makeSquare(f, r)];
            if (p == NO_PIECE) {
                ++empty;
            } else {
                if (empty) s += char('0' + empty);
                empty = 0;
                s += PIECE_CHARS[p];
            }
        }
        if (empty) s += char('0' + empty);
        if (r) s += '/';
    }
    s += side == WHITE ? " w " : " b ";
    std::string c;
    if (castling & WHITE_OO) c += 'K';
    if (castling & WHITE_OOO) c += 'Q';
    if (castling & BLACK_OO) c += 'k';
    if (castling & BLACK_OOO) c += 'q';
    s += c.empty() ? "-" : c;
    s += ' ';
    if (ep == NO_SQ) {
        s += '-';
    } else {
        s += char('a' + fileOf(ep));
        s += char('1' + rankOf(ep));
    }
    s += ' ' + std::to_string(halfmove) + ' ' + std::to_string(fullmove);
    return s;
}

std::string Board::pretty() const {
    std::ostringstream os;
    os << " +---+---+---+---+---+---+---+---+\n";
    for (int r = 7; r >= 0; --r) {
        for (int f = 0; f < 8; ++f) {
            Piece p = squares[makeSquare(f, r)];
            os << " | " << (p == NO_PIECE ? ' ' : PIECE_CHARS[p]);
        }
        os << " | " << (r + 1) << "\n +---+---+---+---+---+---+---+---+\n";
    }
    os << "   a   b   c   d   e   f   g   h\n\n";
    os << "Fen: " << fen() << "\n";
    os << "Key: " << std::hex << std::uppercase << key << std::dec << "\n";
    os << "Checkers: " << (inCheck() ? "yes" : "none") << "\n";
    return os.str();
}

// ---------------------------------------------------------------------------
// Attacks
// ---------------------------------------------------------------------------
bool Board::isAttacked(int sq, Color by) const {
    if (pawnAttacks(~by, sq) & pieces[makePiece(by, PAWN)]) return true;
    if (knightAttacks(sq) & pieces[makePiece(by, KNIGHT)]) return true;
    if (kingAttacks(sq) & pieces[makePiece(by, KING)]) return true;
    Bitboard bq = pieces[makePiece(by, BISHOP)] | pieces[makePiece(by, QUEEN)];
    if (bq && (bishopAttacks(sq, occ[2]) & bq)) return true;
    Bitboard rq = pieces[makePiece(by, ROOK)] | pieces[makePiece(by, QUEEN)];
    if (rq && (rookAttacks(sq, occ[2]) & rq)) return true;
    return false;
}

// ---------------------------------------------------------------------------
// Make / unmake
// ---------------------------------------------------------------------------
bool Board::makeMove(Move m) {
    const int from = fromSq(m), to = toSq(m);
    const uint32_t fl = flagsOf(m);
    const Color us = side, them = ~side;
    const Piece p = squares[from];

    Undo u{m, NO_PIECE, castling, ep, halfmove, key};
    nnue::DirtyPiece* dirty = acc_.p ? acc_.p->push() : nullptr;

    if (ep != NO_SQ) key ^= Z.epFile[fileOf(ep)];
    ep = NO_SQ;
    ++halfmove;

    if (fl & F_EP) {
        int capSq = to + (us == WHITE ? -8 : 8);
        u.captured = squares[capSq];
        removePiece(capSq);
        if (dirty) dirty->add(u.captured, capSq, NO_SQ);
    } else if (squares[to] != NO_PIECE) {
        u.captured = squares[to];
        removePiece(to);
        halfmove = 0;
        if (dirty) dirty->add(u.captured, to, NO_SQ);
    }
    movePiece(from, to);
    if (dirty) dirty->add(p, from, to);

    if (typeOf(p) == PAWN) {
        halfmove = 0;
        if (int promo = promoOf(m)) {
            removePiece(to);
            addPiece(to, makePiece(us, PieceType(promo)));
            if (dirty) {
                dirty->to[dirty->n - 1] = NO_SQ;  // the pawn disappears ...
                dirty->add(makePiece(us, PieceType(promo)), NO_SQ, to);  // ... and the new piece appears
            }
        } else if (fl & F_DOUBLE) {
            int epSq = (from + to) / 2;
            if (pawnAttacks(us, epSq) & pieces[makePiece(them, PAWN)]) {
                ep = epSq;
                key ^= Z.epFile[fileOf(ep)];
            }
        }
    } else if (fl & F_CASTLE) {
        int rf = NO_SQ, rt = NO_SQ;
        switch (to) {
            case 6: rf = 7, rt = 5; break;     // g1: h1 -> f1
            case 2: rf = 0, rt = 3; break;     // c1: a1 -> d1
            case 62: rf = 63, rt = 61; break;  // g8: h8 -> f8
            case 58: rf = 56, rt = 59; break;  // c8: a8 -> d8
            default: break;
        }
        if (rf != NO_SQ) {
            movePiece(rf, rt);
            if (dirty) dirty->add(makePiece(us, ROOK), rf, rt);
        }
    }

    key ^= Z.castling[castling];
    castling &= CASTLE_MASK[from] & CASTLE_MASK[to];
    key ^= Z.castling[castling];

    if (us == BLACK) ++fullmove;
    side = them;
    key ^= Z.side;
    history_.push_back(u);

    if (isAttacked(kingSquare(us), them)) {
        unmakeMove();
        return false;
    }
    return true;
}

void Board::unmakeMove() {
    const Undo u = history_.back();
    history_.pop_back();
    if (acc_.p) acc_.p->pop();
    side = ~side;
    const Color us = side;
    const Move m = u.move;
    const int from = fromSq(m), to = toSq(m);

    if (promoOf(m)) {
        removePiece(to);
        addPiece(to, makePiece(us, PAWN));
    }
    movePiece(to, from);
    if (flagsOf(m) & F_CASTLE) {
        switch (to) {
            case 6: movePiece(5, 7); break;
            case 2: movePiece(3, 0); break;
            case 62: movePiece(61, 63); break;
            case 58: movePiece(59, 56); break;
            default: break;
        }
    }
    if (u.captured != NO_PIECE) {
        int capSq = (flagsOf(m) & F_EP) ? to + (us == WHITE ? -8 : 8) : to;
        addPiece(capSq, u.captured);
    }
    castling = u.castling;
    ep = u.ep;
    halfmove = u.halfmove;
    key = u.key;
    if (us == BLACK) --fullmove;
}

void Board::makeNullMove() {
    history_.push_back(Undo{NULL_MOVE, NO_PIECE, castling, ep, halfmove, key});
    if (acc_.p) acc_.p->push();  // no pieces change
    if (ep != NO_SQ) key ^= Z.epFile[fileOf(ep)];
    ep = NO_SQ;
    halfmove = 0;  // a null move breaks repetition chains
    side = ~side;
    key ^= Z.side;
}

void Board::unmakeNullMove() {
    const Undo u = history_.back();
    history_.pop_back();
    if (acc_.p) acc_.p->pop();
    side = ~side;
    ep = u.ep;
    halfmove = u.halfmove;
    key = u.key;
}

// ---------------------------------------------------------------------------
// Move generation
// ---------------------------------------------------------------------------
void Board::generatePseudo(MoveList& list, bool capturesOnly) const {
    const Color us = side, them = ~side;
    const Bitboard own = occ[us], enemy = occ[them], all = occ[2];
    const int up = us == WHITE ? 8 : -8;
    const int startRank = us == WHITE ? 1 : 6;
    const int promoRank = us == WHITE ? 7 : 0;

    auto addPawnMove = [&](int from, int to, uint32_t flags) {
        if (rankOf(to) == promoRank) {
            list.push(encodeMove(from, to, QUEEN, flags));
            if (!capturesOnly) {
                list.push(encodeMove(from, to, KNIGHT, flags));
                list.push(encodeMove(from, to, ROOK, flags));
                list.push(encodeMove(from, to, BISHOP, flags));
            }
        } else {
            list.push(encodeMove(from, to, 0, flags));
        }
    };

    // Pawns
    Bitboard pawns = pieces[makePiece(us, PAWN)];
    while (pawns) {
        int from = popLsb(pawns);
        int to = from + up;
        if (!(all & bit(to))) {
            if (!capturesOnly || rankOf(to) == promoRank) addPawnMove(from, to, F_NONE);
            if (!capturesOnly && rankOf(from) == startRank && !(all & bit(to + up)))
                list.push(encodeMove(from, to + up, 0, F_DOUBLE));
        }
        Bitboard caps = pawnAttacks(us, from) & enemy;
        while (caps) addPawnMove(from, popLsb(caps), F_CAPTURE);
        if (ep != NO_SQ && (pawnAttacks(us, from) & bit(ep))) list.push(encodeMove(from, ep, 0, F_EP));
    }

    const Bitboard targetMask = capturesOnly ? enemy : ~own;
    auto addTargets = [&](int from, Bitboard targets) {
        targets &= targetMask;
        while (targets) {
            int to = popLsb(targets);
            list.push(encodeMove(from, to, 0, (enemy & bit(to)) ? F_CAPTURE : F_NONE));
        }
    };

    Bitboard bb = pieces[makePiece(us, KNIGHT)];
    while (bb) {
        int s = popLsb(bb);
        addTargets(s, knightAttacks(s));
    }
    bb = pieces[makePiece(us, BISHOP)];
    while (bb) {
        int s = popLsb(bb);
        addTargets(s, bishopAttacks(s, all));
    }
    bb = pieces[makePiece(us, ROOK)];
    while (bb) {
        int s = popLsb(bb);
        addTargets(s, rookAttacks(s, all));
    }
    bb = pieces[makePiece(us, QUEEN)];
    while (bb) {
        int s = popLsb(bb);
        addTargets(s, bishopAttacks(s, all) | rookAttacks(s, all));
    }
    int ksq = kingSquare(us);
    addTargets(ksq, kingAttacks(ksq));

    if (capturesOnly) return;

    // Castling: rights guarantee king/rook are on their home squares.
    if (us == WHITE) {
        if ((castling & WHITE_OO) && !(all & (bit(5) | bit(6))) && !isAttacked(4, them) &&
            !isAttacked(5, them) && !isAttacked(6, them))
            list.push(encodeMove(4, 6, 0, F_CASTLE));
        if ((castling & WHITE_OOO) && !(all & (bit(1) | bit(2) | bit(3))) && !isAttacked(4, them) &&
            !isAttacked(3, them) && !isAttacked(2, them))
            list.push(encodeMove(4, 2, 0, F_CASTLE));
    } else {
        if ((castling & BLACK_OO) && !(all & (bit(61) | bit(62))) && !isAttacked(60, them) &&
            !isAttacked(61, them) && !isAttacked(62, them))
            list.push(encodeMove(60, 62, 0, F_CASTLE));
        if ((castling & BLACK_OOO) && !(all & (bit(57) | bit(58) | bit(59))) && !isAttacked(60, them) &&
            !isAttacked(59, them) && !isAttacked(58, them))
            list.push(encodeMove(60, 58, 0, F_CASTLE));
    }
}

bool Board::isLegal(Move m) const {
    if (flagsOf(m) & F_CASTLE) return true;  // the generator already checked the path
    const Color us = side, them = ~side;
    const int from = fromSq(m), to = toSq(m);
    int ksq = kingSquare(us);
    Bitboard occAfter = (occ[2] ^ bit(from)) | bit(to);
    Bitboard captured = bit(to);
    if (flagsOf(m) & F_EP) {
        int capSq = to + (us == WHITE ? -8 : 8);
        occAfter ^= bit(capSq);
        captured = bit(capSq);
    }
    if (from == ksq) ksq = to;
    const Bitboard keep = ~captured;
    if (pawnAttacks(us, ksq) & pieces[makePiece(them, PAWN)] & keep) return false;
    if (knightAttacks(ksq) & pieces[makePiece(them, KNIGHT)] & keep) return false;
    if (kingAttacks(ksq) & pieces[makePiece(them, KING)]) return false;
    const Bitboard bq = (pieces[makePiece(them, BISHOP)] | pieces[makePiece(them, QUEEN)]) & keep;
    if (bq && (bishopAttacks(ksq, occAfter) & bq)) return false;
    const Bitboard rq = (pieces[makePiece(them, ROOK)] | pieces[makePiece(them, QUEEN)]) & keep;
    if (rq && (rookAttacks(ksq, occAfter) & rq)) return false;
    return true;
}

bool Board::isPseudoLegal(Move m) const {
    if (m == NULL_MOVE) return false;
    const int from = fromSq(m), to = toSq(m);
    const Piece p = squares[from];
    if (p == NO_PIECE || colorOf(p) != side || (occ[side] & bit(to))) return false;
    const PieceType pt = typeOf(p);
    if (pt != PAWN && pt != KING) {
        if (promoOf(m)) return false;
        const Bitboard all = occ[2];
        Bitboard att = pt == KNIGHT   ? knightAttacks(from)
                       : pt == BISHOP ? bishopAttacks(from, all)
                       : pt == ROOK   ? rookAttacks(from, all)
                                      : bishopAttacks(from, all) | rookAttacks(from, all);
        if (!(att & bit(to))) return false;
        return m == encodeMove(from, to, 0, (occ[~side] & bit(to)) ? F_CAPTURE : F_NONE);
    }
    // Pawns and kings (promotions, en passant, castling): compare against the generator.
    MoveList list;
    generatePseudo(list);
    for (int i = 0; i < list.size; ++i)
        if (list.moves[i] == m) return true;
    return false;
}

void Board::generateLegal(MoveList& list) {
    MoveList pseudo;
    generatePseudo(pseudo);
    list.size = 0;
    for (int i = 0; i < pseudo.size; ++i)
        if (isLegal(pseudo.moves[i])) list.push(pseudo.moves[i]);
}

// ---------------------------------------------------------------------------
// Draw detection
// ---------------------------------------------------------------------------
int Board::repetitionCount() const {
    int count = 0;
    int n = int(history_.size());
    int limit = halfmove < n ? halfmove : n;
    // Positions with the same side to move are 2, 4, ... plies back.
    for (int i = 2; i <= limit; i += 2)
        if (history_[n - i].key == key) ++count;
    return count;
}

bool Board::isRepetition() const {
    int n = int(history_.size());
    int limit = halfmove < n ? halfmove : n;
    for (int i = 4; i <= limit; i += 2)
        if (history_[n - i].key == key) return true;
    return false;
}

bool Board::isInsufficientMaterial() const {
    if (pieces[WP] | pieces[BP] | pieces[WR] | pieces[BR] | pieces[WQ] | pieces[BQ]) return false;
    int minors = popcount(pieces[WN] | pieces[BN] | pieces[WB] | pieces[BB]);
    if (minors <= 1) return true;
    // Only bishops, all on the same colour complex.
    if (!(pieces[WN] | pieces[BN])) {
        const Bitboard DARK = 0xAA55AA55AA55AA55ULL;
        Bitboard bishops = pieces[WB] | pieces[BB];
        if (!(bishops & DARK) || !(bishops & ~DARK)) return true;
    }
    return false;
}

bool Board::hasNonPawnMaterial(Color c) const {
    return (pieces[makePiece(c, KNIGHT)] | pieces[makePiece(c, BISHOP)] | pieces[makePiece(c, ROOK)] |
            pieces[makePiece(c, QUEEN)]) != 0;
}

// ---------------------------------------------------------------------------
// Perft / UCI move strings
// ---------------------------------------------------------------------------
uint64_t Board::perft(int depth) {
    if (depth <= 0) return 1;
    MoveList list;
    generatePseudo(list);
    uint64_t nodes = 0;
    if (depth == 1) {
        // Bulk counting: legality test without making the moves.
        for (int i = 0; i < list.size; ++i) nodes += isLegal(list.moves[i]);
        return nodes;
    }
    for (int i = 0; i < list.size; ++i) {
        if (!makeMove(list.moves[i])) continue;
        nodes += perft(depth - 1);
        unmakeMove();
    }
    return nodes;
}

std::string Board::moveToUci(Move m) const {
    if (m == NULL_MOVE) return "0000";
    std::string s;
    s += char('a' + fileOf(fromSq(m)));
    s += char('1' + rankOf(fromSq(m)));
    s += char('a' + fileOf(toSq(m)));
    s += char('1' + rankOf(toSq(m)));
    if (int p = promoOf(m)) s += "pnbrqk"[p];
    return s;
}

Move Board::parseUciMove(const std::string& s) {
    MoveList list;
    generateLegal(list);
    for (int i = 0; i < list.size; ++i)
        if (moveToUci(list.moves[i]) == s) return list.moves[i];
    return NULL_MOVE;
}

} // namespace engine
