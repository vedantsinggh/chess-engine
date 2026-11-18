/// A Fischer time control: [initial] time per side plus [increment] added
/// after each move. [TimeControl.none] means an untimed game.
class TimeControl {
  final Duration initial;
  final Duration increment;

  const TimeControl(this.initial, [this.increment = Duration.zero]);

  static const none = TimeControl(Duration.zero);

  static const presets = <TimeControl>[
    none,
    TimeControl(Duration(minutes: 1)),
    TimeControl(Duration(minutes: 3), Duration(seconds: 2)),
    TimeControl(Duration(minutes: 5)),
    TimeControl(Duration(minutes: 10)),
    TimeControl(Duration(minutes: 15), Duration(seconds: 10)),
    TimeControl(Duration(minutes: 30)),
  ];

  bool get isTimed => initial > Duration.zero;

  /// "None", "1+0", "3+2", ...; also used as the persisted id.
  String get label =>
      isTimed ? '${initial.inMinutes}+${increment.inSeconds}' : 'None';

  /// The preset with this [label], or [none].
  static TimeControl fromLabel(String? label) =>
      presets.firstWhere((t) => t.label == label, orElse: () => none);

  @override
  bool operator ==(Object other) =>
      other is TimeControl &&
      other.initial == initial &&
      other.increment == increment;

  @override
  int get hashCode => Object.hash(initial, increment);

  @override
  String toString() => 'TimeControl($label)';
}
