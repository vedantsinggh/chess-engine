import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/game_state.dart';
import '../models/piece.dart';
import 'engine_loader.dart';

/// A UCI option advertised by the engine during the handshake.
class UciOption {
  final String name;
  final String type;
  final int? min;
  final int? max;
  const UciOption(this.name, this.type, this.min, this.max);
}

/// Talks UCI to an engine subprocess (the built-in "Rank" engine or Stockfish).
///
/// Every engine conversation (handshake, evaluation, best-move search) runs
/// through a single queue, so two requests can never interleave on the
/// engine's stdin/stdout or steal each other's `bestmove` reply.
class ChessEngineService {
  static final ChessEngineService _instance = ChessEngineService._internal();
  factory ChessEngineService() => _instance;
  ChessEngineService._internal();

  Process? _engine;
  bool _isReady = false;
  Future<bool>? _initFuture;

  String? _enginePath;
  String? _engineName;
  String? _engineAuthor;
  final Map<String, UciOption> _options = {};

  final StreamController<String> _outputController =
      StreamController<String>.broadcast();
  Stream<String> get outputStream => _outputController.stream;

  /// Live evaluation while the engine searches, in pawns from the point of
  /// view of the side to move (as UCI reports it).
  final StreamController<double> _evalController =
      StreamController<double>.broadcast();
  Stream<double> get liveEvalStream => _evalController.stream;

  Completer<void>? _uciOkCompleter;
  Completer<void>? _readyOkCompleter;
  Completer<String>? _bestMoveCompleter;
  double? _lastSearchEval;

  Future<void> _queue = Future.value();
  bool _evalPending = false;

  /// Strength currently configured on the engine (null = full strength).
  /// `_strengthKnown` is false until the first configuration.
  int? _configuredElo;
  bool _strengthKnown = false;
  int? _depthCap;

  bool get isAvailable => _isReady;
  String? get engineName => _engineName;
  String? get engineAuthor => _engineAuthor;
  String? get enginePath => _enginePath;
  Map<String, UciOption> get options => Map.unmodifiable(_options);

  // ─── Initialization ────────────────────────────────────────────────────────

  Future<bool> initialize() {
    if (_isReady) return Future.value(true);
    return _initFuture ??= _initialize().whenComplete(() => _initFuture = null);
  }

  Future<bool> _initialize() async {
    try {
      final binaryPath = await EngineLoader().findEngine();
      if (binaryPath == null) {
        debugPrint('No UCI engine found');
        return false;
      }
      debugPrint('Starting engine: $binaryPath');
      _enginePath = binaryPath;

      final proc = await Process.start(binaryPath, []);
      _engine = proc;

      proc.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_handleOutput);
      proc.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => debugPrint('engine stderr: $line'));
      proc.exitCode.then((code) {
        debugPrint('Engine exited with code $code');
        if (identical(_engine, proc)) _onEngineGone();
      });

      await _serialized(_handshake);
      _isReady = true;
      debugPrint('Engine ready — $_engineName by $_engineAuthor');
      return true;
    } catch (e, st) {
      debugPrint('Failed to initialize engine: $e\n$st');
      _engine?.kill();
      _onEngineGone();
      return false;
    }
  }

  Future<void> _handshake() async {
    _options.clear();
    _uciOkCompleter = Completer<void>();
    _sendCommand('uci');
    await _uciOkCompleter!.future.timeout(const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException('uciok timeout'));

    final threads = _options['Threads'];
    if (threads != null) {
      final want = (Platform.numberOfProcessors / 2).ceil().clamp(1, 4);
      _setOption('Threads', _clampTo(threads, want));
    }
    final hash = _options['Hash'];
    if (hash != null) _setOption('Hash', _clampTo(hash, 128));

    _strengthKnown = false;
    await _sync();
  }

  int _clampTo(UciOption o, int v) =>
      v.clamp(o.min ?? v, o.max ?? v);

  /// `isready` / `readyok` round-trip: the engine has processed everything sent.
  Future<void> _sync() async {
    _readyOkCompleter = Completer<void>();
    _sendCommand('isready');
    await _readyOkCompleter!.future.timeout(const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException('readyok timeout'));
  }

  // ─── Output handling ───────────────────────────────────────────────────────

  void _handleOutput(String line) {
    _outputController.add(line);

    if (line.startsWith('id name ')) {
      _engineName = line.substring(8).trim();
    } else if (line.startsWith('id author ')) {
      _engineAuthor = line.substring(10).trim();
    } else if (line.startsWith('option name ')) {
      _parseOption(line);
    } else if (line == 'uciok') {
      _uciOkCompleter?.complete();
      _uciOkCompleter = null;
    } else if (line == 'readyok') {
      _readyOkCompleter?.complete();
      _readyOkCompleter = null;
    } else if (line.startsWith('bestmove')) {
      _bestMoveCompleter?.complete(line);
      _bestMoveCompleter = null;
    } else if (line.startsWith('info') && line.contains(' score ')) {
      _handleInfoScore(line);
    }
  }

  void _parseOption(String line) {
    final m = RegExp(r'^option name (.+?) type (\S+)').firstMatch(line);
    if (m == null) return;
    final min = RegExp(r' min (-?\d+)').firstMatch(line);
    final max = RegExp(r' max (-?\d+)').firstMatch(line);
    final name = m.group(1)!;
    _options[name] = UciOption(
      name,
      m.group(2)!,
      min == null ? null : int.parse(min.group(1)!),
      max == null ? null : int.parse(max.group(1)!),
    );
  }

  void _handleInfoScore(String line) {
    double? pawns;
    final cp = RegExp(r'score cp (-?\d+)').firstMatch(line);
    if (cp != null) {
      pawns = (int.parse(cp.group(1)!) / 100.0).clamp(-10.0, 10.0);
    } else {
      final mate = RegExp(r'score mate (-?\d+)').firstMatch(line);
      if (mate != null) pawns = int.parse(mate.group(1)!) > 0 ? 10.0 : -10.0;
    }
    if (pawns == null) return;
    _lastSearchEval = pawns;
    _evalController.add(pawns);
  }

  void _onEngineGone() {
    _isReady = false;
    _engine = null;
    _strengthKnown = false;
    // Unblock anyone waiting on a reply that will never come.
    _uciOkCompleter?.completeError(StateError('engine exited'));
    _readyOkCompleter?.completeError(StateError('engine exited'));
    _bestMoveCompleter?.complete('');
    _uciOkCompleter = null;
    _readyOkCompleter = null;
    _bestMoveCompleter = null;
  }

  // ─── Public API ────────────────────────────────────────────────────────────

  /// Evaluates the position with a short search. Returns pawns from White's
  /// point of view, or null if unavailable. If an evaluation is already
  /// waiting in the queue this returns null instead of piling up another.
  Future<double?> evaluatePosition(GameState state,
      {Duration moveTime = const Duration(milliseconds: 300)}) async {
    if (!_isReady || _evalPending) return null;
    _evalPending = true;
    final position = _positionCommand(state);
    final whiteToMove = state.currentTurn == PieceColor.white;
    try {
      return await _serialized(() async {
        _evalPending = false;
        await _configureStrength(null);
        final r = await _search(position, 'go movetime ${moveTime.inMilliseconds}',
            moveTime + const Duration(seconds: 3));
        if (r.eval == null) return null;
        return whiteToMove ? r.eval : -r.eval!;
      });
    } catch (e) {
      debugPrint('evaluatePosition error: $e');
      return null;
    } finally {
      _evalPending = false;
    }
  }

  /// Best move for [state] in UCI notation (e.g. "e2e4", "e7e8q").
  ///
  /// [elo] limits playing strength (null = full strength). It uses the
  /// engine's UCI_LimitStrength/UCI_Elo or "Skill Level" options when it has
  /// them, and caps search depth below the engine's minimum Elo.
  ///
  /// When [wtime] and [btime] are given the engine manages its own time
  /// (`go wtime .. btime .. winc .. binc ..`) and [moveTime] is ignored.
  Future<String?> getBestMove({
    required GameState state,
    Duration moveTime = const Duration(milliseconds: 1000),
    int depth = 0,
    int? elo,
    Duration? wtime,
    Duration? btime,
    Duration winc = Duration.zero,
    Duration binc = Duration.zero,
  }) async {
    if (!_isReady) return null;
    final position = _positionCommand(state);
    final onClock = wtime != null && btime != null;
    final ownTime = state.currentTurn == PieceColor.white ? wtime : btime;
    try {
      return await _serialized(() async {
        await _configureStrength(elo);
        final d = depth > 0 ? depth : (_depthCap ?? 0);
        final go = goCommand(
          moveTime: onClock ? null : moveTime,
          depth: d,
          wtime: wtime,
          btime: btime,
          winc: winc,
          binc: binc,
        );
        final budget = onClock ? ownTime! : moveTime;
        final r = await _search(position, go, budget + const Duration(seconds: 3));
        return r.bestMove;
      });
    } catch (e) {
      debugPrint('getBestMove error: $e');
      return null;
    }
  }

  /// Builds a UCI `go` command. Exposed for tests.
  @visibleForTesting
  static String goCommand({
    Duration? moveTime,
    int depth = 0,
    Duration? wtime,
    Duration? btime,
    Duration winc = Duration.zero,
    Duration binc = Duration.zero,
  }) {
    var go = 'go';
    if (wtime != null && btime != null) {
      go += ' wtime ${wtime.inMilliseconds} btime ${btime.inMilliseconds}'
          ' winc ${winc.inMilliseconds} binc ${binc.inMilliseconds}';
    } else if (moveTime != null && moveTime > Duration.zero) {
      go += ' movetime ${moveTime.inMilliseconds}';
    }
    if (depth > 0) go += ' depth $depth';
    return go;
  }

  Map<String, String> getEngineInfo() => {
        if (_engineName != null) 'name': _engineName!,
        if (_engineAuthor != null) 'author': _engineAuthor!,
        if (_enginePath != null) 'path': _enginePath!,
      };

  /// Interrupts the current search; its `getBestMove` returns early.
  void stop() {
    if (_bestMoveCompleter != null) _sendCommand('stop');
  }

  /// Shuts down the engine process. The service can be re-initialized later.
  void dispose() {
    final proc = _engine;
    if (proc == null) return;
    try {
      _sendCommand('quit');
      Future.delayed(const Duration(milliseconds: 300), () => proc.kill());
    } catch (e) {
      debugPrint('Error stopping engine: $e');
    }
    _onEngineGone();
  }

  // ─── Internal helpers ──────────────────────────────────────────────────────

  /// Runs [task] after every previously queued engine task has finished.
  Future<T> _serialized<T>(Future<T> Function() task) {
    final result = _queue.then((_) => task());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// `position` command that includes the move history, so the engine can
  /// see repetitions and the real 50-move counter.
  String _positionCommand(GameState state) {
    final base = state.startFen == GameState.startPositionFen
        ? 'position startpos'
        : 'position fen ${state.startFen}';
    return state.moveHistory.isEmpty
        ? base
        : '$base moves ${state.moveHistory.join(' ')}';
  }

  Future<({String? bestMove, double? eval})> _search(
      String position, String go, Duration timeout) async {
    if (_engine == null) return (bestMove: null, eval: null);
    _sendCommand(position);
    await _sync();

    _lastSearchEval = null;
    final completer = _bestMoveCompleter = Completer<String>();
    _sendCommand(go);

    var line = await completer.future.timeout(timeout, onTimeout: () async {
      debugPrint('Search timed out — sending stop');
      _sendCommand('stop');
      // Wait for the engine's real bestmove so it can't leak into the next
      // request.
      return completer.future
          .timeout(const Duration(seconds: 2), onTimeout: () => '');
    });
    if (identical(_bestMoveCompleter, completer)) _bestMoveCompleter = null;

    final m = RegExp(r'^bestmove\s+(\S+)').firstMatch(line);
    var move = m?.group(1);
    if (move == '0000' || move == '(none)') move = null;
    return (bestMove: move, eval: _lastSearchEval);
  }

  Future<void> _configureStrength(int? elo) async {
    if (_strengthKnown && elo == _configuredElo) return;
    _configuredElo = elo;
    _strengthKnown = true;
    _depthCap = null;

    final limit = _options['UCI_LimitStrength'];
    final uciElo = _options['UCI_Elo'];
    final skill = _options['Skill Level'];

    void fullStrength() {
      if (limit != null) _setOption('UCI_LimitStrength', 'false');
      if (skill != null) _setOption('Skill Level', skill.max ?? 20);
    }

    if (elo == null) {
      fullStrength();
    } else if (uciElo != null && limit != null) {
      final min = uciElo.min ?? 0, max = uciElo.max ?? 1 << 30;
      if (elo >= max) {
        fullStrength();
      } else if (elo >= min) {
        if (skill != null) _setOption('Skill Level', skill.max ?? 20);
        _setOption('UCI_LimitStrength', 'true');
        _setOption('UCI_Elo', elo);
      } else {
        // Weaker than the engine can limit itself to: use its floor and also
        // cap search depth.
        _setOption('UCI_LimitStrength', 'true');
        _setOption('UCI_Elo', min);
        if (skill != null) _setOption('Skill Level', skill.min ?? 0);
        _depthCap = _depthForElo(elo);
      }
    } else if (skill != null) {
      final lo = skill.min ?? 0, hi = skill.max ?? 20;
      // Map ~400..2800 Elo onto the skill range.
      final t = ((elo - 400) / 2400).clamp(0.0, 1.0);
      _setOption('Skill Level', (lo + (hi - lo) * t).round());
      if (elo < 1200) _depthCap = _depthForElo(elo);
    } else {
      _depthCap = _depthForElo(elo);
    }
    await _sync();
  }

  int _depthForElo(int elo) {
    if (elo < 800) return 1;
    if (elo < 1200) return 2;
    if (elo < 1600) return 4;
    if (elo < 2000) return 6;
    return 10;
  }

  void _setOption(String name, Object value) =>
      _sendCommand('setoption name $name value $value');

  void _sendCommand(String command) {
    final proc = _engine;
    if (proc == null) {
      debugPrint('Cannot send command — engine not running: $command');
      return;
    }
    try {
      debugPrint('-> $command');
      proc.stdin.writeln(command);
    } catch (e) {
      debugPrint('Error sending command: $e');
      _onEngineGone();
    }
  }
}
