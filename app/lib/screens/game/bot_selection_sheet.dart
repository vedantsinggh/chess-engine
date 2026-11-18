import 'dart:math';
import 'package:flutter/material.dart';
import '../../models/time_control.dart';
import 'bot_profiles.dart';

/// Which colour the human wants to play.
enum SideChoice { white, random, black }

/// What the bot setup sheet returns.
class BotGameSetup {
  final BotProfile bot;
  final SideChoice side;
  final TimeControl timeControl;
  const BotGameSetup(this.bot, this.side, this.timeControl);
}

// ─────────────────────────────────────────────
// BOT SELECTION SHEET
// ─────────────────────────────────────────────

class BotSelectionSheet extends StatefulWidget {
  final BotProfile? currentBot;
  final SideChoice side;
  final TimeControl timeControl;
  const BotSelectionSheet({
    super.key,
    this.currentBot,
    this.side = SideChoice.white,
    this.timeControl = TimeControl.none,
  });

  @override
  State<BotSelectionSheet> createState() => _BotSelectionSheetState();
}

class _BotSelectionSheetState extends State<BotSelectionSheet>
    with SingleTickerProviderStateMixin {
  late BotProfile _selected;
  late SideChoice _side;
  late TimeControl _timeControl;
  late AnimationController _ctrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _selected = widget.currentBot ?? kBotProfiles[3];
    _side = widget.side;
    _timeControl = widget.timeControl;
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
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
                // The modal sheet itself is at most 640 wide.
                horizontal: ((min(screenW, 640.0) - 520) / 2).clamp(0.0, 60.0),
                vertical: 40,
              )
            : EdgeInsets.zero,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(isWide ? 24 : 28),
          ),
          border: Border(
            top: BorderSide(
              color: isDark ? Colors.white10 : Colors.black,
              width: 1,
            ),
          ),
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
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: _selected.accentColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _selected.accentColor.withOpacity(0.35),
                      ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
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
            // Side + time control
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('PLAY AS', isDark),
                  const SizedBox(height: 6),
                  SegmentedButton<SideChoice>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: SideChoice.white,
                        label: Text('White'),
                        icon: Icon(Icons.circle_outlined, size: 14),
                      ),
                      ButtonSegment(
                        value: SideChoice.random,
                        label: Text('Random'),
                        icon: Icon(Icons.shuffle_rounded, size: 14),
                      ),
                      ButtonSegment(
                        value: SideChoice.black,
                        label: Text('Black'),
                        icon: Icon(Icons.circle, size: 14),
                      ),
                    ],
                    selected: {_side},
                    onSelectionChanged: (s) => setState(() => _side = s.first),
                  ),
                  const SizedBox(height: 12),
                  _label('TIME CONTROL', isDark),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final tc in TimeControl.presets)
                        ChoiceChip(
                          label: Text(tc.label),
                          selected: tc == _timeControl,
                          onSelected: (_) => setState(() => _timeControl = tc),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            // CTA button
            Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                12,
                20,
                20 + MediaQuery.of(context).padding.bottom,
              ),
              child: SizedBox(
                width: double.infinity,
                child: _FancyButton(
                  label: 'PLAY VS ${_selected.name.toUpperCase()}',
                  icon: _selected.icon,
                  accentColor: _selected.accentColor,
                  isDark: isDark,
                  onTap: () => Navigator.pop(
                    context,
                    BotGameSetup(_selected, _side, _timeControl),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _label(String text, bool isDark) => Text(
  text,
  style: TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w800,
    letterSpacing: 3,
    color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.4),
  ),
);

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
                          Flexible(
                            child: Text(
                              bot.name,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: isDark ? Colors.white : Colors.black,
                              ),
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
                          color: isDark ? Colors.white : Colors.black,
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
                                : (isDark ? Colors.white : Colors.black),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
                if (isSelected) ...[
                  const SizedBox(width: 10),
                  Icon(
                    Icons.check_circle_rounded,
                    color: bot.accentColor,
                    size: 18,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tag(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scale = Tween<double>(
      begin: 1.0,
      end: 0.96,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
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
              Icon(widget.icon, size: 18, color: widget.accentColor),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  widget.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                    color: widget.isDark ? Colors.black : Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
