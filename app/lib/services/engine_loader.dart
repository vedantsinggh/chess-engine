import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Single source of truth for locating a UCI engine binary on disk.
///
/// Search order:
///   1. `CHESS_ENGINE_PATH` environment variable (any UCI engine).
///   2. The project's own engine, `chess_engine` ("Rank"): the app-support
///      directory, `~/.local/bin` (where `chess.sh` installs it), or a local
///      `engine/build` directory when running from the repo.
///   3. Stockfish: well-known system paths, the app-support directory, `PATH`.
class EngineLoader {
  static final EngineLoader _instance = EngineLoader._internal();
  factory EngineLoader() => _instance;
  EngineLoader._internal();

  static String get _exe => Platform.isWindows ? '.exe' : '';

  /// Desktop platforms only — mobile sandboxes don't allow spawning binaries.
  bool get isSupportedPlatform =>
      !kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows);

  Future<bool> isEngineAvailable() async => await findEngine() != null;

  /// Directory where engines can be dropped in for the app to find.
  Future<String?> appSupportDir() async {
    try {
      return (await getApplicationSupportDirectory()).path;
    } catch (_) {
      return null;
    }
  }

  /// Returns the absolute path of the first engine found, or null.
  Future<String?> findEngine() async {
    if (!isSupportedPlatform) return null;

    final override = Platform.environment['CHESS_ENGINE_PATH'];
    if (override != null && override.isNotEmpty) {
      if (await _usable(override)) return override;
      debugPrint('CHESS_ENGINE_PATH=$override is not an executable file');
    }

    final support = await appSupportDir();
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    final sep = Platform.pathSeparator;

    final candidates = <String>[
      // ── Built-in engine ──
      if (support != null) '$support${sep}chess_engine$_exe',
      if (home != null) '$home$sep.local${sep}bin${sep}chess_engine$_exe',
      if (!Platform.isWindows) '/usr/local/bin/chess_engine',
      '${Directory.current.path}$sep..${sep}engine${sep}build${sep}chess_engine$_exe',
      '${Directory.current.path}${sep}engine${sep}build${sep}chess_engine$_exe',

      // ── Stockfish ──
      if (support != null) '$support${sep}stockfish$_exe',
      if (Platform.isLinux) ...[
        '/usr/local/bin/stockfish',
        '/usr/bin/stockfish',
        '/usr/games/stockfish',
      ],
      if (Platform.isMacOS) ...[
        '/usr/local/bin/stockfish',
        '/opt/homebrew/bin/stockfish',
      ],
      if (Platform.isWindows) ...[
        'C:\\stockfish\\stockfish.exe',
        'C:\\Program Files\\stockfish\\stockfish.exe',
      ],
      if (home != null) '$home$sep.local${sep}bin${sep}stockfish$_exe',
    ];

    for (final path in candidates) {
      if (await _usable(path)) return File(path).absolute.path;
    }

    // PATH lookup.
    for (final name in ['chess_engine', 'stockfish']) {
      try {
        final result = await Process.run(
          Platform.isWindows ? 'where' : 'which',
          [name],
        );
        if (result.exitCode == 0) {
          final p = (result.stdout as String).trim().split('\n').first.trim();
          if (p.isNotEmpty) return p;
        }
      } catch (_) {}
    }
    return null;
  }

  Future<bool> _usable(String path) async {
    try {
      final stat = await FileStat.stat(path);
      if (stat.type != FileSystemEntityType.file) return false;
      if (Platform.isWindows) return true;
      return stat.mode & 0x49 != 0; // any execute bit (0o111)
    } catch (_) {
      return false;
    }
  }
}
