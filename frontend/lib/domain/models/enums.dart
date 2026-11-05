/// Wire-format enums shared with the backend (docs/API_CONTRACT.md §5.3).
///
/// Every enum exposes `wire` (the UPPER_SNAKE_CASE API value) and `fromWire`.
/// Decision-related enums live in `lib/domain/decisions/`.
library;

T _fromWire<T>(List<T> values, String Function(T) wireOf, Object? raw, String what) {
  for (final T value in values) {
    if (wireOf(value) == raw) {
      return value;
    }
  }
  throw FormatException('Unknown $what: $raw');
}

enum MatchStatus {
  draft('DRAFT'),
  scanning('SCANNING'),
  ready('READY'),
  live('LIVE'),
  completed('COMPLETED'),
  abandoned('ABANDONED');

  const MatchStatus(this.wire);

  final String wire;

  /// COMPLETED and ABANDONED can never be left again (the server enforces this too).
  bool get isTerminal => this == MatchStatus.completed || this == MatchStatus.abandoned;

  String get label {
    switch (this) {
      case MatchStatus.draft:
        return 'Draft';
      case MatchStatus.scanning:
        return 'Scanning';
      case MatchStatus.ready:
        return 'Ready';
      case MatchStatus.live:
        return 'Live';
      case MatchStatus.completed:
        return 'Completed';
      case MatchStatus.abandoned:
        return 'Abandoned';
    }
  }

  static MatchStatus fromWire(Object? raw) =>
      _fromWire<MatchStatus>(values, (MatchStatus v) => v.wire, raw, 'match status');
}

enum BattingHand {
  left('LEFT'),
  right('RIGHT'),
  unknown('UNKNOWN');

  const BattingHand(this.wire);

  final String wire;

  String get label {
    switch (this) {
      case BattingHand.left:
        return 'Left-handed';
      case BattingHand.right:
        return 'Right-handed';
      case BattingHand.unknown:
        return 'Not set';
    }
  }

  /// Unknown or missing values fall back to [BattingHand.unknown].
  static BattingHand fromWire(Object? raw) {
    for (final BattingHand value in values) {
      if (value.wire == raw) {
        return value;
      }
    }
    return BattingHand.unknown;
  }
}

enum DismissalType {
  bowled('BOWLED'),
  caught('CAUGHT'),
  lbw('LBW'),
  runOut('RUN_OUT'),
  stumped('STUMPED'),
  hitWicket('HIT_WICKET');

  const DismissalType(this.wire);

  final String wire;

  String get label {
    switch (this) {
      case DismissalType.bowled:
        return 'Bowled';
      case DismissalType.caught:
        return 'Caught';
      case DismissalType.lbw:
        return 'LBW';
      case DismissalType.runOut:
        return 'Run out';
      case DismissalType.stumped:
        return 'Stumped';
      case DismissalType.hitWicket:
        return 'Hit wicket';
    }
  }

  /// Credited to the bowler (everything except a run-out).
  bool get isBowlerWicket => this != DismissalType.runOut;

  static DismissalType fromWire(Object? raw) =>
      _fromWire<DismissalType>(values, (DismissalType v) => v.wire, raw, 'dismissal type');

  static DismissalType? fromWireOrNull(Object? raw) => raw == null ? null : fromWire(raw);
}

enum TossSide {
  heads('HEADS'),
  tails('TAILS');

  const TossSide(this.wire);

  final String wire;

  String get label => this == TossSide.heads ? 'Heads' : 'Tails';

  TossSide get opposite => this == TossSide.heads ? TossSide.tails : TossSide.heads;

  static TossSide fromWire(Object? raw) =>
      _fromWire<TossSide>(values, (TossSide v) => v.wire, raw, 'toss side');
}

enum TossDecision {
  bat('BAT'),
  bowl('BOWL');

  const TossDecision(this.wire);

  final String wire;

  String get label => this == TossDecision.bat ? 'bat' : 'bowl';

  static TossDecision fromWire(Object? raw) =>
      _fromWire<TossDecision>(values, (TossDecision v) => v.wire, raw, 'toss decision');

  static TossDecision? fromWireOrNull(Object? raw) => raw == null ? null : fromWire(raw);
}

enum DecisionSource {
  aiAssist('AI_ASSIST'),
  manual('MANUAL');

  const DecisionSource(this.wire);

  final String wire;

  static DecisionSource fromWire(Object? raw) =>
      _fromWire<DecisionSource>(values, (DecisionSource v) => v.wire, raw, 'decision source');
}
