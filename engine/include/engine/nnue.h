#pragma once

// NNUE evaluation: (768 -> HIDDEN) x 2 perspectives -> 1, SCReLU activation.
//
// Inputs: 12 piece types x 64 squares, seen from each side ("us"/"them" piece colour,
// squares flipped vertically for black). The two HIDDEN-wide accumulators (side to move
// first) are concatenated and fed to a single output neuron.
// Quantisation: feature weights/biases * QA (int16), output weights * QB (int16), output
// bias * QA * QB (int32); eval = output * SCALE / (QA * QB) centipawns. The squared
// activations clamp(x, 0, QA)^2 are rounded to multiples of 64 (10 bits) so that the
// output layer is an int16 x int16 -> int32 multiply-add.
//
// Accumulators are kept on a per-thread stack (AccStack) attached to a Board. The board
// records which pieces moved in makeMove/makeNullMove ("dirty pieces") and the
// accumulators are brought up to date lazily when a position is evaluated.

#include <cstddef>
#include <cstdint>
#include <string>

#include "engine/types.h"

namespace engine {

class Board;

namespace nnue {

constexpr int INPUTS = 768;
constexpr int HIDDEN = 256;
constexpr int QA = 255;
constexpr int QB = 256;
constexpr int SCALE = 400;

// File layout (little-endian): u32 magic 'RNK1', u32 version (1), u32 inputs, u32 hidden,
// i16 ftWeights[INPUTS][HIDDEN], i16 ftBias[HIDDEN], i16 outWeights[2 * HIDDEN], i32 outBias.
constexpr uint32_t MAGIC = 0x314B4E52;  // "RNK1"
constexpr uint32_t VERSION = 1;

struct alignas(64) Network {
    int16_t ftWeights[INPUTS * HIDDEN];
    int16_t ftBias[HIDDEN];
    int16_t outWeights[2 * HIDDEN];
    int32_t outBias;
};

inline int featureIndex(int perspective, int piece, int sq) {
    // piece = engine::Piece (WP..BK); colour relative to the perspective.
    const int color = piece / 6, type = piece % 6;
    const int rel = color == perspective ? 0 : 1;
    const int s = perspective == 0 ? sq : sq ^ 56;
    return (rel * 6 + type) * 64 + s;
}

// Changes made by one move: up to 3 pieces (move/capture/promotion, castling rook).
// from == NO_SQ: piece added at `to`; to == NO_SQ: piece removed from `from`.
struct DirtyPiece {
    int n = 0;
    int piece[3];
    int from[3];
    int to[3];
    void add(int p, int f, int t) {
        piece[n] = p;
        from[n] = f;
        to[n] = t;
        ++n;
    }
};

struct alignas(64) Accumulator {
    int16_t v[2][HIDDEN];  // [perspective: white, black]
    DirtyPiece dirty;      // changes from the previous stack entry to this one
    bool computed = false;
};

struct AccStack {
    static constexpr int SIZE = MAX_PLY + 64;
    Accumulator acc[SIZE];
    int top = 0;
    int overflow = 0;  // pushes beyond SIZE (evaluation then refreshes from scratch)

    DirtyPiece* push() {
        if (overflow || top + 1 >= SIZE) {
            ++overflow;
            return nullptr;
        }
        ++top;
        acc[top].computed = false;
        acc[top].dirty.n = 0;
        return &acc[top].dirty;
    }
    void pop() {
        if (overflow) --overflow;
        else if (top > 0) --top;
    }
};

// Network management (not thread-safe w.r.t. running searches; callers stop searching first).
bool available();            // a network is loaded
bool enabled();              // available() && "Use NNUE"
void setEnabled(bool on);
bool defaultEnabled();       // compile-time default of "Use NNUE"
bool loadFile(const std::string& path, std::string& error);
bool loadEmbedded();         // false if no net was embedded at build time
bool loadFromMemory(const void* data, size_t size, std::string& error);
const char* embeddedName();  // file name of the embedded net ("" if none)
std::string currentName();   // name/path of the loaded net
const Network* network();

// Initialises from the embedded net (called once by initTables()).
void init();

// Rebuilds stack entry `top` of `st` from the board (used when attaching a stack).
void refresh(const Board& b, AccStack& st);
// Evaluation in centipawns from the side to move's perspective. Uses the board's
// attached accumulator stack when present, otherwise computes from scratch.
int evaluate(const Board& b);
// Same network, computed from scratch with floating point (test reference).
double evaluateFloat(const Board& b);
// Testing helper: true if the board's incremental accumulator equals a full refresh.
bool accumulatorMatchesRefresh(const Board& b);

} // namespace nnue
} // namespace engine
