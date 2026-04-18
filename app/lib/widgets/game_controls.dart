import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/game_state.dart';
import '../services/game_service.dart';
import '../services/chess_engine_service.dart';
import '../utils/fen_converter.dart';
import 'evaluation_bar.dart';

class GameControls extends StatelessWidget {
  final GameService gameService;
  final ChessEngineService engineService;
  final bool engineAvailable;
  final VoidCallback? onEngineMoveRequested;

  const GameControls({
    super.key,
    required this.gameService,
    required this.engineService,
    required this.engineAvailable,
    this.onEngineMoveRequested,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<GameState>(
      builder: (context, state, child) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 20),

            // Evaluation Score
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade400),
              ),
              child: Text(
                _formatEvaluation(state.evaluation),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _getScoreColor(state.evaluation),
                ),
              ),
            ),

            const SizedBox(height: 30),

            // Engine Move Button
            if (state.currentMode == GameMode.engine)
              ElevatedButton.icon(
                onPressed: state.isEngineThinking || !engineAvailable
                    ? null
                    : onEngineMoveRequested,
                icon: const Icon(Icons.psychology),
                label: const Text('Engine Move'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
              ),

            if (state.currentMode == GameMode.engine)
              const SizedBox(height: 15),

            // Copy FEN Button
            OutlinedButton.icon(
              onPressed: state.isEngineThinking
                  ? null
                  : () => _copyFenToClipboard(context, state),
              icon: const Icon(Icons.copy_all),
              label: const Text('Copy FEN'),
            ),

            const SizedBox(height: 15),

            // Engine Status
            if (!engineAvailable && state.currentMode == GameMode.engine)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.warning, color: Colors.orange, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Engine not available. Install in Settings.',
                        style: TextStyle(fontSize: 12, color: Colors.orange),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  String _formatEvaluation(double eval) {
    final sign = eval > 0 ? '+' : '';
    return '$sign${eval.toStringAsFixed(2)}';
  }

  Color _getScoreColor(double eval) {
    if (eval > 0.5) return Colors.green[700]!;
    if (eval < -0.5) return Colors.red[700]!;
    return Colors.grey[700]!;
  }

  void _copyFenToClipboard(BuildContext context, GameState state) {
    final fen = FenConverter.boardToFen(state);
    Clipboard.setData(ClipboardData(text: fen));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('FEN copied to clipboard: $fen'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
