# Engine tools

## `match` — engine-vs-engine games, Elo and SPRT

Built with the engine (`cmake --build engine/build`, Linux only) as `engine/build/match`.
It runs two UCI engines as subprocesses, uses the engine's own `Board` for legality and
game-end rules (mate, stalemate, 3-fold, 50-move, insufficient material) and scores
time losses, crashes/disconnects and illegal moves as losses.

```sh
# Fixed number of games, 10s+0.1s, 10 games in parallel
engine/build/match \
  -engine cmd=engine/build/chess_engine name=new \
  -engine cmd=/path/to/old_engine name=old \
  -each option.Hash=16 \
  -tc 10+0.1 -games 400 -concurrency 10 \
  -resign movecount=4 score=800 -draw movenumber=40 movecount=8 score=8 \
  -pgnout games.pgn

# SPRT: stop as soon as H0 (elo <= elo0) or H1 (elo >= elo1) is accepted
engine/build/match -engine cmd=./new -engine cmd=./old -tc 8+0.08 -games 20000 \
  -concurrency 10 -sprt elo0=0 elo1=5 alpha=0.05 beta=0.05 model=logistic
```

Options:

| option | meaning |
| --- | --- |
| `-engine cmd=PATH [name=N] [dir=D] [option.NAME=VALUE ...] [ponder]` | engine (give exactly two); `ponder` enables pondering (`go ponder`/`ponderhit`) |
| `-each ...` | engine arguments applied to both engines (per-engine values win) |
| `-tc BASE+INC` | clock in seconds, sent as `wtime/btime/winc/binc` |
| `-movetime MS`, `-nodes N`, `-depth D` | fixed per-move limits instead of (or in addition to) a clock |
| `-games N` | total games (rounded up to even; every opening is played twice with colours swapped) |
| `-concurrency N` | games played in parallel (keep below the number of cores; add up `Threads`) |
| `-openings builtin\|random\|FILE` | 60 built-in balanced 4–8 ply lines (default), random legal plies (`-plies N`, positions with \|static eval\| > 120 cp rejected), or a file with one FEN/EPD (optionally `moves ...`) or UCI move list per line |
| `-sprt elo0= elo1= alpha= beta= model=logistic\|normalized` | GSPRT on game-pair (pentanomial) results; scheduling stops once a bound is crossed |
| `-resign movecount=N score=CP` | adjudicate a loss when the side to move reports <= -CP for N consecutive moves and the opponent agrees |
| `-draw movenumber=M movecount=N score=CP` | adjudicate a draw after move M when both sides report \|score\| <= CP for N moves each |
| `-maxmoves N` | adjudicate a draw after N full moves |
| `-timemargin MS` | grace before a move counts as a time loss (default 0) |
| `-pgnout FILE`, `-seed N`, `-ratinginterval N`, `-verbose` | PGN output (appends), opening shuffle seed, report interval, echo engine output |

The report gives W/L/D from the first engine's point of view, the Elo difference with a
95% confidence interval (computed from game-pair statistics), normalized Elo, LOS, the
pentanomial pair distribution and, with `-sprt`, the log-likelihood ratio and its bounds.
Ctrl-C (SIGINT/SIGTERM) kills all engine processes; engines also receive
`PR_SET_PDEATHSIG` so they die with the runner.

Tips:
- Use `-concurrency` at most (cores - 2), and fewer when engines use `Threads > 1`
  (e.g. `-concurrency 2` for two 4-thread engines on 12 cores).
- At very short controls check the final "Time losses" line; a correct engine has none.

## Benchmark

`chess_engine` understands a non-standard `bench [depth]` command that searches a fixed
set of positions single-threaded and prints total nodes and nodes/second (useful to
check that a change is a pure speedup: the node count must not change).

## NNUE pipeline

Network: (768 → 256)×2 perspective → 1, int16 accumulators updated incrementally.
The default net `engine/nets/rank-1.nnue` is embedded in the binary at build time.
UCI options: `Use NNUE` (default **true**, CMake `-DRANK_USE_NNUE_DEFAULT=OFF` to change) and
`EvalFile` (load another net).

```sh
# 1. Self-play data (HCE-labelled for the first net; add -nnue to label with the current net)
./engine/build/datagen -out data/gen1.bin -threads 10 -nodes 5000 -plies 8 -hours 1.6

# 2. Train (writes epochN.ckpt / epochN.nnue into the outdir)
./engine/build/train -data data/gen1.bin -outdir nets/g1 -epochs 13 -batch 16384 \
    -lr 0.001 -lr-end 1e-5 -wdl 0.2 -wd 0.01 -threads 10

# 3. Test against the HCE build (or the previous net)
./engine/build/match -engine cmd=./engine/build/chess_engine name=nnue \
    "option.EvalFile=nets/g1/epoch12.nnue" -engine cmd=./old_engine name=old \
    -tc 3+0.03 -games 300 -concurrency 11 -sprt elo0=0 elo1=20
```

rank-1 numbers: 112k self-play games / 10.1M positions in 96 min (~1,760 pos/s on 10 threads);
13 epochs at ~45 s each; validation loss 0.00611 (HCE static eval: 0.00744).
Vs the HCE engine at 3+0.03: +110 ± 53 Elo over 101 games, SPRT [0, 20] accepted H1. A stopped
10+0.1 run was 105-58-29 after 192 games. Not yet done: training a second net on data labelled by
the first one (`datagen -nnue`).
