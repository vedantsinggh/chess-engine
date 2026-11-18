import 'package:app/models/game_state.dart';
import 'package:app/utils/chess_rules.dart';
import 'package:app/utils/san.dart';
import 'package:flutter_test/flutter_test.dart';

GameState _pos(String fen) {
  final s = GameState()..currentMode = GameMode.engine;
  ChessRules.replay(s, fen, const []);
  return s;
}

void main() {
  group('SanFormatter.toSan', () {
    test('pawn and piece moves', () {
      final s = GameState();
      expect(SanFormatter.toSan(s, 'e2e4'), 'e4');
      expect(SanFormatter.toSan(s, 'g1f3'), 'Nf3');
      expect(SanFormatter.toSan(s, 'e2e5'), isNull); // illegal
      expect(s.moveHistory, isEmpty); // not modified
    });

    test('captures, castling and en passant', () {
      final s = _pos(
        'r3k2r/pppq1ppp/2n5/3pP3/8/8/PPP2PPP/R3K2R w KQkq d6 0 10',
      );
      expect(SanFormatter.toSan(s, 'e5d6'), 'exd6');
      expect(SanFormatter.toSan(s, 'e1g1'), 'O-O');
      expect(SanFormatter.toSan(s, 'e1c1'), 'O-O-O');
      final b = _pos('r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 0 1');
      expect(SanFormatter.toSan(b, 'e8g8'), 'O-O');
      expect(SanFormatter.toSan(b, 'e8c8'), 'O-O-O');
      expect(SanFormatter.toSan(b, 'a8a1'), 'Rxa1+');
    });

    test('promotion with check, and under-promotion', () {
      final s = _pos('2k5/4P3/8/8/8/8/8/4K3 w - - 0 1');
      expect(SanFormatter.toSan(s, 'e7e8q'), 'e8=Q+');
      expect(SanFormatter.toSan(s, 'e7e8n'), 'e8=N');
      final c = _pos('3qk3/4P3/8/8/8/8/8/4K3 w - - 0 1');
      expect(SanFormatter.toSan(c, 'e7d8r'), 'exd8=R+');
    });

    test('checkmate', () {
      final s = GameState()..currentMode = GameMode.engine;
      ChessRules.replay(s, GameState.startPositionFen, [
        'e2e4',
        'e7e5',
        'f1c4',
        'b8c6',
        'd1h5',
        'g8f6',
      ]);
      expect(SanFormatter.toSan(s, 'h5f7'), 'Qxf7#');
    });

    test('disambiguation by file, rank, and both', () {
      // Knights on b1 and f3 can both reach d2.
      final n = _pos('4k3/8/8/8/8/5N2/8/1N2K3 w - - 0 1');
      expect(SanFormatter.toSan(n, 'b1d2'), 'Nbd2');
      expect(SanFormatter.toSan(n, 'f3d2'), 'Nfd2');
      // Rooks on e1 and e5 (same file) both reach e3.
      final r = _pos('k7/8/8/4R3/8/8/8/K3R3 w - - 0 1');
      expect(SanFormatter.toSan(r, 'e1e3'), 'R1e3');
      expect(SanFormatter.toSan(r, 'e5e3'), 'R5e3');
      // Queens on h4, e4 and h1 all reach e1: h4 needs file and rank.
      final q = _pos('1k6/8/8/8/4Q2Q/8/8/K6Q w - - 0 1');
      expect(SanFormatter.toSan(q, 'h4e1'), 'Qh4e1');
      expect(SanFormatter.toSan(q, 'e4e1'), 'Qee1');
      expect(SanFormatter.toSan(q, 'h1e1'), 'Q1e1');
    });

    test('no disambiguation when the other piece is pinned', () {
      final s = _pos('4k3/8/8/8/1b6/2N5/8/4K1N1 w - - 0 1');
      // Nc3 is pinned against e1, so only Ng1 can go to e2.
      expect(SanFormatter.toSan(s, 'g1e2'), 'Ne2');
    });
  });

  test('fromUciMoves numbers a whole game', () {
    expect(
      SanFormatter.fromUciMoves(GameState.startPositionFen, [
        'e2e4',
        'e7e5',
        'g1f3',
        'b8c6',
        'f1b5',
        'a7a6',
        'e1g1',
      ]),
      ['e4', 'e5', 'Nf3', 'Nc6', 'Bb5', 'a6', 'O-O'],
    );
  });

  test('GameState.sanHistory is kept in step with moveHistory', () {
    final s = GameState()..currentMode = GameMode.engine;
    for (final m in ['d2d4', 'd7d5', 'c2c4', 'd5c4']) {
      expect(ChessRules.applyUci(s, m), isTrue);
    }
    expect(s.sanHistory, ['d4', 'd5', 'c4', 'dxc4']);
    expect(s.clone().sanHistory, s.sanHistory);
  });
}
