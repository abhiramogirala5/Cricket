/// Entity kinds the backend accepts in `POST /sync/push` (docs/API_CONTRACT.md §5.3).
enum SyncEntityType {
  player('PLAYER'),
  team('TEAM'),
  match('MATCH'),
  matchPlayer('MATCH_PLAYER'),
  matchRules('MATCH_RULES'),
  sceneScan('SCENE_SCAN'),
  wicketDetection('WICKET_DETECTION'),
  toss('TOSS'),
  innings('INNINGS'),
  delivery('DELIVERY'),
  deliveryDecision('DELIVERY_DECISION'),
  trajectorySnapshot('TRAJECTORY_SNAPSHOT');

  const SyncEntityType(this.wire);

  final String wire;

  /// A short, plain-language name for the "Sync issues" screen.
  String get label {
    switch (this) {
      case SyncEntityType.player:
        return 'Player';
      case SyncEntityType.team:
        return 'Team';
      case SyncEntityType.match:
        return 'Match';
      case SyncEntityType.matchPlayer:
        return 'Match squad';
      case SyncEntityType.matchRules:
        return 'Match rules';
      case SyncEntityType.sceneScan:
        return 'Area scan';
      case SyncEntityType.wicketDetection:
        return 'Wicket position';
      case SyncEntityType.toss:
        return 'Toss';
      case SyncEntityType.innings:
        return 'Innings';
      case SyncEntityType.delivery:
        return 'Ball';
      case SyncEntityType.deliveryDecision:
        return 'Umpire decision';
      case SyncEntityType.trajectorySnapshot:
        return 'Ball path';
    }
  }

  static SyncEntityType fromWire(Object? raw) {
    for (final SyncEntityType value in values) {
      if (value.wire == raw) {
        return value;
      }
    }
    throw FormatException('Unknown sync entity type: $raw');
  }
}

/// What an outbox event does to its entity.
enum SyncAction {
  upsert('UPSERT'),
  voidDelivery('VOID'),
  delete('DELETE');

  const SyncAction(this.wire);

  final String wire;

  static SyncAction fromWire(Object? raw) {
    for (final SyncAction value in values) {
      if (value.wire == raw) {
        return value;
      }
    }
    throw FormatException('Unknown sync action: $raw');
  }
}
