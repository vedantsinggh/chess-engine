import 'package:app/models/game_state.dart';
import 'package:app/models/time_control.dart';
import 'package:app/services/chess_engine_service.dart';
import 'package:app/services/game_service.dart';
import 'package:app/services/settings_controller.dart';
import 'package:app/themes/board_theme.dart';
import 'package:app/widgets/chess_board.dart';
import 'package:app/widgets/move_list.dart';
import 'package:app/widgets/piece_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('SettingsController', () {
    test('defaults', () async {
      SharedPreferences.setMockInitialValues({});
      final s = await SettingsController.load();
      expect(s.boardTheme.name, 'Classic');
      expect(s.pieceStyle, PieceStyle.classic);
      expect(s.defaultTimeControl, TimeControl.none);
      expect(s.defaultBotId, isNull);
      expect(s.showCoordinates, isTrue);
      expect(s.autoQueen, isFalse);
    });

    test('persists and reloads', () async {
      SharedPreferences.setMockInitialValues({});
      final s = await SettingsController.load();
      var notified = 0;
      s.addListener(() => notified++);
      s.boardTheme = BoardTheme.byName('Green');
      s.pieceStyle = PieceStyle.vector;
      s.defaultBotId = 'casual';
      s.defaultTimeControl = TimeControl.fromLabel('3+2');
      s.showLastMove = false;
      s.autoQueen = true;
      expect(notified, 6);

      final again = await SettingsController.load();
      expect(again.boardTheme.name, 'Green');
      expect(again.pieceStyle, PieceStyle.vector);
      expect(again.defaultBotId, 'casual');
      expect(again.defaultTimeControl.label, '3+2');
      expect(again.showLastMove, isFalse);
      expect(again.autoQueen, isTrue);
    });

    test('unknown stored values fall back to defaults', () async {
      SharedPreferences.setMockInitialValues({
        'board_theme': 'Nope',
        'piece_style': 'Letters',
      });
      final s = await SettingsController.load();
      expect(s.boardTheme.name, 'Classic');
      expect(s.pieceStyle, PieceStyle.classic);
    });

    test('at least four board themes', () {
      expect(BoardTheme.all.length, greaterThanOrEqualTo(4));
    });
  });

  group('widgets', () {
    testWidgets('MoveList numbers moves and reports taps', (tester) async {
      int? tapped;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MoveList(
              sanMoves: const ['e4', 'e5', 'Nf3'],
              startFen: GameState.startPositionFen,
              viewPly: null,
              onSelectPly: (p) => tapped = p,
            ),
          ),
        ),
      );
      expect(find.text('1.'), findsOneWidget);
      expect(find.text('2.'), findsOneWidget);
      await tester.tap(find.text('e5'));
      expect(tapped, 2);
      expect(find.text('LIVE'), findsNothing);
    });

    testWidgets('MoveList starting with Black shows an ellipsis', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MoveList(
              sanMoves: const ['Kd8', 'Ra3'],
              startFen: '4k3/8/8/8/8/8/R7/4K3 b - - 0 30',
              viewPly: 1,
              onSelectPly: (_) {},
              onLive: () {},
            ),
          ),
        ),
      );
      expect(find.text('30.'), findsOneWidget);
      expect(find.text('31.'), findsOneWidget);
      expect(find.text('…'), findsOneWidget);
      expect(find.text('LIVE'), findsOneWidget);
    });

    testWidgets('board orientation and read-only review', (tester) async {
      final settings = SettingsController.defaults();
      final state = GameState()..currentMode = GameMode.engine;
      final svc = GameService(ChessEngineService());
      Widget board({required bool flipped, GameState? view}) => MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: state),
        ],
        child: MaterialApp(
          home: Center(
            child: SizedBox(
              width: 400,
              height: 400,
              child: ChessBoard(
                gameService: svc,
                flipped: flipped,
                viewState: view,
              ),
            ),
          ),
        ),
      );

      await tester.pumpWidget(board(flipped: false));
      expect(find.byType(PieceImage), findsNWidgets(32));
      // Squares are ~50px. Unflipped, display column 4 / row 6 is e2.
      final topLeft = tester.getTopLeft(find.byType(GridView));
      await tester.tapAt(topLeft + const Offset(25 + 200, 25 + 300));
      expect(state.selectedPosition?.algebraic, 'e2');

      // Flipped, display column 3 / row 6 is e7 and column 3 / row 1 is e2.
      state.selectedPosition = null;
      state.validMoves = [];
      await tester.pumpWidget(board(flipped: true));
      await tester.tapAt(topLeft + const Offset(25 + 150, 25 + 300));
      expect(state.selectedPosition, isNull); // e7 is Black's: not to move
      await tester.tapAt(topLeft + const Offset(25 + 150, 25 + 50));
      expect(state.selectedPosition?.algebraic, 'e2');

      // Review mode ignores taps.
      state.selectedPosition = null;
      state.validMoves = [];
      await tester.pumpWidget(board(flipped: false, view: state.clone()));
      await tester.tapAt(topLeft + const Offset(25 + 200, 25 + 300));
      expect(state.selectedPosition, isNull);
    });
  });
}
