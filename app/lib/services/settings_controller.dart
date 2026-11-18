import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/time_control.dart';
import '../themes/board_theme.dart';

/// User preferences, persisted with shared_preferences and applied live
/// through Provider.
class SettingsController extends ChangeNotifier {
  static const _kBoardTheme = 'board_theme';
  static const _kPieceStyle = 'piece_style';
  static const _kBotId = 'default_bot';
  static const _kTimeControl = 'default_time_control';
  static const _kCoordinates = 'show_coordinates';
  static const _kLegalMoves = 'show_legal_moves';
  static const _kLastMove = 'show_last_move';
  static const _kAutoQueen = 'auto_queen';

  final SharedPreferences? _prefs;

  BoardTheme _boardTheme;
  PieceStyle _pieceStyle;
  String? _defaultBotId;
  TimeControl _defaultTimeControl;
  bool _showCoordinates;
  bool _showLegalMoves;
  bool _showLastMove;
  bool _autoQueen;

  SettingsController._(this._prefs)
    : _boardTheme = BoardTheme.byName(_prefs?.getString(_kBoardTheme)),
      _pieceStyle = PieceStyle.byLabel(_prefs?.getString(_kPieceStyle)),
      _defaultBotId = _prefs?.getString(_kBotId),
      _defaultTimeControl = TimeControl.fromLabel(
        _prefs?.getString(_kTimeControl),
      ),
      _showCoordinates = _prefs?.getBool(_kCoordinates) ?? true,
      _showLegalMoves = _prefs?.getBool(_kLegalMoves) ?? true,
      _showLastMove = _prefs?.getBool(_kLastMove) ?? true,
      _autoQueen = _prefs?.getBool(_kAutoQueen) ?? false;

  /// In-memory defaults (no persistence) — for tests and fallbacks.
  SettingsController.defaults() : this._(null);

  /// Loads persisted settings. Falls back to defaults if storage fails.
  static Future<SettingsController> load() async {
    try {
      return SettingsController._(await SharedPreferences.getInstance());
    } catch (e) {
      debugPrint('Settings unavailable, using defaults: $e');
      return SettingsController.defaults();
    }
  }

  BoardTheme get boardTheme => _boardTheme;
  PieceStyle get pieceStyle => _pieceStyle;

  /// Id of the default bot profile (null = the game screen's default).
  String? get defaultBotId => _defaultBotId;
  TimeControl get defaultTimeControl => _defaultTimeControl;
  bool get showCoordinates => _showCoordinates;
  bool get showLegalMoves => _showLegalMoves;
  bool get showLastMove => _showLastMove;
  bool get autoQueen => _autoQueen;

  set boardTheme(BoardTheme v) {
    _boardTheme = v;
    _prefs?.setString(_kBoardTheme, v.name);
    notifyListeners();
  }

  set pieceStyle(PieceStyle v) {
    _pieceStyle = v;
    _prefs?.setString(_kPieceStyle, v.label);
    notifyListeners();
  }

  set defaultBotId(String? v) {
    _defaultBotId = v;
    if (v == null) {
      _prefs?.remove(_kBotId);
    } else {
      _prefs?.setString(_kBotId, v);
    }
    notifyListeners();
  }

  set defaultTimeControl(TimeControl v) {
    _defaultTimeControl = v;
    _prefs?.setString(_kTimeControl, v.label);
    notifyListeners();
  }

  set showCoordinates(bool v) {
    _showCoordinates = v;
    _prefs?.setBool(_kCoordinates, v);
    notifyListeners();
  }

  set showLegalMoves(bool v) {
    _showLegalMoves = v;
    _prefs?.setBool(_kLegalMoves, v);
    notifyListeners();
  }

  set showLastMove(bool v) {
    _showLastMove = v;
    _prefs?.setBool(_kLastMove, v);
    notifyListeners();
  }

  set autoQueen(bool v) {
    _autoQueen = v;
    _prefs?.setBool(_kAutoQueen, v);
    notifyListeners();
  }
}
