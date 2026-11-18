// NNUE tests: incrementally updated accumulators must equal a full refresh along random
// games (including captures, promotions, castling, en passant and null moves), and the
// quantised integer output must match a floating-point reference within rounding error.
#include <cmath>
#include <cstdio>
#include <memory>
#include <random>
#include <string>
#include <vector>

#include "engine/board.h"
#include "engine/eval.h"
#include "engine/nnue.h"

using namespace engine;

namespace {

void putU32(std::vector<unsigned char>& v, uint32_t x) {
    for (int i = 0; i < 4; ++i) v.push_back(uint8_t(x >> (8 * i)));
}
void putI16(std::vector<unsigned char>& v, int x) {
    uint16_t u = uint16_t(int16_t(x));
    v.push_back(uint8_t(u & 0xFF));
    v.push_back(uint8_t(u >> 8));
}

std::vector<unsigned char> randomNet(uint64_t seed) {
    std::mt19937_64 rng(seed);
    std::uniform_int_distribution<int> ft(-70, 70), bias(-40, 120), out(-nnue::QB / 3, nnue::QB / 3),
        ob(-100000, 100000);
    std::vector<unsigned char> v;
    putU32(v, nnue::MAGIC);
    putU32(v, nnue::VERSION);
    putU32(v, nnue::INPUTS);
    putU32(v, nnue::HIDDEN);
    for (int i = 0; i < nnue::INPUTS * nnue::HIDDEN; ++i) putI16(v, ft(rng));
    for (int i = 0; i < nnue::HIDDEN; ++i) putI16(v, bias(rng));
    for (int i = 0; i < 2 * nnue::HIDDEN; ++i) putI16(v, out(rng));
    putU32(v, uint32_t(ob(rng)));
    return v;
}

int failures = 0;
void check(bool ok, const std::string& what) {
    if (!ok) {
        ++failures;
        if (failures < 20) std::printf("FAIL %s\n", what.c_str());
    }
}

} // namespace

int main() {
    initTables();
    std::string err;
    std::vector<unsigned char> net = randomNet(7);
    check(nnue::loadFromMemory(net.data(), net.size(), err), "load random net: " + err);
    std::vector<unsigned char> bad = net;
    bad[0] ^= 1;
    check(!nnue::loadFromMemory(bad.data(), bad.size(), err), "corrupt header rejected");
    check(!nnue::loadFromMemory(net.data(), net.size() - 2, err), "truncated net rejected");
    nnue::setEnabled(true);

    std::unique_ptr<nnue::AccStack> st(new nnue::AccStack());
    std::mt19937_64 rng(2024);
    const char* fens[] = {
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
        "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
        "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1",
        "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1",
        "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8",
    };
    long positions = 0;
    // Worst-case quantisation error: each squared activation is rounded by at most
    // 32 / QA^2 (float units), times |w_out|, summed over both perspectives; +2 cp for the
    // integer divisions.
    double tolerance = 2.0;
    for (int i = 0; i < 2 * nnue::HIDDEN; ++i)
        tolerance += nnue::SCALE * 32.0 / (double(nnue::QA) * nnue::QA) *
                     std::abs(nnue::network()->outWeights[i]) / double(nnue::QB);
    double maxFloatDiff = 0;
    for (int game = 0; game < 200; ++game) {
        Board b;
        b.setFen(fens[game % 5]);
        b.attachAcc(st.get());
        int made = 0;
        for (int ply = 0; ply < 160; ++ply) {
            MoveList l;
            b.generateLegal(l);
            if (!l.size) break;
            // Mostly random moves; prefer captures/promotions sometimes to exercise them.
            Move m = l.moves[rng() % uint64_t(l.size)];
            if (rng() % 3 == 0)
                for (int i = 0; i < l.size; ++i)
                    if (isCapture(l.moves[i]) || promoOf(l.moves[i])) m = l.moves[i];
            b.makeMove(m);
            ++made;
            // Only evaluate some plies so that lazy updates span several moves.
            if (rng() % 3 == 0) {
                const int inc = nnue::evaluate(b);
                check(nnue::accumulatorMatchesRefresh(b), "incremental == refresh at " + b.fen());
                Board copy = b;  // copies are detached: evaluated from scratch
                const int full = nnue::evaluate(copy);
                check(inc == full, "incremental eval == full eval at " + b.fen());
                const double ref = nnue::evaluateFloat(b);
                maxFloatDiff = std::max(maxFloatDiff, std::fabs(ref - inc));
                check(std::fabs(ref - inc) <= tolerance, "quantised vs float reference at " + b.fen() + ": " +
                                                       std::to_string(inc) + " vs " + std::to_string(ref));
                ++positions;
            }
            if (rng() % 10 == 0 && !b.inCheck()) {
                b.makeNullMove();
                check(nnue::accumulatorMatchesRefresh(b), "null move at " + b.fen());
                b.unmakeNullMove();
            }
            // Occasionally take back a few moves and continue from there.
            if (rng() % 15 == 0) {
                int back = int(rng() % 4);
                for (int i = 0; i < back && made > 0; ++i, --made) b.unmakeMove();
                check(nnue::accumulatorMatchesRefresh(b), "after unmake at " + b.fen());
            }
            // Illegal pseudo-legal moves are undone inside makeMove.
            MoveList pseudo;
            b.generatePseudo(pseudo);
            for (int i = 0; i < pseudo.size; ++i)
                if (!b.isLegal(pseudo.moves[i])) {
                    check(!b.makeMove(pseudo.moves[i]), "illegal move rejected");
                    break;
                }
        }
        check(nnue::accumulatorMatchesRefresh(b), "end of game");
    }
    // evaluate() dispatch: enabled -> NNUE, disabled -> HCE.
    Board b;
    check(evaluate(b) == nnue::evaluate(b), "evaluate() uses NNUE when enabled");
    nnue::setEnabled(false);
    check(evaluate(b) == evaluateHce(b), "evaluate() uses HCE when disabled");

    std::printf("%ld positions checked, max |int - float| = %.3f cp (bound %.1f cp)\n", positions, maxFloatDiff,
                tolerance);
    std::printf("%s\n", failures ? "NNUE tests FAILED" : "All NNUE tests passed");
    return failures ? 1 : 0;
}
