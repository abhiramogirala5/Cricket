import 'package:gully_umpire/cv/adapters/mock/mock_scenario.dart';

/// Plain words for the simulated deliveries of a development build.
String mockDeliveryLabel(MockDeliveryKind kind) {
  switch (kind) {
    case MockDeliveryKind.straightHit:
      return 'Straight ball, hits the stumps';
    case MockDeliveryKind.offStumpMiss:
      return 'Good ball, just misses off stump';
    case MockDeliveryKind.wide:
      return 'Wide, far outside the batter';
    case MockDeliveryKind.highFullToss:
      return 'High full toss above the waist';
    case MockDeliveryKind.bouncer:
      return 'Bouncer up to chest height';
    case MockDeliveryKind.lbwHitting:
      return 'Hits the pad, heading for the stumps';
    case MockDeliveryKind.lbwMissing:
      return 'Hits the pad, heading wide of the stumps';
    case MockDeliveryKind.edge:
      return 'Touches the bat with a sound';
    case MockDeliveryKind.lostBall:
      return 'Ball is hard to follow';
  }
}
