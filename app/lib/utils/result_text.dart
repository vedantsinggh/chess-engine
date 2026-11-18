import '../models/game_state.dart';
import '../models/piece.dart';

String _name(PieceColor c) => c == PieceColor.white ? 'White' : 'Black';

/// Human-readable result, e.g. "You resigned", "White wins on time",
/// "Draw agreed". [human] is the human's colour in a bot game (null in
/// analysis mode), so messages can say "you".
String describeResult(GameResult r, {PieceColor? human}) {
  final winner = r.winner;
  if (winner == null) {
    return switch (r.drawReason) {
      DrawReason.agreement => 'Draw agreed',
      DrawReason.stalemate => 'Draw — stalemate',
      DrawReason.threefoldRepetition => 'Draw — threefold repetition',
      DrawReason.fiftyMoveRule => 'Draw — 50-move rule',
      DrawReason.insufficientMaterial => 'Draw — insufficient material',
      DrawReason.timeoutVsInsufficientMaterial =>
        'Draw — time out vs insufficient material',
      null => 'Draw',
    };
  }
  final loser = winner == PieceColor.white
      ? PieceColor.black
      : PieceColor.white;
  switch (r.status) {
    case GameStatus.checkmate:
      if (human == null) return 'Checkmate — ${_name(winner)} wins';
      return winner == human ? 'Checkmate — you win' : 'Checkmate — you lost';
    case GameStatus.resigned:
      if (human == null)
        return '${_name(loser)} resigned — ${_name(winner)} wins';
      return loser == human ? 'You resigned' : 'Bot resigned — you win';
    case GameStatus.timeout:
      return '${_name(winner)} wins on time';
    default:
      return '${_name(winner)} wins';
  }
}
