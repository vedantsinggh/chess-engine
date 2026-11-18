#include "engine/nnue.h"

#include <algorithm>
#include <cstring>
#include <fstream>
#include <memory>
#include <vector>

#include "engine/board.h"

// Generated at build time from the default .nnue file (see CMakeLists.txt / cmake/embed_net.cmake).
namespace engine {
namespace nnue {
namespace embedded {
extern const unsigned char data[];
extern const size_t size;
extern const char name[];
} // namespace embedded
} // namespace nnue
} // namespace engine

#ifndef RANK_NNUE_DEFAULT
#define RANK_NNUE_DEFAULT 0
#endif

namespace engine {
namespace nnue {

namespace {

std::unique_ptr<Network> gNet;
bool gEnabled = RANK_NNUE_DEFAULT != 0;
std::string gName;

inline int16_t readI16(const unsigned char* p) { return int16_t(uint16_t(p[0]) | (uint16_t(p[1]) << 8)); }
inline uint32_t readU32(const unsigned char* p) {
    return uint32_t(p[0]) | (uint32_t(p[1]) << 8) | (uint32_t(p[2]) << 16) | (uint32_t(p[3]) << 24);
}

constexpr size_t HEADER_BYTES = 16;
constexpr int ACT_SHIFT = 6;
constexpr size_t PARAM_COUNT = size_t(INPUTS) * HIDDEN + HIDDEN + 2 * HIDDEN + 1;
constexpr size_t FILE_BYTES = HEADER_BYTES + (PARAM_COUNT - 1) * 2 + 4;

inline void addFeature(int16_t* __restrict v, const int16_t* __restrict w) {
    for (int i = 0; i < HIDDEN; ++i) v[i] = int16_t(v[i] + w[i]);
}

// dst = src + sum(adds) - sum(subs), fused for the common move shapes.
void applyDelta(const int16_t* __restrict src, int16_t* __restrict dst, const int16_t* const* adds, int na,
                const int16_t* const* subs, int ns) {
    if (na == 1 && ns == 1) {
        const int16_t *a = adds[0], *s = subs[0];
        for (int i = 0; i < HIDDEN; ++i) dst[i] = int16_t(src[i] + a[i] - s[i]);
    } else if (na == 1 && ns == 2) {
        const int16_t *a = adds[0], *s0 = subs[0], *s1 = subs[1];
        for (int i = 0; i < HIDDEN; ++i) dst[i] = int16_t(src[i] + a[i] - s0[i] - s1[i]);
    } else if (na == 2 && ns == 2) {
        const int16_t *a0 = adds[0], *a1 = adds[1], *s0 = subs[0], *s1 = subs[1];
        for (int i = 0; i < HIDDEN; ++i) dst[i] = int16_t(src[i] + a0[i] + a1[i] - s0[i] - s1[i]);
    } else {
        std::memcpy(dst, src, sizeof(int16_t) * HIDDEN);
        for (int k = 0; k < na; ++k)
            for (int i = 0; i < HIDDEN; ++i) dst[i] = int16_t(dst[i] + adds[k][i]);
        for (int k = 0; k < ns; ++k)
            for (int i = 0; i < HIDDEN; ++i) dst[i] = int16_t(dst[i] - subs[k][i]);
    }
}

void refreshAcc(const Network& net, const Board& b, int16_t (&v)[2][HIDDEN]) {
    for (int p = 0; p < 2; ++p) {
        std::memcpy(v[p], net.ftBias, sizeof(net.ftBias));
        Bitboard bb = b.occ[2];
        while (bb) {
            int sq = popLsb(bb);
            addFeature(v[p], &net.ftWeights[size_t(featureIndex(p, b.squares[sq], sq)) * HIDDEN]);
        }
    }
}

void updateStack(const Network& net, AccStack& st) {
    int k = st.top;
    while (k > 0 && !st.acc[k].computed) --k;
    for (int i = k + 1; i <= st.top; ++i) {
        const Accumulator& prev = st.acc[i - 1];
        Accumulator& cur = st.acc[i];
        const DirtyPiece& d = cur.dirty;
        for (int p = 0; p < 2; ++p) {
            const int16_t* adds[3];
            const int16_t* subs[3];
            int na = 0, ns = 0;
            for (int j = 0; j < d.n; ++j) {
                if (d.from[j] != NO_SQ)
                    subs[ns++] = &net.ftWeights[size_t(featureIndex(p, d.piece[j], d.from[j])) * HIDDEN];
                if (d.to[j] != NO_SQ)
                    adds[na++] = &net.ftWeights[size_t(featureIndex(p, d.piece[j], d.to[j])) * HIDDEN];
            }
            applyDelta(prev.v[p], cur.v[p], adds, na, subs, ns);
        }
        cur.computed = true;
    }
}

int output(const Network& net, const int16_t* us, const int16_t* them) {
    int32_t sum = 0;
    const int16_t* w0 = net.outWeights;
    const int16_t* w1 = net.outWeights + HIDDEN;
    // SCReLU: a = round(clamp(x, 0, QA)^2 / 64) <= 1016 fits in int16, so a * w is a
    // 16x16->32 multiply-add; with |w| <= 2 * QB the sum stays below 2^29 (no overflow).
    for (int i = 0; i < HIDDEN; ++i) {
        uint16_t c = uint16_t(std::min<int>(std::max<int>(us[i], 0), QA));
        int16_t a = int16_t((uint32_t(c * c) + 32) >> ACT_SHIFT);
        sum += int32_t(a) * int32_t(w0[i]);
    }
    for (int i = 0; i < HIDDEN; ++i) {
        uint16_t c = uint16_t(std::min<int>(std::max<int>(them[i], 0), QA));
        int16_t a = int16_t((uint32_t(c * c) + 32) >> ACT_SHIFT);
        sum += int32_t(a) * int32_t(w1[i]);
    }
    // sum is in units of QA^2 * QB / 64; bring it to QA * QB.
    const int64_t v = int64_t(sum) * (1 << ACT_SHIFT) / QA + net.outBias;
    return int(v * SCALE / (int64_t(QA) * QB));
}

} // namespace

bool available() { return gNet != nullptr; }
bool enabled() { return gEnabled && gNet != nullptr; }
void setEnabled(bool on) { gEnabled = on; }
bool defaultEnabled() { return RANK_NNUE_DEFAULT != 0; }
const Network* network() { return gNet.get(); }
const char* embeddedName() { return embedded::size ? embedded::name : ""; }
std::string currentName() { return gName; }

bool loadFromMemory(const void* data, size_t size, std::string& error) {
    const unsigned char* p = static_cast<const unsigned char*>(data);
    if (size != FILE_BYTES) {
        error = "unexpected size " + std::to_string(size) + " (expected " + std::to_string(FILE_BYTES) + ")";
        return false;
    }
    if (readU32(p) != MAGIC || readU32(p + 4) != VERSION || readU32(p + 8) != uint32_t(INPUTS) ||
        readU32(p + 12) != uint32_t(HIDDEN)) {
        error = "bad header (not a Rank 768x" + std::to_string(HIDDEN) + " network)";
        return false;
    }
    std::unique_ptr<Network> net(new Network());
    const unsigned char* q = p + HEADER_BYTES;
    for (size_t i = 0; i < size_t(INPUTS) * HIDDEN; ++i, q += 2) net->ftWeights[i] = readI16(q);
    for (int i = 0; i < HIDDEN; ++i, q += 2) net->ftBias[i] = readI16(q);
    for (int i = 0; i < 2 * HIDDEN; ++i, q += 2) {
        net->outWeights[i] = readI16(q);
        if (net->outWeights[i] > 2 * QB || net->outWeights[i] < -2 * QB) {
            error = "output weight out of range";
            return false;
        }
    }
    net->outBias = int32_t(readU32(q));
    gNet = std::move(net);
    return true;
}

bool loadFile(const std::string& path, std::string& error) {
    std::ifstream f(path, std::ios::binary);
    if (!f) {
        error = "cannot open " + path;
        return false;
    }
    std::vector<char> buf((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
    if (!loadFromMemory(buf.data(), buf.size(), error)) {
        error = path + ": " + error;
        return false;
    }
    gName = path;
    return true;
}

bool loadEmbedded() {
    if (!embedded::size) return false;
    std::string err;
    if (!loadFromMemory(embedded::data, embedded::size, err)) return false;
    gName = embedded::name;
    return true;
}

void init() { loadEmbedded(); }

void refresh(const Board& b, AccStack& st) {
    if (!gNet) return;
    refreshAcc(*gNet, b, st.acc[st.top].v);
    st.acc[st.top].computed = true;
}

int evaluate(const Board& b) {
    const Network& net = *gNet;
    AccStack* st = b.accStack();
    if (st && !st->overflow) {
        updateStack(net, *st);
        const Accumulator& a = st->acc[st->top];
        return output(net, a.v[b.side], a.v[~b.side]);
    }
    alignas(64) int16_t v[2][HIDDEN];
    refreshAcc(net, b, v);
    return output(net, v[b.side], v[~b.side]);
}

double evaluateFloat(const Board& b) {
    const Network& net = *gNet;
    double out = double(net.outBias) / (double(QA) * QB);
    for (int p = 0; p < 2; ++p) {
        const int persp = p == 0 ? int(b.side) : int(~b.side);
        std::vector<double> h(HIDDEN);
        for (int i = 0; i < HIDDEN; ++i) h[size_t(i)] = double(net.ftBias[i]) / QA;
        for (int sq = 0; sq < 64; ++sq) {
            if (b.squares[sq] == NO_PIECE) continue;
            const int16_t* w = &net.ftWeights[size_t(featureIndex(persp, b.squares[sq], sq)) * HIDDEN];
            for (int i = 0; i < HIDDEN; ++i) h[size_t(i)] += double(w[i]) / QA;
        }
        for (int i = 0; i < HIDDEN; ++i) {
            double c = std::min(1.0, std::max(0.0, h[size_t(i)]));
            out += c * c * double(net.outWeights[p * HIDDEN + i]) / QB;
        }
    }
    return out * SCALE;
}

bool accumulatorMatchesRefresh(const Board& b) {
    AccStack* st = b.accStack();
    if (!st || !gNet || st->overflow) return true;
    updateStack(*gNet, *st);
    alignas(64) int16_t v[2][HIDDEN];
    refreshAcc(*gNet, b, v);
    return std::memcmp(v, st->acc[st->top].v, sizeof(v)) == 0;
}

} // namespace nnue
} // namespace engine
