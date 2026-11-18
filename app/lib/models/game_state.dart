import 'package:flutter/material.dart';
import 'position.dart';
import 'piece.dart';
import '../utils/fen_converter.dart';

enum GameMode { offline, online, engine }

enum GameStatus {
  whiteTurn,
  blackTurn,
  engineThinking,
  check,
  checkmate,
  stalemate,
  draw,

  /// [GameState.loser] resigned.
  resigned,

  /// [GameState.loser] ran out of time (and the opponent could still mate).
  timeout,
}

enum DrawReason {
  stalemate,
  threefoldRepetition,
  fiftyMoveRule,
  insufficientMaterial,

  /// Both players agreed to a draw.
  agreement,

  /// A player ran out of time but the opponent has no mating material.
  timeoutVsInsufficientMaterial,
}

/// How a finished game ended. [winner] is null for a draw.
class GameResult {
  final PieceColor? winner;
  final GameStatus status;
  final DrawReason? drawReason;

  const GameResult({this.winner, required this.status, this.drawReason});

  bool get isDraw => winner == null;

  /// PGN-style score: "1-0", "0-1" or "1/2-1/2".
  String get score => winner == null
      ? '1/2-1/2'
      : (winner == PieceColor.white ? '1-0' : '0-1');
}

class CastlingRights {
  bool whiteKingside;
  bool whiteQueenside;
  bool blackKingside;
  bool blackQueenside;

  CastlingRights({
    this.whiteKingside = true,
    this.whiteQueenside = true,
    this.blackKingside = true,
    this.blackQueenside = true,
  });

  CastlingRights copy() => CastlingRights(
        whiteKingside: whiteKingside,
        whiteQueenside: whiteQueenside,
        blackKingside: blackKingside,
        blackQueenside: blackQueenside,
      );
}

/// A move that reached the last rank and is waiting for the player to pick a
/// promotion piece.
class PendingPromotion {
  final Position from;
  final Position to;
  final bool wasCapture;
  const PendingPromotion(this.from, this.to, this.wasCapture);
}

class GameState extends ChangeNotifier {
  static const String startPositionFen =
      'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

  List<List<Piece?>> board;
  Position? selectedPosition;
  GameStatus status = GameStatus.whiteTurn;
  DrawReason? drawReason;

  /// The side that resigned or lost on time (for [GameStatus.resigned] and
  /// [GameStatus.timeout]).
  PieceColor? loser;
  PieceColor currentTurn = PieceColor.white;
  double evaluation = 0.0;
  List<Position> validMoves = [];
  bool isEngineThinking = false;
  GameMode currentMode = GameMode.offline;

  CastlingRights castlingRights = CastlingRights();
  Position? enPassantTarget;

  /// Square of a pawn that reached the last rank and awaits a promotion choice.
  Position? get pendingPromotion => pendingPromotionMove?.to;
  PendingPromotion? pendingPromotionMove;

  /// Plies since the last capture or pawn move (for the 50-move rule).
  int halfmoveClock = 0;
  int fullmoveNumber = 1;

  /// FEN the game started from, and every move since in UCI notation.
  /// Engines get `position fen <startFen> moves ...` so they can see history.
  String startFen = startPositionFen;
  final List<String> moveHistory = [];

  /// [moveHistory] in Standard Algebraic Notation (same length).
  final List<String> sanHistory = [];

  /// How many times each position (board + side + castling + ep) occurred.
  final Map<String, int> positionCounts = {};

  GameState() : board = _createInitialBoard() {
    positionCounts[FenConverter.positionKey(this)] = 1;
  }

  bool get isGameOver =>
      status == GameStatus.checkmate ||
      status == GameStatus.stalemate ||
      status == GameStatus.draw ||
      status == GameStatus.resigned ||
      status == GameStatus.timeout;

  /// The result once the game is over, otherwise null.
  GameResult? get result {
    switch (status) {
      case GameStatus.checkmate:
        // The side to move is mated.
        return GameResult(
            winner: currentTurn == PieceColor.white
                ? PieceColor.black
                : PieceColor.white,
            status: status);
      case GameStatus.resigned:
      case GameStatus.timeout:
        final l = loser ?? currentTurn;
        return GameResult(
            winner:
                l == PieceColor.white ? PieceColor.black : PieceColor.white,
            status: status);
      case GameStatus.stalemate:
        return GameResult(status: status, drawReason: DrawReason.stalemate);
      case GameStatus.draw:
        return GameResult(status: status, drawReason: drawReason);
      default:
        return null;
    }
  }

  // ================= INIT BOARD =================
  static List<List<Piece?>> _createInitialBoard() {
    const back = [
      PieceType.rook,
      PieceType.knight,
      PieceType.bishop,
      PieceType.queen,
      PieceType.king,
      PieceType.bishop,
      PieceType.knight,
      PieceType.rook,
    ];
    return List.generate(8, (row) {
      return List.generate(8, (col) {
        if (row == 1) return const Piece(PieceType.pawn, PieceColor.black);
        if (row == 6) return const Piece(PieceType.pawn, PieceColor.white);
        if (row == 0) return Piece(back[col], PieceColor.black);
        if (row == 7) return Piece(back[col], PieceColor.white);
        return null;
      });
    });
  }

  String get currentFen => FenConverter.boardToFen(this);

  /// Deep copy (without listeners). Used for search/tests.
  GameState clone() {
    final c = GameState();
    c.board = List.generate(8, (r) => List<Piece?>.from(board[r]));
    c.status = status;
    c.drawReason = drawReason;
    c.loser = loser;
    c.currentTurn = currentTurn;
    c.currentMode = currentMode;
    c.castlingRights = castlingRights.copy();
    c.enPassantTarget = enPassantTarget;
    c.pendingPromotionMove = pendingPromotionMove;
    c.halfmoveClock = halfmoveClock;
    c.fullmoveNumber = fullmoveNumber;
    c.startFen = startFen;
    c.moveHistory
      ..clear()
      ..addAll(moveHistory);
    c.sanHistory
      ..clear()
      ..addAll(sanHistory);
    c.positionCounts
      ..clear()
      ..addAll(positionCounts);
    return c;
  }

  // ================= RESET =================
  void reset() {
    board = GameState._createInitialBoard();
    selectedPosition = null;
    status = GameStatus.whiteTurn;
    drawReason = null;
    loser = null;
    currentTurn = PieceColor.white;
    evaluation = 0.0;
    validMoves = [];
    isEngineThinking = false;
    castlingRights = CastlingRights();
    enPassantTarget = null;
    pendingPromotionMove = null;
    halfmoveClock = 0;
    fullmoveNumber = 1;
    startFen = startPositionFen;
    moveHistory.clear();
    sanHistory.clear();
    positionCounts
      ..clear()
      ..[FenConverter.positionKey(this)] = 1;
    notifyListeners();
  }

  void setMode(GameMode mode) {
    currentMode = mode;
    reset();
  }

  // Public so services can trigger rebuilds after mutating state.
  @override
  // ignore: unnecessary_overrides
  void notifyListeners() => super.notifyListeners();
}
