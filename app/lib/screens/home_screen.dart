import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'game_screen.dart';
import 'settings_screen.dart';

// ─────────────────────────────────────────────────────────────
//  Floating chess-piece particle
// ─────────────────────────────────────────────────────────────
class _ChessPiece {
  final String svgAsset;
  double x;        // 0..1 relative to width
  double y;        // 0..1 relative to height
  double speed;    // pixels per second
  double size;
  double opacity;
  double rotation; // radians

  _ChessPiece({
    required this.svgAsset,
    required this.x,
    required this.y,
    required this.speed,
    required this.size,
    required this.opacity,
    required this.rotation,
  });
}

class _GraffitiPainter extends CustomPainter {
  final double progress; // 0..1, drives the overall animation tick

  _GraffitiPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.04)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    // Draw faint diagonal grid lines for a "street court" vibe
    for (double i = -size.height; i < size.width + size.height; i += 60) {
      canvas.drawLine(
        Offset(i, 0),
        Offset(i + size.height, size.height),
        paint,
      );
    }

    // Scattered dots
    final dotPaint = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..style = PaintingStyle.fill;
    final rng = Random(42);
    for (int i = 0; i < 40; i++) {
      canvas.drawCircle(
        Offset(rng.nextDouble() * size.width, rng.nextDouble() * size.height),
        rng.nextDouble() * 2 + 0.5,
        dotPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_GraffitiPainter old) => false;
}

// ─────────────────────────────────────────────────────────────
//  Animated background widget
// ─────────────────────────────────────────────────────────────
class _AnimatedChessBackground extends StatefulWidget {
  final bool isDark;
  const _AnimatedChessBackground({required this.isDark});

  @override
  State<_AnimatedChessBackground> createState() =>
      _AnimatedChessBackgroundState();
}

class _AnimatedChessBackgroundState extends State<_AnimatedChessBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  final _pieces = <_ChessPiece>[];
  final _assets = [
    'assets/icons/queen.svg',
    'assets/icons/king.svg',
    'assets/icons/knight.svg',
    'assets/icons/pawn.svg',
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();

    final rng = Random(7);
    for (int i = 0; i < 14; i++) {
      _pieces.add(_ChessPiece(
        svgAsset: _assets[rng.nextInt(_assets.length)],
        x: rng.nextDouble(),
        y: rng.nextDouble(),
        speed: 18 + rng.nextDouble() * 28,
        size: 22 + rng.nextDouble() * 32,
        opacity: 0.04 + rng.nextDouble() * 0.08,
        rotation: rng.nextDouble() * pi * 2,
      ));
    }
  }

  DateTime _lastTick = DateTime.now();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fg = widget.isDark ? Colors.white : Colors.black;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final now = DateTime.now();
        final dt = now.difference(_lastTick).inMilliseconds / 1000.0;
        _lastTick = now;

        for (final p in _pieces) {
          p.y -= (p.speed * dt) / MediaQuery.of(context).size.height;
          if (p.y < -0.15) {
            p.y = 1.1;
            p.x = Random().nextDouble();
          }
        }

        return CustomPaint(
          painter: _GraffitiPainter(progress: _controller.value),
          child: Stack(
            children: _pieces.map((p) {
              return Positioned(
                left: p.x * MediaQuery.of(context).size.width - p.size / 2,
                top: p.y * MediaQuery.of(context).size.height - p.size / 2,
                child: Transform.rotate(
                  angle: p.rotation,
                  child: Opacity(
                    opacity: p.opacity,
                    child: SvgPicture.asset(
                      p.svgAsset,
                      height: p.size,
                      colorFilter:
                          ColorFilter.mode(fg, BlendMode.srcIn),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  HomeScreen
// ─────────────────────────────────────────────────────────────
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // ✅ Fix: read dark mode from Theme, not a hardcoded prop
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? Colors.black : Colors.white;
    final fg = isDark ? Colors.white : Colors.black;
    final secondary = isDark ? Colors.white54 : Colors.black45;

    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        children: [
          // ── Animated background ──────────────────────────────
          Positioned.fill(
            child: _AnimatedChessBackground(isDark: isDark),
          ),

          // ── Main content ─────────────────────────────────────
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                // ✅ Fix: max-width so it looks great on web & landscape
                constraints: const BoxConstraints(maxWidth: 480),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;

                    return Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: width * 0.06,
                        vertical: 20,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // HEADER
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              SvgPicture.asset(
                                'assets/icons/queen.svg',
                                height: 28,
                                colorFilter:
                                    ColorFilter.mode(fg, BlendMode.srcIn),
                              ),
                              SvgPicture.asset(
                                'assets/icons/king.svg',
                                height: 28,
                                colorFilter:
                                    ColorFilter.mode(fg, BlendMode.srcIn),
                              ),
                            ],
                          ),

                          const SizedBox(height: 40),

                          // TITLE
                          Text(
                            "RANK",
                            style: TextStyle(
                              fontSize: width * 0.13,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 8,
                              color: fg,
                              height: 1,
                            ),
                          ),

                          const SizedBox(height: 6),

                          // Accent underline bar
                          Container(
                            width: 48,
                            height: 3,
                            decoration: BoxDecoration(
                              color: fg,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),

                          const SizedBox(height: 12),

                          Text(
                            "Play. Learn. Improve.",
                            style: TextStyle(
                              fontSize: 13,
                              letterSpacing: 1.5,
                              color: secondary,
                            ),
                          ),

                          const SizedBox(height: 48),

                          // MODES
                          _modeTile(
                            context,
                            fg: fg,
                            bg: bg,
                            title: "Offline vs Bot",
                            subtitle: "Play against engine",
                            iconPath: "assets/icons/knight.svg",
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    const GameScreen(mode: 'offline'),
                              ),
                            ),
                          ),

                          const SizedBox(height: 14),

                          _modeTile(
                            context,
                            fg: fg,
                            bg: bg,
                            title: "Engine Analysis",
                            subtitle: "Analyze positions",
                            iconPath: "assets/icons/pawn.svg",
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    const GameScreen(mode: 'engine'),
                              ),
                            ),
                          ),

                          const SizedBox(height: 14),

                          _modeTile(
                            context,
                            fg: fg,
                            bg: bg,
                            title: "Online Multiplayer",
                            subtitle: "Coming soon",
                            iconPath: "assets/icons/king.svg",
                            disabled: true,
                            onTap: () {},
                          ),

                          const Spacer(),

                          // SETTINGS BUTTON
                          // ✅ Fix: constrained width so it doesn't stretch wide
                          Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 420),
                              child: SizedBox(
                                width: double.infinity,
                                child: TextButton(
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                    backgroundColor: fg,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const SettingsScreen(),
                                      ),
                                    );
                                  },
                                  child: Text(
                                    "SETTINGS",
                                    style: TextStyle(
                                      color: bg,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 3,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 8),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeTile(
    BuildContext context, {
    required Color fg,
    required Color bg,
    required String title,
    required String subtitle,
    required String iconPath,
    required VoidCallback onTap,
    bool disabled = false,
  }) {
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          // Slight frosted tint so tiles read over the animated bg
          color: bg.withOpacity(0.88),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: disabled ? fg.withOpacity(0.18) : fg.withOpacity(0.85),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: fg.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            SvgPicture.asset(
              iconPath,
              height: 26,
              colorFilter: ColorFilter.mode(
                disabled ? fg.withOpacity(0.25) : fg,
                BlendMode.srcIn,
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title.toUpperCase(),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4,
                      fontSize: 13,
                      color: disabled ? fg.withOpacity(0.25) : fg,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: fg.withOpacity(0.5),
                      fontSize: 12,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: disabled ? 0.2 : 0.7,
              child: Icon(Icons.arrow_forward_ios_rounded,
                  size: 15, color: fg),
            ),
          ],
        ),
      ),
    );
  }
}
