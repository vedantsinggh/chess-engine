import 'dart:async';

import 'package:app/models/game_state.dart';
import 'package:app/models/piece.dart';
import 'package:app/models/time_control.dart';
import 'package:app/services/chess_clock.dart';
import 'package:app/services/chess_engine_service.dart';
import 'package:app/services/game_service.dart';
import 'package:app/utils/fen_converter.dart';
import 'package:app/utils/result_text.dart';
import 'package:flutter_test/flutter_test.dart';

/// Bot whose replies the test controls.
class FakeBot {
  final requests = <({String fen, Completer<String?> reply})>[];

  Future<String?> call(GameState s) {
    final c = Completer<String?>();
    requests.add((fen: s.currentFen, reply: c));
    return c.future;
  }

  void reply(String? move) => requests.last.reply.complete(move);
}

/// Controllable time source.
class FakeTime {
  DateTime now = DateTime(2026);
  void advance(Duration d) => now = now.add(d);
}

Future<void> settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void play(GameService svc, GameState s, String moves) {
  for (final m in moves.split(' ')) {
    expect(svc.makeUciMove(s, m), isTrue, reason: m);
  }
}

GameState analysis() => GameState()..currentMode = GameMode.engine;

void main() {
  group('undo / redo (analysis)', () {
    test('undo takes back one ply and restores counters and FEN', () {
      final svc = GameService(ChessEngineService());
      final s = analysis();
      play(svc, s, 'g1f3 g8f6 b1c3');
      final fenBefore = s.currentFen;
      final countsBefore = Map.of(s.positionCounts);
      play(svc, s, 'e7e5');

      expect(svc.undo(s), isTrue);
      expect(s.currentFen, fenBefore);
      expect(s.halfmoveClock, 3);
      expect(s.moveHistory, ['g1f3', 'g8f6', 'b1c3']);
      expect(s.sanHistory, ['Nf3', 'Nf6', 'Nc3']);
      expect(s.positionCounts, countsBefore);

      expect(svc.redo(s), isTrue);
      expect(s.moveHistory.last, 'e7e5');
      expect(s.halfmoveClock, 0);
      expect(svc.canRedo(s), isFalse);
    });

    test('repetition counts are correct after undo', () {
      final svc = GameService(ChessEngineService());
      final s = analysis();
      play(svc, s, 'g1f3 g8f6 f3g1 f6g8 g1f3 g8f6 f3g1 f6g8');
      expect(s.status, GameStatus.draw);
      expect(s.drawReason, DrawReason.threefoldRepetition);
      final startKey = FenConverter.positionKey(GameState());
      expect(s.positionCounts[startKey], 3);

      expect(svc.undo(s), isTrue);
      expect(s.isGameOver, isFalse);
      expect(s.positionCounts[startKey], 2);
      // A different move now; the repetition is avoided and redo is gone.
      play(svc, s, 'e7e5');
      expect(svc.canRedo(s), isFalse);
      expect(s.positionCounts[startKey], 2);
      expect(s.isGameOver, isFalse);
    });

    test('undo from a loaded FEN keeps the start position', () {
      final svc = GameService(ChessEngineService());
      final s = analysis();
      const fen = '4k3/8/8/8/8/8/R7/4K3 w - - 40 60';
      svc.loadFen(s, fen);
      play(svc, s, 'a2a3 e8d8');
      expect(svc.undo(s), isTrue);
      expect(svc.undo(s), isTrue);
      expect(s.currentFen, fen);
      expect(svc.canUndo(s), isFalse);
    });

    test('nothing to undo at the start', () {
      final svc = GameService(ChessEngineService());
      final s = analysis();
      expect(svc.canUndo(s), isFalse);
      expect(svc.undo(s), isFalse);
      expect(svc.redo(s), isFalse);
    });
  });

  group('bot games', () {
    test('human White: undo while the bot thinks takes back one ply and '
        'discards the late reply', () async {
      final bot = FakeBot();
      final svc = GameService(ChessEngineService(), botMoveProvider: bot.call);
      final s = GameState();
      svc.startNewGame(s, botColor: PieceColor.black);
      expect(bot.requests, isEmpty);

      play(svc, s, 'e2e4');
      expect(s.isEngineThinking, isTrue);
      expect(bot.requests, hasLength(1));
      // Human can't move for the bot.
      svc.handleSquareTap(s, 1, 4);
      expect(s.selectedPosition, isNull);

      expect(svc.undoPlies(s), 1);
      expect(svc.undo(s), isTrue);
      expect(s.isEngineThinking, isFalse);
      expect(s.moveHistory, isEmpty);

      bot.reply('e7e5'); // late reply for the undone position
      await settle();
      expect(s.moveHistory, isEmpty);
      expect(s.currentFen, GameState.startPositionFen);
    });

    test('human White: undo after the bot replied takes back two plies; '
        'redo replays both', () async {
      final bot = FakeBot();
      final svc = GameService(ChessEngineService(), botMoveProvider: bot.call);
      final s = GameState();
      svc.startNewGame(s, botColor: PieceColor.black);
      play(svc, s, 'e2e4');
      bot.reply('c7c5');
      await settle();
      expect(s.moveHistory, ['e2e4', 'c7c5']);
      expect(s.isEngineThinking, isFalse);

      expect(svc.undoPlies(s), 2);
      svc.undo(s);
      expect(s.moveHistory, isEmpty);
      expect(s.currentTurn, PieceColor.white);

      expect(svc.redo(s), isTrue);
      expect(s.moveHistory, ['e2e4', 'c7c5']);
      expect(s.currentTurn, PieceColor.white);
      expect(bot.requests, hasLength(1)); // no new search was needed
    });

    test(
      'bot as White moves first; human Black cannot undo the bot opening',
      () async {
        final bot = FakeBot();
        final svc = GameService(
          ChessEngineService(),
          botMoveProvider: bot.call,
        );
        final s = GameState();
        svc.startNewGame(s, botColor: PieceColor.white);
        expect(svc.humanColor, PieceColor.black);
        expect(s.isEngineThinking, isTrue);
        expect(bot.requests.single.fen, GameState.startPositionFen);

        // White pieces can't be touched by the (Black) human.
        svc.handleSquareTap(s, 6, 4);
        expect(s.selectedPosition, isNull);

        bot.reply('d2d4');
        await settle();
        expect(s.moveHistory, ['d2d4']);
        expect(svc.canUndo(s), isFalse);

        // Human plays by tapping d7 -> d5.
        svc.handleSquareTap(s, 1, 3);
        svc.handleSquareTap(s, 3, 3);
        expect(s.moveHistory, ['d2d4', 'd7d5']);
        expect(bot.requests, hasLength(2));
        bot.reply('c2c4');
        await settle();
        expect(s.sanHistory, ['d4', 'd5', 'c4']);
        expect(svc.undoPlies(s), 2);
        svc.undo(s);
        expect(s.moveHistory, ['d2d4']);
        expect(s.currentTurn, PieceColor.black);
        expect(s.isEngineThinking, isFalse);
      },
    );

    test('an illegal bot move is ignored', () async {
      final bot = FakeBot();
      final svc = GameService(ChessEngineService(), botMoveProvider: bot.call);
      final s = GameState();
      svc.startNewGame(s, botColor: PieceColor.white);
      bot.reply('e2e5');
      await settle();
      expect(s.moveHistory, isEmpty);
      expect(s.isEngineThinking, isFalse);
      expect(s.status, GameStatus.whiteTurn);
    });

    test('new game discards a pending bot reply', () async {
      final bot = FakeBot();
      final svc = GameService(ChessEngineService(), botMoveProvider: bot.call);
      final s = GameState();
      svc.startNewGame(s, botColor: PieceColor.black);
      play(svc, s, 'e2e4');
      final stale = bot.requests.single.reply;
      svc.startNewGame(s, botColor: PieceColor.black);
      stale.complete('e7e5');
      await settle();
      expect(s.moveHistory, isEmpty);
    });
  });

  group('ChessClock', () {
    test('runs, switches with increment, and flags', () {
      final t = FakeTime();
      final clock = ChessClock(
        const TimeControl(Duration(minutes: 3), Duration(seconds: 2)),
        now: () => t.now,
        autoTick: false,
      );
      PieceColor? flagged;
      clock.onFlag = (c) => flagged = c;

      clock.start(PieceColor.white);
      t.advance(const Duration(seconds: 10));
      expect(clock.remaining(PieceColor.white), const Duration(seconds: 170));
      clock.moveMade(PieceColor.white);
      expect(clock.remaining(PieceColor.white), const Duration(seconds: 172));
      expect(clock.active, PieceColor.black);

      t.advance(const Duration(seconds: 165));
      expect(clock.isLow(PieceColor.black), isTrue); // 15s < 20s
      expect(clock.isLow(PieceColor.white), isFalse);
      t.advance(const Duration(seconds: 20));
      clock.tick();
      expect(flagged, PieceColor.black);
      expect(clock.remaining(PieceColor.black), Duration.zero);
      expect(clock.isRunning, isFalse);
      expect(clock.remaining(PieceColor.white), const Duration(seconds: 172));
    });

    test('stop freezes both clocks', () {
      final t = FakeTime();
      final clock = ChessClock(
        const TimeControl(Duration(minutes: 1)),
        now: () => t.now,
        autoTick: false,
      );
      clock.start(PieceColor.white);
      t.advance(const Duration(seconds: 5));
      clock.stop();
      t.advance(const Duration(seconds: 30));
      expect(clock.remaining(PieceColor.white), const Duration(seconds: 55));
    });

    test('format', () {
      expect(ChessClock.format(const Duration(minutes: 5)), '5:00');
      expect(ChessClock.format(const Duration(seconds: 42)), '0:42');
      expect(ChessClock.format(const Duration(milliseconds: 7350)), '7.3');
      expect(ChessClock.format(const Duration(minutes: 75)), '1:15:00');
    });

    test('presets and labels', () {
      expect(TimeControl.presets.map((t) => t.label), [
        'None',
        '1+0',
        '3+2',
        '5+0',
        '10+0',
        '15+10',
        '30+0',
      ]);
      expect(
        TimeControl.fromLabel('15+10'),
        const TimeControl(Duration(minutes: 15), Duration(seconds: 10)),
      );
      expect(TimeControl.fromLabel('bogus'), TimeControl.none);
    });
  });

  group('clocks in a game', () {
    late FakeTime t;
    late FakeBot bot;
    late GameService svc;
    late GameState s;

    setUp(() {
      t = FakeTime();
      bot = FakeBot();
      svc = GameService(ChessEngineService(), botMoveProvider: bot.call);
      s = GameState();
    });

    ChessClock clock(TimeControl tc) =>
        ChessClock(tc, now: () => t.now, autoTick: false);

    test('increment after each move; flag-fall loses', () async {
      svc.startNewGame(
        s,
        botColor: PieceColor.black,
        clock: clock(
          const TimeControl(Duration(minutes: 1), Duration(seconds: 1)),
        ),
      );
      expect(svc.clock!.active, PieceColor.white);
      t.advance(const Duration(seconds: 4));
      play(svc, s, 'e2e4');
      expect(
        svc.clock!.remaining(PieceColor.white),
        const Duration(seconds: 57),
      );
      expect(svc.clock!.active, PieceColor.black);

      t.advance(const Duration(seconds: 61));
      svc.clock!.tick();
      expect(s.status, GameStatus.timeout);
      expect(s.loser, PieceColor.black);
      expect(s.isEngineThinking, isFalse);
      expect(s.result!.winner, PieceColor.white);
      expect(
        describeResult(s.result!, human: PieceColor.white),
        'White wins on time',
      );

      bot.reply('e7e5'); // too late
      await settle();
      expect(s.moveHistory, ['e2e4']);
      expect(svc.canUndo(s), isFalse);
    });

    test('flag-fall against a bare king is a draw', () {
      svc.startNewGame(
        s,
        botColor: PieceColor.black,
        clock: clock(const TimeControl(Duration(minutes: 1))),
      );
      svc.loadFen(s, '4k3/8/8/8/8/8/4P3/4K3 b - - 0 40');
      // Black (bare king) is to move; White's clock runs out instead.
      svc.handleFlag(s, PieceColor.white);
      expect(s.status, GameStatus.draw);
      expect(s.drawReason, DrawReason.timeoutVsInsufficientMaterial);
      expect(s.result!.isDraw, isTrue);
    });

    test('flag-fall with a lone knight vs pawns still loses', () {
      svc.startNewGame(s, botColor: PieceColor.black);
      svc.loadFen(s, '4k3/8/8/8/8/8/4P3/2n1K3 w - - 0 40');
      svc.handleFlag(s, PieceColor.white);
      expect(s.status, GameStatus.timeout);
      expect(s.loser, PieceColor.white);
    });

    test('checkmate stops the clock', () {
      svc.startNewGame(
        s,
        botColor: PieceColor.black,
        clock: clock(const TimeControl(Duration(minutes: 5))),
      );
      s.currentMode = GameMode.engine; // play both sides by hand
      play(svc, s, 'f2f3 e7e5 g2g4 d8h4');
      expect(s.status, GameStatus.checkmate);
      expect(svc.clock!.isRunning, isFalse);
    });

    test('engine go command uses the clock', () {
      expect(
        ChessEngineService.goCommand(
          wtime: const Duration(seconds: 60),
          btime: const Duration(seconds: 55),
          winc: const Duration(seconds: 2),
          binc: const Duration(seconds: 2),
          moveTime: const Duration(seconds: 1),
        ),
        'go wtime 60000 btime 55000 winc 2000 binc 2000',
      );
      expect(
        ChessEngineService.goCommand(moveTime: const Duration(seconds: 1)),
        'go movetime 1000',
      );
      expect(
        ChessEngineService.goCommand(
          moveTime: const Duration(milliseconds: 500),
          depth: 2,
        ),
        'go movetime 500 depth 2',
      );
    });
  });

  group('resign and draw offers', () {
    test('resigning ends the game and blocks moves', () async {
      final bot = FakeBot();
      final svc = GameService(ChessEngineService(), botMoveProvider: bot.call);
      final s = GameState();
      svc.startNewGame(s, botColor: PieceColor.white);
      expect(s.isEngineThinking, isTrue);
      expect(svc.resign(s), isTrue);
      expect(s.status, GameStatus.resigned);
      expect(s.loser, PieceColor.black);
      expect(s.result!.winner, PieceColor.white);
      expect(s.result!.score, '1-0');
      expect(
        describeResult(s.result!, human: PieceColor.black),
        'You resigned',
      );
      expect(s.isEngineThinking, isFalse);
      bot.reply('e2e4');
      await settle();
      expect(s.moveHistory, isEmpty);
      expect(svc.makeUciMove(s, 'e2e4'), isFalse);
      expect(svc.resign(s), isFalse);
      expect(svc.canUndo(s), isFalse);
    });

    GameService drawSvc(double? whiteEval, List<int> calls) => GameService(
      ChessEngineService(),
      botMoveProvider: FakeBot().call,
      evaluator: (_) async {
        calls.add(1);
        return whiteEval;
      },
    );

    GameState midgame(GameService svc, {int moveNo = 25}) {
      final s = GameState();
      svc.startNewGame(s, botColor: PieceColor.black);
      svc.loadFen(
        s,
        'r1bq1rk1/pp3ppp/2n1pn2/2pp4/3P4/2PBPN2/PP3PPP/RN1Q1RK1 w - - 0 $moveNo',
      );
      return s;
    }

    test('declined before move 20 without asking the engine', () async {
      final calls = <int>[];
      final svc = drawSvc(0.0, calls);
      final s = midgame(svc, moveNo: 12);
      expect(await svc.offerDraw(s), DrawOfferResult.declined);
      expect(calls, isEmpty);
      expect(s.isGameOver, isFalse);
    });

    test('accepted after move 20 when the bot is not better', () async {
      // White +0.2 => the bot (Black) sees -0.2.
      final svc = drawSvc(0.2, []);
      final s = midgame(svc);
      expect(await svc.offerDraw(s), DrawOfferResult.accepted);
      expect(s.status, GameStatus.draw);
      expect(s.drawReason, DrawReason.agreement);
      expect(describeResult(s.result!, human: PieceColor.white), 'Draw agreed');
      expect(svc.makeUciMove(s, 'e3e4'), isFalse);
    });

    test('declined when the bot is better', () async {
      final svc = drawSvc(-0.8, []); // Black (bot) +0.8
      final s = midgame(svc);
      expect(await svc.offerDraw(s), DrawOfferResult.declined);
      expect(s.isGameOver, isFalse);
    });

    test('declined when the engine gives no evaluation', () async {
      final svc = drawSvc(null, []);
      expect(await svc.offerDraw(midgame(svc)), DrawOfferResult.declined);
    });

    test('accepted in drawish material even early', () async {
      final calls = <int>[];
      final svc = drawSvc(-5, calls);
      final s = GameState();
      svc.startNewGame(s, botColor: PieceColor.black);
      svc.loadFen(s, '4k3/8/8/3r4/8/8/8/3RK3 w - - 0 5'); // R v R
      expect(await svc.offerDraw(s), DrawOfferResult.accepted);
      expect(calls, isEmpty);
    });
  });

  group('result text', () {
    GameResult r(PieceColor? w, GameStatus st, [DrawReason? d]) =>
        GameResult(winner: w, status: st, drawReason: d);

    test('bot game and analysis wording', () {
      expect(
        describeResult(
          r(PieceColor.white, GameStatus.checkmate),
          human: PieceColor.white,
        ),
        'Checkmate — you win',
      );
      expect(
        describeResult(
          r(PieceColor.white, GameStatus.checkmate),
          human: PieceColor.black,
        ),
        'Checkmate — you lost',
      );
      expect(
        describeResult(r(PieceColor.black, GameStatus.checkmate)),
        'Checkmate — Black wins',
      );
      expect(
        describeResult(r(PieceColor.black, GameStatus.timeout)),
        'Black wins on time',
      );
      expect(
        describeResult(r(PieceColor.white, GameStatus.resigned)),
        'Black resigned — White wins',
      );
      expect(
        describeResult(
          r(null, GameStatus.draw, DrawReason.threefoldRepetition),
        ),
        'Draw — threefold repetition',
      );
    });

    test('checkmate result: the side to move lost', () {
      final svc = GameService(ChessEngineService());
      final s = analysis();
      play(svc, s, 'f2f3 e7e5 g2g4 d8h4');
      expect(s.result!.winner, PieceColor.black);
      expect(s.result!.score, '0-1');
    });
  });
}
