import '../models/piece.dart';
import '../models/position.dart';
import '../models/game_state.dart';

class MoveValidator {
  /// Returns true if moving [piece] from (fromR,fromC) to (toR,toC) is legal,
  /// including check-evasion, castling and en passant.
  bool isValidMove(GameState state, int fromR, int fromC, int toR, int toC) {
    final board = state.board;
    final piece = board[fromR][fromC];
    if (piece == null) return false;

    // Can't move to same square
    if (fromR == toR && fromC == toC) return false;

    // Can't capture own piece
    final targetPiece = board[toR][toC];
    if (targetPiece != null && targetPiece.color == piece.color) return false;

    // Check piece-type movement rules (includes castling & en passant shape)
    if (!_isPseudoLegalMove(state, fromR, fromC, toR, toC)) return false;

    // Make sure the move doesn't leave our own king in check
    if (_moveLeavesKingInCheck(state, fromR, fromC, toR, toC)) return false;

    return true;
  }

  /// Returns all legal destination squares for the piece at (row, col).
  List<Position> getLegalMoves(GameState state, int row, int col) {
    final moves = <Position>[];
    for (var r = 0; r < 8; r++) {
      for (var c = 0; c < 8; c++) {
        if (isValidMove(state, row, col, r, c)) {
          moves.add(Position(r, c));
        }
      }
    }
    return moves;
  }

  /// Is the given color's king currently in check?
  bool isKingInCheck(List<List<Piece?>> board, PieceColor color) {
    final kingPos = _findKing(board, color);
    if (kingPos == null) return false;
    return _isSquareAttackedBy(
      board,
      kingPos.row,
      kingPos.col,
      _opposite(color),
    );
  }

  /// Does the current player have at least one legal move?
  bool hasLegalMoves(GameState state) {
    for (var r = 0; r < 8; r++) {
      for (var c = 0; c < 8; c++) {
        final p = state.board[r][c];
        if (p == null || p.color != state.currentTurn) continue;
        for (var tr = 0; tr < 8; tr++) {
          for (var tc = 0; tc < 8; tc++) {
            if (isValidMove(state, r, c, tr, tc)) return true;
          }
        }
      }
    }
    return false;
  }

  /// True when neither side can possibly deliver mate: K v K, K+minor v K,
  /// or kings plus bishops that all stand on the same square colour.
  bool isInsufficientMaterial(List<List<Piece?>> board) {
    final minors = <({PieceType type, int squareColor})>[];
    for (var r = 0; r < 8; r++) {
      for (var c = 0; c < 8; c++) {
        final p = board[r][c];
        if (p == null || p.type == PieceType.king) continue;
        if (p.type == PieceType.pawn ||
            p.type == PieceType.rook ||
            p.type == PieceType.queen) {
          return false;
        }
        minors.add((type: p.type, squareColor: (r + c) % 2));
      }
    }
    if (minors.length <= 1) return true;
    // Any number of bishops, all on one colour, with no knights.
    return minors.every((m) => m.type == PieceType.bishop) &&
        minors.every((m) => m.squareColor == minors.first.squareColor);
  }

  // PSEUDO-LEGAL MOVE SHAPES (ignore leaving king in check)
  bool _isPseudoLegalMove(
    GameState state,
    int fromR,
    int fromC,
    int toR,
    int toC,
  ) {
    final board = state.board;
    final piece = board[fromR][fromC]!;

    switch (piece.type) {
      case PieceType.pawn:
        return _isValidPawnMove(state, fromR, fromC, toR, toC, piece.isWhite);
      case PieceType.knight:
        return _isValidKnightMove(fromR, fromC, toR, toC);
      case PieceType.bishop:
        return _isValidBishopMove(board, fromR, fromC, toR, toC);
      case PieceType.rook:
        return _isValidRookMove(board, fromR, fromC, toR, toC);
      case PieceType.queen:
        return _isValidQueenMove(board, fromR, fromC, toR, toC);
      case PieceType.king:
        return _isValidKingMove(state, fromR, fromC, toR, toC);
    }
  }

  // ─── Pawn ───────────────────────────────────────────────────────────────

  bool _isValidPawnMove(
    GameState state,
    int fromR,
    int fromC,
    int toR,
    int toC,
    bool isWhite,
  ) {
    final board = state.board;
    final direction = isWhite ? -1 : 1;
    final startRow = isWhite ? 6 : 1;
    final targetPiece = board[toR][toC];

    // One square forward
    if (fromC == toC && toR == fromR + direction && targetPiece == null) {
      return true;
    }

    // Two squares forward from starting rank
    if (fromC == toC &&
        fromR == startRow &&
        toR == fromR + 2 * direction &&
        targetPiece == null &&
        board[fromR + direction][fromC] == null) {
      return true;
    }

    // Diagonal capture (normal)
    if ((toC == fromC + 1 || toC == fromC - 1) &&
        toR == fromR + direction &&
        targetPiece != null) {
      return true;
    }

    // En passant capture
    if ((toC == fromC + 1 || toC == fromC - 1) &&
        toR == fromR + direction &&
        state.enPassantTarget != null &&
        state.enPassantTarget!.row == toR &&
        state.enPassantTarget!.col == toC) {
      return true;
    }

    return false;
  }

  // ─── Knight ─────────────────────────────────────────────────────────────

  bool _isValidKnightMove(int fromR, int fromC, int toR, int toC) {
    final rowDiff = (fromR - toR).abs();
    final colDiff = (fromC - toC).abs();
    return (colDiff == 2 && rowDiff == 1) || (colDiff == 1 && rowDiff == 2);
  }

  // ─── Bishop ─────────────────────────────────────────────────────────────

  bool _isValidBishopMove(
    List<List<Piece?>> board,
    int fromR,
    int fromC,
    int toR,
    int toC,
  ) {
    final rowDiff = (fromR - toR).abs();
    final colDiff = (fromC - toC).abs();
    if (rowDiff != colDiff) return false;

    final rowStep = toR > fromR ? 1 : -1;
    final colStep = toC > fromC ? 1 : -1;

    var r = fromR + rowStep;
    var c = fromC + colStep;
    while (r != toR) {
      if (board[r][c] != null) return false;
      r += rowStep;
      c += colStep;
    }
    return true;
  }

  // ─── Rook ───────────────────────────────────────────────────────────────

  bool _isValidRookMove(
    List<List<Piece?>> board,
    int fromR,
    int fromC,
    int toR,
    int toC,
  ) {
    if (fromR != toR && fromC != toC) return false;

    if (fromR == toR) {
      final step = toC > fromC ? 1 : -1;
      var c = fromC + step;
      while (c != toC) {
        if (board[fromR][c] != null) return false;
        c += step;
      }
    } else {
      final step = toR > fromR ? 1 : -1;
      var r = fromR + step;
      while (r != toR) {
        if (board[r][fromC] != null) return false;
        r += step;
      }
    }
    return true;
  }

  // ─── Queen ──────────────────────────────────────────────────────────────

  bool _isValidQueenMove(
    List<List<Piece?>> board,
    int fromR,
    int fromC,
    int toR,
    int toC,
  ) {
    return _isValidBishopMove(board, fromR, fromC, toR, toC) ||
        _isValidRookMove(board, fromR, fromC, toR, toC);
  }

  // ─── King (including castling) ───────────────────────────────────────────

  bool _isValidKingMove(
    GameState state,
    int fromR,
    int fromC,
    int toR,
    int toC,
  ) {
    final board = state.board;
    final piece = board[fromR][fromC]!;
    final rowDiff = (toR - fromR).abs();
    final colDiff = (toC - fromC).abs();

    // Normal king move
    if (rowDiff <= 1 && colDiff <= 1) return true;

    // Castling — king moves exactly 2 squares horizontally
    if (rowDiff == 0 && colDiff == 2) {
      return _isCastlingLegal(state, piece.color, fromR, fromC, toC);
    }

    return false;
  }

  bool _isCastlingLegal(
    GameState state,
    PieceColor color,
    int row,
    int fromC,
    int toC,
  ) {
    final board = state.board;
    final rights = state.castlingRights;
    final isKingside =
        toC > fromC; // toC == 6 means kingside, toC == 2 queenside

    // Check castling rights
    if (color == PieceColor.white) {
      if (isKingside && !rights.whiteKingside) return false;
      if (!isKingside && !rights.whiteQueenside) return false;
    } else {
      if (isKingside && !rights.blackKingside) return false;
      if (!isKingside && !rights.blackQueenside) return false;
    }

    // King must not be in check
    if (isKingInCheck(board, color)) return false;

    if (isKingside) {
      // Squares between king and rook must be empty (f-file, g-file = cols 5,6)
      if (board[row][5] != null || board[row][6] != null) return false;
      // Rook must still be on h-file (col 7)
      final rook = board[row][7];
      if (rook == null || rook.type != PieceType.rook || rook.color != color)
        return false;
      // King must not pass through or land on an attacked square
      if (_isSquareAttackedBy(board, row, 5, _opposite(color))) return false;
      if (_isSquareAttackedBy(board, row, 6, _opposite(color))) return false;
    } else {
      // Squares between king and rook must be empty (d-file, c-file, b-file = cols 3,2,1)
      if (board[row][3] != null ||
          board[row][2] != null ||
          board[row][1] != null)
        return false;
      // Rook must still be on a-file (col 0)
      final rook = board[row][0];
      if (rook == null || rook.type != PieceType.rook || rook.color != color)
        return false;
      // King must not pass through or land on an attacked square
      if (_isSquareAttackedBy(board, row, 3, _opposite(color))) return false;
      if (_isSquareAttackedBy(board, row, 2, _opposite(color))) return false;
    }

    return true;
  }

  /// Simulate the move on a copied board and test if our king is left in check.
  bool _moveLeavesKingInCheck(
    GameState state,
    int fromR,
    int fromC,
    int toR,
    int toC,
  ) {
    final piece = state.board[fromR][fromC]!;

    // Deep-copy the board
    final tempBoard = List.generate(
      8,
      (r) => List<Piece?>.from(state.board[r]),
    );

    // Apply the move on the temp board
    tempBoard[toR][toC] = tempBoard[fromR][fromC];
    tempBoard[fromR][fromC] = null;

    // En passant: remove the captured pawn
    if (piece.type == PieceType.pawn &&
        fromC != toC &&
        state.board[toR][toC] == null) {
      // This was an en passant capture; the captured pawn is on the same rank as fromR
      tempBoard[fromR][toC] = null;
    }

    // Castling: move rook as well
    if (piece.type == PieceType.king && (toC - fromC).abs() == 2) {
      if (toC == 6) {
        // Kingside
        tempBoard[fromR][5] = tempBoard[fromR][7];
        tempBoard[fromR][7] = null;
      } else {
        // Queenside
        tempBoard[fromR][3] = tempBoard[fromR][0];
        tempBoard[fromR][0] = null;
      }
    }

    return isKingInCheck(tempBoard, piece.color);
  }

  /// Is the square (r, c) attacked by any piece of [byColor]?
  bool _isSquareAttackedBy(
    List<List<Piece?>> board,
    int r,
    int c,
    PieceColor byColor,
  ) {
    for (var fr = 0; fr < 8; fr++) {
      for (var fc = 0; fc < 8; fc++) {
        final p = board[fr][fc];
        if (p == null || p.color != byColor) continue;
        if (_attacksSquare(board, fr, fc, r, c, p)) return true;
      }
    }
    return false;
  }

  /// Does piece at (fromR,fromC) attack (toR,toC)?
  /// This is similar to pseudo-legal moves but for pawns uses attack direction only.
  bool _attacksSquare(
    List<List<Piece?>> board,
    int fromR,
    int fromC,
    int toR,
    int toC,
    Piece piece,
  ) {
    switch (piece.type) {
      case PieceType.pawn:
        final dir = piece.isWhite ? -1 : 1;
        return toR == fromR + dir && (toC == fromC + 1 || toC == fromC - 1);
      case PieceType.knight:
        return _isValidKnightMove(fromR, fromC, toR, toC);
      case PieceType.bishop:
        return _isValidBishopMove(board, fromR, fromC, toR, toC);
      case PieceType.rook:
        return _isValidRookMove(board, fromR, fromC, toR, toC);
      case PieceType.queen:
        return _isValidQueenMove(board, fromR, fromC, toR, toC);
      case PieceType.king:
        return (fromR - toR).abs() <= 1 && (fromC - toC).abs() <= 1;
    }
  }

  Position? _findKing(List<List<Piece?>> board, PieceColor color) {
    for (var r = 0; r < 8; r++) {
      for (var c = 0; c < 8; c++) {
        final p = board[r][c];
        if (p != null && p.type == PieceType.king && p.color == color) {
          return Position(r, c);
        }
      }
    }
    return null;
  }

  PieceColor _opposite(PieceColor color) =>
      color == PieceColor.white ? PieceColor.black : PieceColor.white;
}
