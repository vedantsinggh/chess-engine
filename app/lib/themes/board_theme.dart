import 'package:flutter/material.dart';

/// Square colours for the chess board.
class BoardTheme {
  final String name;
  final Color light;
  final Color dark;

  const BoardTheme(this.name, this.light, this.dark);

  /// Colour for coordinate labels drawn on a square of the other colour.
  Color labelOn(bool lightSquare) => lightSquare ? dark : light;

  static const all = <BoardTheme>[
    BoardTheme('Classic', Color(0xFFD7CCC8), Color(0xFF5D4037)),
    BoardTheme('Walnut', Color(0xFFF0D9B5), Color(0xFFB58863)),
    BoardTheme('Green', Color(0xFFEEEED2), Color(0xFF769656)),
    BoardTheme('Ocean', Color(0xFFDEE3E6), Color(0xFF8CA2AD)),
    BoardTheme('Midnight', Color(0xFF9AA5B1), Color(0xFF3E4C59)),
    BoardTheme('Sand', Color(0xFFF2E6CE), Color(0xFFCDAA7D)),
  ];

  static BoardTheme byName(String? name) =>
      all.firstWhere((t) => t.name == name, orElse: () => all.first);
}

/// Piece artwork. Only styles backed by bundled assets are offered:
/// [classic] uses assets/pieces/*.png, [vector] the single-colour SVGs in
/// assets/icons/ (recoloured at runtime for White).
enum PieceStyle {
  classic('Classic'),
  vector('Vector');

  final String label;
  const PieceStyle(this.label);

  static PieceStyle byLabel(String? label) => PieceStyle.values.firstWhere(
    (s) => s.label == label,
    orElse: () => PieceStyle.classic,
  );
}
