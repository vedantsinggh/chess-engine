import 'package:app/models/game_state.dart';
import 'package:app/models/piece.dart';
import 'package:app/models/position.dart';
import 'package:app/services/chess_engine_service.dart';
import 'package:app/services/game_service.dart';
import 'package:app/utils/fen_converter.dart';
import 'package:app/utils/move_validator.dart';
import 'package:flutter_test/flutter_test.dart';

final _validator = MoveValidator();

GameService _service() => GameService(ChessEngineService());

/// Fresh state in analysis mode so no bot move gets triggered.
GameState _state([String? fen]) {
  final s = GameState()..currentMode = GameMode.engine;
  if (fen != null) _service().loadFen(s, fen);
  return s;
}

List<String> _legalUciMoves(GameState s) {
  final moves = <String>[];
  for (var r = 0; r < 8; r++) {
    for (var c = 0; c < 8; c++) {
      final p = s.board[r][c];
      if (p == null || p.color != s.currentTurn) continue;
      for (final to in _validator.getLegalMoves(s, r, c)) {
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

int _perft(GameService svc, GameState s, int depth) {
  final moves = _legalUciMoves(s);
  if (depth == 1) return moves.length;
  var nodes = 0;
  for (final m in moves) {
    final child = s.clone();
    expect(svc.makeUciMove(child, m), isTrue, reason: 'move $m');
    nodes += _perft(svc, child, depth - 1);
  }
  return nodes;
}

void _play(GameService svc, GameState s, String moves) {
  for (final m in moves.split(' ')) {
    expect(svc.makeUciMove(s, m), isTrue, reason: 'move $m');
  }
}

void main() {
  group('FEN', () {
    test('round-trips', () {
      for (final fen in [
        GameState.startPositionFen,
        'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1',
        'rnbqkbnr/ppp1pppp/8/3pP3/8/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 3',
        '8/2p5/3p4/KP5r/1R3p1k/8/4P2P/8 b - - 13 42',
      ]) {
        expect(_state(fen).currentFen, fen);
      }
    });

    test('rejects malformed FEN and leaves state unchanged', () {
      final s = _state();
      final before = s.currentFen;
      for (final bad in [
        '',
        'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP w KQkq - 0 1', // 7 ranks
        'rnbqkbnr/pppppppp/9/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
        'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNRR w KQkq - 0 1',
        'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQ1BNR w KQkq - 0 1', // no K
        'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR x KQkq - 0 1',
        'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq e9 0 1',
      ]) {
        expect(() => _service().loadFen(s, bad), throwsFormatException,
            reason: bad);
        expect(s.currentFen, before);
      }
    });

    test('drops castling rights the board cannot support', () {
      expect(_state('4k3/8/8/8/8/8/8/4K3 w KQkq - 0 1').currentFen,
          '4k3/8/8/8/8/8/8/4K3 w - - 0 1');
    });

    test('tracks halfmove clock and fullmove number', () {
      final svc = _service();
      final s = _state();
      _play(svc, s, 'g1f3 g8f6 b1c3');
      expect(s.currentFen,
          'rnbqkb1r/pppppppp/5n2/8/8/2N2N2/PPPPPPPP/R1BQKB1R b KQkq - 3 2');
      _play(svc, s, 'e7e5');
      expect(s.halfmoveClock, 0);
      expect(s.fullmoveNumber, 3);
      expect(s.moveHistory, ['g1f3', 'g8f6', 'b1c3', 'e7e5']);
    });
  });

  group('perft (move generation)', () {
    final cases = <String, List<int>>{
      GameState.startPositionFen: [20, 400, 8902],
      'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1':
          [48, 2039],
      '8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1': [14, 191, 2812],
      'r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1':
          [6, 264],
      'rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8': [44, 1486],
    };
    cases.forEach((fen, counts) {
      test(fen, () {
        final svc = _service();
        for (var d = 1; d <= counts.length; d++) {
          expect(_perft(svc, _state(fen), d), counts[d - 1], reason: 'depth $d');
        }
      });
    });
  });

  group('game end', () {
    test('checkmate', () {
      final svc = _service();
      final s = _state();
      _play(svc, s, 'e2e4 e7e5 f1c4 b8c6 d1h5 g8f6 h5f7');
      expect(s.status, GameStatus.checkmate);
      expect(svc.makeUciMove(s, 'e8f7'), isFalse);
    });

    test('stalemate', () {
      final svc = _service();
      final s = _state('7k/8/6Q1/8/8/8/8/K7 w - - 0 1');
      _play(svc, s, 'g6f7');
      expect(s.status, GameStatus.stalemate);
    });

    test('threefold repetition', () {
      final svc = _service();
      final s = _state();
      _play(svc, s, 'g1f3 g8f6 f3g1 f6g8 g1f3 g8f6 f3g1');
      expect(s.status, isNot(GameStatus.draw));
      _play(svc, s, 'f6g8');
      expect(s.status, GameStatus.draw);
      expect(s.drawReason, DrawReason.threefoldRepetition);
    });

    test('fifty-move rule', () {
      final svc = _service();
      final s = _state('4k3/8/8/8/8/8/R7/4K3 w - - 99 80');
      _play(svc, s, 'a2a3');
      expect(s.status, GameStatus.draw);
      expect(s.drawReason, DrawReason.fiftyMoveRule);
    });

    test('insufficient material', () {
      final svc = _service();
      final s = _state('4k3/8/8/8/8/8/4r3/4K3 w - - 0 1');
      _play(svc, s, 'e1e2');
      expect(s.drawReason, DrawReason.insufficientMaterial);
      expect(_validator.isInsufficientMaterial(
          _state('4k3/8/8/8/8/8/2B5/2B1K3 w - - 0 1').board), isFalse);
      expect(_validator.isInsufficientMaterial(
          _state('4k3/8/8/8/8/8/1B6/B3K3 w - - 0 1').board), isTrue);
    });
  });

  group('special moves', () {
    test('capturing a rook on its home square removes castling rights', () {
      final svc = _service();
      final s = _state('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1');
      _play(svc, s, 'a1a8');
      expect(s.currentFen.split(' ')[2], 'Kk');
    });

    test('en passant', () {
      final svc = _service();
      final s = _state();
      _play(svc, s, 'e2e4 a7a6 e4e5 d7d5');
      expect(s.currentFen.split(' ')[3], 'd6');
      _play(svc, s, 'e5d6');
      expect(s.board[3][3], isNull); // d5 pawn removed
    });

    test('engine promotion, with and without a piece letter', () {
      final svc = _service();
      final s = _state('4k3/1P6/8/8/8/8/8/4K3 w - - 0 1');
      _play(svc, s, 'b7b8n');
      expect(s.board[0][1]!.type, PieceType.knight);
      expect(s.board[0][1]!.color, PieceColor.white);
      expect(s.moveHistory.last, 'b7b8n');

      final s2 = _state('4k3/1P6/8/8/8/8/8/4K3 w - - 0 1');
      _play(svc, s2, 'b7b8');
      expect(s2.board[0][1]!.type, PieceType.queen);
      expect(s2.moveHistory.last, 'b7b8q');
    });

    test('illegal or malformed engine moves are rejected', () {
      final svc = _service();
      final s = _state();
      for (final m in ['e2e5', 'e7e5', 'z9a1', 'e2', 'e2e4q', 'e1g1']) {
        expect(svc.makeUciMove(s, m), isFalse, reason: m);
      }
      expect(s.currentFen, GameState.startPositionFen);
    });
  });

  test('FenConverter.positionKey ignores move counters', () {
    final a = _state('4k3/8/8/8/8/8/8/4K2R w K - 0 1');
    final b = _state('4k3/8/8/8/8/8/8/4K2R w K - 12 30');
    expect(FenConverter.positionKey(a), FenConverter.positionKey(b));
  });
}
