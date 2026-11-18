// Integration test: talks UCI to a real engine binary. Skipped when none is
// built (run ./chess.sh first, or set CHESS_ENGINE_PATH).
import 'dart:io';

import 'package:app/models/game_state.dart';
import 'package:app/services/chess_engine_service.dart';
import 'package:app/services/game_service.dart';
import 'package:flutter_test/flutter_test.dart';

String? _findEngine() {
  final env = Platform.environment['CHESS_ENGINE_PATH'];
  if (env != null && File(env).existsSync()) return env;
  for (final p in ['../engine/build/chess_engine', 'engine/build/chess_engine']) {
    if (File(p).existsSync()) return File(p).absolute.path;
  }
  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final enginePath = _findEngine();

  group('ChessEngineService', () {
    final engine = ChessEngineService();
    final svc = GameService(engine);

    setUpAll(() async {
      // Unit tests have no path_provider plugin; the loader tolerates that and
      // still finds ../engine/build/chess_engine relative to the app dir.
      expect(await engine.initialize(), isTrue);
    });
    tearDownAll(engine.dispose);

    test('handshake reads name and options', () {
      expect(engine.engineName, isNotNull);
      expect(engine.options.keys, contains('UCI_Elo'));
    });

    test('returns a legal best move that includes history', () async {
      final s = GameState()..currentMode = GameMode.engine;
      svc.makeUciMove(s, 'e2e4');
      final move = await engine.getBestMove(
          state: s, moveTime: const Duration(milliseconds: 200));
      expect(move, isNotNull);
      expect(svc.makeUciMove(s, move!), isTrue, reason: move);
    });

    test('finds mate in one', () async {
      final s = GameState()..currentMode = GameMode.engine;
      svc.loadFen(s, '6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1');
      final move = await engine.getBestMove(
          state: s, moveTime: const Duration(milliseconds: 300));
      expect(move, 'a1a8');
    });

    test('concurrent requests are serialized, not dropped', () async {
      final s = GameState()..currentMode = GameMode.engine;
      final results = await Future.wait([
        engine.getBestMove(state: s, moveTime: const Duration(milliseconds: 100)),
        engine.getBestMove(
            state: s, moveTime: const Duration(milliseconds: 100), elo: 600),
        engine.evaluatePosition(s,
            moveTime: const Duration(milliseconds: 100)),
      ]);
      expect(results[0], isA<String>());
      expect(results[1], isA<String>());
      expect(results[2], isA<double>());
    });

    test('limited strength still plays legal moves', () async {
      final s = GameState()..currentMode = GameMode.engine;
      for (var i = 0; i < 6 && !s.isGameOver; i++) {
        final m = await engine.getBestMove(
            state: s, moveTime: const Duration(milliseconds: 50), elo: 600);
        expect(svc.makeUciMove(s, m!), isTrue, reason: m);
      }
    });
  }, skip: enginePath == null ? 'no engine binary built' : false);
}
