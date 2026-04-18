import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/game_state.dart';
import '../models/position.dart';
import '../services/game_service.dart';
import 'move_dot.dart';

class ChessBoard extends StatelessWidget {
  final GameService gameService;

  const ChessBoard({super.key, required this.gameService});
  @override
  Widget build(BuildContext context) {
    return Consumer<GameState>(
      builder: (context, state, child) {
        return Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade800, width: 2),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
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
                final row = index ~/ 8;
                final col = index % 8;
                final isLight = (row + col) % 2 == 0;
                final piece = state.board[row][col];

                final isSelected =
                    state.selectedPosition != null &&
                    state.selectedPosition!.row == row &&
                    state.selectedPosition!.col == col;

                final isValidMoveTarget = state.validMoves.any(
                  (pos) => pos.row == row && pos.col == col,
                );

                final isCapture = isValidMoveTarget && piece != null;

                return GestureDetector(
                  onTap: () {
                    gameService.handleSquareTap(state, row, col);
                  },
                  child: Container(
                    color: _getSquareColor(
                      isLight: isLight,
                      isSelected: isSelected,
                      isCapture: isCapture,
                      isValidMoveTarget: isValidMoveTarget,
                    ),
                    child: Stack(
                      children: [
                        if (isValidMoveTarget && !isSelected)
                          MoveDot(isCapture: isCapture),

                        // Coordinate labels: files on rank 1 (row 7),
                        // ranks on h-file (col 7).
                        if (row == 7)
                          Positioned(
                            bottom: 2,
                            left: 4,
                            child: Text(
                              String.fromCharCode('a'.codeUnitAt(0) + col),
                              style: TextStyle(
                                fontSize: 10,
                                color: isLight
                                    ? Colors.brown[800]
                                    : Colors.brown[100],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),

                        if (col == 7)
                          Positioned(
                            top: 2,
                            right: 4,
                            child: Text(
                              '${8 - row}',
                              style: TextStyle(
                                fontSize: 10,
                                color: isLight
                                    ? Colors.brown[800]
                                    : Colors.brown[100],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),

                        Center(
                          child: piece != null
                              ? Image.asset(
                                  piece.assetPath,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      color: Colors.red,
                                      child: Text(piece.toCode()),
                                    );
                                  },
                                )
                              : null,
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

  Color _getSquareColor({
    required bool isLight,
    required bool isSelected,
    required bool isCapture,
    required bool isValidMoveTarget,
  }) {
    if (isSelected) return Colors.blue[400]!.withOpacity(0.7);
    if (isValidMoveTarget && isCapture) return Colors.red.withOpacity(0.4);
    return isLight ? Colors.brown[100]! : Colors.brown[700]!;
  }
}
