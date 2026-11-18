// Smoke test: the game and settings screens lay out without overflow at
// phone, tablet and desktop sizes, and the bot setup -> clock -> resign flow
// works end to end. (The engine may or may not be available here.)
import 'package:app/screens/game_screen.dart';
import 'package:app/screens/settings_screen.dart';
import 'package:app/services/settings_controller.dart';
import 'package:app/themes/theme_controller.dart';
import 'package:app/widgets/clock_display.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Widget app(Widget home) => MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => ThemeController()),
    ChangeNotifierProvider(create: (_) => SettingsController.defaults()),
  ],
  child: MaterialApp(home: home),
);

void main() {
  for (final size in [
    const Size(400, 900),
    const Size(1400, 900),
    const Size(800, 700),
  ]) {
    for (final mode in ['offline', 'engine']) {
      testWidgets('game screen $mode $size', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(app(GameScreen(mode: mode)));
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 300));
        }
        if (mode == 'offline') {
          // setup sheet
          expect(find.text('PLAY AS'), findsOneWidget);
          await tester.tap(find.text('Black'));
          await tester.tap(find.text('3+2'));
          await tester.pump();
          await tester.tap(find.textContaining('PLAY VS'));
          for (var i = 0; i < 5; i++) {
            await tester.pump(const Duration(milliseconds: 300));
          }
          expect(find.byType(ClockDisplay), findsNWidgets(2));
          expect(find.text('3:00'), findsWidgets);
          await tester.tap(find.byTooltip('Resign'));
          await tester.pump(const Duration(milliseconds: 500));
          await tester.tap(find.text('RESIGN'));
          await tester.pump(const Duration(milliseconds: 500));
          expect(find.text('YOU RESIGNED'), findsOneWidget);
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      });
    }
  }
  testWidgets('settings screen', (tester) async {
    tester.view.physicalSize = const Size(400, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(const SettingsScreen()));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Green'));
    await tester.tap(find.text('Vector'));
    await tester.pump();
    expect(find.text('Board Theme'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
