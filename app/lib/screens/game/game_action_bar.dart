import 'package:flutter/material.dart';

/// Undo / redo / flip, plus draw offer and resign in bot games.
class GameActionBar extends StatelessWidget {
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final VoidCallback onFlip;
  final VoidCallback? onOfferDraw;
  final VoidCallback? onResign;
  final bool showGameEndActions;

  const GameActionBar({
    super.key,
    required this.onUndo,
    required this.onRedo,
    required this.onFlip,
    this.onOfferDraw,
    this.onResign,
    this.showGameEndActions = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? Colors.white12 : Colors.black12;
    final surface = isDark ? const Color(0xFF141414) : Colors.white;
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            tooltip: 'Undo',
            icon: const Icon(Icons.undo_rounded),
            onPressed: onUndo,
          ),
          IconButton(
            tooltip: 'Redo',
            icon: const Icon(Icons.redo_rounded),
            onPressed: onRedo,
          ),
          IconButton(
            tooltip: 'Flip board',
            icon: const Icon(Icons.swap_vert_rounded),
            onPressed: onFlip,
          ),
          if (showGameEndActions) ...[
            IconButton(
              tooltip: 'Offer draw',
              icon: const Icon(Icons.handshake_outlined),
              onPressed: onOfferDraw,
            ),
            IconButton(
              tooltip: 'Resign',
              icon: const Icon(Icons.flag_outlined),
              onPressed: onResign,
            ),
          ],
        ],
      ),
    );
  }
}
