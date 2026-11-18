import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/piece.dart';
import '../models/time_control.dart';

/// Two-sided chess clock with Fischer increment.
///
/// Time is measured with [now] (injectable for tests). With [autoTick] a
/// periodic timer calls [tick] so listeners repaint and flag-fall is
/// detected; tests pass `autoTick: false` and call [tick] themselves.
class ChessClock extends ChangeNotifier {
  final TimeControl control;
  final DateTime Function() _now;
  final bool autoTick;
  final Duration tickInterval;

  final Map<PieceColor, Duration> _remaining;
  PieceColor? _active;
  DateTime? _since;
  PieceColor? _flagged;
  Timer? _timer;
  bool _disposed = false;

  /// Called once when a side's time runs out.
  void Function(PieceColor flagged)? onFlag;

  ChessClock(
    this.control, {
    DateTime Function()? now,
    this.autoTick = true,
    this.tickInterval = const Duration(milliseconds: 100),
  }) : _now = now ?? DateTime.now,
       _remaining = {
         PieceColor.white: control.initial,
         PieceColor.black: control.initial,
       };

  /// Side whose clock is running (null when stopped).
  PieceColor? get active => _active;
  PieceColor? get flagged => _flagged;
  bool get isRunning => _active != null;

  Duration remaining(PieceColor color) {
    var r = _remaining[color]!;
    if (color == _active && _since != null) r -= _now().difference(_since!);
    return r.isNegative ? Duration.zero : r;
  }

  /// Below this a clock is shown as "low on time".
  Duration get lowTimeThreshold => control.initial < const Duration(minutes: 3)
      ? const Duration(seconds: 10)
      : const Duration(seconds: 20);

  bool isLow(PieceColor color) => remaining(color) <= lowTimeThreshold;

  /// Starts (or switches to) [side]'s clock without adding any increment.
  void start(PieceColor side) {
    if (_flagged != null || !control.isTimed) return;
    _commit();
    _active = side;
    _since = _now();
    _ensureTimer();
    _notify();
  }

  /// [mover] completed a move: adds the increment to their clock and starts
  /// the opponent's. If [mover] had already run out, they lose on time.
  void moveMade(PieceColor mover) {
    if (_flagged != null || !control.isTimed) return;
    _commit();
    if (_remaining[mover]! <= Duration.zero) {
      _flag(mover);
      return;
    }
    _remaining[mover] = _remaining[mover]! + control.increment;
    start(mover == PieceColor.white ? PieceColor.black : PieceColor.white);
  }

  /// Stops both clocks (game over / paused).
  void stop() {
    _commit();
    _active = null;
    _since = null;
    _timer?.cancel();
    _timer = null;
    _notify();
  }

  /// Checks for flag-fall and notifies listeners.
  void tick() {
    final a = _active;
    if (a == null) return;
    if (remaining(a) <= Duration.zero) {
      _flag(a);
    } else {
      _notify();
    }
  }

  void _commit() {
    final a = _active, s = _since;
    if (a == null || s == null) return;
    final now = _now();
    _remaining[a] = _remaining[a]! - now.difference(s);
    _since = now;
  }

  void _flag(PieceColor color) {
    _commit();
    _remaining[color] = Duration.zero;
    _flagged = color;
    _active = null;
    _since = null;
    _timer?.cancel();
    _timer = null;
    _notify();
    onFlag?.call(color);
  }

  void _ensureTimer() {
    if (!autoTick || _timer != null) return;
    _timer = Timer.periodic(tickInterval, (_) => tick());
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    onFlag = null;
    super.dispose();
  }

  /// "5:00", "0:42", and tenths below ten seconds ("7.3").
  static String format(Duration d) {
    if (d < const Duration(seconds: 10)) {
      final tenths = (d.inMilliseconds / 100).floor();
      return '${tenths ~/ 10}.${tenths % 10}';
    }
    final totalSeconds = d.inMilliseconds ~/ 1000;
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
  }
}
