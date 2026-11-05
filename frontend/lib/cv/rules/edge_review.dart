import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:gully_umpire/cv/contracts/audio_impulse.dart';
import 'package:gully_umpire/cv/geometry/line.dart';
import 'package:gully_umpire/cv/geometry/point2d.dart';
import 'package:gully_umpire/cv/geometry/polygon.dart';
import 'package:gully_umpire/cv/tracking/ball_track_point.dart';
import 'package:gully_umpire/cv/util/math_utils.dart';

/// Result of an edge check (spec §9 `EdgeAssessment`).
///
/// Edge is a review aid. None of these results dismisses a batter; the umpire always decides.
enum EdgeResult {
  edgeLikely('EDGE_LIKELY'),
  noEdgeEvidence('NO_EDGE_EVIDENCE'),
  reviewRecommended('REVIEW_RECOMMENDED'),
  inconclusive('INCONCLUSIVE');

  const EdgeResult(this.wire);

  /// Value stored as `automated_result`.
  final String wire;
}

final class EdgeAssessment extends Equatable {
  const EdgeAssessment({
    required this.result,
    required this.confidence,
    required this.visualScore,
    required this.audioScore,
    required this.audioAvailable,
    this.suspectedContactTimestampMs,
    this.directionChangeDegrees = 0,
    this.deviation = 0,
    this.reason,
  });

  /// Not enough reliable data.
  const EdgeAssessment.inconclusive(this.reason)
      : result = EdgeResult.inconclusive,
        confidence = 0,
        visualScore = 0,
        audioScore = 0,
        audioAvailable = false,
        suspectedContactTimestampMs = null,
        directionChangeDegrees = 0,
        deviation = 0;

  final EdgeResult result;

  /// Belief (0..1) that [result] is right.
  final double confidence;

  /// 0..1 from path deviation, direction change and bat proximity.
  final double visualScore;

  /// 0..1 from a synchronised sharp sound, 0 when no audio analyser was available.
  final double audioScore;

  final bool audioAvailable;

  final int? suspectedContactTimestampMs;

  /// Angle between the ball's direction before and after the suspected contact.
  final double directionChangeDegrees;

  /// Mean distance (normalised) of the post-contact points from the pre-contact line.
  final double deviation;

  final String? reason;

  @override
  List<Object?> get props => <Object?>[
        result,
        confidence,
        visualScore,
        audioScore,
        audioAvailable,
        suspectedContactTimestampMs,
        directionChangeDegrees,
        deviation,
        reason,
      ];
}

/// Window sizes of spec §11 "Edge structures": 6-12 points before contact, 3-8 after.
const int edgeMinBefore = 6;
const int edgeMaxBefore = 12;
const int edgeMinAfter = 3;
const int edgeMaxAfter = 8;

/// A sound within this many milliseconds of the suspected contact counts as simultaneous.
const int edgeAudioWindowMs = 40;

/// Deterministic evidence fusion for a possible edge:
///
/// ```text
/// visual  = path deviation + direction change (+ bat proximity when a bat zone is known)
/// audio   = a bright, loud impulse within 40 ms of the suspected contact
/// result  = fusion, minus a penalty for tracking uncertainty
/// ```
///
/// [before] and [after] are the ball points before and after the suspected contact, oldest
/// first; only the last [edgeMaxBefore] and first [edgeMaxAfter] are used. Pass [impulses] as
/// `null` when no audio analyser is available (audio is then ignored, never assumed silent).
EdgeAssessment assessEdge({
  required List<BallTrackPoint> before,
  required List<BallTrackPoint> after,
  required int contactTimestampMs,
  required double trackingConfidence,
  Polygon? batZone,
  List<AudioImpulse>? impulses,
}) {
  if (before.length < edgeMinBefore || after.length < edgeMinAfter) {
    return const EdgeAssessment.inconclusive('Too few ball points around the contact.');
  }
  if (trackingConfidence < 0.5) {
    return const EdgeAssessment.inconclusive('The ball track is not reliable enough.');
  }

  final List<BallTrackPoint> pre =
      before.sublist(math.max(0, before.length - edgeMaxBefore));
  final List<BallTrackPoint> post = after.sublist(0, math.min(after.length, edgeMaxAfter));

  final LineFit2D? preFit = fitLineOverTime(
    pre.map<int>((BallTrackPoint p) => p.timestampMs).toList(),
    pre.map<Point2D>((BallTrackPoint p) => p.position).toList(),
  );
  final LineFit2D? postFit = fitLineOverTime(
    post.map<int>((BallTrackPoint p) => p.timestampMs).toList(),
    post.map<Point2D>((BallTrackPoint p) => p.position).toList(),
  );
  if (preFit == null || postFit == null) {
    return const EdgeAssessment.inconclusive('The ball path could not be fitted.');
  }

  // 1. Where the ball ended up compared with where the earlier path predicted it.
  double deviationSum = 0;
  for (final BallTrackPoint point in post) {
    deviationSum += point.position.distanceTo(preFit.positionAt(point.timestampMs));
  }
  final double deviation = deviationSum / post.length;
  final double deviationScore = scoreRising(deviation, low: 0.01, high: 0.05);

  // 2. How much the direction of travel changed.
  final double angle = _angleBetweenDegrees(preFit.velocity, postFit.velocity);
  final double directionScore = scoreRising(angle, low: 8, high: 35);

  // 3. Whether the ball was near the bat.
  double? proximityScore;
  if (batZone != null && batZone.isValid) {
    double nearest = double.infinity;
    final int from = math.max(0, pre.length - 3);
    for (int i = from; i < pre.length; i++) {
      nearest = math.min(nearest, batZone.distanceToPoint(pre[i].position));
    }
    nearest = math.min(nearest, batZone.distanceToPoint(post.first.position));
    proximityScore = scoreFalling(nearest, good: 0.01, bad: 0.08);
  }

  final double visual = proximityScore == null
      ? deviationScore * 0.5 + directionScore * 0.5
      : deviationScore * 0.35 + directionScore * 0.35 + proximityScore * 0.30;

  // 4. A sharp, bright sound at the same moment.
  final bool audioAvailable = impulses != null;
  double audio = 0;
  if (impulses != null) {
    for (final AudioImpulse impulse in impulses) {
      if ((impulse.timestampMs - contactTimestampMs).abs() > edgeAudioWindowMs) {
        continue;
      }
      final double score = clamp01(impulse.impulseConfidence) *
          scoreRising(impulse.spectralCentroid, low: 1500, high: 3500) *
          scoreRising(impulse.peakAmplitude, low: 0.1, high: 0.4);
      audio = math.max(audio, score);
    }
  }

  final double penalty = (1 - clamp01(trackingConfidence)) * 0.25;
  final double fused = audioAvailable ? visual * 0.65 + audio * 0.35 : visual;
  final double confidence = clamp01(fused - penalty);

  EdgeResult result;
  double reported;
  if (confidence >= 0.7 && visual >= 0.5 && (!audioAvailable || audio >= 0.3)) {
    result = EdgeResult.edgeLikely;
    reported = confidence;
  } else if (confidence >= 0.35) {
    result = EdgeResult.reviewRecommended;
    reported = confidence;
  } else {
    result = EdgeResult.noEdgeEvidence;
    // Absence of evidence is weaker than evidence: never report more than 0.8.
    reported = math.min(0.8, (1 - confidence) * clamp01(trackingConfidence));
  }

  return EdgeAssessment(
    result: result,
    confidence: reported,
    visualScore: visual,
    audioScore: audio,
    audioAvailable: audioAvailable,
    suspectedContactTimestampMs: contactTimestampMs,
    directionChangeDegrees: angle,
    deviation: deviation,
  );
}

/// Angle in degrees (0..180) between two velocity vectors; 0 when either is almost zero.
double _angleBetweenDegrees(Point2D a, Point2D b) {
  final double la = a.length;
  final double lb = b.length;
  if (la < 1e-6 || lb < 1e-6) {
    return 0;
  }
  final double cosine = clampDouble(a.dot(b) / (la * lb), -1, 1);
  return radToDeg(math.acos(cosine));
}
