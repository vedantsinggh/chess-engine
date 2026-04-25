import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../services/engine_loader.dart';
import '../themes/theme_controller.dart';

// ─────────────────────────────────────────────────────────────
//  Settings Screen
// ─────────────────────────────────────────────────────────────
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with TickerProviderStateMixin {
  // Engine
  bool _isEngineInstalled = false;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;

  // Game preferences
  int _botDifficulty = 5; // 1–10
  bool _showHints = false;
  bool _showCoordinates = true;
  bool _autoPromote = true;
  bool _soundEnabled = true;
  bool _hapticEnabled = true;
  String _boardTheme = 'Classic';
  String _pieceStyle = 'Standard';
  bool _showMoveAnimation = true;
  bool _showLastMove = true;
  bool _showLegalMoves = true;
  double _animationSpeed = 0.5; // 0 slow – 1 fast
  int _clockMinutes = 10;

  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnim;

  static const _boardThemes = ['Classic', 'Walnut', 'Ocean', 'Midnight', 'Sand'];
  static const _pieceStyles = ['Standard', 'Minimalist', 'Letters'];
  static const _clockOptions = [1, 3, 5, 10, 15, 30];

  @override
  void initState() {
    super.initState();
    _checkEngineStatus();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _checkEngineStatus() async {
    final loader = EngineLoader();
    final isLoaded = await loader.loadEngine();
    if (mounted) setState(() => _isEngineInstalled = isLoaded);
  }

  void _notReady() {
    _showSnack('Feature not implemented yet');
  }

  Future<void> _downloadEngine() async {
    final engineUrl = _getEngineDownloadUrl();
    if (engineUrl.isEmpty) {
      _showSnack('Platform not supported for download');
      return;
    }
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
    });
    try {
      final loader = EngineLoader();
      final installPath = await loader.getInstallPath();
      final dir = File(installPath).parent;
      if (!await dir.exists()) await dir.create(recursive: true);

      final request = http.Request('GET', Uri.parse(engineUrl));
      final response = await request.send();
      if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');

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
      await File(installPath).writeAsBytes(bytes);
      await loader.makeExecutable(installPath);
      _showSnack('Engine installed successfully!');
      await _checkEngineStatus();
    } catch (e) {
      _showSnack('Download failed: $e');
    } finally {
      if (mounted) setState(() { _isDownloading = false; _downloadProgress = 0; });
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _getEngineDownloadUrl() {
    if (Platform.isAndroid || Platform.isIOS) return '';
    if (Platform.isWindows) return 'https://example.com/engines/stockfish_windows.exe';
    if (Platform.isMacOS) return 'https://example.com/engines/stockfish_macos';
    if (Platform.isLinux) return 'https://example.com/engines/stockfish_linux';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final themeController = context.watch<ThemeController>();
    final isDark = themeController.isDark;
    final bg = isDark ? const Color(0xFF0A0A0A) : const Color(0xFFF7F7F5);
    final surface = isDark ? const Color(0xFF141414) : Colors.white;
    final fg = isDark ? Colors.white : Colors.black;
    final fgSoft = isDark ? Colors.white60 : Colors.black45;
    final border = isDark ? Colors.white12 : Colors.black12;
    final accent = isDark ? Colors.white : Colors.black;
    final canDownload = !Platform.isAndroid && !Platform.isIOS;

    return Scaffold(
      backgroundColor: bg,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: CustomScrollView(
                slivers: [
                  // ── App Bar ─────────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                border: Border.all(color: border, width: 1.5),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(Icons.arrow_back_ios_new_rounded,
                                  size: 16, color: fg),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Text(
                            'SETTINGS',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 4,
                              color: fg,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 28)),

                  // ── APPEARANCE ──────────────────────────────────────────
                  _sectionHeader('Appearance', fg),
                  SliverToBoxAdapter(
                    child: _card(
                      surface: surface,
                      border: border,
                      child: Column(
                        children: [
                          // Theme toggle
                          _rowItem(
                            fg: fg,
                            fgSoft: fgSoft,
                            icon: isDark
                                ? Icons.dark_mode_rounded
                                : Icons.light_mode_rounded,
                            label: 'Theme',
                            subtitle: isDark ? 'Dark' : 'Light',
                            trailing: _PillToggle(
                              isDark: isDark,
                              fg: fg,
                              bg: bg,
                              onToggle: themeController.toggleTheme,
                            ),
                          ),
                          _divider(border),
                          // Board theme
                          _rowItem(
                            fg: fg,
                            fgSoft: fgSoft,
                            icon: Icons.grid_on_rounded,
                            label: 'Board Theme',
                            subtitle: _boardTheme,
                            trailing: _ChipSelector(
                              options: _boardThemes,
                              selected: _boardTheme,
                              fg: fg,
                              bg: bg,
                              surface: surface,
                              border: border,
                              //onSelected: (v) => setState(() => _boardTheme = v),
							  onSelected: (_) => _notReady(),
                            ),
                          ),
                          _divider(border),
                          // Piece style
                          _rowItem(
                            fg: fg,
                            fgSoft: fgSoft,
                            icon: Icons.category_rounded,
                            label: 'Piece Style',
                            subtitle: _pieceStyle,
                            trailing: _ChipSelector(
                              options: _pieceStyles,
                              selected: _pieceStyle,
                              fg: fg,
                              bg: bg,
                              surface: surface,
                              border: border,
                              //onSelected: (v) => setState(() => _pieceStyle = v),
							  onSelected: (_) => _notReady(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 24)),

                  // ── GAMEPLAY ────────────────────────────────────────────
                  _sectionHeader('Gameplay', fg),
                  SliverToBoxAdapter(
                    child: _card(
                      surface: surface,
                      border: border,
                      child: Column(
                        children: [
                          // Bot difficulty
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                            child: Row(
                              children: [
                                Icon(Icons.psychology_rounded,
                                    size: 20, color: fgSoft),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('Bot Difficulty',
                                          style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.4,
                                              color: fg)),
                                      const SizedBox(height: 2),
                                      Text(
                                        _difficultyLabel(_botDifficulty),
                                        style: TextStyle(
                                            fontSize: 11, color: fgSoft),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  '$_botDifficulty',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    color: fg,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 2,
                                thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 7),
                                overlayShape: const RoundSliderOverlayShape(
                                    overlayRadius: 16),
                                activeTrackColor: fg,
                                inactiveTrackColor: border,
                                thumbColor: fg,
                                overlayColor: fg.withOpacity(0.1),
                              ),
                              child: Slider(
                                value: _botDifficulty.toDouble(),
                                min: 1,
                                max: 10,
                                divisions: 9,
                                //onChanged: (v) =>
                                //  setState(() => _botDifficulty = v.round()),
								onChanged: (_) => _notReady(),
                              ),
                            ),
                          ),

                          _divider(border),

                          // Clock
                          _rowItem(
                            fg: fg,
                            fgSoft: fgSoft,
                            icon: Icons.timer_rounded,
                            label: 'Time Control',
                            subtitle: '$_clockMinutes min per side',
                            trailing: _ChipSelector(
                              options:
                                  _clockOptions.map((e) => '${e}m').toList(),
                              selected: '${_clockMinutes}m',
                              fg: fg,
                              bg: bg,
                              surface: surface,
                              border: border,
							  onSelected: (_) => _notReady(),
                            ),
                          ),
                          _divider(border),
                          _switchRow(
                              icon: Icons.lightbulb_outline_rounded,
                              label: 'Show Hints',
                              subtitle: 'Highlight suggested moves',
                              value: _showHints,
                              fg: fg,
                              fgSoft: fgSoft,
                              accent: accent,
                              border: border,
							  onChanged: (_) => _notReady(),),
                          _divider(border),
                          _switchRow(
                              icon: Icons.upgrade_rounded,
                              label: 'Auto-Promote to Queen',
                              subtitle: 'Skip promotion dialog',
                              value: _autoPromote,
                              fg: fg,
                              fgSoft: fgSoft,
                              accent: accent,
                              border: border,
							  onChanged: (_) => _notReady(),),
                        ],
                      ),
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 24)),

                  // ── BOARD DISPLAY ───────────────────────────────────────
                  _sectionHeader('Board Display', fg),
                  SliverToBoxAdapter(
                    child: _card(
                      surface: surface,
                      border: border,
                      child: Column(
                        children: [
                          _switchRow(
                              icon: Icons.grid_4x4_rounded,
                              label: 'Coordinates',
                              subtitle: 'Show a–h and 1–8',
                              value: _showCoordinates,
                              fg: fg,
                              fgSoft: fgSoft,
                              accent: accent,
                              border: border,
							  onChanged: (_) => _notReady(),),
                          _divider(border),
                          _switchRow(
                              icon: Icons.radio_button_checked_rounded,
                              label: 'Legal Move Dots',
                              subtitle: 'Show valid squares',
                              value: _showLegalMoves,
                              fg: fg,
                              fgSoft: fgSoft,
                              accent: accent,
                              border: border,
							  onChanged: (_) => _notReady(),),
                          _divider(border),
                          _switchRow(
                              icon: Icons.history_rounded,
                              label: 'Highlight Last Move',
                              subtitle: 'Shade the previous move',
                              value: _showLastMove,
                              fg: fg,
                              fgSoft: fgSoft,
                              accent: accent,
                              border: border,
							  onChanged: (_) => _notReady(),),
                          _divider(border),
                          _switchRow(
                              icon: Icons.animation_rounded,
                              label: 'Move Animation',
                              subtitle: 'Animate piece movement',
                              value: _showMoveAnimation,
                              fg: fg,
                              fgSoft: fgSoft,
                              accent: accent,
                              border: border,
							  onChanged: (_) => _notReady(),),
                          if (_showMoveAnimation) ...[
                            _divider(border),
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 12, 16, 12),
                              child: Row(
                                children: [
                                  Icon(Icons.speed_rounded,
                                      size: 20, color: fgSoft),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text('Animation Speed',
                                            style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: 0.4,
                                                color: fg)),
                                        const SizedBox(height: 2),
                                        Text(
                                          _animationSpeedLabel(_animationSpeed),
                                          style: TextStyle(
                                              fontSize: 11, color: fgSoft),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 2,
                                  thumbShape: const RoundSliderThumbShape(
                                      enabledThumbRadius: 7),
                                  overlayShape:
                                      const RoundSliderOverlayShape(
                                          overlayRadius: 16),
                                  activeTrackColor: fg,
                                  inactiveTrackColor: border,
                                  thumbColor: fg,
                                  overlayColor: fg.withOpacity(0.1),
                                ),
                                child: Slider(
                                  value: _animationSpeed,
                                  min: 0,
                                  max: 1,
							      onChanged: (_) => _notReady(),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 24)),

                  // ── SOUND & HAPTICS ─────────────────────────────────────
                  _sectionHeader('Sound & Haptics', fg),
                  SliverToBoxAdapter(
                    child: _card(
                      surface: surface,
                      border: border,
                      child: Column(
                        children: [
                          _switchRow(
                              icon: Icons.volume_up_rounded,
                              label: 'Sound Effects',
                              subtitle: 'Move, capture & check sounds',
                              value: _soundEnabled,
                              fg: fg,
                              fgSoft: fgSoft,
                              accent: accent,
                              border: border,
							  onChanged: (_) => _notReady(),),
                          _divider(border),
                          _switchRow(
                              icon: Icons.vibration_rounded,
                              label: 'Haptic Feedback',
                              subtitle: 'Vibrate on capture & check',
                              value: _hapticEnabled,
                              fg: fg,
                              fgSoft: fgSoft,
                              accent: accent,
                              border: border,
							  onChanged: (_) => _notReady(),),
                        ],
                      ),
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 24)),

                  // ── ENGINE ──────────────────────────────────────────────
                  _sectionHeader('Engine', fg),
                  SliverToBoxAdapter(
                    child: _card(
                      surface: surface,
                      border: border,
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: _isEngineInstalled
                                        ? Colors.green.withOpacity(0.12)
                                        : Colors.red.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    _isEngineInstalled
                                        ? Icons.check_circle_rounded
                                        : Icons.cancel_rounded,
                                    size: 20,
                                    color: _isEngineInstalled
                                        ? Colors.green
                                        : Colors.red,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('Stockfish Engine',
                                          style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.4,
                                              color: fg)),
                                      const SizedBox(height: 2),
                                      Text(
                                        _isEngineInstalled
                                            ? 'Ready to play'
                                            : 'Not installed',
                                        style: TextStyle(
                                            fontSize: 11, color: fgSoft),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_isDownloading) ...[
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 0, 16, 4),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: _downloadProgress > 0
                                      ? _downloadProgress
                                      : null,
                                  backgroundColor: border,
                                  color: fg,
                                  minHeight: 3,
                                ),
                              ),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  _downloadProgress > 0
                                      ? '${(_downloadProgress * 100).toStringAsFixed(0)}%'
                                      : 'Connecting…',
                                  style: TextStyle(
                                      fontSize: 11, color: fgSoft),
                                ),
                              ),
                            ),
                          ],
                          if (!canDownload) ...[
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: Text(
                                'On Android / iOS, Stockfish is bundled at build time. See the README for integration.',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.orange.shade700),
                              ),
                            ),
                          ],
                          if (canDownload) ...[
                            _divider(border),
                            _actionRow(
                              label: _isEngineInstalled
                                  ? 'REINSTALL ENGINE'
                                  : 'INSTALL ENGINE',
                              icon: Icons.download_rounded,
                              fg: fg,
                              fgSoft: fgSoft,
                              enabled: !_isDownloading,
                              onTap: _downloadEngine,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 24)),

                  // ── ABOUT ───────────────────────────────────────────────
                  _sectionHeader('About', fg),
                  SliverToBoxAdapter(
                    child: _card(
                      surface: surface,
                      border: border,
                      child: Column(
                        children: [
                          _infoRow(
                              label: 'App Version',
                              value: '1.0.0',
                              icon: Icons.info_outline_rounded,
                              fg: fg,
                              fgSoft: fgSoft),
                          _divider(border),
                          _infoRow(
                              label: 'Last Updated',
                              value: 'April 2026',
                              icon: Icons.calendar_today_rounded,
                              fg: fg,
                              fgSoft: fgSoft),
                          _divider(border),
                          _infoRow(
                              label: 'Engine',
                              value: 'Stockfish 17',
                              icon: Icons.memory_rounded,
                              fg: fg,
                              fgSoft: fgSoft),
                          _divider(border),
                          _actionRow(
                            label: 'PRIVACY POLICY',
                            icon: Icons.lock_outline_rounded,
                            fg: fg,
                            fgSoft: fgSoft,
                            enabled: true,
                            onTap: () {_notReady();},
                          ),
                          _divider(border),
                          _actionRow(
                            label: 'RATE THIS APP',
                            icon: Icons.star_outline_rounded,
                            fg: fg,
                            fgSoft: fgSoft,
                            enabled: true,
                            onTap: () {_notReady();},
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 40)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  String _difficultyLabel(int d) {
    if (d <= 2) return 'Beginner';
    if (d <= 4) return 'Easy';
    if (d <= 6) return 'Intermediate';
    if (d <= 8) return 'Advanced';
    return 'Master';
  }

  String _animationSpeedLabel(double v) {
    if (v < 0.33) return 'Slow';
    if (v < 0.67) return 'Normal';
    return 'Fast';
  }

  Widget _divider(Color border) => Divider(
        height: 1,
        thickness: 1,
        color: border,
        indent: 16,
        endIndent: 16,
      );

  SliverToBoxAdapter _sectionHeader(String title, Color fg) =>
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 3,
              color: fg.withOpacity(0.4),
            ),
          ),
        ),
      );

  Widget _card({
    required Color surface,
    required Color border,
    required Widget child,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: border, width: 1),
          ),
          child: child,
        ),
      );

  Widget _rowItem({
    required Color fg,
    required Color fgSoft,
    required IconData icon,
    required String label,
    required String subtitle,
    required Widget trailing,
  }) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: fgSoft),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                          color: fg)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(fontSize: 11, color: fgSoft)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            trailing,
          ],
        ),
      );

  Widget _switchRow({
    required IconData icon,
    required String label,
    required String subtitle,
    required bool value,
    required Color fg,
    required Color fgSoft,
    required Color accent,
    required Color border,
    required ValueChanged<bool> onChanged,
  }) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: fgSoft),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                          color: fg)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(fontSize: 11, color: fgSoft)),
                ],
              ),
            ),
            _MinimalSwitch(
              value: value,
              fg: fg,
              border: border,
              onChanged: onChanged,
            ),
          ],
        ),
      );

  Widget _infoRow({
    required String label,
    required String value,
    required IconData icon,
    required Color fg,
    required Color fgSoft,
  }) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: fgSoft),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                      color: fg)),
            ),
            Text(value,
                style: TextStyle(fontSize: 12, color: fgSoft)),
          ],
        ),
      );

  Widget _actionRow({
    required String label,
    required IconData icon,
    required Color fg,
    required Color fgSoft,
    required bool enabled,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            children: [
              Icon(icon, size: 20, color: enabled ? fgSoft : fgSoft.withOpacity(0.4)),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                    color: enabled ? fg : fg.withOpacity(0.3),
                  ),
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded,
                  size: 13,
                  color: enabled ? fgSoft : fgSoft.withOpacity(0.3)),
            ],
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────
//  Pill toggle (Light / Dark)
// ─────────────────────────────────────────────────────────────
class _PillToggle extends StatelessWidget {
  final bool isDark;
  final Color fg, bg;
  final VoidCallback onToggle;

  const _PillToggle({
    required this.isDark,
    required this.fg,
    required this.bg,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.all(3),
        width: 100,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: fg.withOpacity(0.25), width: 1.2),
        ),
        child: Row(
          children: [
            _pill('☀', !isDark, fg, bg),
            _pill('☾', isDark, fg, bg),
          ],
        ),
      ),
    );
  }

  Widget _pill(String emoji, bool active, Color fg, Color bg) => Expanded(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: active ? fg : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Center(
            child: Text(emoji,
                style: TextStyle(
                    fontSize: 13,
                    color: active ? bg : fg.withOpacity(0.5))),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────
//  Minimal custom switch
// ─────────────────────────────────────────────────────────────
class _MinimalSwitch extends StatelessWidget {
  final bool value;
  final Color fg, border;
  final ValueChanged<bool> onChanged;

  const _MinimalSwitch({
    required this.value,
    required this.fg,
    required this.border,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: 46,
        height: 26,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          color: value ? fg : Colors.transparent,
          border: Border.all(
            color: value ? fg : border,
            width: 1.5,
          ),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          alignment:
              value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: value
                  ? (fg == Colors.white ? Colors.black : Colors.white)
                  : fg.withOpacity(0.35),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  Chip selector (scrollable horizontal chips)
// ─────────────────────────────────────────────────────────────
class _ChipSelector extends StatelessWidget {
  final List<String> options;
  final String selected;
  final Color fg, bg, surface, border;
  final ValueChanged<String> onSelected;

  const _ChipSelector({
    required this.options,
    required this.selected,
    required this.fg,
    required this.bg,
    required this.surface,
    required this.border,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: options.map((opt) {
          final active = opt == selected;
          return GestureDetector(
            onTap: () => onSelected(opt),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: active ? fg : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: active ? fg : border,
                  width: 1.2,
                ),
              ),
              child: Text(
                opt,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: active
                      ? (fg == Colors.white ? Colors.black : Colors.white)
                      : fg.withOpacity(0.6),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
