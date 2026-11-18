import 'package:flutter/material.dart';
import '../../widgets/evaluation_bar.dart';

// ─────────────────────────────────────────────
// EVAL BAR CARD WRAPPER
// ─────────────────────────────────────────────

class EvalBarCard extends StatelessWidget {
  final double evaluation;
  final bool isDark;

  const EvalBarCard({
    super.key,
    required this.evaluation,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final border = isDark ? Colors.white12 : Colors.black12;
    final surface = isDark ? const Color(0xFF141414) : Colors.white;
    final fg = isDark ? Colors.white : Colors.black;

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.bar_chart_rounded,
                size: 15,
                color: fg.withOpacity(0.4),
              ),
              const SizedBox(width: 7),
              Text(
                'EVALUATION',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 3,
                  color: fg.withOpacity(0.4),
                ),
              ),
              const Spacer(),
              // Numeric eval
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  _evalLabel(evaluation),
                  key: ValueKey(evaluation.toStringAsFixed(1)),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: evaluation > 0
                        ? (isDark ? Colors.white : Colors.black)
                        : (isDark ? Colors.white60 : Colors.black54),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 36,
            child: EvaluationBar(evaluation: evaluation, isHorizontal: true),
          ),
        ],
      ),
    );
  }

  String _evalLabel(double v) {
    if (v.abs() > 50) return v > 0 ? '+M' : '-M'; // mate
    final sign = v > 0 ? '+' : '';
    return '$sign${v.toStringAsFixed(1)}';
  }
}
