import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/settings_controller.dart';
import 'themes/theme_controller.dart';
import 'app.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

Future<void> main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  final settings = await SettingsController.load();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeController()),
        ChangeNotifierProvider.value(value: settings),
      ],
      child: const ChessApp(),
    ),
  );
}
