import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:gully_umpire/cv/geometry/bounding_box.dart';
import 'package:gully_umpire/cv/geometry/line.dart';
import 'package:gully_umpire/cv/geometry/point2d.dart';
import 'package:gully_umpire/cv/geometry/polygon.dart';
import 'package:gully_umpire/cv/tracking/ball_track_point.dart';
import 'package:gully_umpire/cv/util/math_utils.dart';

/// Result of an LBW check (spec §9 `LbwAssessment`).
///
/// LBW is a review aid. A single camera cannot reconstruct the ball in 3D, so the result is
/// always "likely", never certain, and the umpire makes the call.
enum LbwResult {
  likelyHitting('LIKELY_HITTING'),
  likelyMissing('LIKELY_MISSING'),
  reviewRecommended('REVIEW_RECOMMENDED'),
  inconclusive('INCONCLUSIVE');

  const LbwResult(this.wire);

  /// Value stored as `automated_result`.
  final String wire;
}

final class LbwAssessment extends Equatable {
  const LbwAssessment({
    required this.result,
    required this.confidence,
    this.impactInLine,
    this.projectedHitPoint,
    this.coneHalfAngleDegrees = 0,
    this.uncertaintyRays = const <Ray2D>[],
    this.raysHitting = 0,
    this.reason,
  });

  /// Not enough reliable data.
  const LbwAssessment.inconclusive(this.reason)
      : result = LbwResult.inconclusive,
        confidence = 0,
        impactInLine = null,
        projectedHitPoint = null,
        coneHalfAngleDegrees = 0,
        uncertaintyRays = const <Ray2D>[],
        raysHitting = 0;

  final LbwResult result;

  /// Belief (0..1) that [result] is right. Never above [lbwMaxConfidence].
  final double confidence;

  /// Whether the point of impact is in line with the wicket sideways.
  final bool? impactInLine;

  /// Where the central projected path first touches the wicket target (image space).
  final Point2D? projectedHitPoint;

  /// Half-angle of the uncertainty cone.
  final double coneHalfAngleDegrees;

  /// Central ray plus the edges of the cone (3-5 rays), for the overlay.
  final List<Ray2D> uncertaintyRays;

  /// How many of [uncertaintyRays] reach the wicket target.
  final int raysHitting;

  final String? reason;

  @override
  List<Object?> get props => <Object?>[
        result,
        confidence,
        impactInLine,
        projectedHitPoint,
        coneHalfAngleDegrees,
        uncertaintyRays,
        raysHitting,
        reason,
      ];
}

/// An LBW confidence is capped here: single-camera projection is never certain.
const double lbwMaxConfidence = 0.75;

/// Spec §11: LBW uses the current delivery only, over a short window.
const int lbwMinPoints = 5;
const int lbwMaxPoints = 12;

/// Extrapolates the ball's path from the point of impact to the wicket target.
///
/// [preImpact] are the ball points after the bounce and up to the impact (oldest first); only the
/// last [lbwMaxPoints] are fitted with a straight line. The line is extended from the impact
/// point and tested against [wicketTarget]; a cone of 5 rays (central plus +-half and +-full
/// angle) shows how far the answer could move because of fit noise.
///
/// * All rays reach the target: [LbwResult.likelyHitting].
/// * No ray reaches it: [LbwResult.likelyMissing].
/// * Some do: [LbwResult.reviewRecommended].
/// * A poor track, a doubtful wicket, or a ball that already overlaps the wicket in the image
///   (depth is ambiguous): [LbwResult.inconclusive].
LbwAssessment assessLbw({
  required List<BallTrackPoint> preImpact,
  required Polygon wicketTarget,
  required double wicketConfidence,
  required double trackingConfidence,
  double maxProjectionDistance = 1.0,
}) {
  if (!wicketTarget.isValid) {
    return const LbwAssessment.inconclusive('The wicket is not visible.');
  }
  if (wicketConfidence < 0.7) {
    return const LbwAssessment.inconclusive('The wicket was not found with enough confidence.');
  }
  if (trackingConfidence < 0.6) {
    return const LbwAssessment.inconclusive('The ball track is not reliable enough.');
  }
  if (preImpact.length < lbwMinPoints) {
    return const LbwAssessment.inconclusive('Too few ball points before the impact.');
  }

  final List<BallTrackPoint> window =
      preImpact.sublist(math.max(0, preImpact.length - lbwMaxPoints));
  final LineFit2D? fit = fitLineOverTime(
    window.map<int>((BallTrackPoint p) => p.timestampMs).toList(),
    window.map<Point2D>((BallTrackPoint p) => p.position).toList(),
  );
  if (fit == null) {
    return const LbwAssessment.inconclusive('The ball path could not be fitted.');
  }
  if (fit.residual > 0.02) {
    return const LbwAssessment.inconclusive('The ball path is too uneven to project.');
  }
  final double speed = fit.velocity.length;
  if (speed < 0.05) {
    return const LbwAssessment.inconclusive('The ball was almost stationary.');
  }

  final Point2D impact = window.last.position;
  if (wicketTarget.containsPoint(impact)) {
    return const LbwAssessment.inconclusive(
      'The ball overlaps the wicket in the image, so its depth cannot be judged.',
    );
  }

  // Angular uncertainty from the fit noise over the distance the window covers.
  final double span = math.max(window.first.position.distanceTo(impact), 0.05);
  final double halfAngle = clampDouble(
    math.atan2(fit.residual * 2, span),
    degToRad(3),
    degToRad(20),
  );

  final Point2D direction = fit.velocity.normalized();
  final Ray2D centre = Ray2D(impact, direction);
  final List<Ray2D> rays = <Ray2D>[
    centre.rotated(-halfAngle),
    centre.rotated(-halfAngle / 2),
    centre,
    centre.rotated(halfAngle / 2),
    centre.rotated(halfAngle),
  ];

  int hitting = 0;
  for (final Ray2D ray in rays) {
    if (wicketTarget.firstRayHit(ray, maxT: maxProjectionDistance) != null) {
      hitting += 1;
    }
  }
  final double? centreT = wicketTarget.firstRayHit(centre, maxT: maxProjectionDistance);
  final Point2D? hitPoint = centreT == null ? null : centre.pointAt(centreT);

  final BoundingBox bounds = wicketTarget.bounds;
  final double margin = bounds.width * 0.25;
  final bool inLine = impact.x >= bounds.left - margin && impact.x <= bounds.right + margin;

  final double base = math.min(wicketConfidence, trackingConfidence);
  final double conePenalty = clamp01(radToDeg(halfAngle) / 20) * 0.3;

  LbwResult result;
  double confidence;
  if (hitting == rays.length) {
    result = LbwResult.likelyHitting;
    confidence = base * (1 - conePenalty);
  } else if (hitting == 0) {
    result = LbwResult.likelyMissing;
    confidence = base * (1 - conePenalty);
  } else {
    result = LbwResult.reviewRecommended;
    confidence = base * (1 - conePenalty) * 0.8;
  }

  return LbwAssessment(
    result: result,
    confidence: clampDouble(confidence, 0, lbwMaxConfidence),
    impactInLine: inLine,
    projectedHitPoint: hitPoint,
    coneHalfAngleDegrees: radToDeg(halfAngle),
    uncertaintyRays: rays,
    raysHitting: hitting,
  );
}
