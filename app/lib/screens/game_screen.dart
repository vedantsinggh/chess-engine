import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/game_state.dart';
import '../models/piece.dart';
import '../models/time_control.dart';
import '../services/chess_clock.dart';
import '../services/game_service.dart';
import '../services/chess_engine_service.dart';
import '../services/settings_controller.dart';
import '../utils/chess_rules.dart';
import '../widgets/chess_board.dart';
import '../widgets/game_controls.dart';
import '../widgets/move_list.dart';
import '../widgets/promotion_dialog.dart';
import 'game/bot_profiles.dart';
import 'game/bot_selection_sheet.dart';
import 'game/dev_panel.dart';
import 'game/eval_bar_card.dart';
import 'game/fen_panel.dart';
import 'game/game_action_bar.dart';
import 'game/player_bar.dart';
import 'game/player_chip.dart';
import 'game/status_banner.dart';

export 'game/bot_profiles.dart';
export 'game/bot_selection_sheet.dart';

// ─────────────────────────────────────────────
// DEVELOPER FLAG — set to false before release
// ─────────────────────────────────────────────
const bool kDevMode = false;

// ─────────────────────────────────────────────
// MAIN GAME SCREEN
// ─────────────────────────────────────────────

class GameScreen extends StatefulWidget {
  final String mode;
  const GameScreen({super.key, required this.mode});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  late GameService _gameService;
  late ChessEngineService _engineService;
  late GameState _gameState;

  bool _isEngineInitialized = false;
  BotProfile _currentBot = kBotProfiles[0]; // full strength by default
  SideChoice _side = SideChoice.white;
  TimeControl _timeControl = TimeControl.none;

  /// Board drawn from Black's side.
  bool _flipped = false;

  /// Ply being reviewed (null = live position) and its replayed state.
  int? _viewPly;
  GameState? _viewState;

  bool _offeringDraw = false;

  StreamSubscription<double>? _evalSubscription;

  // Whether we're in offline (vs bot) or engine (analysis) mode
  bool get _isAnalysisMode => widget.mode == 'engine';

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _engineService = ChessEngineService();
    _gameService = GameService(_engineService);
    _gameState = GameState()..currentMode = _getModeFromString(widget.mode);
    _gameState.addListener(_onGameChanged);

    final settings = context.read<SettingsController>();
    _currentBot = botProfileById(settings.defaultBotId) ?? kBotProfiles[0];
    _timeControl = settings.defaultTimeControl;

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();

    _applyBotStrength();
    _initializeEngine();
    if (!_isAnalysisMode) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _showBotSelection(initial: true),
      );
    }
  }

  @override
  void dispose() {
    if (_gameState.isEngineThinking) _engineService.stop();
    _gameService.dispose();
    _gameState.removeListener(_onGameChanged);
    _evalSubscription?.cancel();
    _fadeCtrl.dispose();
    super.dispose();
  }

  /// Drops a review position that no longer exists (e.g. after undo).
  void _onGameChanged() {
    final v = _viewPly;
    if (v != null && v >= _gameState.moveHistory.length) {
      setState(() {
        _viewPly = null;
        _viewState = null;
      });
    }
  }

  Future<void> _initializeEngine() async {
    final ok = await _engineService.initialize();
    if (!mounted) return;
    setState(() => _isEngineInitialized = ok);
    if (!ok) {
      if (!_isAnalysisMode) _showEngineError();
      return;
    }
    _evalSubscription = _engineService.liveEvalStream.listen((pawns) {
      if (!mounted) return;
      final relative = _gameState.currentTurn == PieceColor.black
          ? -pawns
          : pawns;
      _gameState.evaluation = relative;
      _gameState.notifyListeners();
    });
    if (_isAnalysisMode) {
      _gameService.updateEvaluation(_gameState, _engineService);
    } else {
      // The bot may already be waiting to make its first move.
      _gameService.onMoveCompleted(_gameState);
    }
  }

  void _showEngineError() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Engine Unavailable'),
        content: const Text(
          'Chess engine could not be loaded. Offline mode is still available.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _showBotSelection({bool initial = false}) async {
    final result = await showModalBottomSheet<BotGameSetup>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BotSelectionSheet(
        currentBot: _currentBot,
        side: _side,
        timeControl: _timeControl,
      ),
    );
    if (!mounted) return;
    if (result != null) {
      _startBotGame(result);
    } else if (initial) {
      // Dismissed: play with the current (default) setup.
      _startBotGame(BotGameSetup(_currentBot, _side, _timeControl));
    }
  }

  void _startBotGame(BotGameSetup setup) {
    final human = switch (setup.side) {
      SideChoice.white => PieceColor.white,
      SideChoice.black => PieceColor.black,
      SideChoice.random =>
        Random().nextBool() ? PieceColor.white : PieceColor.black,
    };
    setState(() {
      _currentBot = setup.bot;
      _side = setup.side;
      _timeControl = setup.timeControl;
      _flipped = human == PieceColor.black;
      _viewPly = null;
      _viewState = null;
    });
    _applyBotStrength();
    _gameService.startNewGame(
      _gameState,
      botColor: ChessRules.opposite(human),
      clock: setup.timeControl.isTimed ? ChessClock(setup.timeControl) : null,
    );
  }

  /// The top bot plays at full strength; the others are Elo-limited.
  void _applyBotStrength() {
    _gameService.botElo = identical(_currentBot, kBotProfiles.first)
        ? null
        : _currentBot.eloRating;
  }

  void _newGame() {
    if (_isAnalysisMode) {
      setState(() {
        _viewPly = null;
        _viewState = null;
      });
      _gameService.startNewGame(_gameState);
    } else {
      _startBotGame(BotGameSetup(_currentBot, _side, _timeControl));
    }
  }

  // ─── Review / undo / game end ─────────────────────────────────────────────

  void _setView(int? ply) {
    final n = _gameState.moveHistory.length;
    setState(() {
      if (ply == null || ply >= n || ply < 0) {
        _viewPly = null;
        _viewState = null;
      } else {
        _viewPly = ply;
        _viewState = ChessRules.positionAt(_gameState, ply);
      }
    });
  }

  bool get _canGoBack => (_viewPly ?? _gameState.moveHistory.length) > 0;
  bool get _canGoForward => _viewPly != null;

  void _viewBack() {
    if (_canGoBack) _setView((_viewPly ?? _gameState.moveHistory.length) - 1);
  }

  void _viewForward() {
    if (_canGoForward) _setView(_viewPly! + 1);
  }

  void _undo() {
    _setView(null);
    _gameService.undo(_gameState);
  }

  void _redo() {
    _setView(null);
    _gameService.redo(_gameState);
  }

  Future<void> _confirmResign() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Resign?'),
        content: const Text('The game will be scored as a loss.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('RESIGN'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) _gameService.resign(_gameState);
  }

  Future<void> _offerDraw() async {
    if (_offeringDraw) return;
    setState(() => _offeringDraw = true);
    final result = await _gameService.offerDraw(_gameState);
    if (!mounted) return;
    setState(() => _offeringDraw = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result == DrawOfferResult.accepted
              ? '${_currentBot.name} accepts the draw.'
              : '${_currentBot.name} declines the draw offer.',
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    // Leave arrow keys to text fields (FEN input).
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused != null &&
        focused.findAncestorStateOfType<EditableTextState>() != null) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _viewBack();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _viewForward();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ─── Layout sizing ────────────────────────────────────────────────────────

  // Breakpoints
  bool _isMobile(Size s) => s.width < 600;
  bool _isTablet(Size s) => s.width >= 600 && s.width < 1024;
  bool _isDesktop(Size s) => s.width >= 1024;

  double _boardSize(Size s) {
    if (_isDesktop(s)) return (s.width * 0.52).clamp(420.0, 700.0);
    if (_isTablet(s)) return (s.width * 0.58).clamp(340.0, 560.0);
    // Mobile: fill width minus padding, also respect height so board
    // doesn't overflow on landscape phones
    final byWidth = s.width - 32;
    final byHeight = s.height * 0.52;
    return byWidth.clamp(0.0, byHeight.clamp(240.0, 480.0));
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    _gameService.autoQueen = context.watch<SettingsController>().autoQueen;
    return ChangeNotifierProvider.value(
      value: _gameState,
      child: Consumer<GameState>(
        builder: (context, state, _) {
          final size = MediaQuery.of(context).size;

          return Scaffold(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            appBar: _buildAppBar(context, state),
            body: Focus(
              autofocus: true,
              onKeyEvent: _onKey,
              child: FadeTransition(
                opacity: _fadeAnim,
                child: _isMobile(size)
                    ? _buildMobileLayout(context, state, size)
                    : _buildWideLayout(context, state, size),
              ),
            ),
          );
        },
      ),
    );
  }

  // ─── AppBar ───────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar(BuildContext context, GameState state) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? Colors.white : Colors.black;

    return AppBar(
      backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
      foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => Navigator.pop(context),
      ),
      title: _isAnalysisMode
          ? _analysisTitleWidget(fg)
          : _botTitleWidget(state),
      actions: [
        // Spinner while engine is thinking
        if (state.isEngineThinking)
          Padding(
            padding: const EdgeInsets.all(14),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: fg),
            ),
          ),
        // Offline vs bot: new game with a different setup
        if (!_isAnalysisMode)
          IconButton(
            icon: const Icon(Icons.swap_horiz_rounded),
            tooltip: 'Change Bot',
            onPressed: () => _showBotSelection(),
          ),
        // New game / Reset
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          tooltip: _isAnalysisMode ? 'Reset Board' : 'New Game',
          onPressed: _newGame,
        ),
        if (kDevMode)
          const IconButton(
            icon: Icon(Icons.terminal_rounded, color: Color(0xFF6366F1)),
            tooltip: 'Dev',
            onPressed: null,
          ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _botTitleWidget(GameState state) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: Icon(
            _currentBot.icon,
            key: ValueKey(_currentBot.id),
            color: _currentBot.accentColor,
            size: 20,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            _currentBot.name,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: _currentBot.accentColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '${_currentBot.eloRating}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: _currentBot.accentColor,
            ),
          ),
        ),
      ],
    );
  }

  Widget _analysisTitleWidget(Color fg) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.bar_chart_rounded,
          size: 20,
          color: fg.withValues(alpha: 0.7),
        ),
        const SizedBox(width: 8),
        const Flexible(
          child: Text(
            'ENGINE ANALYSIS',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1),
          ),
        ),
      ],
    );
  }

  // ─── Shared pieces ────────────────────────────────────────────────────────

  Widget _playerBar(GameState state, PieceColor color, bool isDark) {
    final isBot = color == _gameService.botColor;
    final active = state.currentTurn == color && !state.isGameOver;
    final chip = isBot
        ? PlayerChip(
            name: _currentBot.name,
            icon: _currentBot.icon,
            accentColor: _currentBot.accentColor,
            isActive: active,
            isDark: isDark,
            subtitle: state.isEngineThinking
                ? 'Thinking…'
                : '${_currentBot.eloRating} ELO',
          )
        : PlayerChip(
            name: 'You',
            icon: Icons.person_rounded,
            isActive: active,
            isDark: isDark,
            subtitle: state.isGameOver
                ? (color == PieceColor.white ? 'White' : 'Black')
                : (active ? 'Your turn' : 'Waiting…'),
          );
    return PlayerBar(chip: chip, color: color, clock: _gameService.clock);
  }

  Widget _board(double boardSz) {
    return SizedBox(
      width: boardSz,
      height: boardSz,
      child: Stack(
        children: [
          ChessBoard(
            gameService: _gameService,
            flipped: _flipped,
            viewState: _viewState,
          ),
          if (_viewState == null)
            Consumer<GameState>(
              builder: (context, s, _) =>
                  PromotionDialog(state: s, gameService: _gameService),
            ),
        ],
      ),
    );
  }

  Widget _actionBar(GameState state) {
    final svc = _gameService;
    return GameActionBar(
      onUndo: svc.canUndo(state) ? _undo : null,
      onRedo: svc.canRedo(state) ? _redo : null,
      onFlip: () => setState(() => _flipped = !_flipped),
      showGameEndActions: !_isAnalysisMode,
      onOfferDraw: state.isGameOver || _offeringDraw ? null : _offerDraw,
      onResign: state.isGameOver ? null : _confirmResign,
    );
  }

  Widget _moveList(GameState state, double height) {
    final n = state.moveHistory.length;
    return MoveList(
      sanMoves: state.sanHistory,
      startFen: state.startFen,
      viewPly: _viewPly,
      height: height,
      onSelectPly: _setView,
      onFirst: n > 0 && _viewPly != 0 ? () => _setView(0) : null,
      onBack: _canGoBack ? _viewBack : null,
      onForward: _canGoForward ? _viewForward : null,
      onLive: _viewPly != null ? () => _setView(null) : null,
    );
  }

  Widget _controls() => GameControls(
    gameService: _gameService,
    engineService: _engineService,
    engineAvailable: _isEngineInitialized,
    onEngineMoveRequested: () {
      _setView(null);
      _gameService.playEngineMove(_gameState);
    },
  );

  PieceColor get _topColor => _flipped ? PieceColor.white : PieceColor.black;

  // ─── Mobile layout ────────────────────────────────────────────────────────

  Widget _buildMobileLayout(BuildContext context, GameState state, Size size) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final boardSz = _boardSize(size);
    final human = _isAnalysisMode ? null : _gameService.humanColor;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          StatusBanner(state: state, humanColor: human),

          // Analysis mode: FEN panel at top on mobile
          if (_isAnalysisMode) ...[
            FenPanel(
              state: state,
              gameService: _gameService,
              engineService: _engineService,
            ),
            const SizedBox(height: 12),
          ],

          if (!_isAnalysisMode) ...[
            SizedBox(
              width: boardSz,
              child: _playerBar(state, _topColor, isDark),
            ),
            const SizedBox(height: 8),
          ],

          Center(child: _board(boardSz)),

          if (!_isAnalysisMode) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: boardSz,
              child: _playerBar(state, ChessRules.opposite(_topColor), isDark),
            ),
          ],

          const SizedBox(height: 12),
          _actionBar(state),
          const SizedBox(height: 12),
          _moveList(state, 150),
          const SizedBox(height: 12),

          // Eval bar — analysis mode only
          if (_isAnalysisMode && _isEngineInitialized) ...[
            EvalBarCard(evaluation: state.evaluation, isDark: isDark),
            const SizedBox(height: 12),
          ],

          _controls(),

          if (kDevMode && !_isAnalysisMode) ...[
            const SizedBox(height: 12),
            DevPanel(bot: _currentBot, state: state),
          ],

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ─── Wide layout (tablet + desktop) ──────────────────────────────────────

  Widget _buildWideLayout(BuildContext context, GameState state, Size size) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDesktop = _isDesktop(size);
    final boardSz = _boardSize(size);
    final sideWidth = isDesktop ? 320.0 : 260.0;
    final human = _isAnalysisMode ? null : _gameService.humanColor;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1400),
        child: Padding(
          padding: EdgeInsets.all(isDesktop ? 32 : 20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Board column
              Flexible(
                flex: 3,
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        StatusBanner(state: state, humanColor: human),
                        if (!_isAnalysisMode)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: SizedBox(
                              width: boardSz,
                              child: _playerBar(state, _topColor, isDark),
                            ),
                          ),
                        _board(boardSz),
                        if (!_isAnalysisMode)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: SizedBox(
                              width: boardSz,
                              child: _playerBar(
                                state,
                                ChessRules.opposite(_topColor),
                                isDark,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(width: isDesktop ? 36 : 22),
              // Side panel
              SizedBox(
                width: sideWidth,
                child: _buildSidePanel(context, state, isDark),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSidePanel(BuildContext context, GameState state, bool isDark) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Analysis: FEN panel
          if (_isAnalysisMode) ...[
            FenPanel(
              state: state,
              gameService: _gameService,
              engineService: _engineService,
            ),
            const SizedBox(height: 16),
          ],

          // Analysis: eval bar
          if (_isAnalysisMode && _isEngineInitialized) ...[
            EvalBarCard(evaluation: state.evaluation, isDark: isDark),
            const SizedBox(height: 16),
          ],

          _actionBar(state),
          const SizedBox(height: 16),
          _moveList(state, 240),
          const SizedBox(height: 4),

          _controls(),

          if (kDevMode && !_isAnalysisMode) ...[
            const SizedBox(height: 12),
            DevPanel(bot: _currentBot, state: state),
          ],
        ],
      ),
    );
  }

  GameMode _getModeFromString(String mode) {
    switch (mode) {
      case 'offline':
        return GameMode.offline;
      case 'engine':
        return GameMode.engine;
      default:
        return GameMode.offline;
    }
  }
}
