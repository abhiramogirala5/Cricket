import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/cv/geometry/bounding_box.dart';
import 'package:gully_umpire/cv/geometry/point2d.dart';
import 'package:gully_umpire/cv/geometry/polygon.dart';
import 'package:gully_umpire/cv/rules/lbw_review.dart';
import 'package:gully_umpire/cv/tracking/ball_track_point.dart';

final Polygon stumps = Polygon.fromBox(BoundingBox.fromLTRB(0.477, 0.42, 0.523, 0.56));

/// A ball moving straight up the image at a constant speed (0.5 units per second)
/// at image x [x], from [startY] at the first timestamp.
List<BallTrackPoint> straightPath(
  double x, {
  int fromMs = 0,
  int toMs = 300,
  int stepMs = 50,
  double startY = 0.75,
  double speed = 0.5,
}) {
  final List<BallTrackPoint> points = <BallTrackPoint>[];
  for (int ms = fromMs; ms <= toMs; ms += stepMs) {
    points.add(
      BallTrackPoint(
        timestampMs: ms,
        x: x,
        y: startY - speed * (ms - fromMs) / 1000.0,
        confidence: 0.9,
      ),
    );
  }
  return points;
}

LbwAssessment assess(
  List<BallTrackPoint> points, {
  Polygon? target,
  double wicketConfidence = 0.9,
  double trackingConfidence = 0.9,
}) {
  return assessLbw(
    preImpact: points,
    wicketTarget: target ?? stumps,
    wicketConfidence: wicketConfidence,
    trackingConfidence: trackingConfidence,
  );
}

void main() {
  group('assessLbw', () {
    test('a ball heading straight at the stumps is likely hitting, and capped', () {
      final LbwAssessment result = assess(straightPath(0.5));
      expect(result.result, LbwResult.likelyHitting);
      expect(result.raysHitting, 5);
      expect(result.uncertaintyRays, hasLength(5));
      expect(result.impactInLine, isTrue);
      expect(result.coneHalfAngleDegrees, closeTo(3, 1e-6));
      // 0.9 * (1 - 0.045) = 0.8595 is above the cap.
      expect(result.confidence, lbwMaxConfidence);
      final Point2D? hit = result.projectedHitPoint;
      expect(hit, isNotNull);
      expect(hit!.x, closeTo(0.5, 1e-6));
      expect(hit.y, closeTo(0.56, 1e-6));
    });

    test('a ball heading well outside the stumps is likely missing', () {
      final LbwAssessment result = assess(straightPath(0.6));
      expect(result.result, LbwResult.likelyMissing);
      expect(result.raysHitting, 0);
      expect(result.impactInLine, isFalse);
      expect(result.projectedHitPoint, isNull);
      expect(result.confidence, lbwMaxConfidence);
    });

    test('confidence follows the weaker of wicket and tracking confidence', () {
      final LbwAssessment result = assess(
        straightPath(0.6),
        wicketConfidence: 0.8,
        trackingConfidence: 0.65,
      );
      expect(result.result, LbwResult.likelyMissing);
      // 0.65 * (1 - 0.045)
      expect(result.confidence, closeTo(0.65 * 0.955, 1e-9));
    });

    test('a ball that only just misses on one side recommends a review', () {
      final LbwAssessment close = assess(straightPath(0.5245));
      expect(close.result, LbwResult.reviewRecommended);
      expect(close.raysHitting, 2);
      expect(close.projectedHitPoint, isNull);
      // 0.9 * 0.955 * 0.8
      expect(close.confidence, closeTo(0.6876, 1e-9));

      final LbwAssessment edgeOfCone = assess(straightPath(0.53));
      expect(edgeOfCone.result, LbwResult.reviewRecommended);
      expect(edgeOfCone.raysHitting, 1);
      expect(edgeOfCone.confidence, closeTo(0.6876, 1e-9));
    });

    test('only the last twelve points are fitted', () {
      // A long straight path still gives the same answer.
      final LbwAssessment result = assess(straightPath(0.5, toMs: 600, startY: 0.9, speed: 0.4));
      expect(result.result, LbwResult.likelyHitting);
      expect(result.uncertaintyRays, hasLength(5));
    });

    group('is inconclusive when', () {
      test('there are too few points', () {
        final LbwAssessment result = assess(straightPath(0.5, toMs: 150));
        expect(result.result, LbwResult.inconclusive);
        expect(result.confidence, 0);
        expect(result.reason, isNotNull);
      });

      test('the wicket is not confident enough', () {
        expect(assess(straightPath(0.5), wicketConfidence: 0.69).result, LbwResult.inconclusive);
        expect(assess(straightPath(0.5), wicketConfidence: 0.7).result, LbwResult.likelyHitting);
      });

      test('the track is not reliable enough', () {
        expect(assess(straightPath(0.5), trackingConfidence: 0.59).result, LbwResult.inconclusive);
        expect(assess(straightPath(0.5), trackingConfidence: 0.6).result, LbwResult.likelyHitting);
      });

      test('the wicket polygon is empty', () {
        final LbwAssessment result = assess(straightPath(0.5), target: Polygon(const <Point2D>[]));
        expect(result.result, LbwResult.inconclusive);
      });

      test('the impact point is already inside the wicket in the image', () {
        // Ends at y = 0.50, which is inside the stumps box.
        final LbwAssessment result = assess(straightPath(0.5, startY: 0.65));
        expect(result.result, LbwResult.inconclusive);
        expect(result.reason, contains('depth'));
      });

      test('the ball is almost stationary', () {
        expect(assess(straightPath(0.5, startY: 0.6, speed: 0)).result, LbwResult.inconclusive);
        expect(assess(straightPath(0.5, startY: 0.6, speed: 0.02)).result, LbwResult.inconclusive);
      });

      test('the path zig-zags too much to project', () {
        final List<BallTrackPoint> zigzag = <BallTrackPoint>[
          for (int i = 0; i < 6; i++)
            BallTrackPoint(
              timestampMs: i * 50,
              x: i.isEven ? 0.5 : 0.6,
              y: 0.75 - 0.025 * i,
              confidence: 0.9,
            ),
        ];
        expect(assess(zigzag).result, LbwResult.inconclusive);
      });
    });

    test('wire values match the API', () {
      expect(LbwResult.likelyHitting.wire, 'LIKELY_HITTING');
      expect(LbwResult.likelyMissing.wire, 'LIKELY_MISSING');
      expect(LbwResult.reviewRecommended.wire, 'REVIEW_RECOMMENDED');
      expect(LbwResult.inconclusive.wire, 'INCONCLUSIVE');
    });
  });
}
