import 'package:equatable/equatable.dart';
import 'package:gully_umpire/cv/geometry/point3d.dart';

/// Result of [UmpiringRules.classifyWide].
enum WideResult {
  wide('WIDE'),
  notWide('NOT_WIDE'),
  inconclusive('INCONCLUSIVE');

  const WideResult(this.wire);

  /// Value stored as `automated_result`.
  final String wire;
}

/// Result of [UmpiringRules.classifyHeightNoBall].
enum HeightNoBallResult {
  noBall('NO_BALL'),
  legal('LEGAL');

  const HeightNoBallResult(this.wire);

  /// Value stored as `automated_result`.
  final String wire;
}

/// Local rules for height no-balls (spec §9 `HeightRuleConfig`).
///
/// The waist and shoulder ratios are fractions of the batsman's height. The spec does not give
/// numbers; these are ordinary anatomical proportions and can be tuned per match.
final class HeightRuleConfig extends Equatable {
  const HeightRuleConfig({
    this.fullTossAboveWaistIsNoBall = true,
    this.bouncedAboveShoulderIsNoBall = false,
    this.aboveHeadIsNoBall = true,
    this.waistHeightRatio = 0.55,
    this.shoulderHeightRatio = 0.82,
  });

  final bool fullTossAboveWaistIsNoBall;
  final bool bouncedAboveShoulderIsNoBall;

  /// A ball above the batsman's head is a no-ball whether or not it bounced.
  final bool aboveHeadIsNoBall;

  final double waistHeightRatio;
  final double shoulderHeightRatio;

  @override
  List<Object?> get props => <Object?>[
        fullTossAboveWaistIsNoBall,
        bouncedAboveShoulderIsNoBall,
        aboveHeadIsNoBall,
        waistHeightRatio,
        shoulderHeightRatio,
      ];
}

/// Deterministic wide / height no-ball rules (spec §9). Pure functions, no I/O.
abstract final class UmpiringRules {
  /// Below this wicket or trajectory confidence no wide call is made.
  static const double minWideConfidence = 0.7;

  /// A wide is a ball that passes further from the batsman's centre than he could reach.
  ///
  /// * Inconclusive when the wicket or the trajectory is not trustworthy enough.
  /// * Never a wide when the batsman moved towards the ball.
  /// * Otherwise wide when the sideways distance exceeds `batsmanHeight x lateralReachMultiplier`.
  static WideResult classifyWide({
    required Point3D ballAtBatsmanPlane,
    required Point3D batsmanCenter,
    required double batsmanHeightM,
    required double lateralReachMultiplier,
    required bool batsmanMovedTowardBall,
    required double wicketConfidence,
    required double trajectoryConfidence,
  }) {
    if (wicketConfidence < minWideConfidence || trajectoryConfidence < minWideConfidence) {
      return WideResult.inconclusive;
    }
    if (batsmanMovedTowardBall) {
      return WideResult.notWide;
    }
    final double reach = batsmanHeightM * lateralReachMultiplier;
    final double distance = (ballAtBatsmanPlane.x - batsmanCenter.x).abs();
    return distance > reach ? WideResult.wide : WideResult.notWide;
  }

  /// Height no-ball rules:
  /// a full toss above the waist, a bounced ball above the shoulder (if enabled) and any ball
  /// above the batsman's head (if enabled) are no-balls. Everything else is legal.
  static HeightNoBallResult classifyHeightNoBall({
    required double ballHeightM,
    required double batsmanHeightM,
    required bool bounced,
    required HeightRuleConfig rules,
  }) {
    final double waist = batsmanHeightM * rules.waistHeightRatio;
    final double shoulder = batsmanHeightM * rules.shoulderHeightRatio;

    if (!bounced && rules.fullTossAboveWaistIsNoBall && ballHeightM > waist) {
      return HeightNoBallResult.noBall;
    }
    if (bounced && rules.bouncedAboveShoulderIsNoBall && ballHeightM > shoulder) {
      return HeightNoBallResult.noBall;
    }
    if (rules.aboveHeadIsNoBall && ballHeightM > batsmanHeightM) {
      return HeightNoBallResult.noBall;
    }
    return HeightNoBallResult.legal;
  }
}

/// Per-match umpiring settings used by the CV layer (the app maps `MatchRules` onto this).
final class UmpiringRuleConfig extends Equatable {
  const UmpiringRuleConfig({
    this.wideEnabled = true,
    this.noBallEnabled = true,
    this.wicketHitEnabled = true,
    this.edgeReviewEnabled = false,
    this.lbwReviewEnabled = false,
    this.lateralReachMultiplier = 0.60,
    this.height = const HeightRuleConfig(),
  });

  final bool wideEnabled;
  final bool noBallEnabled;
  final bool wicketHitEnabled;
  final bool edgeReviewEnabled;
  final bool lbwReviewEnabled;

  /// Fraction of the batsman's height that counts as his sideways reach (0.20 - 1.50).
  final double lateralReachMultiplier;

  final HeightRuleConfig height;

  @override
  List<Object?> get props => <Object?>[
        wideEnabled,
        noBallEnabled,
        wicketHitEnabled,
        edgeReviewEnabled,
        lbwReviewEnabled,
        lateralReachMultiplier,
        height,
      ];
}
