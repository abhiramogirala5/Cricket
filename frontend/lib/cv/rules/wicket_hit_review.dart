import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:gully_umpire/cv/geometry/line.dart';
import 'package:gully_umpire/cv/geometry/point2d.dart';
import 'package:gully_umpire/cv/geometry/polygon.dart';
import 'package:gully_umpire/cv/tracking/ball_track_point.dart';
import 'package:gully_umpire/cv/util/math_utils.dart';

/// Result of a wicket-hit check.
///
/// Like edge and LBW this is a review aid and never dismisses a batter.
enum WicketHitResult {
  likelyHit('LIKELY_HIT'),
  likelyMiss('LIKELY_MISS'),
  inconclusive('INCONCLUSIVE');

  const WicketHitResult(this.wire);

  /// Value stored as `automated_result`.
  final String wire;
}

final class WicketHitAssessment extends Equatable {
  const WicketHitAssessment({
    required this.result,
    required this.confidence,
    this.closestApproach,
    this.hitTimestampMs,
    this.reason,
  });

  /// Not enough reliable data.
  const WicketHitAssessment.inconclusive(this.reason)
      : result = WicketHitResult.inconclusive,
        confidence = 0,
        closestApproach = null,
        hitTimestampMs = null;

  final WicketHitResult result;

  /// Belief (0..1) that [result] is right. Never above [wicketHitMaxConfidence].
  final double confidence;

  /// Smallest distance (normalised) between a tracked ball point and the wicket target.
  final double? closestApproach;

  /// Time of the first tracked point or path segment that touches the target.
  final int? hitTimestampMs;

  final String? reason;

  @override
  List<Object?> get props => <Object?>[result, confidence, closestApproach, hitTimestampMs, reason];
}

/// Confidence cap for wicket-hit assistance (single camera, depth ambiguity).
const double wicketHitMaxConfidence = 0.8;

/// A tracked point that comes within this distance of the target counts as touching it
/// (about the radius of the ball in the image).
const double wicketHitBallRadius = 0.006;

/// A path that stays at least this far from the target is a clear miss; anything between a hit
/// and this distance is too close to call.
const double wicketHitClearMiss = 0.03;

/// Did the tracked ball reach the wicket target?
///
/// Only [track] points at or after [fromTimestampMs] (the moment the ball reached the batsman)
/// are considered, together with the straight segments between them. The target polygon is
/// grown by the ball's radius. The wicket must have been found with confidence of at least 0.7.
WicketHitAssessment assessWicketHit({
  required List<BallTrackPoint> track,
  required int fromTimestampMs,
  required Polygon wicketTarget,
  required double wicketConfidence,
  required double trackingConfidence,
}) {
  if (!wicketTarget.isValid) {
    return const WicketHitAssessment.inconclusive('The wicket is not visible.');
  }
  if (wicketConfidence < 0.7) {
    return const WicketHitAssessment.inconclusive(
      'The wicket was not found with enough confidence.',
    );
  }
  if (trackingConfidence < 0.6) {
    return const WicketHitAssessment.inconclusive('The ball track is not reliable enough.');
  }
  final List<BallTrackPoint> points = track
      .where((BallTrackPoint p) => p.timestampMs >= fromTimestampMs)
      .toList();
  if (points.length < 2) {
    return const WicketHitAssessment.inconclusive('The ball was not tracked up to the wicket.');
  }

  final Polygon grown = wicketTarget.inflated(wicketHitBallRadius);
  double closest = double.infinity;
  int? hitMs;
  for (int i = 0; i < points.length; i++) {
    final Point2D position = points[i].position;
    closest = math.min(closest, wicketTarget.distanceToPoint(position));
    if (hitMs == null && grown.containsPoint(position)) {
      hitMs = points[i].timestampMs;
    }
    if (hitMs == null && i + 1 < points.length) {
      final LineSegment step = LineSegment(position, points[i + 1].position);
      for (final LineSegment edge in grown.edges) {
        if (step.intersection(edge) != null) {
          hitMs = points[i + 1].timestampMs;
          break;
        }
      }
    }
  }

  final double base = math.min(wicketConfidence, trackingConfidence);
  if (hitMs != null) {
    return WicketHitAssessment(
      result: WicketHitResult.likelyHit,
      confidence: clampDouble(base * 0.9, 0, wicketHitMaxConfidence),
      closestApproach: closest,
      hitTimestampMs: hitMs,
    );
  }
  if (closest >= wicketHitClearMiss) {
    final double clearance = scoreRising(closest, low: wicketHitClearMiss, high: 0.10);
    return WicketHitAssessment(
      result: WicketHitResult.likelyMiss,
      confidence: clampDouble(base * (0.6 + 0.3 * clearance), 0, wicketHitMaxConfidence),
      closestApproach: closest,
    );
  }
  return WicketHitAssessment(
    result: WicketHitResult.inconclusive,
    confidence: clampDouble(base * 0.4, 0, wicketHitMaxConfidence),
    closestApproach: closest,
    reason: 'The ball passed too close to the wicket to call.',
  );
}
