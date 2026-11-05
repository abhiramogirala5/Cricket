import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/cv/contracts/audio_impulse.dart';
import 'package:gully_umpire/cv/rules/edge_review.dart';
import 'package:gully_umpire/cv/tracking/ball_track_point.dart';

BallTrackPoint point(int ms, double x, double y) =>
    BallTrackPoint(timestampMs: ms, x: x, y: y, confidence: 0.9);

/// Eight points moving straight up the image (0.5 units per second), 0..350 ms.
final List<BallTrackPoint> approach = <BallTrackPoint>[
  for (int ms = 0; ms <= 350; ms += 50) point(ms, 0.5, 0.75 - 0.5 * ms / 1000),
];

/// The ball leaves sideways at 1.5 units per second: a 90 degree change of direction.
final List<BallTrackPoint> deflected = <BallTrackPoint>[
  for (final int ms in <int>[400, 450, 500, 550]) point(ms, 0.5 + 1.5 * (ms - 400) / 1000, 0.55),
];

/// The ball carries on in the same direction.
final List<BallTrackPoint> carriedOn = <BallTrackPoint>[
  for (final int ms in <int>[400, 450, 500, 550]) point(ms, 0.5, 0.75 - 0.5 * ms / 1000),
];

const int contactMs = 375;

AudioImpulse impulse({
  int timestampMs = contactMs,
  double confidence = 0.9,
  double centroid = 3200,
  double peak = 0.6,
}) {
  return AudioImpulse(
    timestampMs: timestampMs,
    impulseConfidence: confidence,
    spectralCentroid: centroid,
    peakAmplitude: peak,
  );
}

EdgeAssessment assess(
  List<BallTrackPoint> before,
  List<BallTrackPoint> after, {
  double trackingConfidence = 0.9,
  List<AudioImpulse>? impulses,
}) {
  return assessEdge(
    before: before,
    after: after,
    contactTimestampMs: contactMs,
    trackingConfidence: trackingConfidence,
    impulses: impulses,
  );
}

void main() {
  group('assessEdge', () {
    test('a sharp change of direction without audio is a likely edge', () {
      final EdgeAssessment result = assess(approach, deflected);
      expect(result.result, EdgeResult.edgeLikely);
      expect(result.audioAvailable, isFalse);
      expect(result.audioScore, 0);
      expect(result.visualScore, closeTo(1.0, 1e-9));
      expect(result.directionChangeDegrees, closeTo(90, 1e-6));
      expect(result.suspectedContactTimestampMs, contactMs);
      // 1.0 - (1 - 0.9) * 0.25
      expect(result.confidence, closeTo(0.975, 1e-9));
    });

    test('a synchronised bright click is added to the evidence', () {
      final EdgeAssessment result = assess(
        approach,
        deflected,
        impulses: <AudioImpulse>[impulse()],
      );
      expect(result.result, EdgeResult.edgeLikely);
      expect(result.audioAvailable, isTrue);
      // 0.9 * rising(3200, 1500, 3500) * rising(0.6, 0.1, 0.4) = 0.9 * 0.85 * 1
      expect(result.audioScore, closeTo(0.765, 1e-9));
      // (1.0 * 0.65 + 0.765 * 0.35) - 0.025
      expect(result.confidence, closeTo(0.89275, 1e-9));
    });

    test('an analyser that heard nothing weakens the result to a review', () {
      final EdgeAssessment result = assess(approach, deflected, impulses: const <AudioImpulse>[]);
      expect(result.result, EdgeResult.reviewRecommended);
      expect(result.audioAvailable, isTrue);
      expect(result.audioScore, 0);
      // 1.0 * 0.65 - 0.025
      expect(result.confidence, closeTo(0.625, 1e-9));
    });

    test('a sound far from the contact does not count', () {
      final EdgeAssessment result = assess(
        approach,
        deflected,
        impulses: <AudioImpulse>[impulse(timestampMs: contactMs + 125)],
      );
      expect(result.audioScore, 0);
      expect(result.result, EdgeResult.reviewRecommended);
    });

    test('a dull thud does not count as a click', () {
      final EdgeAssessment result = assess(
        approach,
        deflected,
        impulses: <AudioImpulse>[impulse(centroid: 1000)],
      );
      expect(result.audioScore, 0);
      expect(result.result, EdgeResult.reviewRecommended);
    });

    test('a ball that carries on straight shows no edge evidence, reported at most 0.8', () {
      final EdgeAssessment result = assess(approach, carriedOn);
      expect(result.result, EdgeResult.noEdgeEvidence);
      expect(result.visualScore, closeTo(0, 1e-6));
      expect(result.directionChangeDegrees, closeTo(0, 1e-6));
      expect(result.confidence, 0.8);
    });

    test('a gentle drift is not enough', () {
      final List<BallTrackPoint> drift = <BallTrackPoint>[
        for (final int ms in <int>[400, 450, 500, 550])
          point(ms, 0.5 + 0.2 * (ms - 400) / 1000, 0.55 - 0.5 * (ms - 400) / 1000),
      ];
      final EdgeAssessment result = assess(approach, drift);
      expect(result.result, EdgeResult.noEdgeEvidence);
      expect(result.visualScore, closeTo(0.31808, 1e-4));
      expect(result.confidence, closeTo(0.63623, 1e-4));
    });

    test('a clear change of direction with a click is a likely edge', () {
      final List<BallTrackPoint> turned = <BallTrackPoint>[
        for (final int ms in <int>[400, 450, 500, 550])
          point(ms, 0.5 + 0.6 * (ms - 400) / 1000, 0.55 - 0.5 * (ms - 400) / 1000),
      ];
      final EdgeAssessment without = assess(approach, turned);
      expect(without.result, EdgeResult.edgeLikely);
      expect(without.confidence, closeTo(0.9125, 1e-9));
      final EdgeAssessment withClick = assess(approach, turned, impulses: <AudioImpulse>[impulse()]);
      expect(withClick.result, EdgeResult.edgeLikely);
      expect(withClick.confidence, closeTo(0.852125, 1e-9));
    });

    group('is inconclusive when', () {
      test('there are too few points before the contact', () {
        final EdgeAssessment result = assess(approach.sublist(0, 5), deflected);
        expect(result.result, EdgeResult.inconclusive);
        expect(result.confidence, 0);
        expect(result.reason, isNotNull);
      });

      test('there are too few points after the contact', () {
        expect(assess(approach, deflected.sublist(0, 2)).result, EdgeResult.inconclusive);
      });

      test('the tracking confidence is below 0.5', () {
        expect(assess(approach, deflected, trackingConfidence: 0.49).result, EdgeResult.inconclusive);
        expect(assess(approach, deflected, trackingConfidence: 0.5).result, isNot(EdgeResult.inconclusive));
      });
    });

    test('wire values match the API', () {
      expect(EdgeResult.edgeLikely.wire, 'EDGE_LIKELY');
      expect(EdgeResult.noEdgeEvidence.wire, 'NO_EDGE_EVIDENCE');
      expect(EdgeResult.reviewRecommended.wire, 'REVIEW_RECOMMENDED');
      expect(EdgeResult.inconclusive.wire, 'INCONCLUSIVE');
    });
  });
}
