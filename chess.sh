#!/bin/sh
# Builds the built-in UCI engine ("Rank") and installs it where the app finds
# it. Optionally also builds Stockfish. No root needed.
#
# Usage: ./chess.sh [--stockfish] [--prefix DIR]
#   --stockfish   also clone/build Stockfish into ./stockfish and install it
#   --prefix DIR  install directory (default: ~/.local/bin)
#
# Environment: JOBS (parallel jobs, default: CPU count),
#              STOCKFISH_ARCH (passed to Stockfish's make as ARCH=..., optional)

set -eu

ROOT=$(cd "$(dirname "$0")" && pwd)
PREFIX="$HOME/.local/bin"
WITH_STOCKFISH=0

while [ $# -gt 0 ]; do
  case "$1" in
    --stockfish) WITH_STOCKFISH=1 ;;
    --prefix) shift; PREFIX=$1 ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

JOBS=${JOBS:-$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)}
mkdir -p "$PREFIX"

echo "==> Building built-in engine"
cmake -S "$ROOT/engine" -B "$ROOT/engine/build" -DCMAKE_BUILD_TYPE=Release
cmake --build "$ROOT/engine/build" -j "$JOBS"
(cd "$ROOT/engine/build" && ctest --output-on-failure)
install -m 755 "$ROOT/engine/build/chess_engine" "$PREFIX/chess_engine"
echo "    installed $PREFIX/chess_engine"

if [ "$WITH_STOCKFISH" -eq 1 ]; then
  echo "==> Building Stockfish"
  if [ ! -d "$ROOT/stockfish" ]; then
    git clone --depth 1 https://github.com/official-stockfish/Stockfish "$ROOT/stockfish"
  else
    echo "    using existing $ROOT/stockfish"
  fi
  if [ -n "${STOCKFISH_ARCH:-}" ]; then
    make -C "$ROOT/stockfish/src" -j "$JOBS" profile-build ARCH="$STOCKFISH_ARCH"
  else
    make -C "$ROOT/stockfish/src" -j "$JOBS" profile-build
  fi
  install -m 755 "$ROOT/stockfish/src/stockfish" "$PREFIX/stockfish"
  echo "    installed $PREFIX/stockfish"
fi

case ":$PATH:" in
  *":$PREFIX:"*) ;;
  *) if [ "$PREFIX" = "$HOME/.local/bin" ]; then
       echo "Note: $PREFIX is not on your PATH (the app still looks there)."
     else
       echo "Note: the app won't look in $PREFIX; set CHESS_ENGINE_PATH=$PREFIX/chess_engine"
     fi ;;
esac
echo "Done. The app prefers the built-in engine; set CHESS_ENGINE_PATH to override."
