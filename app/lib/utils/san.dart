import '../models/game_state.dart';
import '../models/piece.dart';
import '../models/position.dart';
import 'chess_rules.dart';
import 'move_validator.dart';

/// Standard Algebraic Notation (SAN) for moves, e.g. "Nf3", "exd6", "O-O",
/// "e8=Q+", "Qxf7#", "Nbd2", "R1e2".
class SanFormatter {
  SanFormatter._();

  static final MoveValidator _validator = MoveValidator();

  static const _letters = {
    PieceType.knight: 'N',
    PieceType.bishop: 'B',
    PieceType.rook: 'R',
    PieceType.queen: 'Q',
    PieceType.king: 'K',
  };

  /// SAN of the legal move [from]→[to] in [state] (before it is played),
  /// without the check/mate suffix.
  static String baseSan(
    GameState state,
    Position from,
    Position to,
    PieceType? promotion,
  ) {
    final piece = state.board[from.row][from.col]!;
    final target = state.board[to.row][to.col];

    if (piece.type == PieceType.king && (to.col - from.col).abs() == 2) {
      return to.col > from.col ? 'O-O' : 'O-O-O';
    }

    if (piece.type == PieceType.pawn) {
      final capture = from.col != to.col; // includes en passant
      final sb = StringBuffer();
      if (capture) sb.write('${from.algebraic[0]}x');
      sb.write(to.algebraic);
      if (promotion != null) sb.write('=${_letters[promotion]}');
      return sb.toString();
    }

    final sb = StringBuffer(_letters[piece.type]!);
    sb.write(_disambiguation(state, piece, from, to));
    if (target != null) sb.write('x');
    sb.write(to.algebraic);
    return sb.toString();
  }

  static String _disambiguation(
    GameState state,
    Piece piece,
    Position from,
    Position to,
  ) {
    final rivals = <Position>[];
    for (var r = 0; r < 8; r++) {
      for (var c = 0; c < 8; c++) {
        if (r == from.row && c == from.col) continue;
        final p = state.board[r][c];
        if (p == null || p.type != piece.type || p.color != piece.color) {
          continue;
        }
        if (_validator.isValidMove(state, r, c, to.row, to.col)) {
          rivals.add(Position(r, c));
        }
      }
    }
    if (rivals.isEmpty) return '';
    final file = from.algebraic[0];
    final rank = from.algebraic[1];
    if (rivals.every((p) => p.col != from.col)) return file;
    if (rivals.every((p) => p.row != from.row)) return rank;
    return '$file$rank';
  }

  static String withSuffix(
    String san, {
    required bool inCheck,
    required bool mate,
  }) => mate ? '$san#' : (inCheck ? '$san+' : san);

  /// Full SAN (with "+"/"#") of the UCI move [uci] in [state]. [state] is not
  /// modified. Returns null if the move is illegal.
  static String? toSan(GameState state, String uci) {
    final c = state.clone();
    if (!ChessRules.applyUci(c, uci)) return null;
    return c.sanHistory.last;
  }

  /// SAN for a whole game given as UCI moves from [startFen].
  static List<String> fromUciMoves(String startFen, List<String> moves) {
    final s = GameState();
    ChessRules.replay(s, startFen, moves);
    return List.of(s.sanHistory);
  }
}
