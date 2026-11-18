import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/piece.dart';
import '../themes/board_theme.dart';

/// Draws [piece] in the chosen [style].
class PieceImage extends StatelessWidget {
  final Piece piece;
  final PieceStyle style;

  const PieceImage({super.key, required this.piece, required this.style});

  static const _names = {
    PieceType.pawn: 'pawn',
    PieceType.knight: 'knight',
    PieceType.bishop: 'bishop',
    PieceType.rook: 'rook',
    PieceType.queen: 'queen',
    PieceType.king: 'king',
  };

  @override
  Widget build(BuildContext context) {
    Widget fallback(BuildContext _, Object __, StackTrace? ___) =>
        Center(child: Text(piece.toCode()));

    switch (style) {
      case PieceStyle.classic:
        return Image.asset(
          piece.assetPath,
          fit: BoxFit.contain,
          errorBuilder: fallback,
        );
      case PieceStyle.vector:
        return Padding(
          padding: const EdgeInsets.all(3),
          child: SvgPicture.asset(
            'assets/icons/${_names[piece.type]}.svg',
            fit: BoxFit.contain,
            colorMapper: piece.isWhite ? const _WhitePieceMapper() : null,
            errorBuilder: fallback,
          ),
        );
    }
  }
}

/// The SVG icons are drawn as black pieces (black fill, white detail lines).
/// For White, swap the fills and draw the details in black, keeping the
/// black outline.
class _WhitePieceMapper extends ColorMapper {
  const _WhitePieceMapper();

  static const _black = Color(0xFF000000);
  static const _white = Color(0xFFFFFFFF);

  @override
  Color substitute(
    String? id,
    String elementName,
    String attributeName,
    Color color,
  ) {
    final isBlack = color.toARGB32() == _black.toARGB32();
    final isWhite = color.toARGB32() == _white.toARGB32();
    if (attributeName == 'fill') {
      if (isBlack) return _white;
      if (isWhite) return _black;
    } else if (attributeName == 'stroke' && isWhite) {
      return _black;
    }
    return color;
  }
}
