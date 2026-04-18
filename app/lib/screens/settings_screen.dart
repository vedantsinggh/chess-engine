import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../services/engine_loader.dart';
import '../themes/theme_controller.dart';
import 'package:provider/provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isEngineInstalled = false;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _checkEngineStatus();
  }

  Future<void> _checkEngineStatus() async {
    final loader = EngineLoader();
    final isLoaded = await loader.loadEngine();
    if (mounted) {
      setState(() {
        _isEngineInstalled = isLoaded;
      });
    }
  }

  Future<void> _downloadEngine() async {
    final engineUrl = _getEngineDownloadUrl();
    if (engineUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Platform not supported for download')),
      );
      return;
    }

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
    });

    try {
      final loader = EngineLoader();

      // FIX: use EngineLoader.getInstallPath() so the saved file lands in the
      // same directory that ChessEngineService._getBinaryPath() searches.
      final installPath = await loader.getInstallPath();

      // Ensure the directory exists.
      final dir = File(installPath).parent;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // Stream the download so we can show real progress.
      final request = http.Request('GET', Uri.parse(engineUrl));
      final response = await request.send();

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final total = response.contentLength ?? 0;
      int received = 0;
      final bytes = <int>[];

      await for (final chunk in response.stream) {
        bytes.addAll(chunk);
        received += chunk.length;
        if (total > 0 && mounted) {
          setState(() => _downloadProgress = received / total);
        }
      }

      final engineFile = File(installPath);
      await engineFile.writeAsBytes(bytes);

      // FIX: make the binary executable so the engine can actually be launched.
      await loader.makeExecutable(installPath);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Engine downloaded successfully!')),
        );
        await _checkEngineStatus();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Download failed: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadProgress = 0.0;
        });
      }
    }
  }

  /// Replace these placeholder URLs with real release URLs when you publish.
  /// Recommended source: https://github.com/official-stockfish/Stockfish/releases
  String _getEngineDownloadUrl() {
    // Android and iOS require special integration (JNI / Flutter plugin) and
    // cannot simply download a binary at runtime.
    if (Platform.isAndroid || Platform.isIOS) return '';
    if (Platform.isWindows) {
      return 'https://example.com/engines/stockfish_windows.exe';
    }
    if (Platform.isMacOS) {
      return 'https://example.com/engines/stockfish_macos';
    }
    if (Platform.isLinux) {
      return 'https://example.com/engines/stockfish_linux';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final themeController = context.watch<ThemeController>();
    final isDark = themeController.isDark;

    final fg = isDark ? Colors.white : Colors.black;
    final bg = isDark ? Colors.black : Colors.white;

    // Mobile platforms can't use the download flow.
    final canDownload = !Platform.isAndroid && !Platform.isIOS;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(title: const Text("SETTINGS")),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 10),

          // ── THEME ───────────────────────────────────────────────────────────
          _sectionTitle("Appearance"),
          const SizedBox(height: 12),

          GestureDetector(
            onTap: () => themeController.toggleTheme(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: fg, width: 1.5),
              ),
              child: Row(
                children: [
                  _toggleOption("LIGHT", !isDark, fg, bg),
                  _toggleOption("DARK", isDark, fg, bg),
                ],
              ),
            ),
          ),

          const SizedBox(height: 30),

          // ── ENGINE ──────────────────────────────────────────────────────────
          _sectionTitle("Engine"),
          const SizedBox(height: 12),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        _isEngineInstalled ? Icons.check_circle : Icons.cancel,
                        color: _isEngineInstalled ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _isEngineInstalled
                              ? 'Stockfish ready'
                              : 'Not installed',
                        ),
                      ),
                    ],
                  ),

                  if (_isDownloading) ...[
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      value: _downloadProgress > 0 ? _downloadProgress : null,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _downloadProgress > 0
                          ? '${(_downloadProgress * 100).toStringAsFixed(0)} %'
                          : 'Connecting…',
                      style: const TextStyle(fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],

                  if (!canDownload) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'On Android / iOS, Stockfish is bundled at build time.\n'
                      'See the README for integration instructions.',
                      style: TextStyle(fontSize: 12, color: Colors.orange),
                    ),
                  ],

                  if (canDownload) ...[
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: _isDownloading ? null : _downloadEngine,
                      child: Text(_isEngineInstalled ? "REINSTALL" : "INSTALL"),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 30),

          // ── ABOUT ───────────────────────────────────────────────────────────
          _sectionTitle("About"),
          const SizedBox(height: 12),

          Card(
            child: Column(
              children: const [
                ListTile(title: Text("Version"), subtitle: Text("1.0.0")),
                Divider(),
                ListTile(
                  title: Text("Last Updated"),
                  subtitle: Text("March 2026"),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
    text.toUpperCase(),
    style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2),
  );

  Widget _toggleOption(String label, bool active, Color fg, Color bg) {
    return Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: active ? fg : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: active ? bg : fg,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
