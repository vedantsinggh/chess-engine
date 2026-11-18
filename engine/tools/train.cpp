// train: multi-threaded CPU trainer for Rank's (768 -> HIDDEN) x 2 -> 1 SCReLU network.
//
// Loss: MSE in sigmoid space, pred = sigmoid(out), target = lambda * wdl + (1 - lambda) *
// sigmoid(score / SCALE) (both from the side to move's point of view), where the engine
// evaluation in centipawns is out * SCALE. The input layer is sparse (<= 32 active
// features per perspective), so the forward pass sums weight rows and the backward pass
// only touches those rows. Optimiser: AdamW, cosine learning-rate decay, all parameters
// clipped to [-CLIP, CLIP] so they survive int16 quantisation (QA = 255, QB = 256).
//
//   train -data a.bin[,b.bin] -outdir DIR [-epochs N] [-batch N] [-lr X] [-lr-end X]
//         [-wdl L] [-wd X] [-threads N] [-val F] [-seed S] [-resume CKPT] [-max-positions N]
//   train -export CKPT OUT.nnue        quantise a checkpoint
//   train -gradcheck                   numerical gradient check on a tiny random problem
#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iostream>
#include <numeric>
#include <random>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

#include "engine/board.h"
#include "engine/eval.h"
#include "engine/nnue.h"
#include "nnue_data.h"

using namespace engine;
namespace nn = engine::nnue;

namespace {

constexpr float CLIP = 1.98f;
constexpr uint32_t CKPT_MAGIC = 0x544B4352;  // "RCKT"

// One training sample: active features per perspective (stm first) and the target.
struct Sample {
    int n = 0;
    uint16_t feat[2][32];
    float target = 0;
};

inline float sigmoidf(double x) { return float(1.0 / (1.0 + std::exp(-x))); }

bool decode(const nnuedata::PackedPos& p, float lambda, Sample& s) {
    const int stm = p.stm & 1;
    s.n = 0;
    bool ok = true;
    nnuedata::forEachPiece(p, [&](int sq, int piece) {
        if (piece > 11 || s.n >= 32) {
            ok = false;
            return;
        }
        s.feat[0][s.n] = uint16_t(nn::featureIndex(stm, piece, sq));
        s.feat[1][s.n] = uint16_t(nn::featureIndex(stm ^ 1, piece, sq));
        ++s.n;
    });
    const double score = stm == 0 ? p.score : -p.score;
    const double wdlWhite = p.result * 0.5;
    const double wdl = stm == 0 ? wdlWhite : 1.0 - wdlWhite;
    s.target = float(lambda * wdl + (1.0 - lambda) * sigmoidf(score / nn::SCALE));
    return ok && p.result <= 2;
}

// FEN of a packed position (castling/en passant are not stored).
std::string toFen(const nnuedata::PackedPos& p) {
    char sq[64];
    std::memset(sq, 0, sizeof(sq));
    nnuedata::forEachPiece(p, [&](int s, int piece) { sq[s] = "PNBRQKpnbrqk"[piece % 12]; });
    std::string f;
    for (int r = 7; r >= 0; --r) {
        int e = 0;
        for (int c = 0; c < 8; ++c) {
            char x = sq[r * 8 + c];
            if (!x) {
                ++e;
                continue;
            }
            if (e) f += char('0' + e);
            e = 0;
            f += x;
        }
        if (e) f += char('0' + e);
        if (r) f += '/';
    }
    f += p.stm ? " b - - " : " w - - ";
    f += std::to_string(p.halfmove) + " " + std::to_string(std::max<int>(1, p.fullmove));
    return f;
}

// Parameters are stored flat: W1[INPUTS][H] | b1[H] | W2[2H] | b2.
template <class T>
struct Model {
    int H;
    std::vector<T> p;
    explicit Model(int hidden) : H(hidden), p(size_t(nn::INPUTS) * hidden + hidden + 2 * hidden + 1, T(0)) {}
    T* w1() { return p.data(); }
    T* b1() { return p.data() + size_t(nn::INPUTS) * H; }
    T* w2() { return b1() + H; }
    T* b2() { return w2() + 2 * H; }
    const T* w1() const { return p.data(); }
    const T* b1() const { return p.data() + size_t(nn::INPUTS) * H; }
    const T* w2() const { return b1() + H; }
    const T* b2() const { return w2() + 2 * H; }
};

// Forward + backward for one sample. Adds dLoss/dparam into `g` (same layout as the
// model) if non-null and returns the loss. `acc` must hold 2 * H scratch values.
template <class T>
double sampleStep(const Model<T>& m, const Sample& s, T* g, T* acc) {
    const int H = m.H;
    const T* w1 = m.w1();
    const T* b1 = m.b1();
    const T* w2 = m.w2();
    double out = double(*m.b2());
    for (int q = 0; q < 2; ++q) {
        T* a = acc + q * H;
        std::copy(b1, b1 + H, a);
        for (int k = 0; k < s.n; ++k) {
            const T* row = w1 + size_t(s.feat[q][k]) * H;
            for (int i = 0; i < H; ++i) a[i] += row[i];
        }
        const T* wq = w2 + q * H;
        T sum = 0;
        for (int i = 0; i < H; ++i) {
            T c = std::min(T(1), std::max(T(0), a[i]));
            sum += c * c * wq[i];
        }
        out += double(sum);
    }
    const double pred = 1.0 / (1.0 + std::exp(-out));
    const double err = pred - double(s.target);
    const double loss = err * err;
    if (!g) return loss;

    const T dout = T(2.0 * err * pred * (1.0 - pred));
    T* gw1 = g;
    T* gb1 = g + size_t(nn::INPUTS) * H;
    T* gw2 = gb1 + H;
    T* gb2 = gw2 + 2 * H;
    *gb2 += dout;
    for (int q = 0; q < 2; ++q) {
        T* a = acc + q * H;
        const T* wq = w2 + q * H;
        T* gwq = gw2 + q * H;
        // a[] becomes dLoss/dacc in place.
        for (int i = 0; i < H; ++i) {
            const T x = a[i];
            const bool inside = x > T(0) && x < T(1);
            const T c = inside ? x : (x >= T(1) ? T(1) : T(0));
            gwq[i] += dout * c * c;
            a[i] = inside ? dout * wq[i] * T(2) * x : T(0);
        }
        for (int i = 0; i < H; ++i) gb1[i] += a[i];
        for (int k = 0; k < s.n; ++k) {
            T* row = gw1 + size_t(s.feat[q][k]) * H;
            for (int i = 0; i < H; ++i) row[i] += a[i];
        }
    }
    return loss;
}

// ---------------------------------------------------------------------------
// Gradient check
// ---------------------------------------------------------------------------
int gradCheck() {
    const int H = 8;
    std::mt19937_64 rng(42);
    std::uniform_real_distribution<double> u(-0.6, 0.6);
    Model<double> m(H);
    for (double& x : m.p) x = u(rng);
    // A few random positions from short random games.
    std::vector<Sample> samples;
    Board b;
    for (int gidx = 0; gidx < 6; ++gidx) {
        b.setFen(Board::START_FEN);
        for (int ply = 0; ply < 10 + gidx * 7; ++ply) {
            MoveList l;
            b.generateLegal(l);
            if (!l.size) break;
            b.makeMove(l.moves[rng() % uint64_t(l.size)]);
        }
        int ws = int(rng() % 600) - 300;
        nnuedata::PackedPos p = nnuedata::pack(b, ws, int(rng() % 3));
        Sample s;
        decode(p, 0.3f, s);
        samples.push_back(s);
    }
    std::vector<double> g(m.p.size(), 0.0), acc(2 * H);
    auto totalLoss = [&]() {
        double l = 0;
        for (const Sample& s : samples) l += sampleStep<double>(m, s, nullptr, acc.data());
        return l;
    };
    for (const Sample& s : samples) sampleStep<double>(m, s, g.data(), acc.data());

    // Check every parameter that receives a gradient plus a random selection of others.
    const double eps = 1e-6;
    double maxRel = 0, maxAbs = 0, maxGrad = 0;
    int checked = 0, relChecked = 0;
    for (size_t i = 0; i < m.p.size(); ++i) {
        if (g[i] == 0.0 && (rng() % 50)) continue;
        const double old = m.p[i];
        m.p[i] = old + eps;
        double lp = totalLoss();
        m.p[i] = old - eps;
        double lm = totalLoss();
        m.p[i] = old;
        double num = (lp - lm) / (2 * eps);
        const double absErr = std::fabs(num - g[i]);
        maxAbs = std::max(maxAbs, absErr);
        maxGrad = std::max(maxGrad, std::fabs(g[i]));
        // Relative error where the gradient is not tiny (finite differences are noisy there).
        if (std::fabs(num) + std::fabs(g[i]) > 1e-6) {
            maxRel = std::max(maxRel, absErr / (std::fabs(num) + std::fabs(g[i])));
            ++relChecked;
        }
        ++checked;
    }
    std::printf("gradcheck: %d parameters checked (max |grad| %.3g), max abs error %.3g, "
                "max relative error %.3g over %d non-tiny gradients\n",
                checked, maxGrad, maxAbs, maxRel, relChecked);
    const bool ok = maxRel < 1e-4 && maxAbs < 1e-7 && relChecked > 50;
    std::printf("%s\n", ok ? "gradcheck PASSED" : "gradcheck FAILED");
    return ok ? 0 : 1;
}

// ---------------------------------------------------------------------------
// Checkpoints / export
// ---------------------------------------------------------------------------
struct State {
    Model<float> model{nn::HIDDEN};
    std::vector<float> m1, m2;  // Adam moments
    uint64_t step = 0;
    int epoch = 0;
};

bool saveCheckpoint(const State& st, const std::string& path) {
    std::ofstream f(path, std::ios::binary);
    if (!f) return false;
    uint32_t hdr[4] = {CKPT_MAGIC, uint32_t(st.model.H), uint32_t(st.epoch), 0};
    f.write(reinterpret_cast<const char*>(hdr), sizeof(hdr));
    f.write(reinterpret_cast<const char*>(&st.step), sizeof(st.step));
    const size_t n = st.model.p.size();
    f.write(reinterpret_cast<const char*>(st.model.p.data()), std::streamsize(n * sizeof(float)));
    f.write(reinterpret_cast<const char*>(st.m1.data()), std::streamsize(n * sizeof(float)));
    f.write(reinterpret_cast<const char*>(st.m2.data()), std::streamsize(n * sizeof(float)));
    return bool(f);
}

bool loadCheckpoint(State& st, const std::string& path) {
    std::ifstream f(path, std::ios::binary);
    uint32_t hdr[4];
    if (!f.read(reinterpret_cast<char*>(hdr), sizeof(hdr)) || hdr[0] != CKPT_MAGIC || hdr[1] != uint32_t(nn::HIDDEN))
        return false;
    st.epoch = int(hdr[2]);
    f.read(reinterpret_cast<char*>(&st.step), sizeof(st.step));
    const size_t n = st.model.p.size();
    st.m1.assign(n, 0.f);
    st.m2.assign(n, 0.f);
    f.read(reinterpret_cast<char*>(st.model.p.data()), std::streamsize(n * sizeof(float)));
    f.read(reinterpret_cast<char*>(st.m1.data()), std::streamsize(n * sizeof(float)));
    f.read(reinterpret_cast<char*>(st.m2.data()), std::streamsize(n * sizeof(float)));
    return bool(f);
}

void putI16(std::vector<unsigned char>& out, double v, double scale) {
    long q = std::lround(v * scale);
    q = std::max(-32767L, std::min(32767L, q));
    uint16_t u = uint16_t(int16_t(q));
    out.push_back(uint8_t(u & 0xFF));
    out.push_back(uint8_t(u >> 8));
}
void putU32(std::vector<unsigned char>& out, uint32_t v) {
    for (int i = 0; i < 4; ++i) out.push_back(uint8_t(v >> (8 * i)));
}

bool exportNet(const Model<float>& m, const std::string& path) {
    std::vector<unsigned char> out;
    putU32(out, nn::MAGIC);
    putU32(out, nn::VERSION);
    putU32(out, uint32_t(nn::INPUTS));
    putU32(out, uint32_t(m.H));
    for (size_t i = 0; i < size_t(nn::INPUTS) * m.H; ++i) putI16(out, m.w1()[i], nn::QA);
    for (int i = 0; i < m.H; ++i) putI16(out, m.b1()[i], nn::QA);
    for (int i = 0; i < 2 * m.H; ++i) putI16(out, m.w2()[i], nn::QB);
    putU32(out, uint32_t(int32_t(std::lround(double(m.b2()[0]) * nn::QA * nn::QB))));
    std::ofstream f(path, std::ios::binary);
    f.write(reinterpret_cast<const char*>(out.data()), std::streamsize(out.size()));
    return bool(f);
}

// ---------------------------------------------------------------------------
// Training
// ---------------------------------------------------------------------------
struct Options {
    std::vector<std::string> data;
    std::string outdir = ".";
    std::string resume;
    int epochs = 30;
    int batch = 16384;
    double lr = 1e-3, lrEnd = 1e-5;
    double wdl = 0.3;
    double wd = 0.01;
    int threads = 8;
    double val = 0.02;
    uint64_t seed = 1;
    uint64_t maxPositions = 0;
};

std::vector<std::string> split(const std::string& s, char c) {
    std::vector<std::string> out;
    std::stringstream ss(s);
    std::string x;
    while (std::getline(ss, x, c))
        if (!x.empty()) out.push_back(x);
    return out;
}

bool loadData(const std::vector<std::string>& files, std::vector<nnuedata::PackedPos>& out, uint64_t maxPos) {
    for (const std::string& f : files) {
        std::ifstream in(f, std::ios::binary | std::ios::ate);
        if (!in) {
            std::cerr << "cannot open " << f << "\n";
            return false;
        }
        size_t bytes = size_t(in.tellg());
        size_t n = bytes / sizeof(nnuedata::PackedPos);
        in.seekg(0);
        size_t old = out.size();
        out.resize(old + n);
        in.read(reinterpret_cast<char*>(out.data() + old), std::streamsize(n * sizeof(nnuedata::PackedPos)));
        std::printf("loaded %zu positions from %s\n", n, f.c_str());
    }
    if (maxPos && out.size() > maxPos) out.resize(maxPos);
    return true;
}

int train(const Options& o) {
    std::vector<nnuedata::PackedPos> data;
    if (!loadData(o.data, data, o.maxPositions) || data.empty()) return 1;

    // Validation = the last games of each file region (contiguous, so whole games stay on
    // one side of the split and validation is not inflated by near-duplicate positions).
    const size_t nVal = size_t(double(data.size()) * o.val);
    const size_t nTrain = data.size() - nVal;
    std::vector<Sample> valSet;
    valSet.reserve(nVal);
    for (size_t i = nTrain; i < data.size(); ++i) {
        Sample s;
        if (decode(data[i], float(o.wdl), s)) valSet.push_back(s);
    }
    std::printf("train %zu, validation %zu positions; hidden %d, batch %d, lr %.2g -> %.2g, wdl %.2f, wd %.3g\n",
                nTrain, valSet.size(), nn::HIDDEN, o.batch, o.lr, o.lrEnd, o.wdl, o.wd);

    {
        // Reference: the same loss for the hand-crafted static evaluation.
        double l = 0;
        size_t n = 0;
        Board b;
        for (size_t i = nTrain; i < data.size(); ++i) {
            Sample s;
            if (!decode(data[i], float(o.wdl), s) || !b.setFen(toFen(data[i]))) continue;
            const double e = sigmoidf(double(evaluateHce(b)) / nn::SCALE) - double(s.target);
            l += e * e;
            ++n;
        }
        std::printf("HCE static eval validation loss %.6f\n", l / double(std::max<size_t>(1, n)));
    }

    State st;
    const size_t P = st.model.p.size();
    std::mt19937_64 rng(o.seed);
    if (!o.resume.empty()) {
        if (!loadCheckpoint(st, o.resume)) {
            std::cerr << "cannot load checkpoint " << o.resume << "\n";
            return 1;
        }
        std::printf("resumed from %s (epoch %d)\n", o.resume.c_str(), st.epoch);
    } else {
        Model<float>& m = st.model;
        std::normal_distribution<float> n1(0.f, 0.08f), n2(0.f, 1.f / std::sqrt(float(2 * m.H)));
        for (size_t i = 0; i < size_t(nn::INPUTS) * m.H; ++i) m.w1()[i] = n1(rng);
        for (int i = 0; i < m.H; ++i) m.b1()[i] = 0.2f;
        for (int i = 0; i < 2 * m.H; ++i) m.w2()[i] = n2(rng);
        m.b2()[0] = 0.f;
        st.m1.assign(P, 0.f);
        st.m2.assign(P, 0.f);
    }

    const int T = std::max(1, o.threads);
    std::vector<std::vector<float>> grads(size_t(T), std::vector<float>(P, 0.f));
    std::vector<std::vector<float>> scratch(size_t(T), std::vector<float>(2 * nn::HIDDEN));
    std::vector<double> threadLoss(static_cast<size_t>(T));
    std::vector<Sample> batch(size_t(o.batch));
    std::vector<uint32_t> order(nTrain);
    std::iota(order.begin(), order.end(), 0u);
    const uint64_t batchesPerEpoch = nTrain / size_t(o.batch);
    const uint64_t totalSteps = batchesPerEpoch * uint64_t(o.epochs);
    const double b1c = 0.9, b2c = 0.999, adamEps = 1e-8;

    auto parallel = [&](auto&& fn) {
        std::vector<std::thread> th;
        for (int t = 1; t < T; ++t) th.emplace_back(fn, t);
        fn(0);
        for (auto& x : th) x.join();
    };

    auto validate = [&]() {
        std::vector<double> part(size_t(T), 0.0);
        parallel([&](int t) {
            std::vector<float> acc(2 * nn::HIDDEN);
            for (size_t i = size_t(t); i < valSet.size(); i += size_t(T))
                part[size_t(t)] += sampleStep<float>(st.model, valSet[i], nullptr, acc.data());
        });
        return std::accumulate(part.begin(), part.end(), 0.0) / double(std::max<size_t>(1, valSet.size()));
    };

    std::printf("epoch %d validation loss %.6f\n", st.epoch, validate());
    std::fflush(stdout);
    while (st.epoch < o.epochs) {
        const auto t0 = std::chrono::steady_clock::now();
        std::shuffle(order.begin(), order.end(), rng);
        double epochLoss = 0;
        uint64_t epochSamples = 0;
        for (uint64_t bi = 0; bi < batchesPerEpoch; ++bi) {
            const double progress = double(std::min(st.step, totalSteps)) / double(std::max<uint64_t>(1, totalSteps));
            const double lr = o.lrEnd + 0.5 * (o.lr - o.lrEnd) * (1.0 + std::cos(3.14159265358979323846 * progress));
            const size_t base = size_t(bi) * size_t(o.batch);
            int valid = 0;
            // Phase 1: decode + forward/backward, gradients per thread.
            parallel([&](int t) {
                std::vector<float>& g = grads[size_t(t)];
                std::fill(g.begin(), g.end(), 0.f);
                double l = 0;
                for (int i = t; i < o.batch; i += T) {
                    Sample& s = batch[size_t(i)];
                    if (!decode(data[order[base + size_t(i)]], float(o.wdl), s)) {
                        s.n = -1;
                        continue;
                    }
                    l += sampleStep<float>(st.model, s, g.data(), scratch[size_t(t)].data());
                }
                threadLoss[size_t(t)] = l;
            });
            for (int i = 0; i < o.batch; ++i) valid += batch[size_t(i)].n >= 0;
            epochLoss += std::accumulate(threadLoss.begin(), threadLoss.end(), 0.0);
            epochSamples += uint64_t(valid);
            ++st.step;
            const double bc1 = 1.0 - std::pow(b1c, double(st.step));
            const double bc2 = 1.0 - std::pow(b2c, double(st.step));
            const float scale = 1.f / float(std::max(1, valid));
            // Phase 2: reduce gradients and apply AdamW on disjoint parameter slices.
            parallel([&](int t) {
                const size_t lo = P * size_t(t) / size_t(T), hi = P * size_t(t + 1) / size_t(T);
                float* p = st.model.p.data();
                for (size_t i = lo; i < hi; ++i) {
                    float g = 0;
                    for (int k = 0; k < T; ++k) g += grads[size_t(k)][i];
                    g *= scale;
                    st.m1[i] = float(b1c * st.m1[i] + (1 - b1c) * g);
                    st.m2[i] = float(b2c * st.m2[i] + (1 - b2c) * g * g);
                    const double mhat = st.m1[i] / bc1, vhat = st.m2[i] / bc2;
                    double x = p[i] * (1.0 - lr * o.wd);
                    x -= lr * mhat / (std::sqrt(vhat) + adamEps);
                    p[i] = std::max(-CLIP, std::min(CLIP, float(x)));
                }
            });
        }
        ++st.epoch;
        const double secs = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
        const double vl = validate();
        std::printf("epoch %d  train loss %.6f  validation loss %.6f  (%.1f s, %.0f pos/s)\n", st.epoch,
                    epochLoss / double(std::max<uint64_t>(1, epochSamples)), vl, secs, double(epochSamples) / secs);
        std::fflush(stdout);
        const std::string base = o.outdir + "/epoch" + std::to_string(st.epoch);
        saveCheckpoint(st, base + ".ckpt");
        exportNet(st.model, base + ".nnue");
    }
    if (!valSet.empty()) {
        // Check the exported (quantised) net against the float model on validation positions.
        const std::string last = o.outdir + "/epoch" + std::to_string(st.epoch) + ".nnue";
        std::string err;
        if (nn::loadFile(last, err)) {
            std::vector<float> acc(2 * nn::HIDDEN);
            double maxDiff = 0, sumDiff = 0;
            size_t n = 0;
            Board b;
            for (size_t i = nTrain; i < data.size() && n < 20000; ++i) {
                Sample s;
                if (!decode(data[i], float(o.wdl), s) || !b.setFen(toFen(data[i]))) continue;
                // Recover the raw output from the loss-free forward pass.
                Model<float>& m = st.model;
                double out = m.b2()[0];
                for (int q = 0; q < 2; ++q) {
                    for (int k = 0; k < nn::HIDDEN; ++k) acc[size_t(k)] = m.b1()[k];
                    for (int j = 0; j < s.n; ++j)
                        for (int k = 0; k < nn::HIDDEN; ++k) acc[size_t(k)] += m.w1()[size_t(s.feat[q][j]) * nn::HIDDEN + size_t(k)];
                    for (int k = 0; k < nn::HIDDEN; ++k) {
                        float c = std::min(1.f, std::max(0.f, acc[size_t(k)]));
                        out += double(c * c * m.w2()[q * nn::HIDDEN + k]);
                    }
                }
                const double d = std::fabs(out * nn::SCALE - nn::evaluate(b));
                maxDiff = std::max(maxDiff, d);
                sumDiff += d;
                ++n;
            }
            std::printf("quantised net vs float model on %zu positions: mean |diff| %.2f cp, max %.1f cp\n", n,
                        sumDiff / double(std::max<size_t>(1, n)), maxDiff);
        } else {
            std::printf("could not reload exported net: %s\n", err.c_str());
        }
    }
    return 0;
}

void usage() {
    std::cerr << "usage: train -data FILE[,FILE...] -outdir DIR [-epochs N] [-batch N] [-lr X] [-lr-end X]\n"
                 "             [-wdl L] [-wd X] [-threads N] [-val F] [-seed S] [-resume CKPT] [-max-positions N]\n"
                 "       train -export CKPT OUT.nnue\n"
                 "       train -gradcheck\n";
}

} // namespace

int main(int argc, char** argv) {
    initTables();
    Options o;
    for (int i = 1; i < argc; ++i) {
        std::string a = argv[i];
        auto next = [&]() -> std::string {
            if (i + 1 >= argc) {
                usage();
                std::exit(2);
            }
            return argv[++i];
        };
        if (a == "-gradcheck") return gradCheck();
        if (a == "-export") {
            std::string ck = next(), out = next();
            State st;
            if (!loadCheckpoint(st, ck)) {
                std::cerr << "cannot load " << ck << "\n";
                return 1;
            }
            return exportNet(st.model, out) ? 0 : 1;
        }
        if (a == "-data") o.data = split(next(), ',');
        else if (a == "-outdir") o.outdir = next();
        else if (a == "-resume") o.resume = next();
        else if (a == "-epochs") o.epochs = std::atoi(next().c_str());
        else if (a == "-batch") o.batch = std::max(1, std::atoi(next().c_str()));
        else if (a == "-lr") o.lr = std::atof(next().c_str());
        else if (a == "-lr-end") o.lrEnd = std::atof(next().c_str());
        else if (a == "-wdl") o.wdl = std::atof(next().c_str());
        else if (a == "-wd") o.wd = std::atof(next().c_str());
        else if (a == "-threads") o.threads = std::max(1, std::atoi(next().c_str()));
        else if (a == "-val") o.val = std::atof(next().c_str());
        else if (a == "-seed") o.seed = std::strtoull(next().c_str(), nullptr, 10);
        else if (a == "-max-positions") o.maxPositions = std::strtoull(next().c_str(), nullptr, 10);
        else {
            usage();
            return 2;
        }
    }
    if (o.data.empty()) {
        usage();
        return 2;
    }
    return train(o);
}
