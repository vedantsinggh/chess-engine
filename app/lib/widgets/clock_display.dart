import 'package:flutter/material.dart';
import '../models/piece.dart';
import '../services/chess_clock.dart';

/// One side's remaining time. Highlighted while running, red when low.
class ClockDisplay extends StatelessWidget {
  final ChessClock clock;
  final PieceColor color;

  const ClockDisplay({super.key, required this.clock, required this.color});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListenableBuilder(
      listenable: clock,
      builder: (context, _) {
        final remaining = clock.remaining(color);
        final active = clock.active == color;
        final low = clock.isLow(color);
        final flagged = clock.flagged == color;
        final fg = isDark ? Colors.white : Colors.black;
        final Color bg;
        final Color text;
        if (flagged || (low && active)) {
          bg = Colors.red.shade700;
          text = Colors.white;
        } else if (active) {
          bg = fg;
          text = isDark ? Colors.black : Colors.white;
        } else {
          bg = fg.withValues(alpha: 0.06);
          text = low ? Colors.red.shade400 : fg.withValues(alpha: 0.6);
        }
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            ChessClock.format(remaining),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: text,
            ),
          ),
        );
      },
    );
  }
}
