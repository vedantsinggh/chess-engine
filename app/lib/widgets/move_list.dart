import 'package:flutter/material.dart';

/// Numbered SAN move list ("1. e4 e5 2. Nf3 ...") with navigation buttons.
///
/// Plies are counted from the start position: ply `k` is the position after
/// the first `k` moves. [viewPly] null means the live (latest) position.
class MoveList extends StatefulWidget {
  final List<String> sanMoves;

  /// FEN the game started from (for the first move number / side).
  final String startFen;
  final int? viewPly;
  final ValueChanged<int> onSelectPly;
  final VoidCallback? onFirst;
  final VoidCallback? onBack;
  final VoidCallback? onForward;
  final VoidCallback? onLive;
  final double height;

  const MoveList({
    super.key,
    required this.sanMoves,
    required this.startFen,
    required this.viewPly,
    required this.onSelectPly,
    this.onFirst,
    this.onBack,
    this.onForward,
    this.onLive,
    this.height = 200,
  });

  @override
  State<MoveList> createState() => _MoveListState();
}

class _MoveListState extends State<MoveList> {
  static const _rowHeight = 30.0;
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(MoveList old) {
    super.didUpdateWidget(old);
    if (old.sanMoves.length != widget.sanMoves.length ||
        old.viewPly != widget.viewPly) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  bool get _startsWithBlack {
    final parts = widget.startFen.split(' ');
    return parts.length > 1 && parts[1] == 'b';
  }

  int get _startNumber {
    final parts = widget.startFen.split(' ');
    return parts.length > 5 ? (int.tryParse(parts[5]) ?? 1) : 1;
  }

  void _scrollToCurrent() {
    if (!_scroll.hasClients) return;
    final ply = widget.viewPly ?? widget.sanMoves.length;
    if (ply == 0) {
      _scroll.jumpTo(0);
      return;
    }
    final row = (ply - 1 + (_startsWithBlack ? 1 : 0)) ~/ 2;
    final target = (row * _rowHeight - widget.height / 2 + _rowHeight).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? Colors.white : Colors.black;
    final border = isDark ? Colors.white12 : Colors.black12;
    final surface = isDark ? const Color(0xFF141414) : Colors.white;

    final offset = _startsWithBlack ? 1 : 0;
    final total = widget.sanMoves.length + offset;
    final rows = (total + 1) ~/ 2;
    final current = widget.viewPly ?? widget.sanMoves.length;

    Widget cell(int moveIndex) {
      if (moveIndex < 0 || moveIndex >= widget.sanMoves.length) {
        return Expanded(
          child: Text(
            moveIndex < 0 ? '…' : '',
            style: TextStyle(color: fg.withValues(alpha: 0.4)),
          ),
        );
      }
      final ply = moveIndex + 1;
      final selected = ply == current;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => widget.onSelectPly(ply),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: selected ? fg.withValues(alpha: 0.12) : null,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              widget.sanMoves[moveIndex],
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                color: fg,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(
              children: [
                Icon(
                  Icons.format_list_numbered_rounded,
                  size: 15,
                  color: fg.withValues(alpha: 0.4),
                ),
                const SizedBox(width: 7),
                Text(
                  'MOVES',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 3,
                    color: fg.withValues(alpha: 0.4),
                  ),
                ),
                const Spacer(),
                if (widget.viewPly != null)
                  TextButton.icon(
                    onPressed: widget.onLive,
                    icon: const Icon(Icons.play_arrow_rounded, size: 16),
                    label: const Text('LIVE'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: widget.height,
            child: rows == 0
                ? Center(
                    child: Text(
                      'No moves yet',
                      style: TextStyle(
                        fontSize: 12,
                        color: fg.withValues(alpha: 0.4),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    itemExtent: _rowHeight,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    itemCount: rows,
                    itemBuilder: (context, row) {
                      final whiteIdx = row * 2 - offset;
                      return Row(
                        children: [
                          SizedBox(
                            width: 36,
                            child: Text(
                              '${_startNumber + row}.',
                              style: TextStyle(
                                fontSize: 12,
                                color: fg.withValues(alpha: 0.45),
                              ),
                            ),
                          ),
                          cell(whiteIdx),
                          cell(whiteIdx + 1),
                        ],
                      );
                    },
                  ),
          ),
          Divider(height: 1, color: border),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                tooltip: 'Start',
                icon: const Icon(Icons.first_page_rounded),
                onPressed: widget.onFirst,
              ),
              IconButton(
                tooltip: 'Previous move (←)',
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: widget.onBack,
              ),
              IconButton(
                tooltip: 'Next move (→)',
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: widget.onForward,
              ),
              IconButton(
                tooltip: 'Return to live',
                icon: const Icon(Icons.last_page_rounded),
                onPressed: widget.onLive,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
