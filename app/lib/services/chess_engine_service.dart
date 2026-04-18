import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/game_state.dart';
import '../utils/fen_converter.dart';

class ChessEngineService {
  static final ChessEngineService _instance = ChessEngineService._internal();
  factory ChessEngineService() => _instance;
  ChessEngineService._internal();

  Process? _engine;
  bool _isReady = false;
  bool _isSearching = false;

  // Cached engine identity filled during the initial UCI handshake.
  String? _engineName;
  String? _engineAuthor;

  // Broadcast stream of raw engine output lines (useful for debugging).
  final StreamController<String> _outputController =
      StreamController<String>.broadcast();
  Stream<String> get outputStream => _outputController.stream;

  // Live evaluation stream — emits centipawn values as the engine searches.
  // Positive = white advantage, negative = black advantage.
  final StreamController<double> _evalController =
      StreamController<double>.broadcast();
  Stream<double> get liveEvalStream => _evalController.stream;

  // Completers for pending synchronous-style commands.
  Completer<void>? _uciOkCompleter;
  Completer<void>? _readyOkCompleter;
  Completer<String>? _bestMoveCompleter;

  bool get isAvailable => _isReady;
  String? get engineName => _engineName;
  String? get engineAuthor => _engineAuthor;

  // ─── Initialization ────────────────────────────────────────────────────────

  Future<bool> initialize() async {
    if (_isReady) return true;

    // Engine process exists but hasn't finished init yet — wait briefly.
    if (_engine != null) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (_isReady) return true;
    }

    try {
      final binaryPath = await _getBinaryPath();
      if (binaryPath == null) {
        debugPrint('Stockfish binary not found');
        return false;
      }

      debugPrint('Starting Stockfish from: $binaryPath');

      _engine = await Process.start(
        binaryPath,
        [],
        environment: Platform.environment,
      );

      _engine!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_handleOutput);

      _engine!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => debugPrint('Stockfish stderr: $line'));

      _engine!.exitCode.then((code) {
        debugPrint('Stockfish exited with code $code');
        _isReady = false;
        _engine = null;
      });

      await _initializeUCI();

      _isReady = true;
      debugPrint('Stockfish ready — $_engineName by $_engineAuthor');
      return true;
    } catch (e, st) {
      debugPrint('Failed to initialize Stockfish: $e\n$st');
      _isReady = false;
      return false;
    }
  }

  // ─── Path discovery ────────────────────────────────────────────────────────

  /// Returns the absolute path to the Stockfish binary, or null if not found.
  ///
  /// Search order:
  ///   1. Well-known system paths for each platform.
  ///   2. The app-support directory (where settings_screen downloads it).
  ///   3. PATH lookup via `which` / `where`.
  Future<String?> _getBinaryPath() async {
    final candidates = <String>[];

    if (Platform.isLinux) {
      candidates.addAll([
        '/usr/local/bin/stockfish',
        '/usr/local/lib/stockfish',
        '/usr/bin/stockfish',
      ]);
    } else if (Platform.isWindows) {
      candidates.addAll([
        'C:\\stockfish\\stockfish.exe',
        'C:\\Program Files\\stockfish\\stockfish.exe',
      ]);
    } else if (Platform.isMacOS) {
      candidates.addAll([
        '/usr/local/bin/stockfish',
        '/opt/homebrew/bin/stockfish',
      ]);
    }

    // App-support directory — where the in-app downloader places the binary.
    try {
      // Avoid importing path_provider here; ask the platform directly.
      final supportDir = await _getAppSupportDir();
      if (supportDir != null) {
        final fileName = Platform.isWindows ? 'stockfish.exe' : 'stockfish';
        candidates.add('$supportDir/$fileName');
      }
    } catch (_) {}

    for (final path in candidates) {
      try {
        if (await File(path).exists()) {
          if (!Platform.isWindows) {
            await Process.run('chmod', ['+x', path]);
          }
          return path;
        }
      } catch (e) {
        debugPrint('Error checking $path: $e');
      }
    }

    // Last resort: PATH lookup.
    if (Platform.isLinux || Platform.isMacOS) {
      try {
        final result = await Process.run('which', ['stockfish']);
        if (result.exitCode == 0) {
          final p = (result.stdout as String).trim();
          if (p.isNotEmpty) return p;
        }
      } catch (_) {}
    }

    if (Platform.isWindows) {
      try {
        final result = await Process.run('where', ['stockfish']);
        if (result.exitCode == 0) {
          final p = (result.stdout as String).trim().split('\n').first.trim();
          if (p.isNotEmpty) return p;
        }
      } catch (_) {}
    }

    return null;
  }

  /// Returns the app-support directory path using only dart:io, without
  /// importing the path_provider package into this service.
  Future<String?> _getAppSupportDir() async {
    if (Platform.isLinux) {
      final home = Platform.environment['HOME'];
      return home != null ? '$home/.local/share/chess_app' : null;
    } else if (Platform.isMacOS) {
      final home = Platform.environment['HOME'];
      return home != null
          ? '$home/Library/Application Support/chess_app'
          : null;
    } else if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      return appData != null ? '$appData\\chess_app' : null;
    }
    return null;
  }

  // ─── UCI handshake ─────────────────────────────────────────────────────────

  Future<void> _initializeUCI() async {
    _uciOkCompleter = Completer<void>();
    _sendCommand('uci');

    await _uciOkCompleter!.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => throw TimeoutException('uciok timeout'),
    );

    await Future.delayed(const Duration(milliseconds: 100));

    _sendCommand('setoption name Threads value ${_getOptimalThreads()}');
    await Future.delayed(const Duration(milliseconds: 50));
    _sendCommand('setoption name Hash value 128');
    await Future.delayed(const Duration(milliseconds: 50));

    _readyOkCompleter = Completer<void>();
    _sendCommand('isready');

    await _readyOkCompleter!.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => throw TimeoutException('readyok timeout'),
    );
  }

  int _getOptimalThreads() {
    final cores = Platform.numberOfProcessors;
    return (cores / 2).ceil().clamp(1, 4);
  }

  // ─── Output handling ───────────────────────────────────────────────────────

  void _handleOutput(String line) {
    debugPrint('<- $line');
    _outputController.add(line);

    if (line.startsWith('id name')) {
      // Capture engine name during the initial UCI handshake.
      _engineName = line.substring(7).trim();
    } else if (line.startsWith('id author')) {
      _engineAuthor = line.substring(9).trim();
    } else if (line == 'uciok') {
      _uciOkCompleter?.complete();
      _uciOkCompleter = null;
    } else if (line == 'readyok') {
      _readyOkCompleter?.complete();
      _readyOkCompleter = null;
    } else if (line.startsWith('bestmove')) {
      _bestMoveCompleter?.complete(line);
      _bestMoveCompleter = null;
      _isSearching = false;
    } else if (line.startsWith('info') && line.contains('score cp')) {
      _handleInfoScore(line);
    }
  }

  /// Parses centipawn score from an `info` line and pushes it to the live
  /// evaluation stream so the UI updates in real-time during search.
  ///
  /// FIX: previously this parsed the value and discarded it.
  void _handleInfoScore(String line) {
    // Format: "info depth N seldepth N score cp ±N ..."
    // Also handle mate scores: "score mate N" — treat as ±10_000 cp.
    final cpMatch = RegExp(r'score cp\s+([+-]?\d+)').firstMatch(line);
    if (cpMatch != null) {
      final cp = int.parse(cpMatch.group(1)!);
      // Convert centipawns to pawns, clamped to ±10 for the UI bar.
      final pawns = (cp / 100.0).clamp(-10.0, 10.0);
      _evalController.add(pawns);
      return;
    }

    final mateMatch = RegExp(r'score mate\s+([+-]?\d+)').firstMatch(line);
    if (mateMatch != null) {
      final moves = int.parse(mateMatch.group(1)!);
      _evalController.add(moves > 0 ? 10.0 : -10.0);
    }
  }

  // ─── Public API ────────────────────────────────────────────────────────────

  /// Set the board position by FEN string.
  Future<void> setPosition({String? fen}) async {
    if (!_isReady) throw Exception('Engine not initialized');

    if (fen != null && fen.isNotEmpty) {
      _sendCommand('position fen $fen');
    } else {
      _sendCommand('position startpos');
    }

    await Future.delayed(const Duration(milliseconds: 50));
  }

  /// Evaluate the current position and return the score in pawns from
  /// White's perspective.
  ///
  /// FIX: the old implementation used Stockfish's `eval` command, which is a
  /// non-UCI debug command absent in many builds and always times out in
  /// release binaries.  We now run a short timed search and read the score
  /// from the final `info score cp` line — the same data the live bar already
  /// receives — which works with every UCI-compliant engine.
  Future<double> evaluatePosition(GameState state) async {
    if (!_isReady) return 0.0;
    if (_isSearching) return 0.0; // Don't interrupt an ongoing search.

    try {
      final fen = FenConverter.boardToFen(state);
      await setPosition(fen: fen);

      _isSearching = true;
      _bestMoveCompleter = Completer<String>();

      // A 200 ms search is plenty for an evaluation snapshot.
      _sendCommand('go movetime 200');

      double? lastEval;
      final sub = liveEvalStream.listen((v) => lastEval = v);

      await _bestMoveCompleter!.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          _sendCommand('stop');
          return '';
        },
      );

      await sub.cancel();

      if (lastEval == null) return 0.0;

      // The engine always reports from the perspective of the side to move.
      // Flip for black so the bar stays in White's frame of reference.
      return state.currentTurn.name == 'black' ? -lastEval! : lastEval!;
    } catch (e) {
      debugPrint('evaluatePosition error: $e');
      _isSearching = false;
      return 0.0;
    }
  }

  /// Return the best move for the current position in UCI notation (e.g. "e2e4").
  Future<String?> getBestMove({
    GameState? state,
    Duration moveTime = const Duration(milliseconds: 1000),
    int depth = 0,
  }) async {
    if (!_isReady) return null;
    if (_isSearching) {
      debugPrint('Engine already searching');
      return null;
    }

    try {
      if (state != null) {
        final fen = FenConverter.boardToFen(state);
        await setPosition(fen: fen);
      }

      _isSearching = true;
      _bestMoveCompleter = Completer<String>();

      String goCommand = 'go';
      if (moveTime > Duration.zero) {
        goCommand += ' movetime ${moveTime.inMilliseconds}';
      }
      if (depth > 0) {
        goCommand += ' depth $depth';
      }

      _sendCommand(goCommand);

      final response = await _bestMoveCompleter!.future.timeout(
        moveTime + const Duration(seconds: 2),
        onTimeout: () {
          debugPrint('getBestMove timeout');
          _sendCommand('stop');
          return '';
        },
      );

      // Format: "bestmove e2e4" or "bestmove e2e4 ponder g1f3"
      final match = RegExp(r'bestmove\s+(\S+)').firstMatch(response);
      return match?.group(1);
    } catch (e) {
      debugPrint('getBestMove error: $e');
      _isSearching = false;
      return null;
    }
  }

  /// Returns cached engine identity gathered during the UCI handshake.
  ///
  /// FIX: the old implementation sent `uci` again on an already-running engine.
  /// Stockfish only emits `id name` / `id author` lines during the initial
  /// handshake, so a second `uci` call would just time out every time.
  Map<String, String> getEngineInfo() {
    return {
      if (_engineName != null) 'name': _engineName!,
      if (_engineAuthor != null) 'author': _engineAuthor!,
    };
  }

  /// Stop any ongoing search.
  Future<void> stop() async {
    if (_isReady && _isSearching) {
      _sendCommand('stop');
      _isSearching = false;
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  /// Clean up the engine process and all streams.
  void dispose() {
    if (_engine != null) {
      try {
        _sendCommand('quit');
        _engine!.kill(ProcessSignal.sigterm);
      } catch (e) {
        debugPrint('Error killing engine: $e');
      }
      _engine = null;
    }

    _isReady = false;
    _isSearching = false;

    if (!_outputController.isClosed) _outputController.close();
    if (!_evalController.isClosed) _evalController.close();

    _uciOkCompleter = null;
    _readyOkCompleter = null;
    _bestMoveCompleter = null;
  }

  // ─── Internal helpers ──────────────────────────────────────────────────────

  void _sendCommand(String command) {
    if (_engine == null) {
      debugPrint('Cannot send command — engine not running: $command');
      return;
    }
    try {
      debugPrint('-> $command');
      _engine!.stdin.writeln(command);
      _engine!.stdin.flush();
    } catch (e) {
      debugPrint('Error sending command: $e');
      _isReady = false;
      _engine = null;
    }
  }
}
