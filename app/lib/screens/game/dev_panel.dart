import 'package:flutter/material.dart';
import '../../models/game_state.dart';
import '../../models/piece.dart';
import 'bot_profiles.dart';

// ─────────────────────────────────────────────
// DEV PANEL
// ─────────────────────────────────────────────

class DevPanel extends StatelessWidget {
  final BotProfile bot;
  final GameState state;

  const DevPanel({super.key, required this.bot, required this.state});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.terminal_rounded,
                size: 13,
                color: Color(0xFF6366F1),
              ),
              const SizedBox(width: 6),
              const Text(
                'DEV PANEL',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                  color: Color(0xFF6366F1),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'REMOVE BEFORE RELEASE',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _r('Bot', '${bot.name} (${bot.title})'),
          _r('Depth', '${bot.engineDepth}'),
          _r('Error Rate', '${(bot.errorRate * 100).toInt()}%'),
          _r('ELO', '${bot.eloRating}'),
          _r('Turn', state.currentTurn == PieceColor.white ? 'White' : 'Black'),
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
          child: Text(
            k,
            style: const TextStyle(
              fontSize: 10,
              color: Colors.white54,
              fontFamily: 'monospace',
            ),
          ),
        ),
        Expanded(
          child: Text(
            v,
            style: const TextStyle(
              fontSize: 10,
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}
