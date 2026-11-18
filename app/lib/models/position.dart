class Position {
  final int row;
  final int col;

  const Position(this.row, this.col);

  bool get isOnBoard => row >= 0 && row < 8 && col >= 0 && col < 8;

  /// Algebraic name of this square, e.g. Position(6, 4) -> "e2".
  String get algebraic => '${String.fromCharCode(97 + col)}${8 - row}';

  /// Parses "e2" style squares. Returns null if [s] is not a valid square.
  static Position? fromAlgebraic(String s) {
    if (s.length != 2) return null;
    final col = s.codeUnitAt(0) - 97;
    final rank = int.tryParse(s[1]);
    if (rank == null) return null;
    final p = Position(8 - rank, col);
    return p.isOnBoard ? p : null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Position && row == other.row && col == other.col;

  @override
  int get hashCode => row * 8 + col;

  @override
  String toString() => 'Position($row, $col)';
}
