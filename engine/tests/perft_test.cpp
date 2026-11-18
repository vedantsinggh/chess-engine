// Perft regression test: verifies move generation against well-known node counts.
#include <chrono>
#include <cstdint>
#include <iostream>
#include <vector>

#include "engine/board.h"

namespace {

struct Case {
    const char* name;
    const char* fen;
    std::vector<uint64_t> expected;  // expected[d-1] = perft(d)
};

} // namespace

int main() {
    using namespace engine;
    initTables();
    const std::vector<Case> cases = {
        {"startpos", "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
         {20, 400, 8902, 197281, 4865609}},
        {"kiwipete", "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
         {48, 2039, 97862, 4085603}},
        {"position3", "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", {14, 191, 2812, 43238, 674624, 11030083}},
        {"position4", "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1",
         {6, 264, 9467, 422333, 15833292}},
        {"position5", "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8", {44, 1486, 62379, 2103487}},
    };

    int failures = 0;
    auto t0 = std::chrono::steady_clock::now();
    for (const Case& c : cases) {
        Board b;
        if (!b.setFen(c.fen)) {
            std::cout << "FAIL " << c.name << ": could not parse FEN\n";
            ++failures;
            continue;
        }
        const std::string before = b.fen();
        for (size_t d = 1; d <= c.expected.size(); ++d) {
            uint64_t n = b.perft(int(d));
            bool ok = n == c.expected[d - 1];
            std::cout << (ok ? "ok   " : "FAIL ") << c.name << " depth " << d << ": " << n;
            if (!ok) std::cout << " (expected " << c.expected[d - 1] << ")";
            std::cout << '\n';
            failures += !ok;
        }
        if (b.fen() != before || b.key != b.computeKey()) {
            std::cout << "FAIL " << c.name << ": board state not restored after perft\n";
            ++failures;
        }
    }
    auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - t0).count();
    std::cout << (failures ? "FAILED" : "All perft tests passed") << " in " << ms << " ms\n";
    return failures ? 1 : 0;
}
