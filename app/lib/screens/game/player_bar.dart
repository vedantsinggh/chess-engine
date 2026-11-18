import 'package:flutter/material.dart';
import '../../models/piece.dart';
import '../../services/chess_clock.dart';
import '../../widgets/clock_display.dart';
import 'player_chip.dart';

/// A player's chip plus, in timed games, their clock.
class PlayerBar extends StatelessWidget {
  final PlayerChip chip;
  final PieceColor color;
  final ChessClock? clock;

  const PlayerBar({
    super.key,
    required this.chip,
    required this.color,
    this.clock,
  });

  @override
  Widget build(BuildContext context) {
    final c = clock;
    return Row(
      children: [
        Expanded(
          child: Align(alignment: Alignment.centerLeft, child: chip),
        ),
        if (c != null && c.control.isTimed) ...[
          const SizedBox(width: 10),
          ClockDisplay(clock: c, color: color),
        ],
      ],
    );
  }
}
