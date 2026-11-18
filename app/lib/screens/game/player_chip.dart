import 'package:flutter/material.dart';

// ─────────────────────────────────────────────
// PLAYER HEADER CHIP
// ─────────────────────────────────────────────

class PlayerChip extends StatelessWidget {
  final String name;
  final IconData icon;
  final Color? accentColor;
  final bool isActive;
  final bool isDark;
  final String? subtitle;

  const PlayerChip({
    super.key,
    required this.name,
    required this.icon,
    this.accentColor,
    required this.isActive,
    required this.isDark,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final fg = isDark ? Colors.white : Colors.black;
    final iconColor = accentColor ?? fg;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isActive
            ? iconColor.withOpacity(isDark ? 0.12 : 0.07)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive
              ? iconColor.withOpacity(0.5)
              : (isDark ? Colors.white10 : Colors.black),
          width: isActive ? 1.5 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(isActive ? 0.18 : 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: fg,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: 10,
                    color: isActive ? iconColor : fg.withOpacity(0.4),
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
            ],
          ),
          if (isActive) ...[
            const SizedBox(width: 10),
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: iconColor,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
