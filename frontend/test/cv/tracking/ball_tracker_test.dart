import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/cv/geometry/point2d.dart';
import 'package:gully_umpire/cv/tracking/ball_track_point.dart';
import 'package:gully_umpire/cv/tracking/ball_tracker.dart';

/// Feeds a ball that moves right at 0.5 units per second, one point every 40 ms.
BallTracker steadyTracker({int points = 11}) {
  final BallTracker tracker = BallTracker();
  for (int i = 0; i < points; i++) {
    tracker.update(timestampMs: i * 40, x: 0.1 + 0.5 * i * 0.04, y: 0.2, confidence: 1.0);
  }
  return tracker;
}

void main() {
  group('BallTracker', () {
    test('starts a track and then accepts points on a straight line', () {
      final BallTracker tracker = BallTracker();
      final List<BallTrackStatus> statuses = <BallTrackStatus>[
        for (int i = 0; i < 11; i++)
          tracker.update(timestampMs: i * 40, x: 0.1 + 0.5 * i * 0.04, y: 0.2, confidence: 1.0),
      ];
      expect(statuses.first, BallTrackStatus.started);
      expect(statuses.skip(1), everyElement(BallTrackStatus.accepted));
      expect(tracker.acceptedCount, 11);
      expect(tracker.segmentCount, 1);
      expect(tracker.hasTrack, isTrue);
      expect(tracker.velocity!.x, closeTo(0.5, 0.01));
      expect(tracker.velocity!.y, closeTo(0, 0.01));
      expect(tracker.points.length, 11);
      expect(tracker.latestPoint!.timestampMs, 400);
    });

    test('predicts the next position by constant velocity', () {
      final BallTracker tracker = steadyTracker();
      final Point2D? predicted = tracker.predictedPosition(440);
      expect(predicted, isNotNull);
      expect(predicted!.x, closeTo(0.32, 0.001));
      expect(predicted.y, closeTo(0.2, 0.001));
      expect(tracker.predictedPosition(300), isNull);
      expect(tracker.predictedPosition(400 + 501), isNull);
    });

    test('ignores a single wild measurement and carries on', () {
      final BallTracker tracker = steadyTracker();
      expect(
        tracker.update(timestampMs: 440, x: 0.9, y: 0.9, confidence: 1.0),
        BallTrackStatus.rejected,
      );
      expect(tracker.rejectedCount, 1);
      expect(
        tracker.update(timestampMs: 480, x: 0.1 + 0.5 * 12 * 0.04, y: 0.2, confidence: 1.0),
        BallTrackStatus.accepted,
      );
      expect(tracker.segmentCount, 1);
    });

    test('restarts the motion model when two outliers agree with each other', () {
      final BallTracker tracker = steadyTracker();
      expect(
        tracker.update(timestampMs: 440, x: 0.5, y: 0.6, confidence: 1.0),
        BallTrackStatus.rejected,
      );
      expect(
        tracker.update(timestampMs: 480, x: 0.5, y: 0.65, confidence: 1.0),
        BallTrackStatus.resegmented,
      );
      expect(tracker.segmentCount, 2);
    });

    test('a long silence starts a new track', () {
      final BallTracker tracker = steadyTracker(points: 5);
      expect(
        tracker.update(timestampMs: 160 + 600, x: 0.5, y: 0.5, confidence: 1.0),
        BallTrackStatus.started,
      );
      expect(tracker.segmentCount, 2);
    });

    test('ignores weak, invalid and out-of-order measurements', () {
      final BallTracker tracker = BallTracker();
      expect(
        tracker.update(timestampMs: 0, x: 0.5, y: 0.5, confidence: 0.1),
        BallTrackStatus.rejected,
      );
      expect(
        tracker.update(timestampMs: 0, x: double.nan, y: 0.5, confidence: 1.0),
        BallTrackStatus.rejected,
      );
      expect(tracker.hasTrack, isFalse);
      expect(
        tracker.update(timestampMs: 0, x: 0.5, y: 0.5, confidence: 0.9),
        BallTrackStatus.started,
      );
      expect(
        tracker.update(timestampMs: 0, x: 0.5, y: 0.5, confidence: 0.9),
        BallTrackStatus.rejected,
      );
      expect(
        tracker.update(timestampMs: 10, x: 0.5, y: 0.5, confidence: 0.9),
        BallTrackStatus.accepted,
      );
    });

    test('reset forgets everything', () {
      final BallTracker tracker = steadyTracker();
      tracker.reset();
      expect(tracker.hasTrack, isFalse);
      expect(tracker.points, isEmpty);
      expect(tracker.acceptedCount, 0);
      expect(tracker.segmentCount, 0);
      expect(tracker.position, isNull);
    });

    test('the gate distance is small for a good prediction and large for a bad one', () {
      final BallTracker tracker = steadyTracker();
      final double? good = tracker.gateDistanceSquared(440, 0.32, 0.2);
      final double? bad = tracker.gateDistanceSquared(440, 0.9, 0.9);
      expect(good, isNotNull);
      expect(bad, isNotNull);
      expect(good!, lessThan(tracker.config.gateChiSquare));
      expect(bad!, greaterThan(tracker.config.gateChiSquare));
    });
  });

  group('TrajectoryCodec', () {
    final List<BallTrackPoint> points = <BallTrackPoint>[
      for (int i = 0; i < 1000; i++)
        BallTrackPoint(timestampMs: i * 10, x: i / 1000, y: 0.5, confidence: 0.9),
    ];

    test('round trips', () {
      final List<BallTrackPoint> few = points.take(5).toList();
      final List<List<num>> compressed = TrajectoryCodec.compress(few);
      expect(compressed.length, 5);
      expect(compressed.first, <num>[0, 0.0, 0.5, 0.9]);
      expect(TrajectoryCodec.decompress(compressed), few);
    });

    test('thins long tracks to the limit and keeps the first and last point', () {
      final List<List<num>> compressed = TrajectoryCodec.compress(points);
      expect(compressed.length, TrajectoryCodec.maxPoints);
      expect(compressed.first[0], 0);
      expect(compressed.last[0], 9990);
    });

    test('rounds when asked to', () {
      final List<List<num>> compressed = TrajectoryCodec.compress(
        <BallTrackPoint>[const BallTrackPoint(timestampMs: 1, x: 0.123456, y: 0.987654, confidence: 0.55555)],
        decimals: 3,
      );
      expect(compressed.single, <num>[1, 0.123, 0.988, 0.556]);
    });

    test('rejects a malformed point', () {
      expect(() => BallTrackPoint.fromCompressed(<Object?>[1, 2, 3]), throwsFormatException);
    });
  });
}
