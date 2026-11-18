"""Smoke test for the eval() C API in build/libengine.so (run from engine/)."""
from ctypes import CDLL, c_char_p, c_int
import sys

try:
    lib = CDLL("./build/libengine.so")
except OSError as e:
    print(f"Error loading library: {e}")
    sys.exit(1)

lib.eval.argtypes = [c_char_p]
lib.eval.restype = c_int

for fen in [
    b"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
    b"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b KQkq - 0 1",
    b"r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3",
    b"7k/8/8/8/1P6/8/8/K7 w - - 0 1",
]:
    print(f"{lib.eval(fen):6d}  {fen.decode()}")
