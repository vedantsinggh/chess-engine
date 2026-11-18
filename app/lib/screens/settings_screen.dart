import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/piece.dart';
import '../models/time_control.dart';
import '../services/engine_loader.dart';
import '../services/settings_controller.dart';
import '../themes/board_theme.dart';
import '../themes/theme_controller.dart';
import '../widgets/piece_image.dart';
import 'game/bot_profiles.dart';

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
  bool _isScanning = false;
  String? _enginePath;

  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnim;

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
    final path = await EngineLoader().findEngine();
    if (mounted) {
      setState(() {
        _enginePath = path;
        _isEngineInstalled = path != null;
      });
    }
  }

  Future<void> _rescanEngine() async {
    setState(() => _isScanning = true);
    await _checkEngineStatus();
    if (!mounted) return;
    setState(() => _isScanning = false);
    _showSnack(
      _isEngineInstalled
          ? 'Engine found: $_enginePath'
          : 'No engine found — run ./chess.sh from the repo root',
    );
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final themeController = context.watch<ThemeController>();
    final settings = context.watch<SettingsController>();
    final isDark = themeController.isDark;
    final bg = isDark ? const Color(0xFF0A0A0A) : const Color(0xFFF7F7F5);
    final surface = isDark ? const Color(0xFF141414) : Colors.white;
    final fg = isDark ? Colors.white : Colors.black;
    final fgSoft = isDark ? Colors.white60 : Colors.black45;
    final border = isDark ? Colors.white12 : Colors.black12;
    final accent = isDark ? Colors.white : Colors.black;
    final canRunEngine = EngineLoader().isSupportedPlatform;

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
                              child: Icon(
                                Icons.arrow_back_ios_new_rounded,
                                size: 16,
                                color: fg,
                              ),
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
                          _choiceRow(
                            fg: fg,
                            fgSoft: fgSoft,
                            icon: Icons.grid_on_rounded,
                            label: 'Board Theme',
                            subtitle: settings.boardTheme.name,
                            chips: [
                              for (final t in BoardTheme.all)
                                _chip(
                                  label: t.name,
                                  selected: t.name == settings.boardTheme.name,
                                  fg: fg,
                                  border: border,
                                  leading: _BoardSwatch(theme: t),
                                  onTap: () => settings.boardTheme = t,
                                ),
                            ],
                          ),
                          _divider(border),
                          _choiceRow(
                            fg: fg,
                            fgSoft: fgSoft,
                            icon: Icons.category_rounded,
                            label: 'Piece Style',
                            subtitle: settings.pieceStyle.label,
                            chips: [
                              for (final style in PieceStyle.values)
                                _chip(
                                  label: style.label,
                                  selected: style == settings.pieceStyle,
                                  fg: fg,
                                  border: border,
                                  leading: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: PieceImage(
                                      piece: const Piece(
                                        PieceType.knight,
                                        PieceColor.white,
                                      ),
                                      style: style,
                                    ),
                                  ),
                                  onTap: () => settings.pieceStyle = style,
                                ),
                            ],
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
                          _choiceRow(
                            fg: fg,
                            fgSoft: fgSoft,
                            icon: Icons.psychology_rounded,
                            label: 'Default Bot',
                            subtitle: () {
                              final bot =
                                  botProfileById(settings.defaultBotId) ??
                                  kBotProfiles.first;
                              return '${bot.name} · ${bot.eloRating} ELO';
                            }(),
                            chips: [
                              for (final bot in kBotProfiles.reversed)
                                _chip(
                                  label: bot.name,
                                  selected:
                                      bot.id ==
                                      (settings.defaultBotId ??
                                          kBotProfiles.first.id),
                                  fg: fg,
                                  border: border,
                                  onTap: () => settings.defaultBotId = bot.id,
                                ),
                            ],
                          ),
                          _divider(border),
                          _choiceRow(
                            fg: fg,
                            fgSoft: fgSoft,
                            icon: Icons.timer_rounded,
                            label: 'Default Time Control',
                            subtitle: settings.defaultTimeControl.isTimed
                                ? '${settings.defaultTimeControl.label} (minutes + seconds per move)'
                                : 'Untimed',
                            chips: [
                              for (final tc in TimeControl.presets)
                                _chip(
                                  label: tc.label,
                                  selected: tc == settings.defaultTimeControl,
                                  fg: fg,
                                  border: border,
                                  onTap: () => settings.defaultTimeControl = tc,
                                ),
                            ],
                          ),
                          _divider(border),
                          _switchRow(
                            icon: Icons.upgrade_rounded,
                            label: 'Auto-Promote to Queen',
                            subtitle: 'Skip promotion dialog',
                            value: settings.autoQueen,
                            fg: fg,
                            fgSoft: fgSoft,
                            accent: accent,
                            border: border,
                            onChanged: (v) => settings.autoQueen = v,
                          ),
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
                            value: settings.showCoordinates,
                            fg: fg,
                            fgSoft: fgSoft,
                            accent: accent,
                            border: border,
                            onChanged: (v) => settings.showCoordinates = v,
                          ),
                          _divider(border),
                          _switchRow(
                            icon: Icons.radio_button_checked_rounded,
                            label: 'Legal Move Dots',
                            subtitle: 'Show valid squares',
                            value: settings.showLegalMoves,
                            fg: fg,
                            fgSoft: fgSoft,
                            accent: accent,
                            border: border,
                            onChanged: (v) => settings.showLegalMoves = v,
                          ),
                          _divider(border),
                          _switchRow(
                            icon: Icons.history_rounded,
                            label: 'Highlight Last Move',
                            subtitle: 'Shade the previous move',
                            value: settings.showLastMove,
                            fg: fg,
                            fgSoft: fgSoft,
                            accent: accent,
                            border: border,
                            onChanged: (v) => settings.showLastMove = v,
                          ),
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
                                      Text(
                                        'Chess Engine',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.4,
                                          color: fg,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _isEngineInstalled
                                            ? _enginePath!
                                            : 'Not installed',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: fgSoft,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: Text(
                              canRunEngine
                                  ? 'Run ./chess.sh from the repo root to build the built-in engine '
                                        '(add --stockfish to also build Stockfish), install Stockfish '
                                        'with your package manager, or set CHESS_ENGINE_PATH to any UCI engine.'
                                  : 'Engines run as a separate process, which is only supported on desktop (Linux, macOS, Windows).',
                              style: TextStyle(
                                fontSize: 11,
                                color: canRunEngine
                                    ? fgSoft
                                    : Colors.orange.shade700,
                              ),
                            ),
                          ),
                          if (canRunEngine) ...[
                            _divider(border),
                            _actionRow(
                              label: 'CHECK AGAIN',
                              icon: Icons.refresh_rounded,
                              fg: fg,
                              fgSoft: fgSoft,
                              enabled: !_isScanning,
                              onTap: _rescanEngine,
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
                            fgSoft: fgSoft,
                          ),
                          _divider(border),
                          _infoRow(
                            label: 'Last Updated',
                            value: 'April 2026',
                            icon: Icons.calendar_today_rounded,
                            fg: fg,
                            fgSoft: fgSoft,
                          ),
                          _divider(border),
                          _infoRow(
                            label: 'Engine',
                            value: 'Stockfish 17',
                            icon: Icons.memory_rounded,
                            fg: fg,
                            fgSoft: fgSoft,
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

  /// A setting with a label row and a wrap of choice chips beneath it.
  Widget _choiceRow({
    required Color fg,
    required Color fgSoft,
    required IconData icon,
    required String label,
    required String subtitle,
    required List<Widget> chips,
  }) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: fgSoft),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                      color: fg,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 11, color: fgSoft)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: chips),
      ],
    ),
  );

  Widget _chip({
    required String label,
    required bool selected,
    required Color fg,
    required Color border,
    required VoidCallback onTap,
    Widget? leading,
  }) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? fg : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: selected ? fg : border, width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[leading, const SizedBox(width: 6)],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: selected
                  ? (fg == Colors.white ? Colors.black : Colors.white)
                  : fg.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    ),
  );

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
  }) => Padding(
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
  }) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
    child: Row(
      children: [
        Icon(icon, size: 20, color: fgSoft),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: fg,
                ),
              ),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(fontSize: 11, color: fgSoft)),
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
  }) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
    child: Row(
      children: [
        Icon(icon, size: 20, color: fgSoft),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: fg,
                ),
              ),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(fontSize: 11, color: fgSoft)),
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
  }) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
    child: Row(
      children: [
        Icon(icon, size: 20, color: fgSoft),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: fg,
            ),
          ),
        ),
        Text(value, style: TextStyle(fontSize: 12, color: fgSoft)),
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
  }) => GestureDetector(
    onTap: enabled ? onTap : null,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: enabled ? fgSoft : fgSoft.withOpacity(0.4),
          ),
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
          Icon(
            Icons.arrow_forward_ios_rounded,
            size: 13,
            color: enabled ? fgSoft : fgSoft.withOpacity(0.3),
          ),
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
          children: [_pill('☀', !isDark, fg, bg), _pill('☾', isDark, fg, bg)],
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
        child: Text(
          emoji,
          style: TextStyle(
            fontSize: 13,
            color: active ? bg : fg.withOpacity(0.5),
          ),
        ),
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
          border: Border.all(color: value ? fg : border, width: 1.5),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
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
//  2×2 preview of a board theme
// ─────────────────────────────────────────────────────────────
class _BoardSwatch extends StatelessWidget {
  final BoardTheme theme;
  const _BoardSwatch({required this.theme});

  @override
  Widget build(BuildContext context) {
    Widget sq(Color c) => Container(width: 8, height: 8, color: c);
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [sq(theme.light), sq(theme.dark)],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [sq(theme.dark), sq(theme.light)],
          ),
        ],
      ),
    );
  }
}
