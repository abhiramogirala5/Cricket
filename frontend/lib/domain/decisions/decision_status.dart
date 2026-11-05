/// How an automated umpiring result should be presented to the umpire.
///
/// Wire values match `delivery_decisions.decision_status` (docs/API_CONTRACT.md §5.3).
enum DecisionStatus {
  /// Obvious, high-confidence wide / no-ball style calls only.
  autoCall('AUTO_CALL'),

  /// Evidence is available and the umpire should look at it. Always used for
  /// edge, LBW and wicket-hit assistance (never auto-dismissed).
  reviewRecommended('REVIEW_RECOMMENDED'),

  /// Not enough reliable data to say anything.
  inconclusive('INCONCLUSIVE'),

  /// A human replaced the automated result.
  manualOverride('MANUAL_OVERRIDE');

  const DecisionStatus(this.wire);

  /// UPPER_SNAKE_CASE value used in JSON and in the database.
  final String wire;

  /// Parses a wire value; throws [FormatException] for anything unknown.
  static DecisionStatus fromWire(Object? raw) {
    for (final DecisionStatus value in DecisionStatus.values) {
      if (value.wire == raw) {
        return value;
      }
    }
    throw FormatException('Unknown DecisionStatus: $raw');
  }

  /// Short, friendly text for chips and banners.
  String get label {
    switch (this) {
      case DecisionStatus.autoCall:
        return 'Auto call';
      case DecisionStatus.reviewRecommended:
        return 'Review recommended';
      case DecisionStatus.inconclusive:
        return 'Inconclusive';
      case DecisionStatus.manualOverride:
        return 'Manual override';
    }
  }
}
