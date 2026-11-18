import 'package:flutter/material.dart';
import '../../models/game_state.dart';
import '../../models/piece.dart';
import '../../utils/result_text.dart';

/// Check warning, or the game result once it is over.
class StatusBanner extends StatelessWidget {
  final GameState state;

  /// The human's colour in a bot game; null in analysis mode.
  final PieceColor? humanColor;

  const StatusBanner({super.key, required this.state, this.humanColor});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final result = state.result;
    String message;
    Color color;
    IconData icon;

    if (result != null) {
      message = describeResult(result, human: humanColor).toUpperCase();
      if (result.isDraw) {
        color = Colors.orange;
        icon = Icons.handshake_rounded;
      } else if (humanColor == null || result.winner == humanColor) {
        color = Colors.green;
        icon = Icons.emoji_events_rounded;
      } else {
        color = Colors.red;
        icon = Icons.flag_rounded;
      }
    } else if (state.status == GameStatus.check) {
      message = 'CHECK!';
      color = Colors.amber;
      icon = Icons.warning_amber_rounded;
    } else {
      return const SizedBox.shrink();
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.18 : 0.1),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
