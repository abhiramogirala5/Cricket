import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/cv/geometry/bounding_box.dart';
import 'package:gully_umpire/cv/geometry/point2d.dart';
import 'package:gully_umpire/cv/geometry/polygon.dart';
import 'package:gully_umpire/cv/rules/wicket_hit_review.dart';
import 'package:gully_umpire/cv/tracking/ball_track_point.dart';

final Polygon wicket = Polygon.fromBox(BoundingBox.fromLTRB(0.477, 0.42, 0.523, 0.56));

BallTrackPoint point(int ms, double x, double y) =>
    BallTrackPoint(timestampMs: ms, x: x, y: y, confidence: 0.9);

WicketHitAssessment assess(
  List<BallTrackPoint> track, {
  int from = 900,
  Polygon? target,
  double wicketConfidence = 0.9,
  double trackingConfidence = 0.9,
}) {
  return assessWicketHit(
    track: track,
    fromTimestampMs: from,
    wicketTarget: target ?? wicket,
    wicketConfidence: wicketConfidence,
    trackingConfidence: trackingConfidence,
  );
}

void main() {
  group('assessWicketHit', () {
    test('a ball that enters the wicket is a likely hit (confidence capped)', () {
      final WicketHitAssessment result = assess(<BallTrackPoint>[
        point(900, 0.50, 0.60),
        point(950, 0.50, 0.50),
        point(1000, 0.50, 0.44),
      ]);
      expect(result.result, WicketHitResult.likelyHit);
      expect(result.hitTimestampMs, 950);
      expect(result.confidence, wicketHitMaxConfidence);
    });

    test('a ball that passes well to the side is a likely miss', () {
      final WicketHitAssessment result = assess(<BallTrackPoint>[
        point(900, 0.56, 0.55),
        point(950, 0.56, 0.50),
        point(1000, 0.56, 0.45),
      ]);
      expect(result.result, WicketHitResult.likelyMiss);
      expect(result.closestApproach, closeTo(0.037, 1e-9));
      // 0.9 * (0.6 + 0.3 * rising(0.037, 0.03, 0.10))
      expect(result.confidence, closeTo(0.9 * (0.6 + 0.3 * (0.007 / 0.07)), 1e-9));
    });

    test('a ball that passes very close is too close to call', () {
      final WicketHitAssessment result = assess(<BallTrackPoint>[
        point(900, 0.545, 0.55),
        point(950, 0.545, 0.50),
        point(1000, 0.545, 0.45),
      ]);
      expect(result.result, WicketHitResult.inconclusive);
      expect(result.reason, isNotNull);
      expect(result.confidence, closeTo(0.9 * 0.4, 1e-9));
    });

    test('points before the ball reached the batter are ignored', () {
      final WicketHitAssessment result = assess(
        <BallTrackPoint>[
          point(700, 0.50, 0.50),
          point(750, 0.50, 0.50),
          point(900, 0.56, 0.55),
          point(950, 0.56, 0.50),
        ],
      );
      expect(result.result, WicketHitResult.likelyMiss);
    });

    test('refuses to guess with too little information', () {
      expect(assess(<BallTrackPoint>[point(900, 0.5, 0.5)]).result, WicketHitResult.inconclusive);
      expect(
        assess(<BallTrackPoint>[point(900, 0.5, 0.6), point(950, 0.5, 0.5)], wicketConfidence: 0.6)
            .result,
        WicketHitResult.inconclusive,
      );
      expect(
        assess(<BallTrackPoint>[point(900, 0.5, 0.6), point(950, 0.5, 0.5)], trackingConfidence: 0.5)
            .result,
        WicketHitResult.inconclusive,
      );
      expect(
        assess(
          <BallTrackPoint>[point(900, 0.5, 0.6), point(950, 0.5, 0.5)],
          target: Polygon(const <Point2D>[]),
        ).result,
        WicketHitResult.inconclusive,
      );
    });

    test('wire values', () {
      expect(WicketHitResult.likelyHit.wire, 'LIKELY_HIT');
      expect(WicketHitResult.likelyMiss.wire, 'LIKELY_MISS');
      expect(WicketHitResult.inconclusive.wire, 'INCONCLUSIVE');
    });
  });
}
