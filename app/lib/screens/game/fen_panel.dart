import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/game_state.dart';
import '../../services/chess_engine_service.dart';
import '../../services/game_service.dart';

// ─────────────────────────────────────────────
// FEN PANEL  (engine-analysis mode only)
// ─────────────────────────────────────────────

class FenPanel extends StatefulWidget {
  final GameState state;
  final GameService gameService;
  final ChessEngineService engineService;

  const FenPanel({
    super.key,
    required this.state,
    required this.gameService,
    required this.engineService,
  });

  @override
  State<FenPanel> createState() => FenPanelState();
}

class FenPanelState extends State<FenPanel> {
  late TextEditingController _fenCtrl;
  bool _editing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fenCtrl = TextEditingController(text: widget.state.currentFen);
  }

  @override
  void dispose() {
    _fenCtrl.dispose();
    super.dispose();
  }

  void _copyFen() {
    final fen = widget.state.currentFen;
    Clipboard.setData(ClipboardData(text: fen));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(_buildSnack('FEN copied to clipboard'));
  }

  void _loadFen() {
    final fen = _fenCtrl.text.trim();
    if (fen.isEmpty) return;
    try {
      widget.gameService.loadFen(widget.state, fen);
      widget.gameService.updateEvaluation(widget.state, widget.engineService);
      setState(() {
        _editing = false;
        _error = null;
      });
    } on FormatException catch (e) {
      setState(() => _error = 'Invalid FEN: ${e.message}');
    }
  }

  void _resetToStartPos() {
    _fenCtrl.text = GameState.startPositionFen;
    _loadFen();
  }

  SnackBar _buildSnack(String msg) => SnackBar(
    content: Text(msg),
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  );

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? Colors.white : Colors.black;
    final surface = isDark ? const Color(0xFF141414) : Colors.white;
    final border = isDark ? Colors.white12 : Colors.black12;

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
            child: Row(
              children: [
                Icon(
                  Icons.data_object_rounded,
                  size: 16,
                  color: fg.withOpacity(0.5),
                ),
                const SizedBox(width: 8),
                Text(
                  'FEN',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 3,
                    color: fg.withOpacity(0.4),
                  ),
                ),
                const Spacer(),
                // Copy button
                _iconBtn(
                  icon: Icons.copy_rounded,
                  tooltip: 'Copy FEN',
                  fg: fg,
                  onTap: _copyFen,
                ),
                const SizedBox(width: 4),
                // Edit toggle
                _iconBtn(
                  icon: _editing ? Icons.close_rounded : Icons.edit_rounded,
                  tooltip: _editing ? 'Cancel' : 'Load FEN',
                  fg: fg,
                  onTap: () => setState(() => _editing = !_editing),
                ),
              ],
            ),
          ),
          // FEN display or input
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: _editing
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _fenCtrl,
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          color: fg,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Paste FEN string…',
                          hintStyle: TextStyle(
                            color: fg.withOpacity(0.3),
                            fontSize: 12,
                          ),
                          errorText: _error,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 12,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: fg),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Colors.red),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Colors.red),
                          ),
                        ),
                        maxLines: 2,
                        minLines: 1,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _outlinedBtn(
                              label: 'START POS',
                              fg: fg,
                              border: border,
                              onTap: _resetToStartPos,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _solidBtn(
                              label: 'LOAD',
                              fg: fg,
                              onTap: _loadFen,
                            ),
                          ),
                        ],
                      ),
                    ],
                  )
                : GestureDetector(
                    onTap: () => setState(() => _editing = true),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 12,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withOpacity(0.04)
                            : Colors.black.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: border),
                      ),
                      child: Text(
                        widget.state.currentFen,
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: fg.withOpacity(0.6),
                          height: 1.5,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _iconBtn({
    required IconData icon,
    required String tooltip,
    required Color fg,
    required VoidCallback onTap,
  }) => Tooltip(
    message: tooltip,
    child: GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 18, color: fg.withOpacity(0.5)),
      ),
    ),
  );

  Widget _outlinedBtn({
    required String label,
    required Color fg,
    required Color border,
    required VoidCallback onTap,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
            color: fg.withOpacity(0.7),
          ),
        ),
      ),
    ),
  );

  Widget _solidBtn({
    required String label,
    required Color fg,
    required VoidCallback onTap,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: fg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
            color: fg == Colors.white ? Colors.black : Colors.white,
          ),
        ),
      ),
    ),
  );
}
