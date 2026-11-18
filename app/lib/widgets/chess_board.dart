import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/game_state.dart';
import '../models/position.dart';
import '../services/game_service.dart';
import '../services/settings_controller.dart';
import 'move_dot.dart';
import 'piece_image.dart';

/// The board. Shows the live [GameState] from the nearest provider, or —
/// when [viewState] is given — that (historical) position read-only.
class ChessBoard extends StatelessWidget {
  final GameService gameService;

  /// Draw the board from Black's side (a8 bottom-right, h1 top-left).
  final bool flipped;

  /// A read-only position to show instead of the live game.
  final GameState? viewState;

  const ChessBoard({
    super.key,
    required this.gameService,
    this.flipped = false,
    this.viewState,
  });

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final theme = settings.boardTheme;

    return Consumer<GameState>(
      builder: (context, live, child) {
        final state = viewState ?? live;
        final readOnly = viewState != null;
        final last = state.moveHistory.isEmpty ? null : state.moveHistory.last;
        final lastFrom = settings.showLastMove && last != null
            ? Position.fromAlgebraic(last.substring(0, 2))
            : null;
        final lastTo = settings.showLastMove && last != null
            ? Position.fromAlgebraic(last.substring(2, 4))
            : null;

        return Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade800, width: 2),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(4, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 8,
              ),
              itemCount: 64,
              itemBuilder: (context, index) {
                final displayRow = index ~/ 8;
                final displayCol = index % 8;
                final row = flipped ? 7 - displayRow : displayRow;
                final col = flipped ? 7 - displayCol : displayCol;
                final pos = Position(row, col);
                final isLight = (row + col) % 2 == 0;
                final piece = state.board[row][col];

                final isSelected = !readOnly && state.selectedPosition == pos;
                final isTarget =
                    !readOnly &&
                    settings.showLegalMoves &&
                    state.validMoves.contains(pos);
                final isCapture = isTarget && piece != null;
                final isLastMove = pos == lastFrom || pos == lastTo;
                final labelColor = theme.labelOn(isLight);
                final labelStyle = TextStyle(
                  fontSize: 10,
                  color: labelColor,
                  fontWeight: FontWeight.bold,
                );

                Color color = isLight ? theme.light : theme.dark;
                if (isLastMove) {
                  color = Color.alphaBlend(
                    const Color(0x66F6E05E),
                    color,
                  ); // yellow tint
                }
                if (isSelected) {
                  color = Color.alphaBlend(
                    Colors.blue.withValues(alpha: 0.55),
                    color,
                  );
                } else if (isCapture) {
                  color = Color.alphaBlend(
                    Colors.red.withValues(alpha: 0.35),
                    color,
                  );
                }

                return GestureDetector(
                  onTap: readOnly
                      ? null
                      : () => gameService.handleSquareTap(live, row, col),
                  child: Container(
                    color: color,
                    child: Stack(
                      children: [
                        if (piece != null)
                          Positioned.fill(
                            child: PieceImage(
                              piece: piece,
                              style: settings.pieceStyle,
                            ),
                          ),
                        if (isTarget && !isSelected)
                          MoveDot(isCapture: isCapture),
                        if (settings.showCoordinates && displayRow == 7)
                          Positioned(
                            bottom: 2,
                            left: 4,
                            child: Text(pos.algebraic[0], style: labelStyle),
                          ),
                        if (settings.showCoordinates && displayCol == 7)
                          Positioned(
                            top: 2,
                            right: 4,
                            child: Text(pos.algebraic[1], style: labelStyle),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
