import 'package:equatable/equatable.dart';
import 'package:gully_umpire/cv/geometry/point3d.dart';
import 'package:gully_umpire/cv/rules/edge_review.dart';
import 'package:gully_umpire/cv/rules/lbw_review.dart';
import 'package:gully_umpire/cv/rules/umpiring_rules.dart';
import 'package:gully_umpire/cv/rules/wicket_hit_review.dart';
import 'package:gully_umpire/cv/util/math_utils.dart';
import 'package:gully_umpire/domain/decisions/decision_status.dart';
import 'package:gully_umpire/domain/decisions/delivery_decision.dart';
import 'package:gully_umpire/domain/decisions/delivery_decision_type.dart';

/// A wide check with the numbers behind it.
final class WideAssessment extends Equatable {
  const WideAssessment({
    required this.result,
    required this.confidence,
    required this.distanceM,
    required this.reachM,
    required this.ballLateralM,
    required this.batsmanMovedTowardBall,
    required this.wicketConfidence,
    required this.trajectoryConfidence,
  });

  final WideResult result;

  /// Belief (0..1) that [result] is right; low when the ball was close to the limit.
  final double confidence;

  /// Sideways distance of the ball from the batsman's centre (metres).
  final double distanceM;

  /// How far the batsman could reach (metres).
  final double reachM;

  /// Signed sideways position of the ball relative to the batsman's centre (+ = image right).
  final double ballLateralM;

  final bool batsmanMovedTowardBall;
  final double wicketConfidence;
  final double trajectoryConfidence;

  @override
  List<Object?> get props => <Object?>[
        result,
        confidence,
        distanceM,
        reachM,
        ballLateralM,
        batsmanMovedTowardBall,
        wicketConfidence,
        trajectoryConfidence,
      ];
}

/// A height no-ball check with the numbers behind it.
final class HeightNoBallAssessment extends Equatable {
  const HeightNoBallAssessment({
    required this.result,
    required this.confidence,
    required this.ballHeightM,
    required this.batsmanHeightM,
    required this.bounced,
    required this.waistM,
    required this.shoulderM,
  });

  final HeightNoBallResult result;
  final double confidence;
  final double ballHeightM;
  final double batsmanHeightM;
  final bool bounced;
  final double waistM;
  final double shoulderM;

  @override
  List<Object?> get props =>
      <Object?>[result, confidence, ballHeightM, batsmanHeightM, bounced, waistM, shoulderM];
}

/// Runs [UmpiringRules.classifyWide] and adds a confidence that shrinks near the limit.
WideAssessment assessWide({
  required Point3D ballAtBatsmanPlane,
  required Point3D batsmanCenter,
  required double batsmanHeightM,
  required double lateralReachMultiplier,
  required bool batsmanMovedTowardBall,
  required double wicketConfidence,
  required double trajectoryConfidence,
}) {
  final WideResult result = UmpiringRules.classifyWide(
    ballAtBatsmanPlane: ballAtBatsmanPlane,
    batsmanCenter: batsmanCenter,
    batsmanHeightM: batsmanHeightM,
    lateralReachMultiplier: lateralReachMultiplier,
    batsmanMovedTowardBall: batsmanMovedTowardBall,
    wicketConfidence: wicketConfidence,
    trajectoryConfidence: trajectoryConfidence,
  );
  final double reach = batsmanHeightM * lateralReachMultiplier;
  final double lateral = ballAtBatsmanPlane.x - batsmanCenter.x;
  final double distance = lateral.abs();
  final double base = clamp01(wicketConfidence < trajectoryConfidence
      ? wicketConfidence
      : trajectoryConfidence);

  double confidence;
  switch (result) {
    case WideResult.inconclusive:
      confidence = base * 0.5;
    case WideResult.notWide when batsmanMovedTowardBall:
      confidence = base * 0.9;
    case WideResult.wide:
    case WideResult.notWide:
      // Close to the limit is hard to call: the confidence falls to half of the base.
      final double margin =
          reach <= 0 ? 0 : clamp01((distance - reach).abs() / (reach * 0.5));
      confidence = base * (0.5 + 0.5 * margin);
  }

  return WideAssessment(
    result: result,
    confidence: clamp01(confidence),
    distanceM: distance,
    reachM: reach,
    ballLateralM: lateral,
    batsmanMovedTowardBall: batsmanMovedTowardBall,
    wicketConfidence: wicketConfidence,
    trajectoryConfidence: trajectoryConfidence,
  );
}

/// Runs [UmpiringRules.classifyHeightNoBall] and adds a confidence that shrinks near a limit.
///
/// [measurementConfidence] is how much the ball height and the batsman's height can be trusted.
/// [uncertaintyM] is how far the measured height can be off; a height closer than that to a limit
/// gives half confidence (default: a tenth of the batsman's height).
HeightNoBallAssessment assessHeightNoBall({
  required double ballHeightM,
  required double batsmanHeightM,
  required bool bounced,
  required HeightRuleConfig rules,
  required double measurementConfidence,
  double? uncertaintyM,
}) {
  final HeightNoBallResult result = UmpiringRules.classifyHeightNoBall(
    ballHeightM: ballHeightM,
    batsmanHeightM: batsmanHeightM,
    bounced: bounced,
    rules: rules,
  );
  final double waist = batsmanHeightM * rules.waistHeightRatio;
  final double shoulder = batsmanHeightM * rules.shoulderHeightRatio;

  // Distance from the nearest limit that could have changed the answer.
  final List<double> limits = <double>[
    if (!bounced && rules.fullTossAboveWaistIsNoBall) waist,
    if (bounced && rules.bouncedAboveShoulderIsNoBall) shoulder,
    if (rules.aboveHeadIsNoBall) batsmanHeightM,
  ];
  double margin = 1;
  if (limits.isNotEmpty) {
    double nearest = double.infinity;
    for (final double limit in limits) {
      final double gap = (ballHeightM - limit).abs();
      if (gap < nearest) {
        nearest = gap;
      }
    }
    final double scale = uncertaintyM != null && uncertaintyM > 0 ? uncertaintyM : batsmanHeightM * 0.10;
    margin = clamp01(nearest / scale);
  }
  final double confidence = clamp01(measurementConfidence) * (0.5 + 0.5 * margin);

  return HeightNoBallAssessment(
    result: result,
    confidence: confidence,
    ballHeightM: ballHeightM,
    batsmanHeightM: batsmanHeightM,
    bounced: bounced,
    waistM: waist,
    shoulderM: shoulder,
  );
}

String _metres(double value) => value.toStringAsFixed(1);

/// Builds [DeliveryDecision]s (with the umpire-facing sentence and the evidence for the review
/// screen) from rule results.
///
/// Statuses follow `DeliveryDecision.statusFor`: only wide and height no-ball results can be an
/// `AUTO_CALL`; edge, LBW and wicket-hit results never exceed `REVIEW_RECOMMENDED`; an
/// inconclusive result is always `INCONCLUSIVE`.
abstract final class DecisionFactory {
  /// A decision for a check that could not be made.
  static DeliveryDecision inconclusive(DeliveryDecisionType type, String reason) {
    return DeliveryDecision(
      type: type,
      automatedResult: 'INCONCLUSIVE',
      confidence: 0,
      status: DecisionStatus.inconclusive,
      evidence: <String, Object?>{'reason': reason},
      summary: '${type.label}: not sure. $reason',
    );
  }

  static DeliveryDecision wide(WideAssessment a) {
    if (a.result == WideResult.inconclusive) {
      return DeliveryDecision(
        type: DeliveryDecisionType.wide,
        automatedResult: WideResult.inconclusive.wire,
        confidence: a.confidence,
        status: DecisionStatus.inconclusive,
        evidence: _wideEvidence(a),
        summary: 'Wide: not sure. The wicket or the ball path was not clear enough.',
      );
    }
    final String summary;
    if (a.result == WideResult.wide) {
      summary = 'Wide: the ball passed ${_metres(a.distanceM)} m from the batter, '
          'who can reach ${_metres(a.reachM)} m.';
    } else if (a.batsmanMovedTowardBall) {
      summary = 'Not a wide: the batter moved towards the ball.';
    } else {
      summary = 'Not a wide: the ball was within the batter\'s reach '
          '(${_metres(a.distanceM)} m of ${_metres(a.reachM)} m).';
    }
    return DeliveryDecision(
      type: DeliveryDecisionType.wide,
      automatedResult: a.result.wire,
      confidence: a.confidence,
      status: DeliveryDecision.statusFor(DeliveryDecisionType.wide, a.confidence),
      evidence: _wideEvidence(a),
      summary: summary,
    );
  }

  static DeliveryDecision heightNoBall(HeightNoBallAssessment a) {
    final String summary = a.result == HeightNoBallResult.noBall
        ? 'No-ball: the ball was about ${_metres(a.ballHeightM)} m high '
            '(${a.bounced ? 'after a bounce' : 'a full toss'}, waist is ${_metres(a.waistM)} m).'
        : 'Legal height: about ${_metres(a.ballHeightM)} m '
            '(${a.bounced ? 'after a bounce' : 'a full toss'}).';
    return DeliveryDecision(
      type: DeliveryDecisionType.noBallHeight,
      automatedResult: a.result.wire,
      confidence: a.confidence,
      status: DeliveryDecision.statusFor(DeliveryDecisionType.noBallHeight, a.confidence),
      evidence: <String, Object?>{
        'ball_height_m': a.ballHeightM,
        'batsman_height_m': a.batsmanHeightM,
        'bounced': a.bounced,
        'waist_m': a.waistM,
        'shoulder_m': a.shoulderM,
      },
      summary: summary,
    );
  }

  static DeliveryDecision edge(EdgeAssessment a) {
    final DecisionStatus status;
    final String summary;
    switch (a.result) {
      case EdgeResult.inconclusive:
        status = DecisionStatus.inconclusive;
        summary = 'Edge: not sure. ${a.reason ?? 'Not enough clear information.'}';
      case EdgeResult.reviewRecommended:
        status = DecisionStatus.reviewRecommended;
        summary = 'Edge: mixed evidence. Please review the replay and listen to the sound.';
      case EdgeResult.edgeLikely:
        status = DeliveryDecision.statusFor(DeliveryDecisionType.edge, a.confidence);
        summary = 'Edge: the ball changed direction near the bat. Please review before you decide.';
      case EdgeResult.noEdgeEvidence:
        status = DeliveryDecision.statusFor(DeliveryDecisionType.edge, a.confidence);
        summary = 'Edge: no sign of the ball touching the bat.';
    }
    return DeliveryDecision(
      type: DeliveryDecisionType.edge,
      automatedResult: a.result.wire,
      confidence: a.confidence,
      status: status,
      evidence: <String, Object?>{
        'visual_score': a.visualScore,
        'audio_score': a.audioScore,
        'audio_available': a.audioAvailable,
        'direction_change_deg': a.directionChangeDegrees,
        'deviation': a.deviation,
        'contact_timestamp_ms': a.suspectedContactTimestampMs,
        'reason': a.reason,
      },
      summary: summary,
    );
  }

  static DeliveryDecision lbw(LbwAssessment a) {
    final DecisionStatus status;
    final String summary;
    switch (a.result) {
      case LbwResult.inconclusive:
        status = DecisionStatus.inconclusive;
        summary = 'LBW: not sure. ${a.reason ?? 'Not enough clear information.'}';
      case LbwResult.reviewRecommended:
        status = DecisionStatus.reviewRecommended;
        summary = 'LBW: too close to call from one camera. Please review.';
      case LbwResult.likelyHitting:
        status = DeliveryDecision.statusFor(DeliveryDecisionType.lbw, a.confidence);
        summary = 'LBW: the ball looks like it was going on to hit the wicket. Please review.';
      case LbwResult.likelyMissing:
        status = DeliveryDecision.statusFor(DeliveryDecisionType.lbw, a.confidence);
        summary = 'LBW: the ball looks like it was missing the wicket. Please review.';
    }
    return DeliveryDecision(
      type: DeliveryDecisionType.lbw,
      automatedResult: a.result.wire,
      confidence: a.confidence,
      status: status,
      evidence: <String, Object?>{
        'impact_in_line': a.impactInLine,
        'projected_hit_point': a.projectedHitPoint?.toJson(),
        'cone_half_angle_deg': a.coneHalfAngleDegrees,
        'rays_hitting': a.raysHitting,
        'rays_total': a.uncertaintyRays.length,
        'reason': a.reason,
      },
      summary: summary,
    );
  }

  static DeliveryDecision wicketHit(WicketHitAssessment a) {
    final DecisionStatus status;
    final String summary;
    switch (a.result) {
      case WicketHitResult.inconclusive:
        status = DecisionStatus.inconclusive;
        summary = 'Wicket hit: not sure. ${a.reason ?? 'Not enough clear information.'}';
      case WicketHitResult.likelyHit:
        status = DeliveryDecision.statusFor(DeliveryDecisionType.wicketHit, a.confidence);
        summary = 'Wicket hit: the ball looks like it reached the wicket. Please review.';
      case WicketHitResult.likelyMiss:
        status = DeliveryDecision.statusFor(DeliveryDecisionType.wicketHit, a.confidence);
        summary = 'Wicket hit: the ball looks like it missed the wicket.';
    }
    return DeliveryDecision(
      type: DeliveryDecisionType.wicketHit,
      automatedResult: a.result.wire,
      confidence: a.confidence,
      status: status,
      evidence: <String, Object?>{
        'closest_approach': a.closestApproach,
        'hit_timestamp_ms': a.hitTimestampMs,
        'reason': a.reason,
      },
      summary: summary,
    );
  }

  static Map<String, Object?> _wideEvidence(WideAssessment a) => <String, Object?>{
        'distance_m': a.distanceM,
        'reach_m': a.reachM,
        'ball_lateral_m': a.ballLateralM,
        'batsman_moved_toward_ball': a.batsmanMovedTowardBall,
        'wicket_confidence': a.wicketConfidence,
        'trajectory_confidence': a.trajectoryConfidence,
      };
}
