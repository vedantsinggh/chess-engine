import '../models/game_state.dart';
import '../models/piece.dart';
import '../models/position.dart';
import 'fen_converter.dart';
import 'move_validator.dart';
import 'san.dart';

/// Pure chess rules on top of [GameState]: playing moves, game-end
/// detection and replaying a game. No engine, UI or listener side effects
/// (except that the state is mutated; nothing calls notifyListeners).
class ChessRules {
  ChessRules._();

  static final MoveValidator validator = MoveValidator();

  static PieceColor opposite(PieceColor c) =>
      c == PieceColor.white ? PieceColor.black : PieceColor.white;

  /// Parses a UCI move ("e2e4", "e7e8q"). Returns null when malformed.
  static ({Position from, Position to, PieceType? promotion})? parseUci(
    String uci,
  ) {
    if (uci.length < 4 || uci.length > 5) return null;
    final from = Position.fromAlgebraic(uci.substring(0, 2));
    final to = Position.fromAlgebraic(uci.substring(2, 4));
    if (from == null || to == null) return null;
    PieceType? promo;
    if (uci.length == 5) {
      promo = promotionFromChar(uci[4]);
      if (promo == null) return null;
    }
    return (from: from, to: to, promotion: promo);
  }

  static PieceType? promotionFromChar(String char) {
    switch (char.toLowerCase()) {
      case 'q':
        return PieceType.queen;
      case 'r':
        return PieceType.rook;
      case 'b':
        return PieceType.bishop;
      case 'n':
        return PieceType.knight;
      default:
        return null;
    }
  }

  static bool isPromotionMove(GameState state, Position from, Position to) {
    final p = state.board[from.row][from.col];
    return p != null &&
        p.type == PieceType.pawn &&
        (to.row == 0 || to.row == 7);
  }

  /// Plays [uci] if it is legal in [state]: updates the board, castling
  /// rights, en passant square, clocks, move/SAN history, repetition counts
  /// and status. A promotion without a piece letter promotes to a queen.
  /// Returns false (and changes nothing) for an illegal or malformed move,
  /// or when the game is already over.
  static bool applyUci(GameState state, String uci) {
    if (state.isGameOver) return false;
    final m = parseUci(uci);
    if (m == null) return false;
    final from = m.from, to = m.to;
    final piece = state.board[from.row][from.col];
    if (piece == null || piece.color != state.currentTurn) return false;
    if (!validator.isValidMove(state, from.row, from.col, to.row, to.col)) {
      return false;
    }
    final isPromotion = isPromotionMove(state, from, to);
    PieceType? promo = m.promotion;
    if (isPromotion) {
      promo ??= PieceType.queen;
      if (promo == PieceType.king || promo == PieceType.pawn) return false;
    } else if (promo != null) {
      return false;
    }

    final san = SanFormatter.baseSan(state, from, to, promo);
    _move(state, piece, from, to, promo);

    final canonical =
        '${from.algebraic}${to.algebraic}'
        '${promo == null ? '' : FenConverter.pieceToChar(Piece(promo, PieceColor.black))}';
    state.moveHistory.add(canonical);
    final key = FenConverter.positionKey(state);
    state.positionCounts[key] = (state.positionCounts[key] ?? 0) + 1;
    state.pendingPromotionMove = null;
    state.selectedPosition = null;
    state.validMoves = [];

    updateStatus(state);
    final inCheck = validator.isKingInCheck(state.board, state.currentTurn);
    state.sanHistory.add(
      SanFormatter.withSuffix(
        san,
        inCheck: inCheck,
        mate: state.status == GameStatus.checkmate,
      ),
    );
    return true;
  }

  static void _move(
    GameState state,
    Piece piece,
    Position from,
    Position to,
    PieceType? promo,
  ) {
    final b = state.board;
    var isCapture = b[to.row][to.col] != null;

    if (piece.type == PieceType.pawn &&
        from.col != to.col &&
        b[to.row][to.col] == null) {
      b[from.row][to.col] = null; // en passant
      isCapture = true;
    }
    if (piece.type == PieceType.king && (to.col - from.col).abs() == 2) {
      if (to.col == 6) {
        b[from.row][5] = b[from.row][7];
        b[from.row][7] = null;
      } else {
        b[from.row][3] = b[from.row][0];
        b[from.row][0] = null;
      }
    }
    b[to.row][to.col] = promo == null ? piece : Piece(promo, piece.color);
    b[from.row][from.col] = null;

    _updateCastlingRights(state, piece, from, to);

    state.enPassantTarget =
        piece.type == PieceType.pawn && (to.row - from.row).abs() == 2
        ? Position((from.row + to.row) ~/ 2, from.col)
        : null;

    if (piece.type == PieceType.pawn || isCapture) {
      state.halfmoveClock = 0;
    } else {
      state.halfmoveClock++;
    }
    if (state.currentTurn == PieceColor.black) state.fullmoveNumber++;
    state.currentTurn = opposite(state.currentTurn);
  }

  static void _updateCastlingRights(
    GameState state,
    Piece moved,
    Position from,
    Position to,
  ) {
    final r = state.castlingRights;
    if (moved.type == PieceType.king) {
      if (moved.isWhite) {
        r.whiteKingside = false;
        r.whiteQueenside = false;
      } else {
        r.blackKingside = false;
        r.blackQueenside = false;
      }
    }
    // A rook leaving its home square, or anything landing on it (a capture),
    // removes that castling right.
    for (final p in [from, to]) {
      if (p.row == 7 && p.col == 7) r.whiteKingside = false;
      if (p.row == 7 && p.col == 0) r.whiteQueenside = false;
      if (p.row == 0 && p.col == 7) r.blackKingside = false;
      if (p.row == 0 && p.col == 0) r.blackQueenside = false;
    }
  }

  /// Recomputes [GameState.status] / [GameState.drawReason] for the side to
  /// move from the position alone (checkmate, stalemate, threefold, 50-move,
  /// insufficient material).
  static void updateStatus(GameState state) {
    state.drawReason = null;
    state.loser = null;
    final inCheck = validator.isKingInCheck(state.board, state.currentTurn);
    final hasLegal = validator.hasLegalMoves(state);

    if (!hasLegal) {
      if (inCheck) {
        state.status = GameStatus.checkmate;
      } else {
        state.status = GameStatus.stalemate;
        state.drawReason = DrawReason.stalemate;
      }
      return;
    }

    final key = FenConverter.positionKey(state);
    if ((state.positionCounts[key] ?? 0) >= 3) {
      state.drawReason = DrawReason.threefoldRepetition;
    } else if (state.halfmoveClock >= 100) {
      state.drawReason = DrawReason.fiftyMoveRule;
    } else if (validator.isInsufficientMaterial(state.board)) {
      state.drawReason = DrawReason.insufficientMaterial;
    }
    if (state.drawReason != null) {
      state.status = GameStatus.draw;
      return;
    }

    if (inCheck) {
      state.status = GameStatus.check;
    } else {
      state.status = state.currentTurn == PieceColor.white
          ? GameStatus.whiteTurn
          : GameStatus.blackTurn;
    }
  }

  /// Rebuilds [state] as [startFen] followed by [moves]. Move history,
  /// SAN, repetition counts and the halfmove/fullmove counters come out
  /// exactly as if the moves had been played. Throws [StateError] if a move
  /// is illegal (and [FormatException] for a bad FEN).
  static void replay(GameState state, String startFen, List<String> moves) {
    FenConverter.fenToBoard(startFen, state);
    updateStatus(state);
    for (final m in moves) {
      if (!applyUci(state, m)) {
        throw StateError('Illegal move "$m" while replaying');
      }
    }
  }

  /// A fresh state showing [game] after its first [ply] moves.
  static GameState positionAt(GameState game, int ply) {
    final s = GameState()..currentMode = game.currentMode;
    replay(
      s,
      game.startFen,
      game.moveHistory.sublist(0, ply.clamp(0, game.moveHistory.length)),
    );
    return s;
  }

  /// Every legal move in UCI notation (promotions expanded to q/r/b/n).
  static List<String> legalMoves(GameState s) {
    final moves = <String>[];
    for (var r = 0; r < 8; r++) {
      for (var c = 0; c < 8; c++) {
        final p = s.board[r][c];
        if (p == null || p.color != s.currentTurn) continue;
        for (final to in validator.getLegalMoves(s, r, c)) {
          final base = '${Position(r, c).algebraic}${to.algebraic}';
          if (p.type == PieceType.pawn && (to.row == 0 || to.row == 7)) {
            moves.addAll(['q', 'r', 'b', 'n'].map((x) => '$base$x'));
          } else {
            moves.add(base);
          }
        }
      }
    }
    return moves;
  }

  static const _value = {
    PieceType.pawn: 1,
    PieceType.knight: 3,
    PieceType.bishop: 3,
    PieceType.rook: 5,
    PieceType.queen: 9,
    PieceType.king: 0,
  };

  /// Could [color] still checkmate the opponent by some series of legal
  /// moves? Used for "flag fall vs insufficient material" (FIDE 6.9).
  ///
  /// Conservative approximation: a bare king never can; a king plus a single
  /// minor piece (or only same-coloured bishops) can only when the opponent
  /// has other material that could block their own king. Everything else
  /// counts as mating material.
  static bool hasMatingMaterial(List<List<Piece?>> board, PieceColor color) {
    final own = <({PieceType type, int sq})>[];
    var opponentHasMaterial = false;
    for (var r = 0; r < 8; r++) {
      for (var c = 0; c < 8; c++) {
        final p = board[r][c];
        if (p == null || p.type == PieceType.king) continue;
        if (p.color == color) {
          own.add((type: p.type, sq: (r + c) % 2));
        } else {
          opponentHasMaterial = true;
        }
      }
    }
    if (own.isEmpty) return false;
    final onlyMinors = own.every(
      (m) => m.type == PieceType.knight || m.type == PieceType.bishop,
    );
    if (!onlyMinors) return true;
    final single = own.length == 1;
    final sameColourBishops =
        own.every((m) => m.type == PieceType.bishop) &&
        own.every((m) => m.sq == own.first.sq);
    if (single || sameColourBishops) return opponentHasMaterial;
    return true;
  }

  /// "Objectively drawish" material: already insufficient, or no pawns left
  /// and the material difference is at most two pawns (e.g. R v R, R v B).
  static bool isDrawishMaterial(List<List<Piece?>> board) {
    if (validator.isInsufficientMaterial(board)) return true;
    var white = 0, black = 0;
    for (final row in board) {
      for (final p in row) {
        if (p == null) continue;
        if (p.type == PieceType.pawn) return false;
        if (p.isWhite) {
          white += _value[p.type]!;
        } else {
          black += _value[p.type]!;
        }
      }
    }
    return (white - black).abs() <= 2;
  }
}
