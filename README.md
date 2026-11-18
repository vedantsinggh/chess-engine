# Rank

A chess engine written from scratch in C++, plus a Flutter app to play against it.

- **`engine/`**: "Rank", a UCI chess engine.
  - **Board and moves:** magic bitboards and legal move generation, verified with perft.
  - **Evaluation:** an NNUE network trained on the engine's own self-play games (on by default), with a hand-written PeSTO evaluation as a fallback. The data generator and trainer are in `engine/tools`.
  - **Search:** Lazy SMP multi-threaded PVS with aspiration windows, null-move pruning, LMR, futility/LMP/SEE pruning and a shared lock-free transposition table.
  - **Time and pondering:** adaptive time management and pondering.
  - **Strength limiting:** `UCI_LimitStrength` / `UCI_Elo` 400–2400, `Skill Level`.
  - **Match tool:** `engine/tools/match` plays engines against each other, with SPRT, so every strength change is measured.
- **`app/`**: Flutter desktop UI.
  - **Play:** against bots from 600 Elo to full strength, as White or Black, with or without clocks.
  - **During a game:** resign or offer a draw, undo and redo, and step through a move list in standard notation.
  - **Analysis:** analyse positions with a live evaluation bar, load and copy FEN.
  - **Settings:** board themes and piece styles.
  - **Engines:** talks UCI to whichever engine it finds, so Stockfish works too.

## Quick start

```sh
./chess.sh                 # build + test the engine, install to ~/.local/bin/chess_engine
cd app && flutter run -d linux   # or macos / windows
```

`./chess.sh --stockfish` also clones and builds Stockfish into `~/.local/bin/stockfish`. Root access isn't needed.

### How the app finds an engine

The app checks these places, in order:

1. `CHESS_ENGINE_PATH`: any UCI engine binary.
2. The built-in engine `chess_engine`: in the app-support directory, `~/.local/bin`, `/usr/local/bin`, or `engine/build/` when you run from the repo.
3. Stockfish: in the app-support directory, the usual system paths, or `~/.local/bin`.
4. `chess_engine` / `stockfish` on `PATH`.

The app runs engines as a separate process, which works on desktop only. Android and iOS can't use an engine yet.

## Requirements

- CMake ≥ 3.16 and a C++17 compiler (GCC or Clang)
- Flutter SDK (Dart ≥ 3.9)

## Development

```sh
# Engine
cmake -S engine -B engine/build -DCMAKE_BUILD_TYPE=Release
cmake --build engine/build -j
ctest --test-dir engine/build --output-on-failure    # perft suite

# Measure a change: new build vs a saved copy (see engine/tools/README.md)
./engine/build/match -engine cmd=./engine/build/chess_engine name=new \
    -engine cmd=./old_chess_engine name=old -tc 10+0.1 -games 400 -concurrency 10

# Talk to it directly
./engine/build/chess_engine
> position startpos moves e2e4
> go movetime 1000
> perft 5          # also: d (print board), eval, bench

# App
cd app
flutter analyze
flutter test       # rules/FEN/perft tests; engine integration tests run if engine/build exists
```

## Project structure

```
engine/
  include/engine/   types, board, eval, search, uci, engine.h (C API)
  src/              board.cpp, eval.cpp, search.cpp, uci.cpp, main.cpp, bridge.cpp
  tests/            perft_test.cpp
  tools/            match.cpp (engine-vs-engine matches, SPRT)
app/
  lib/models/       GameState, Piece, Position
  lib/services/     GameService, ChessEngineService (UCI), EngineLoader, ChessClock, SettingsController
  lib/utils/        MoveValidator, ChessRules, FenConverter, SAN
  lib/screens/      UI (game/ holds the game screen's pieces)
  test/             unit + engine integration tests
chess.sh            build/install script
```

## References

- UCI protocol: https://backscattering.de/chess/uci/
- Perft results: https://www.chessprogramming.org/Perft_Results
- FEN: https://www.chessprogramming.org/Forsyth-Edwards_Notation
- PGN: https://en.wikipedia.org/wiki/Portable_Game_Notation
- Board assets: https://sharechess.github.io/
