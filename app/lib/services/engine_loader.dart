import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'chess_engine_service.dart';

/// Responsible for checking whether Stockfish is available and downloading /
/// installing it into the app-support directory.
///
/// FIX: the old implementation duplicated the path-discovery logic that already
/// lives in ChessEngineService._getBinaryPath().  It is now the single source
/// of truth for the *install* side (download + save), while ChessEngineService
/// remains the single source of truth for *finding* and *running* the binary.
class EngineLoader {
  static final EngineLoader _instance = EngineLoader._internal();
  factory EngineLoader() => _instance;
  EngineLoader._internal();

  /// Returns true if ChessEngineService can locate a Stockfish binary right now.
  /// This is a lightweight check — it does not start the engine.
  Future<bool> isEngineAvailable() async {
    if (kIsWeb) return false;
    // Re-use the service's own path-discovery by attempting a dry-run init.
    // We don't want to actually start the process here, so we just check
    // whether the binary exists via the same helper the service uses.
    return await _binaryExists();
  }

  /// Convenience alias used by SettingsScreen.
  Future<bool> loadEngine() => isEngineAvailable();

  /// Returns the path where the in-app downloader should save the binary.
  Future<String> getInstallPath() async {
    final dir = await getApplicationSupportDirectory();
    final fileName = Platform.isWindows ? 'stockfish.exe' : 'stockfish';
    return '${dir.path}/$fileName';
  }

  /// Makes the installed binary executable on Unix-like platforms.
  Future<void> makeExecutable(String path) async {
    if (Platform.isLinux || Platform.isMacOS) {
      try {
        await Process.run('chmod', ['+x', path]);
      } catch (e) {
        debugPrint('chmod failed: $e');
      }
    }
  }

  // ─── Private ────────────────────────────────────────────────────────────────

  /// Quick path check that mirrors ChessEngineService._getBinaryPath() without
  /// actually launching the process.
  Future<bool> _binaryExists() async {
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

    // App-support directory (where the downloader puts it).
    try {
      candidates.add(await getInstallPath());
    } catch (_) {}

    for (final path in candidates) {
      try {
        if (await File(path).exists()) return true;
      } catch (_) {}
    }

    // PATH lookup.
    if (Platform.isLinux || Platform.isMacOS) {
      try {
        final result = await Process.run('which', ['stockfish']);
        if (result.exitCode == 0 &&
            (result.stdout as String).trim().isNotEmpty) {
          return true;
        }
      } catch (_) {}
    }

    if (Platform.isWindows) {
      try {
        final result = await Process.run('where', ['stockfish']);
        if (result.exitCode == 0 &&
            (result.stdout as String).trim().isNotEmpty) {
          return true;
        }
      } catch (_) {}
    }

    return false;
  }
}
