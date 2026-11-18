#include "engine/engine.h"

#include "engine/board.h"
#include "engine/eval.h"

extern "C" int eval(const char* fen) {
    if (!fen) return 0;
    engine::Board b;
    if (!b.setFen(fen)) return 0;
    int s = engine::evaluate(b);
    return b.side == engine::WHITE ? s : -s;
}
