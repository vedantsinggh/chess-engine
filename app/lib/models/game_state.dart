import 'package:flutter/material.dart';
import 'position.dart';
import 'piece.dart';

enum GameMode { offline, online, engine }

enum GameStatus {
  whiteTurn,
  blackTurn,
  engineThinking,
  check,
  checkmate,
  stalemate,
}

class CastlingRights {
  bool whiteKingside;
  bool whiteQueenside;
  bool blackKingside;
  bool blackQueenside;

  CastlingRights({
    this.whiteKingside = true,
    this.whiteQueenside = true,
    this.blackKingside = true,
    this.blackQueenside = true,
  });

  CastlingRights copy() => CastlingRights(
        whiteKingside: whiteKingside,
        whiteQueenside: whiteQueenside,
        blackKingside: blackKingside,
        blackQueenside: blackQueenside,
      );
}

class GameState extends ChangeNotifier {
  List<List<Piece?>> board;
  Position? selectedPosition;
  GameStatus status = GameStatus.whiteTurn;
  PieceColor currentTurn = PieceColor.white;
  double evaluation = 0.0;
  List<Position> validMoves = [];
  bool isEngineThinking = false;
  GameMode currentMode = GameMode.offline;

  CastlingRights castlingRights = CastlingRights();
  Position? enPassantTarget;
  Position? pendingPromotion;

  GameState() : board = _createInitialBoard();

  // ================= INIT BOARD =================
  static List<List<Piece?>> _createInitialBoard() {
    return List.generate(8, (row) {
      return List.generate(8, (col) {
        if (row == 1) return const Piece(PieceType.pawn, PieceColor.black);
        if (row == 6) return const Piece(PieceType.pawn, PieceColor.white);

        if (row == 0 || row == 7) {
          final color = row == 0 ? PieceColor.black : PieceColor.white;
          switch (col) {
            case 0:
              return Piece(PieceType.rook, color);
            case 1:
              return Piece(PieceType.knight, color);
            case 2:
              return Piece(PieceType.bishop, color);
            case 3:
              return Piece(PieceType.queen, color);
            case 4:
              return Piece(PieceType.king, color);
            case 5:
              return Piece(PieceType.bishop, color);
            case 6:
              return Piece(PieceType.knight, color);
            case 7:
              return Piece(PieceType.rook, color);
          }
        }
        return null;
      });
    });
  }

  // ================= FEN GETTER =================
  String get currentFen {
    String fen = '';

    for (int row = 0; row < 8; row++) {
      int empty = 0;

      for (int col = 0; col < 8; col++) {
        final piece = board[row][col];

        if (piece == null) {
          empty++;
        } else {
          if (empty > 0) {
            fen += empty.toString();
            empty = 0;
          }
          fen += _pieceToFen(piece);
        }
      }

      if (empty > 0) fen += empty.toString();
      if (row != 7) fen += '/';
    }

    // Turn
    fen += currentTurn == PieceColor.white ? ' w ' : ' b ';

    // Castling
    String castling = '';
    if (castlingRights.whiteKingside) castling += 'K';
    if (castlingRights.whiteQueenside) castling += 'Q';
    if (castlingRights.blackKingside) castling += 'k';
    if (castlingRights.blackQueenside) castling += 'q';
    fen += castling.isEmpty ? '- ' : '$castling ';

    // En passant
    if (enPassantTarget != null) {
      fen += _posToAlgebraic(enPassantTarget!) + ' ';
    } else {
      fen += '- ';
    }

    // Halfmove + fullmove (basic)
    fen += '0 1';

    return fen;
  }

  String _pieceToFen(Piece piece) {
    String symbol;
    switch (piece.type) {
      case PieceType.pawn:
        symbol = 'p';
        break;
      case PieceType.rook:
        symbol = 'r';
        break;
      case PieceType.knight:
        symbol = 'n';
        break;
      case PieceType.bishop:
        symbol = 'b';
        break;
      case PieceType.queen:
        symbol = 'q';
        break;
      case PieceType.king:
        symbol = 'k';
        break;
    }
    return piece.color == PieceColor.white
        ? symbol.toUpperCase()
        : symbol;
  }

  String _posToAlgebraic(Position pos) {
    return String.fromCharCode(97 + pos.col) + (8 - pos.row).toString();
  }

  // ================= RESET =================
  void reset() {
    board = GameState._createInitialBoard();
    selectedPosition = null;
    status = GameStatus.whiteTurn;
    currentTurn = PieceColor.white;
    evaluation = 0.0;
    validMoves = [];
    isEngineThinking = false;
    castlingRights = CastlingRights();
    enPassantTarget = null;
    pendingPromotion = null;
    notifyListeners();
  }

  void setMode(GameMode mode) {
    currentMode = mode;
    reset();
  }

  @override
  void notifyListeners() {
    super.notifyListeners();
  }
}
