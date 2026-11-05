/// What a [DeliveryDecision] is about.
///
/// Wire values match `delivery_decisions.decision_type` (docs/API_CONTRACT.md §5.3).
enum DeliveryDecisionType {
  wide('WIDE'),
  noBallHeight('NO_BALL_HEIGHT'),
  noBallFrontFoot('NO_BALL_FRONT_FOOT'),
  edge('EDGE'),
  lbw('LBW'),
  wicketHit('WICKET_HIT');

  const DeliveryDecisionType(this.wire);

  /// UPPER_SNAKE_CASE value used in JSON and in the database.
  final String wire;

  /// Parses a wire value; throws [FormatException] for anything unknown.
  static DeliveryDecisionType fromWire(Object? raw) {
    for (final DeliveryDecisionType value in DeliveryDecisionType.values) {
      if (value.wire == raw) {
        return value;
      }
    }
    throw FormatException('Unknown DeliveryDecisionType: $raw');
  }

  /// Short, friendly text for chips and banners.
  String get label {
    switch (this) {
      case DeliveryDecisionType.wide:
        return 'Wide';
      case DeliveryDecisionType.noBallHeight:
        return 'No-ball (height)';
      case DeliveryDecisionType.noBallFrontFoot:
        return 'No-ball (front foot)';
      case DeliveryDecisionType.edge:
        return 'Edge';
      case DeliveryDecisionType.lbw:
        return 'LBW';
      case DeliveryDecisionType.wicketHit:
        return 'Wicket hit';
    }
  }

  /// Only obvious wide / height no-ball events may ever be `AUTO_CALL`.
  ///
  /// Edge, LBW, wicket-hit and front-foot are review-assist features: the
  /// spec forbids auto-dismissing a batter from them (spec §1 rule 12, §3, §9).
  bool get allowsAutoCall {
    switch (this) {
      case DeliveryDecisionType.wide:
      case DeliveryDecisionType.noBallHeight:
        return true;
      case DeliveryDecisionType.noBallFrontFoot:
      case DeliveryDecisionType.edge:
      case DeliveryDecisionType.lbw:
      case DeliveryDecisionType.wicketHit:
        return false;
    }
  }

  /// True for both no-ball flavours.
  bool get isNoBall =>
      this == DeliveryDecisionType.noBallHeight || this == DeliveryDecisionType.noBallFrontFoot;
}
