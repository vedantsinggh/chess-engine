import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'game_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatelessWidget {
  final bool isDark;
  const HomeScreen({super.key, this.isDark = false});

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? Colors.black : Colors.white;
    final fg = isDark ? Colors.white : Colors.black;
    final secondary = isDark ? Colors.white70 : Colors.black54;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
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
                        colorFilter: ColorFilter.mode(fg, BlendMode.srcIn),
                      ),
                      SvgPicture.asset(
                        'assets/icons/king.svg',
                        height: 28,
                        colorFilter: ColorFilter.mode(fg, BlendMode.srcIn),
                      ),
                    ],
                  ),

                  const SizedBox(height: 40),

                  // TITLE
                  Text(
                    "RANK",
                    style: TextStyle(
                      fontSize: width * 0.1,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 6,
                      color: fg,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    "Play. Learn. Improve.",
                    style: TextStyle(
                      fontSize: 14,
                      color: secondary,
                    ),
                  ),

                  const SizedBox(height: 50),

                  // MODES
                  _modeTile(
                    context,
                    fg,
                    bg,
                    title: "Offline vs Bot",
                    subtitle: "Play against engine",
                    iconPath: "assets/icons/knight.svg",
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const GameScreen(mode: 'offline'),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  _modeTile(
                    context,
                    fg,
                    bg,
                    title: "Engine Analysis",
                    subtitle: "Analyze positions",
                    iconPath: "assets/icons/pawn.svg",
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const GameScreen(mode: 'engine'),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  _modeTile(
                    context,
                    fg,
                    bg,
                    title: "Online Multiplayer",
                    subtitle: "Coming soon",
                    iconPath: "assets/icons/king.svg",
                    disabled: true,
                    onTap: () {},
                  ),

                  const Spacer(),

                  // SETTINGS BUTTON
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: fg,
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SettingsScreen(),
                          ),
                        );
                      },
                      child: Text(
                        "SETTINGS",
                        style: TextStyle(
                          color: bg,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _modeTile(
    BuildContext context,
    Color fg,
    Color bg, {
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
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: disabled ? fg.withOpacity(0.2) : fg,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            SvgPicture.asset(
              iconPath,
              height: 28,
              colorFilter: ColorFilter.mode(
                disabled ? fg.withOpacity(0.3) : fg,
                BlendMode.srcIn,
              ),
            ),

            const SizedBox(width: 20),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title.toUpperCase(),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      fontSize: 14,
                      color: disabled ? fg.withOpacity(0.3) : fg,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: fg.withOpacity(0.6),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),

            AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: disabled ? 0.3 : 1,
              child: Icon(Icons.arrow_forward_ios, size: 16, color: fg),
            ),
          ],
        ),
      ),
    );
  }
}
