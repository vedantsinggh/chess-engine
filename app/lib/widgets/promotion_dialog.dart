import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/piece.dart';
import '../models/game_state.dart';
import '../services/game_service.dart';
import '../services/settings_controller.dart';
import 'piece_image.dart';

/// Shows automatically when [GameState.pendingPromotion] is non-null.
/// Place this in the game screen's Stack, above the chess board. Tapping
/// outside the card cancels the move.
class PromotionDialog extends StatelessWidget {
  final GameState state;
  final GameService gameService;

  const PromotionDialog({
    super.key,
    required this.state,
    required this.gameService,
  });

  @override
  Widget build(BuildContext context) {
    if (state.pendingPromotion == null) return const SizedBox.shrink();

    // The pawn has not moved yet: the side to move is promoting.
    final color = state.currentTurn;
    final style = context.watch<SettingsController>().pieceStyle;

    const choices = [
      PieceType.queen,
      PieceType.rook,
      PieceType.bishop,
      PieceType.knight,
    ];

    return GestureDetector(
      onTap: () => gameService.cancelPromotion(state),
      child: Container(
        color: Colors.black54,
        child: Center(
          child: GestureDetector(
            onTap: () {}, // don't cancel when tapping the card itself
            child: Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Promote pawn',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: choices.map((type) {
                        return GestureDetector(
                          onTap: () =>
                              gameService.completePromotion(state, type),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade400),
                            ),
                            child: PieceImage(
                              piece: Piece(type, color),
                              style: style,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
