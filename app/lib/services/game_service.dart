import 'package:flutter/foundation.dart';
import '../models/game_state.dart';
import '../models/position.dart';
import '../models/piece.dart';
import '../utils/chess_rules.dart';
import '../utils/fen_converter.dart';
import '../utils/move_validator.dart';
import 'chess_clock.dart';
import 'chess_engine_service.dart';

/// Produces the bot's move (UCI) for the side to move in [state], or null.
typedef BotMoveProvider = Future<String?> Function(GameState state);

/// Evaluates [state] in pawns from White's point of view, or null.
typedef PositionEvaluator = Future<double?> Function(GameState state);

enum DrawOfferResult { accepted, declined }

/// Game flow on top of [ChessRules]: human input, the bot opponent, undo /
/// redo, clocks, resignation and draw offers.
///
/// One service drives one game ([GameState]) at a time. Any asynchronous
/// engine reply is tagged with [_epoch]; undo, redo, a new game or the end
/// of the game bump the epoch so a late reply can never be applied to a
/// position it wasn't computed for.
class GameService {
  final MoveValidator _moveValidator = MoveValidator();
  final ChessEngineService _engineService;
  late final BotMoveProvider _botMoveProvider;
  late final PositionEvaluator _evaluator;

  int _epoch = 0;
  final List<String> _redo = []; // top of the stack = next move to redo

  /// Strength of the bot opponent in offline mode. Null = full strength.
  int? botElo;

  /// Think time per bot move when there is no clock.
  Duration botMoveTime = const Duration(seconds: 1);

  /// The side the bot plays in offline mode.
  PieceColor botColor = PieceColor.black;
  PieceColor get humanColor => ChessRules.opposite(botColor);

  /// Promote straight to a queen instead of asking.
  bool autoQueen = false;

  ChessClock? _clock;

  /// The running game's clock (null for untimed games).
  ChessClock? get clock => _clock;

  GameService(
    this._engineService, {
    BotMoveProvider? botMoveProvider,
    PositionEvaluator? evaluator,
  }) {
    _botMoveProvider = botMoveProvider ?? _engineBotMove;
    _evaluator = evaluator ?? (s) => _engineService.evaluatePosition(s);
  }

  bool isBotTurn(GameState state) =>
      state.currentMode == GameMode.offline && state.currentTurn == botColor;

  // ================= GAME SETUP =================

  /// Starts a new game from the initial position. In offline mode the bot
  /// plays [botColor] and moves first if it is White. [clock] (optional)
  /// becomes the game's clock; the service owns and disposes it.
  void startNewGame(
    GameState state, {
    PieceColor? botColor,
    ChessClock? clock,
  }) {
    _cancelEngineWork(state);
    _redo.clear();
    if (botColor != null) this.botColor = botColor;
    _setClock(state, clock);
    state.reset();
    if (_clock != null && _clock!.control.isTimed) {
      _clock!.start(state.currentTurn);
    }
    _afterPositionChange(state);
  }

  void _setClock(GameState state, ChessClock? clock) {
    if (!identical(_clock, clock)) _clock?.dispose();
    _clock = clock;
    clock?.onFlag = (color) => handleFlag(state, color);
  }

  /// Loads a position. Throws [FormatException] for an invalid FEN, in which
  /// case [state] is unchanged.
  void loadFen(GameState state, String fen) {
    FenConverter.fenToBoard(fen, state); // throws before touching state
    _cancelEngineWork(state);
    _redo.clear();
    ChessRules.updateStatus(state);
    state.notifyListeners();
  }

  /// Restarts from the initial position without a clock.
  void resetGame(GameState state) => startNewGame(state);

  void dispose() {
    _epoch++;
    _clock?.dispose();
    _clock = null;
  }

  // ================= INPUT =================

  bool canHumanMove(GameState state) =>
      !state.isEngineThinking &&
      state.pendingPromotion == null &&
      !state.isGameOver &&
      !isBotTurn(state);

  void handleSquareTap(GameState state, int row, int col) {
    if (!canHumanMove(state)) return;

    final piece = state.board[row][col];

    if (state.selectedPosition == null) {
      if (piece != null && piece.color == state.currentTurn) {
        state.selectedPosition = Position(row, col);
        state.validMoves = _moveValidator.getLegalMoves(state, row, col);
        state.notifyListeners();
      }
    } else {
      _handleMove(state, row, col);
    }
  }

  void completePromotion(GameState state, PieceType chosenType) {
    final pending = state.pendingPromotionMove;
    if (pending == null) return;
    if (chosenType == PieceType.king || chosenType == PieceType.pawn) return;
    state.pendingPromotionMove = null;
    final ch = FenConverter.pieceToChar(Piece(chosenType, PieceColor.black));
    _playLive(state, '${pending.from.algebraic}${pending.to.algebraic}$ch');
  }

  /// Abandons a pending promotion (the pawn stays where it was).
  void cancelPromotion(GameState state) {
    if (state.pendingPromotionMove == null) return;
    state.pendingPromotionMove = null;
    state.notifyListeners();
  }

  /// Plays a move given in UCI notation (e.g. "e2e4", "e7e8q") after checking
  /// it is legal. Returns false (and changes nothing) if it isn't.
  /// A promotion without a piece letter promotes to a queen.
  bool makeUciMove(GameState state, String uci) {
    if (state.isGameOver || state.pendingPromotion != null) return false;
    return _playLive(state, uci);
  }

  void _handleMove(GameState state, int toR, int toC) {
    final from = state.selectedPosition!;
    final to = Position(toR, toC);

    if (from == to) {
      _clearSelection(state);
      return;
    }

    final targetPiece = state.board[toR][toC];
    if (targetPiece != null && targetPiece.color == state.currentTurn) {
      state.selectedPosition = to;
      state.validMoves = _moveValidator.getLegalMoves(state, toR, toC);
      state.notifyListeners();
      return;
    }

    if (!_moveValidator.isValidMove(state, from.row, from.col, toR, toC)) {
      _clearSelection(state);
      return;
    }

    final uci = '${from.algebraic}${to.algebraic}';
    if (ChessRules.isPromotionMove(state, from, to) && !autoQueen) {
      state.pendingPromotionMove = PendingPromotion(
        from,
        to,
        state.board[toR][toC] != null,
      );
      state.selectedPosition = null;
      state.validMoves = [];
      state.notifyListeners();
      return;
    }
    _playLive(state, uci);
  }

  void _clearSelection(GameState state) {
    state.selectedPosition = null;
    state.validMoves = [];
    state.notifyListeners();
  }

  /// Plays a new move in the live game (not a replay or redo).
  bool _playLive(GameState state, String uci) {
    final mover = state.currentTurn;
    if (!ChessRules.applyUci(state, uci)) return false;
    _redo.clear();
    final clock = _clock;
    if (clock != null && clock.control.isTimed) {
      state.isGameOver ? clock.stop() : clock.moveMade(mover);
    }
    _afterPositionChange(state);
    return true;
  }

  /// Notifies, refreshes the analysis evaluation and lets the bot move if
  /// it is its turn.
  void _afterPositionChange(GameState state) {
    state.notifyListeners();
    if (state.currentMode == GameMode.engine && !state.isGameOver) {
      updateEvaluation(state, _engineService);
    }
    onMoveCompleted(state);
  }

  // ================= UNDO / REDO =================

  bool _isFinalResult(GameState state) =>
      state.status == GameStatus.resigned ||
      state.status == GameStatus.timeout ||
      (state.status == GameStatus.draw &&
          (state.drawReason == DrawReason.agreement ||
              state.drawReason == DrawReason.timeoutVsInsufficientMaterial));

  /// How many plies [undo] would take back: one in analysis mode; in a bot
  /// game, back to the human's turn (two plies, or one if the bot hasn't
  /// replied yet). Zero when nothing can be undone.
  int undoPlies(GameState state) {
    if (state.pendingPromotion != null || _isFinalResult(state)) return 0;
    final n = state.moveHistory.length;
    if (n == 0) return 0;
    if (state.currentMode != GameMode.offline) return 1;
    final k = state.currentTurn == humanColor ? 2 : 1;
    return n >= k ? k : 0;
  }

  bool canUndo(GameState state) => undoPlies(state) > 0;

  bool canRedo(GameState state) =>
      _redo.isNotEmpty &&
      !state.isGameOver &&
      !state.isEngineThinking &&
      state.pendingPromotion == null;

  /// Takes back moves (see [undoPlies]). Stops any running engine search
  /// first; its reply is discarded.
  bool undo(GameState state) {
    final k = undoPlies(state);
    if (k == 0) return false;
    _cancelEngineWork(state);
    final history = List<String>.of(state.moveHistory);
    final keep = history.sublist(0, history.length - k);
    _redo.addAll(history.sublist(history.length - k).reversed);
    _rebuild(state, keep);
    return true;
  }

  /// Replays undone moves: one in analysis mode, back to the human's turn
  /// in a bot game.
  bool redo(GameState state) {
    if (!canRedo(state)) return false;
    _cancelEngineWork(state);
    final history = List<String>.of(state.moveHistory);
    do {
      history.add(_redo.removeLast());
    } while (state.currentMode == GameMode.offline &&
        _redo.isNotEmpty &&
        _turnAfter(state, history.length) != humanColor);
    try {
      _rebuild(state, history);
    } on StateError {
      _redo.clear(); // stale stack (shouldn't happen) — drop it
      _rebuild(state, history.sublist(0, state.moveHistory.length));
    }
    return true;
  }

  PieceColor _turnAfter(GameState state, int plies) {
    final startTurn = state.startFen.split(' ')[1] == 'b'
        ? PieceColor.black
        : PieceColor.white;
    return plies.isEven ? startTurn : ChessRules.opposite(startTurn);
  }

  /// Replays [moves] from the start position, keeping mode and evaluation.
  void _rebuild(GameState state, List<String> moves) {
    final mode = state.currentMode;
    final eval = state.evaluation;
    ChessRules.replay(state, state.startFen, moves);
    state.currentMode = mode;
    state.evaluation = eval;
    final clock = _clock;
    if (clock != null && clock.control.isTimed && clock.flagged == null) {
      state.isGameOver ? clock.stop() : clock.start(state.currentTurn);
    }
    _afterPositionChange(state);
  }

  // ================= GAME END =================

  /// The human (or, in analysis mode, the side to move) resigns.
  bool resign(GameState state, [PieceColor? color]) {
    if (state.isGameOver) return false;
    final who =
        color ??
        (state.currentMode == GameMode.offline
            ? humanColor
            : state.currentTurn);
    state.status = GameStatus.resigned;
    state.drawReason = null;
    state.loser = who;
    _endGame(state);
    return true;
  }

  /// [color]'s clock ran out: they lose, or it is a draw when the opponent
  /// has no mating material (FIDE 6.9).
  void handleFlag(GameState state, PieceColor color) {
    if (state.isGameOver) return;
    final opponent = ChessRules.opposite(color);
    if (ChessRules.hasMatingMaterial(state.board, opponent)) {
      state.status = GameStatus.timeout;
      state.drawReason = null;
      state.loser = color;
    } else {
      state.status = GameStatus.draw;
      state.drawReason = DrawReason.timeoutVsInsufficientMaterial;
      state.loser = null;
    }
    _endGame(state);
  }

  /// Offers the bot a draw. It accepts when, after move 20, its own
  /// evaluation is at most +0.3 pawns, or when the material is objectively
  /// drawish; otherwise it declines.
  Future<DrawOfferResult> offerDraw(GameState state) async {
    if (state.isGameOver || state.currentMode != GameMode.offline) {
      return DrawOfferResult.declined;
    }
    final epoch = _epoch;
    final key = FenConverter.positionKey(state);
    final drawish = ChessRules.isDrawishMaterial(state.board);
    var accept = drawish;
    if (!accept && state.fullmoveNumber > 20) {
      double? whiteEval;
      try {
        whiteEval = await _evaluator(state.clone());
      } catch (e) {
        debugPrint('Draw-offer evaluation failed: $e');
      }
      if (epoch != _epoch || state.isGameOver) return DrawOfferResult.declined;
      if (whiteEval != null) {
        final botEval = botColor == PieceColor.white ? whiteEval : -whiteEval;
        accept = botEval <= 0.3 && FenConverter.positionKey(state) == key;
      }
    }
    if (!accept) return DrawOfferResult.declined;
    state.status = GameStatus.draw;
    state.drawReason = DrawReason.agreement;
    state.loser = null;
    _endGame(state);
    return DrawOfferResult.accepted;
  }

  void _endGame(GameState state) {
    _cancelEngineWork(state, recomputeStatus: false);
    state.pendingPromotionMove = null;
    state.selectedPosition = null;
    state.validMoves = [];
    _clock?.stop();
    state.notifyListeners();
  }

  /// Invalidates any pending engine reply and stops the search.
  void _cancelEngineWork(GameState state, {bool recomputeStatus = true}) {
    _epoch++;
    if (state.isEngineThinking) {
      _engineService.stop();
      state.isEngineThinking = false;
      if (recomputeStatus && state.status == GameStatus.engineThinking) {
        ChessRules.updateStatus(state);
      }
    }
  }

  // ================= ENGINE =================

  Future<void> updateEvaluation(
    GameState state,
    ChessEngineService engineService,
  ) async {
    if (!engineService.isAvailable || state.isGameOver) return;
    final key = FenConverter.positionKey(state);
    try {
      final eval = await engineService.evaluatePosition(state);
      // Ignore results for a position we have since left.
      if (eval != null && FenConverter.positionKey(state) == key) {
        state.evaluation = eval;
        state.notifyListeners();
      }
    } catch (e) {
      debugPrint('Evaluation update error: $e');
    }
  }

  Future<String?> getEngineMove(
    GameState state,
    ChessEngineService engineService, {
    Duration moveTime = const Duration(seconds: 1),
    int? elo,
  }) async {
    if (!engineService.isAvailable) return null;
    try {
      return await engineService.getBestMove(
        state: state,
        moveTime: moveTime,
        elo: elo,
      );
    } catch (e) {
      debugPrint('Get engine move error: $e');
      return null;
    }
  }

  /// Default [BotMoveProvider]: asks the engine, on the clock when there is
  /// one, otherwise with a fixed think time.
  Future<String?> _engineBotMove(GameState state) async {
    if (!_engineService.isAvailable) return null;
    final c = _clock;
    if (c != null && c.control.isTimed) {
      return _engineService.getBestMove(
        state: state,
        elo: botElo,
        wtime: c.remaining(PieceColor.white),
        btime: c.remaining(PieceColor.black),
        winc: c.control.increment,
        binc: c.control.increment,
      );
    }
    return getEngineMove(
      state,
      _engineService,
      moveTime: botMoveTime,
      elo: botElo,
    );
  }

  void onMoveCompleted(GameState state) {
    if (!isBotTurn(state)) return;
    if (state.isGameOver || state.isEngineThinking) return;
    _requestBotMove(state, _botMoveProvider);
  }

  /// Analysis mode: the engine (full strength) plays the side to move.
  Future<void> playEngineMove(GameState state) async {
    if (state.isGameOver || state.isEngineThinking) return;
    await _requestBotMove(
      state,
      (s) => getEngineMove(
        s,
        _engineService,
        moveTime: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _requestBotMove(
    GameState state,
    BotMoveProvider provider,
  ) async {
    final epoch = _epoch;
    state.isEngineThinking = true;
    state.status = GameStatus.engineThinking;
    state.notifyListeners();

    String? move;
    try {
      move = await provider(state.clone());
    } catch (e) {
      debugPrint('Bot move error: $e');
    }
    if (epoch != _epoch) return; // undone / new game / game over meanwhile

    state.isEngineThinking = false;
    if (move == null) {
      debugPrint('Engine returned no move');
    } else if (!_playLive(state, move)) {
      debugPrint('Engine returned illegal move "$move" — ignored');
    } else {
      return;
    }
    // No move was played: restore the real status.
    if (state.status == GameStatus.engineThinking) {
      ChessRules.updateStatus(state);
    }
    state.notifyListeners();
  }
}
