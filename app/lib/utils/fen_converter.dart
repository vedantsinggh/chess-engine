import '../models/game_state.dart';
import '../models/piece.dart';
import '../models/position.dart';

/// The single place that converts between [GameState] and FEN strings.
class FenConverter {
  static const _typeToChar = {
    PieceType.pawn: 'p',
    PieceType.knight: 'n',
    PieceType.bishop: 'b',
    PieceType.rook: 'r',
    PieceType.queen: 'q',
    PieceType.king: 'k',
  };
  static const _charToType = {
    'p': PieceType.pawn,
    'n': PieceType.knight,
    'b': PieceType.bishop,
    'r': PieceType.rook,
    'q': PieceType.queen,
    'k': PieceType.king,
  };

  /// Full 6-field FEN for the current state.
  static String boardToFen(GameState state) =>
      '${positionKey(state)} ${state.halfmoveClock} ${state.fullmoveNumber}';

  /// The first four FEN fields. Two positions with the same key are the
  /// "same position" for threefold-repetition purposes.
  static String positionKey(GameState state) {
    final rows = <String>[];
    for (var r = 0; r < 8; r++) {
      var empty = 0;
      final sb = StringBuffer();
      for (var c = 0; c < 8; c++) {
        final piece = state.board[r][c];
        if (piece == null) {
          empty++;
          continue;
        }
        if (empty > 0) {
          sb.write(empty);
          empty = 0;
        }
        sb.write(pieceToChar(piece));
      }
      if (empty > 0) sb.write(empty);
      rows.add(sb.toString());
    }

    final turn = state.currentTurn == PieceColor.white ? 'w' : 'b';

    final cr = state.castlingRights;
    var castling = '';
    if (cr.whiteKingside) castling += 'K';
    if (cr.whiteQueenside) castling += 'Q';
    if (cr.blackKingside) castling += 'k';
    if (cr.blackQueenside) castling += 'q';
    if (castling.isEmpty) castling = '-';

    final ep = state.enPassantTarget?.algebraic ?? '-';

    return '${rows.join('/')} $turn $castling $ep';
  }

  static String pieceToChar(Piece piece) {
    final ch = _typeToChar[piece.type]!;
    return piece.isWhite ? ch.toUpperCase() : ch;
  }

  /// Loads [fen] into [state], replacing the board, side to move, castling
  /// rights, en passant square and move counters, and starting a fresh move
  /// history from this position.
  ///
  /// Throws [FormatException] if [fen] is malformed; [state] is left
  /// untouched in that case.
  static void fenToBoard(String fen, GameState state) {
    final parts = fen.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) {
      throw const FormatException('Empty FEN');
    }

    // ── Board ──
    final rows = parts[0].split('/');
    if (rows.length != 8) {
      throw FormatException('FEN board must have 8 ranks, got ${rows.length}');
    }
    final board = List.generate(8, (_) => List<Piece?>.filled(8, null));
    var whiteKings = 0, blackKings = 0;
    for (var r = 0; r < 8; r++) {
      var c = 0;
      for (final ch in rows[r].split('')) {
        final n = int.tryParse(ch);
        if (n != null) {
          if (n < 1 || n > 8) throw FormatException('Bad empty count "$ch"');
          c += n;
        } else {
          final type = _charToType[ch.toLowerCase()];
          if (type == null) throw FormatException('Invalid FEN piece "$ch"');
          if (c >= 8) throw FormatException('Rank ${8 - r} is too long');
          final color =
              ch == ch.toUpperCase() ? PieceColor.white : PieceColor.black;
          if (type == PieceType.pawn && (r == 0 || r == 7)) {
            throw const FormatException('Pawn on first or last rank');
          }
          if (type == PieceType.king) {
            color == PieceColor.white ? whiteKings++ : blackKings++;
          }
          board[r][c] = Piece(type, color);
          c++;
        }
        if (c > 8) throw FormatException('Rank ${8 - r} is too long');
      }
      if (c != 8) throw FormatException('Rank ${8 - r} has $c squares, not 8');
    }
    if (whiteKings != 1 || blackKings != 1) {
      throw const FormatException('Each side needs exactly one king');
    }

    // ── Side to move ──
    final turnStr = parts.length > 1 ? parts[1] : 'w';
    if (turnStr != 'w' && turnStr != 'b') {
      throw FormatException('Bad side to move "$turnStr"');
    }
    final turn = turnStr == 'w' ? PieceColor.white : PieceColor.black;

    // ── Castling ──
    final castlingStr = parts.length > 2 ? parts[2] : '-';
    if (!RegExp(r'^(-|K?Q?k?q?)$').hasMatch(castlingStr)) {
      throw FormatException('Bad castling field "$castlingStr"');
    }
    bool hasPiece(int r, int c, PieceType t, PieceColor col) =>
        board[r][c]?.type == t && board[r][c]?.color == col;
    // Drop rights that the board can't support (king/rook not on home squares).
    final wk = hasPiece(7, 4, PieceType.king, PieceColor.white);
    final bk = hasPiece(0, 4, PieceType.king, PieceColor.black);
    final rights = CastlingRights(
      whiteKingside: castlingStr.contains('K') &&
          wk &&
          hasPiece(7, 7, PieceType.rook, PieceColor.white),
      whiteQueenside: castlingStr.contains('Q') &&
          wk &&
          hasPiece(7, 0, PieceType.rook, PieceColor.white),
      blackKingside: castlingStr.contains('k') &&
          bk &&
          hasPiece(0, 7, PieceType.rook, PieceColor.black),
      blackQueenside: castlingStr.contains('q') &&
          bk &&
          hasPiece(0, 0, PieceType.rook, PieceColor.black),
    );

    // ── En passant ──
    Position? ep;
    final epStr = parts.length > 3 ? parts[3] : '-';
    if (epStr != '-') {
      ep = Position.fromAlgebraic(epStr);
      final expectedRow = turn == PieceColor.white ? 2 : 5; // rank 6 / rank 3
      if (ep == null || ep.row != expectedRow) {
        throw FormatException('Bad en passant square "$epStr"');
      }
    }

    // ── Counters ──
    final halfmove = parts.length > 4 ? int.tryParse(parts[4]) : 0;
    final fullmove = parts.length > 5 ? int.tryParse(parts[5]) : 1;
    if (halfmove == null || halfmove < 0) {
      throw FormatException('Bad halfmove clock "${parts[4]}"');
    }
    if (fullmove == null || fullmove < 1) {
      throw FormatException('Bad fullmove number "${parts[5]}"');
    }

    // ── Commit ──
    state.board = board;
    state.currentTurn = turn;
    state.castlingRights = rights;
    state.enPassantTarget = ep;
    state.halfmoveClock = halfmove;
    state.fullmoveNumber = fullmove;
    state.selectedPosition = null;
    state.validMoves = [];
    state.pendingPromotionMove = null;
    state.drawReason = null;
    state.loser = null;
    state.moveHistory.clear();
    state.sanHistory.clear();
    state.startFen = boardToFen(state);
    state.positionCounts
      ..clear()
      ..[positionKey(state)] = 1;
  }
}
