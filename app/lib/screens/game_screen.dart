import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/game_state.dart';
import '../models/piece.dart';
import '../services/game_service.dart';
import '../services/chess_engine_service.dart';
import '../widgets/chess_board.dart';
import '../widgets/evaluation_bar.dart';
import '../widgets/game_controls.dart';
import '../widgets/promotion_dialog.dart';

// ─────────────────────────────────────────────
// DEVELOPER FLAG — set to false before release
// ─────────────────────────────────────────────
const bool kDevMode = false;

// ─────────────────────────────────────────────
// BOT DEFINITIONS
// ─────────────────────────────────────────────

enum BotDifficulty { beginner, casual, intermediate, advanced, master, grandmaster }

class BotProfile {
  final String id;
  final String name;
  final String title;
  final String description;
  final BotDifficulty difficulty;
  final IconData icon;
  final Color accentColor;
  final int eloRating;
  final int engineDepth;
  final double errorRate;

  const BotProfile({
    required this.id,
    required this.name,
    required this.title,
    required this.description,
    required this.difficulty,
    required this.icon,
    required this.accentColor,
    required this.eloRating,
    required this.engineDepth,
    required this.errorRate,
  });
}

const List<BotProfile> kBotProfiles = [
  BotProfile(
    id: 'stockfish',
    name: 'Stockfish',
    title: 'GM',
    description: 'World-class chess engine at full strength',
    difficulty: BotDifficulty.grandmaster,
    icon: Icons.psychology_rounded,
    accentColor: Color(0xFF10B981),
    eloRating: 3500,
    engineDepth: 20,
    errorRate: 0.0,
  ),
  BotProfile(
    id: 'master',
    name: 'Master',
    title: 'Expert',
    description: 'Strong opponent for advanced players',
    difficulty: BotDifficulty.master,
    icon: Icons.emoji_events_rounded,
    accentColor: Color(0xFFF59E0B),
    eloRating: 2200,
    engineDepth: 14,
    errorRate: 0.1,
  ),
  BotProfile(
    id: 'advanced',
    name: 'Advanced',
    title: 'Hard',
    description: 'Challenging for club-level players',
    difficulty: BotDifficulty.advanced,
    icon: Icons.trending_up_rounded,
    accentColor: Color(0xFFEF4444),
    eloRating: 1800,
    engineDepth: 10,
    errorRate: 0.2,
  ),
  BotProfile(
    id: 'intermediate',
    name: 'Intermediate',
    title: 'Medium',
    description: 'Good for casual players',
    difficulty: BotDifficulty.intermediate,
    icon: Icons.equalizer_rounded,
    accentColor: Color(0xFF8B5CF6),
    eloRating: 1400,
    engineDepth: 6,
    errorRate: 0.3,
  ),
  BotProfile(
    id: 'casual',
    name: 'Casual',
    title: 'Easy',
    description: 'Perfect for beginners',
    difficulty: BotDifficulty.casual,
    icon: Icons.spa_rounded,
    accentColor: Color(0xFF06B6D4),
    eloRating: 1000,
    engineDepth: 4,
    errorRate: 0.4,
  ),
  BotProfile(
    id: 'beginner',
    name: 'Beginner',
    title: 'Very Easy',
    description: 'Learn the basics comfortably',
    difficulty: BotDifficulty.beginner,
    icon: Icons.child_care_rounded,
    accentColor: Color(0xFFEC4899),
    eloRating: 600,
    engineDepth: 2,
    errorRate: 0.6,
  ),
];

// ─────────────────────────────────────────────
// BOT SELECTION SHEET
// ─────────────────────────────────────────────

class BotSelectionSheet extends StatefulWidget {
  final BotProfile? currentBot;
  const BotSelectionSheet({super.key, this.currentBot});

  @override
  State<BotSelectionSheet> createState() => _BotSelectionSheetState();
}

class _BotSelectionSheetState extends State<BotSelectionSheet>
    with SingleTickerProviderStateMixin {
  late BotProfile _selected;
  late AnimationController _ctrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _selected = widget.currentBot ?? kBotProfiles[3];
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _fadeAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? Colors.white : Colors.black;
    final bg = isDark ? const Color(0xFF0D0D0D) : Colors.white;
    final border = isDark ? Colors.white12 : Colors.black12;
    final screenH = MediaQuery.of(context).size.height;
    final screenW = MediaQuery.of(context).size.width;
    final isWide = screenW > 600;

    return FadeTransition(
      opacity: _fadeAnim,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: screenH * 0.88,
          maxWidth: isWide ? 520 : double.infinity,
        ),
        margin: isWide
            ? EdgeInsets.symmetric(
                horizontal: (screenW - 520) / 2, vertical: 40)
            : EdgeInsets.zero,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(isWide ? 24 : 28)),
          border: Border(
              top: BorderSide(
                  color: isDark ? Colors.white10 : Colors.black,
                  width: 1)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 6),
              child: Container(
                width: 36,
                height: 3.5,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white : Colors.black,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CHOOSE OPPONENT',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 3,
                            color: fg.withOpacity(0.4),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Select difficulty',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                            color: fg,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // ELO badge — animated
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: _selected.accentColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: _selected.accentColor.withOpacity(0.35)),
                    ),
                    child: Column(
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          child: Text(
                            '${_selected.eloRating}',
                            key: ValueKey(_selected.eloRating),
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: _selected.accentColor,
                              letterSpacing: -1,
                            ),
                          ),
                        ),
                        Text(
                          'ELO',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                            color: _selected.accentColor.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Bot list
            Flexible(
              child: ListView.builder(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                shrinkWrap: true,
                itemCount: kBotProfiles.length,
                itemBuilder: (context, i) {
                  final bot = kBotProfiles[i];
                  return _BotCard(
                    bot: bot,
                    isSelected: _selected.id == bot.id,
                    isDark: isDark,
                    onTap: () => setState(() => _selected = bot),
                  );
                },
              ),
            ),
            // CTA button
            Padding(
              padding: EdgeInsets.fromLTRB(
                  20, 12, 20, 20 + MediaQuery.of(context).padding.bottom),
              child: SizedBox(
                width: double.infinity,
                child: _FancyButton(
                  label: 'PLAY VS ${_selected.name.toUpperCase()}',
                  icon: _selected.icon,
                  accentColor: _selected.accentColor,
                  isDark: isDark,
                  onTap: () => Navigator.pop(context, _selected),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BotCard extends StatelessWidget {
  final BotProfile bot;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  const _BotCard({
    required this.bot,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        decoration: BoxDecoration(
          color: isSelected
              ? bot.accentColor.withOpacity(isDark ? 0.13 : 0.07)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? bot.accentColor.withOpacity(0.7)
                : (isDark ? Colors.white : Colors.black),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                // Icon box
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? bot.accentColor.withOpacity(0.18)
                        : (isDark
                            ? Colors.white.withOpacity(0.06)
                            : Colors.black.withOpacity(0.04)),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    bot.icon,
                    size: 24,
                    color: isSelected
                        ? bot.accentColor
                        : (isDark ? Colors.white38 : Colors.black38),
                  ),
                ),
                const SizedBox(width: 13),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            bot.name,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                          ),
                          const SizedBox(width: 7),
                          _tag(bot.title, bot.accentColor),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        bot.description,
                        style: TextStyle(
                          fontSize: 11,
                          color:
                              isDark ? Colors.white : Colors.black,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // Right: ELO + difficulty dots
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${bot.eloRating}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: isSelected
                            ? bot.accentColor
                            : (isDark ? Colors.white : Colors.black),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: List.generate(6, (i) {
                        final filled = i <= bot.difficulty.index;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 5,
                          height: 5,
                          margin: const EdgeInsets.only(left: 2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: filled
                                ? bot.accentColor
                                : (isDark
                                    ? Colors.white
                                    : Colors.black),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
                if (isSelected) ...[
                  const SizedBox(width: 10),
                  Icon(Icons.check_circle_rounded,
                      color: bot.accentColor, size: 18),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tag(String label, Color color) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.14),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: color,
          ),
        ),
      );
}

// ─────────────────────────────────────────────
// FANCY BUTTON
// ─────────────────────────────────────────────

class _FancyButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final Color accentColor;
  final bool isDark;
  final VoidCallback onTap;

  const _FancyButton({
    required this.label,
    required this.icon,
    required this.accentColor,
    required this.isDark,
    required this.onTap,
  });

  @override
  State<_FancyButton> createState() => _FancyButtonState();
}

class _FancyButtonState extends State<_FancyButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 100));
    _scale = Tween<double>(begin: 1.0, end: 0.96)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: widget.isDark ? Colors.white : Colors.black,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon,
                  size: 18, color: widget.accentColor),
              const SizedBox(width: 10),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                  color: widget.isDark ? Colors.black : Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// FEN PANEL  (engine-analysis mode only)
// ─────────────────────────────────────────────

class _FenPanel extends StatefulWidget {
  final GameState state;
  final GameService gameService;
  final ChessEngineService engineService;

  const _FenPanel({
    required this.state,
    required this.gameService,
    required this.engineService,
  });

  @override
  State<_FenPanel> createState() => _FenPanelState();
}

class _FenPanelState extends State<_FenPanel> {
  late TextEditingController _fenCtrl;
  bool _editing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fenCtrl = TextEditingController(
        text: widget.state.currentFen ?? '');
  }

  @override
  void dispose() {
    _fenCtrl.dispose();
    super.dispose();
  }

  void _copyFen() {
    final fen = widget.state.currentFen ?? '';
    Clipboard.setData(ClipboardData(text: fen));
    ScaffoldMessenger.of(context).showSnackBar(
      _buildSnack('FEN copied to clipboard'),
    );
  }

  void _loadFen() {
    final fen = _fenCtrl.text.trim();
    if (fen.isEmpty) return;
    try {
      widget.gameService.loadFen(widget.state, fen);
      widget.gameService.updateEvaluation(widget.state, widget.engineService);
      setState(() { _editing = false; _error = null; });
    } catch (e) {
      setState(() => _error = 'Invalid FEN string');
    }
  }

  void _resetToStartPos() {
    _fenCtrl.text =
        'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
    _loadFen();
  }

  SnackBar _buildSnack(String msg) => SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      );

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? Colors.white : Colors.black;
    final surface = isDark ? const Color(0xFF141414) : Colors.white;
    final border = isDark ? Colors.white12 : Colors.black12;

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
            child: Row(
              children: [
                Icon(Icons.data_object_rounded,
                    size: 16,
                    color: fg.withOpacity(0.5)),
                const SizedBox(width: 8),
                Text(
                  'FEN',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 3,
                    color: fg.withOpacity(0.4),
                  ),
                ),
                const Spacer(),
                // Copy button
                _iconBtn(
                  icon: Icons.copy_rounded,
                  tooltip: 'Copy FEN',
                  fg: fg,
                  onTap: _copyFen,
                ),
                const SizedBox(width: 4),
                // Edit toggle
                _iconBtn(
                  icon: _editing
                      ? Icons.close_rounded
                      : Icons.edit_rounded,
                  tooltip: _editing ? 'Cancel' : 'Load FEN',
                  fg: fg,
                  onTap: () => setState(
                      () => _editing = !_editing),
                ),
              ],
            ),
          ),
          // FEN display or input
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: _editing
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _fenCtrl,
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          color: fg,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Paste FEN string…',
                          hintStyle: TextStyle(
                              color: fg.withOpacity(0.3),
                              fontSize: 12),
                          errorText: _error,
                          isDense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(
                                  vertical: 10, horizontal: 12),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: fg),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                                color: Colors.red),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                                color: Colors.red),
                          ),
                        ),
                        maxLines: 2,
                        minLines: 1,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _outlinedBtn(
                              label: 'START POS',
                              fg: fg,
                              border: border,
                              onTap: _resetToStartPos,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _solidBtn(
                              label: 'LOAD',
                              fg: fg,
                              onTap: _loadFen,
                            ),
                          ),
                        ],
                      ),
                    ],
                  )
                : GestureDetector(
                    onTap: () =>
                        setState(() => _editing = true),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          vertical: 10, horizontal: 12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withOpacity(0.04)
                            : Colors.black.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: border),
                      ),
                      child: Text(
                        widget.state.currentFen ??
                            'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: fg.withOpacity(0.6),
                          height: 1.5,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _iconBtn({
    required IconData icon,
    required String tooltip,
    required Color fg,
    required VoidCallback onTap,
  }) =>
      Tooltip(
        message: tooltip,
        child: GestureDetector(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, size: 18, color: fg.withOpacity(0.5)),
          ),
        ),
      );

  Widget _outlinedBtn({
    required String label,
    required Color fg,
    required Color border,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: fg.withOpacity(0.7),
              ),
            ),
          ),
        ),
      );

  Widget _solidBtn({
    required String label,
    required Color fg,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: fg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: fg == Colors.white ? Colors.black : Colors.white,
              ),
            ),
          ),
        ),
      );
}

// ─────────────────────────────────────────────
// PLAYER HEADER CHIP
// ─────────────────────────────────────────────

class _PlayerChip extends StatelessWidget {
  final String name;
  final IconData icon;
  final Color? accentColor;
  final bool isActive;
  final bool isDark;
  final String? subtitle;

  const _PlayerChip({
    required this.name,
    required this.icon,
    this.accentColor,
    required this.isActive,
    required this.isDark,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final fg = isDark ? Colors.white : Colors.black;
    final iconColor = accentColor ?? fg;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isActive
            ? iconColor.withOpacity(isDark ? 0.12 : 0.07)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive
              ? iconColor.withOpacity(0.5)
              : (isDark ? Colors.white10 : Colors.black),
          width: isActive ? 1.5 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(isActive ? 0.18 : 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: fg,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: 10,
                    color: isActive ? iconColor : fg.withOpacity(0.4),
                    fontWeight: isActive
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
            ],
          ),
          if (isActive) ...[
            const SizedBox(width: 10),
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: iconColor,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// STATUS BANNER
// ─────────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  final GameStatus status;
  final PieceColor currentTurn;

  const _StatusBanner({required this.status, required this.currentTurn});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    String? message;
    Color? color;
    IconData? icon;

    switch (status) {
      case GameStatus.check:
        message = 'CHECK!';
        color = Colors.amber;
        icon = Icons.warning_amber_rounded;
        break;
      case GameStatus.checkmate:
        message = currentTurn == PieceColor.black ? 'YOU WIN! 🎉' : 'CHECKMATE';
        color = currentTurn == PieceColor.black ? Colors.green : Colors.red;
        icon = currentTurn == PieceColor.black
            ? Icons.emoji_events_rounded
            : Icons.flag_rounded;
        break;
      case GameStatus.stalemate:
        message = 'STALEMATE — DRAW';
        color = Colors.orange;
        icon = Icons.handshake_rounded;
        break;
      default:
        return const SizedBox.shrink();
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        color: color!.withOpacity(isDark ? 0.18 : 0.1),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: color.withOpacity(0.55)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Text(
            message!,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// DEV PANEL
// ─────────────────────────────────────────────

class _DevPanel extends StatelessWidget {
  final BotProfile bot;
  final GameState state;

  const _DevPanel({required this.bot, required this.state});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: const Color(0xFF6366F1).withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.terminal_rounded,
                  size: 13, color: Color(0xFF6366F1)),
              const SizedBox(width: 6),
              const Text('DEV PANEL',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                      color: Color(0xFF6366F1))),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('REMOVE BEFORE RELEASE',
                    style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _r('Bot', '${bot.name} (${bot.title})'),
          _r('Depth', '${bot.engineDepth}'),
          _r('Error Rate', '${(bot.errorRate * 100).toInt()}%'),
          _r('ELO', '${bot.eloRating}'),
          _r('Turn',
              state.currentTurn == PieceColor.white ? 'White' : 'Black'),
          _r('Status', state.status.name),
        ],
      ),
    );
  }

  Widget _r(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
                width: 80,
                child: Text(k,
                    style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white54,
                        fontFamily: 'monospace'))),
            Expanded(
              child: Text(v,
                  style: const TextStyle(
                      fontSize: 10,
                      color: Colors.white,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────
// MAIN GAME SCREEN
// ─────────────────────────────────────────────

class GameScreen extends StatefulWidget {
  final String mode;
  const GameScreen({super.key, required this.mode});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  late GameService _gameService;
  late ChessEngineService _engineService;
  late GameState _gameState;

  bool _isEngineInitialized = false;
  BotProfile _currentBot = kBotProfiles[0]; // Stockfish default

  StreamSubscription<double>? _evalSubscription;

  // Whether we're in offline (vs bot) or engine (analysis) mode
  bool get _isAnalysisMode => widget.mode == 'engine';

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _engineService = ChessEngineService();
    _gameService = GameService(_engineService);
    _gameState = GameState()
      ..currentMode = _getModeFromString(widget.mode);

    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _fadeAnim =
        CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();

    _initializeEngine();
    if (!_isAnalysisMode) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _showBotSelection());
    }
  }

  @override
  void dispose() {
    _evalSubscription?.cancel();
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _initializeEngine() async {
    final ok = await _engineService.initialize();
    if (!mounted) return;
    setState(() => _isEngineInitialized = ok);
    if (!ok) {
      if (!_isAnalysisMode) _showEngineError();
      return;
    }
    _evalSubscription = _engineService.liveEvalStream.listen((pawns) {
      if (!mounted) return;
      final relative = _gameState.currentTurn == PieceColor.black
          ? -pawns
          : pawns;
      _gameState.evaluation = relative;
      _gameState.notifyListeners();
    });
    if (_isAnalysisMode) {
      _gameService.updateEvaluation(_gameState, _engineService);
    }
  }

  void _showEngineError() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18)),
        title: const Text('Engine Unavailable'),
        content: const Text(
            'Chess engine could not be loaded. Offline mode is still available.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _showBotSelection({bool isChange = false}) async {
    final result = await showModalBottomSheet<BotProfile>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BotSelectionSheet(currentBot: _currentBot),
    );
    if (result != null && mounted) {
      setState(() => _currentBot = result);
      if (isChange) {
        _gameState.reset();
        if (_isEngineInitialized && _isAnalysisMode) {
          _gameService.updateEvaluation(_gameState, _engineService);
        }
      }
    }
  }

  void _newGame() {
    _gameState.reset();
    if (_isEngineInitialized && _isAnalysisMode) {
      _gameService.updateEvaluation(_gameState, _engineService);
    }
  }

  // ─── Layout sizing ────────────────────────────────────────────────────────

  // Breakpoints
  bool _isMobile(Size s) => s.width < 600;
  bool _isTablet(Size s) => s.width >= 600 && s.width < 1024;
  bool _isDesktop(Size s) => s.width >= 1024;

  double _boardSize(Size s) {
    if (_isDesktop(s)) return (s.width * 0.52).clamp(420.0, 700.0);
    if (_isTablet(s)) return (s.width * 0.58).clamp(340.0, 560.0);
    // Mobile: fill width minus padding, also respect height so board
    // doesn't overflow on landscape phones
    final byWidth = s.width - 32;
    final byHeight = s.height * 0.52;
    return byWidth.clamp(0.0, byHeight.clamp(240.0, 480.0));
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _gameState,
      child: Consumer<GameState>(
        builder: (context, state, _) {
          final size = MediaQuery.of(context).size;

          return Scaffold(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            appBar: _buildAppBar(context, state),
            body: FadeTransition(
              opacity: _fadeAnim,
              child: _isMobile(size)
                  ? _buildMobileLayout(context, state, size)
                  : _buildWideLayout(context, state, size),
            ),
          );
        },
      ),
    );
  }

  // ─── AppBar ───────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar(BuildContext context, GameState state) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? Colors.white : Colors.black;

    return AppBar(
      backgroundColor:
          Theme.of(context).appBarTheme.backgroundColor,
      foregroundColor:
          Theme.of(context).appBarTheme.foregroundColor,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => Navigator.pop(context),
      ),
      title: _isAnalysisMode
          ? _analysisTitleWidget(fg)
          : _botTitleWidget(state),
      actions: [
        // Spinner while engine is thinking
        if (state.isEngineThinking)
          Padding(
            padding: const EdgeInsets.all(14),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: fg),
            ),
          ),
        // Offline vs bot: change bot
        if (!_isAnalysisMode)
          IconButton(
            icon: const Icon(Icons.swap_horiz_rounded),
            tooltip: 'Change Bot',
            onPressed: () => _showBotSelection(isChange: true),
          ),
        // New game / Reset
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          tooltip: _isAnalysisMode ? 'Reset Board' : 'New Game',
          onPressed: state.isEngineThinking ? null : _newGame,
        ),
        if (kDevMode)
          const IconButton(
            icon: Icon(Icons.terminal_rounded,
                color: Color(0xFF6366F1)),
            tooltip: 'Dev',
            onPressed: null,
          ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _botTitleWidget(GameState state) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: Icon(
            _currentBot.icon,
            key: ValueKey(_currentBot.id),
            color: _currentBot.accentColor,
            size: 20,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _currentBot.name,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        const SizedBox(width: 6),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: _currentBot.accentColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '${_currentBot.eloRating}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: _currentBot.accentColor,
            ),
          ),
        ),
      ],
    );
  }

  Widget _analysisTitleWidget(Color fg) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.bar_chart_rounded,
            size: 20, color: fg.withOpacity(0.7)),
        const SizedBox(width: 8),
        const Text('ENGINE ANALYSIS',
            style: TextStyle(
                fontWeight: FontWeight.w900, letterSpacing: 1)),
      ],
    );
  }

  // ─── Mobile layout ────────────────────────────────────────────────────────

  Widget _buildMobileLayout(
      BuildContext context, GameState state, Size size) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isYourTurn = state.currentTurn == PieceColor.white &&
        !state.isEngineThinking;
    final boardSz = _boardSize(size);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          // Status banner
          _StatusBanner(
              status: state.status,
              currentTurn: state.currentTurn),

          // Bot-mode: show bot + player chips
          if (!_isAnalysisMode) ...[
            Row(
              children: [
                Expanded(
                  child: _PlayerChip(
                    name: _currentBot.name,
                    icon: _currentBot.icon,
                    accentColor: _currentBot.accentColor,
                    isActive: state.currentTurn == PieceColor.black,
                    isDark: isDark,
                    subtitle: state.isEngineThinking
                        ? 'Thinking…'
                        : '${_currentBot.eloRating} ELO',
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text('vs',
                      style: TextStyle(
                          fontSize: 12,
                          color: (isDark ? Colors.white : Colors.black)
                              .withOpacity(0.3),
                          fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  child: _PlayerChip(
                    name: 'You',
                    icon: Icons.person_rounded,
                    isActive: isYourTurn,
                    isDark: isDark,
                    subtitle: isYourTurn ? 'Your turn' : 'Waiting…',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],

          // Analysis mode: FEN panel at top on mobile
          if (_isAnalysisMode) ...[
            _FenPanel(
                state: state,
                gameService: _gameService,
                engineService: _engineService),
            const SizedBox(height: 12),
          ],

          // Chess board
          Center(
            child: SizedBox(
              width: boardSz,
              height: boardSz,
              child: Stack(
                children: [
                  ChessBoard(gameService: _gameService),
                  Consumer<GameState>(
                    builder: (context, s, _) => PromotionDialog(
                        state: s, gameService: _gameService),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Eval bar — analysis mode only
          if (_isAnalysisMode && _isEngineInitialized)
            _EvalBarCard(
                evaluation: state.evaluation, isDark: isDark),

          if (_isAnalysisMode) const SizedBox(height: 12),

          // Game controls
          GameControls(
            gameService: _gameService,
            engineService: _engineService,
            engineAvailable: _isEngineInitialized,
            onEngineMoveRequested: () {},
          ),

          if (kDevMode && !_isAnalysisMode) ...[
            const SizedBox(height: 12),
            _DevPanel(bot: _currentBot, state: state),
          ],

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ─── Wide layout (tablet + desktop) ──────────────────────────────────────

  Widget _buildWideLayout(
      BuildContext context, GameState state, Size size) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDesktop = _isDesktop(size);
    final boardSz = _boardSize(size);
    final sideWidth = isDesktop ? 320.0 : 260.0;
    final isYourTurn = state.currentTurn == PieceColor.white &&
        !state.isEngineThinking;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1400),
        child: Padding(
          padding: EdgeInsets.all(isDesktop ? 32 : 20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Board column
              Flexible(
                flex: 3,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _StatusBanner(
                          status: state.status,
                          currentTurn: state.currentTurn),
                      // Bot header above board
                      if (!_isAnalysisMode)
                        Padding(
                          padding:
                              const EdgeInsets.only(bottom: 10),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _PlayerChip(
                                name: _currentBot.name,
                                icon: _currentBot.icon,
                                accentColor: _currentBot.accentColor,
                                isActive:
                                    state.currentTurn ==
                                        PieceColor.black,
                                isDark: isDark,
                                subtitle: state.isEngineThinking
                                    ? 'Thinking…'
                                    : '${_currentBot.eloRating} ELO',
                              ),
                            ],
                          ),
                        ),
                      SizedBox(
                        width: boardSz,
                        height: boardSz,
                        child: Stack(
                          children: [
                            ChessBoard(gameService: _gameService),
                            Consumer<GameState>(
                              builder: (context, s, _) =>
                                  PromotionDialog(
                                      state: s,
                                      gameService: _gameService),
                            ),
                          ],
                        ),
                      ),
                      if (!_isAnalysisMode)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: _PlayerChip(
                            name: 'You',
                            icon: Icons.person_rounded,
                            isActive: isYourTurn,
                            isDark: isDark,
                            subtitle: isYourTurn
                                ? 'Your turn'
                                : 'Waiting…',
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              SizedBox(width: isDesktop ? 36 : 22),
              // Side panel
              SizedBox(
                width: sideWidth,
                child: _buildSidePanel(context, state, isDark, isYourTurn),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSidePanel(
    BuildContext context,
    GameState state,
    bool isDark,
    bool isYourTurn,
  ) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Analysis: FEN panel
          if (_isAnalysisMode) ...[
            _FenPanel(
                state: state,
                gameService: _gameService,
                engineService: _engineService),
            const SizedBox(height: 16),
          ],

          // Analysis: vertical eval bar
          if (_isAnalysisMode && _isEngineInitialized) ...[
            _EvalBarCard(evaluation: state.evaluation, isDark: isDark),
            const SizedBox(height: 16),
          ],

          // Game controls
          GameControls(
            gameService: _gameService,
            engineService: _engineService,
            engineAvailable: _isEngineInitialized,
            onEngineMoveRequested: () {},
          ),

          if (kDevMode && !_isAnalysisMode) ...[
            const SizedBox(height: 12),
            _DevPanel(bot: _currentBot, state: state),
          ],
        ],
      ),
    );
  }

  GameMode _getModeFromString(String mode) {
    switch (mode) {
      case 'offline':
        return GameMode.offline;
      case 'engine':
        return GameMode.engine;
      default:
        return GameMode.offline;
    }
  }
}

// ─────────────────────────────────────────────
// EVAL BAR CARD WRAPPER
// ─────────────────────────────────────────────

class _EvalBarCard extends StatelessWidget {
  final double evaluation;
  final bool isDark;

  const _EvalBarCard(
      {required this.evaluation, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final border = isDark ? Colors.white12 : Colors.black12;
    final surface =
        isDark ? const Color(0xFF141414) : Colors.white;
    final fg = isDark ? Colors.white : Colors.black;

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bar_chart_rounded,
                  size: 15, color: fg.withOpacity(0.4)),
              const SizedBox(width: 7),
              Text(
                'EVALUATION',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 3,
                  color: fg.withOpacity(0.4),
                ),
              ),
              const Spacer(),
              // Numeric eval
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  _evalLabel(evaluation),
                  key: ValueKey(evaluation.toStringAsFixed(1)),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: evaluation > 0
                        ? (isDark ? Colors.white : Colors.black)
                        : (isDark
                            ? Colors.white60
                            : Colors.black54),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 36,
            child: EvaluationBar(
                evaluation: evaluation, isHorizontal: true),
          ),
        ],
      ),
    );
  }

  String _evalLabel(double v) {
    if (v.abs() > 50) return v > 0 ? '+M' : '-M'; // mate
    final sign = v > 0 ? '+' : '';
    return '$sign${v.toStringAsFixed(1)}';
  }
}
