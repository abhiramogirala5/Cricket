import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/cv/pipelines/ball_observation.dart';
import 'package:gully_umpire/cv/tracking/multi_ball_tracker.dart';

// The expectations were checked against a line-by-line Python port of the tracker.

BallObservation obs(int t, double x, double y, {double d = 0.03, double c = 0.9}) {
  return BallObservation(timestampMs: t, x: x, y: y, confidence: c, diameter: d);
}

/// A ball that flies away: it moves up the picture, drifts right and shrinks.
List<BallObservation> flyingBall({int count = 10, int startMs = 0}) {
  return <BallObservation>[
    for (int i = 0; i < count; i++)
      obs(startMs + 33 * i, 0.30 + 0.004 * i, 0.80 - 0.03 * i, d: 0.04 - 0.002 * i),
  ];
}

void feed(MultiBallTracker tracker, Iterable<BallObservation> detections) {
  for (final BallObservation o in detections) {
    tracker.step(o.timestampMs, <BallObservation>[o]);
  }
}

void main() {
  group('MultiBallTracker with one ball', () {
    late MultiBallTracker tracker;

    setUp(() {
      tracker = MultiBallTracker();
      feed(tracker, flyingBall());
    });

    test('follows it as one path', () {
      expect(tracker.active, hasLength(1));
      expect(tracker.finished, isEmpty);
      final BallHypothesis path = tracker.active.single;
      expect(path.records, hasLength(10));
      expect(path.firstTimestampMs, 0);
      expect(path.lastTimestampMs, 297);
      expect(path.lastDiameter, closeTo(0.022, 1e-12));
      expect(path.last!.timestampMs, 297);
    });

    test('rates a long, moving, shrinking path highly', () {
      expect(tracker.active.single.quality(), closeTo(0.9, 1e-6));
    });

    test('offers it as the best path', () {
      final TrackedBall? best = tracker.best();

      expect(best, isNotNull);
      expect(best!.observations, hasLength(10));
      expect(best.quality, closeTo(0.9, 1e-6));
      expect(best.hypothesis, same(tracker.active.single));
    });

    test('offers nothing when the demands are higher than the path can meet', () {
      expect(tracker.best(minPoints: 11), isNull);
      expect(tracker.best(minQuality: 0.95), isNull);
      expect(tracker.best(accept: (List<BallObservation> points) => false), isNull);
    });

    test('lets the caller choose which paths count', () {
      final TrackedBall? best = tracker.best(
        accept: (List<BallObservation> points) => points.last.diameter < points.first.diameter,
      );

      expect(best, isNotNull);
    });

    test('finishes the path after a silence longer than the gap, and still offers it', () {
      // The ball was last seen at 297 ms; the gap is 100 ms, so the path ends after 397 ms.
      tracker.step(330, const <BallObservation>[]);
      expect(tracker.active, hasLength(1));
      tracker.step(396, const <BallObservation>[]);
      expect(tracker.active, hasLength(1));

      tracker.step(400, const <BallObservation>[]);

      expect(tracker.active, isEmpty);
      expect(tracker.finished, hasLength(1));
      expect(tracker.best(), isNotNull);
      expect(tracker.best()!.observations, hasLength(10));
    });

    test('the gap can be changed', () {
      tracker.gapMs = 400;

      tracker.step(500, const <BallObservation>[]);

      expect(tracker.active, hasLength(1));
      tracker.step(800, const <BallObservation>[]);
      expect(tracker.active, isEmpty);
    });

    test('forgets its paths but not what it learned about the scene when told to clear the paths', () {
      final MultiBallTracker still = MultiBallTracker();
      feed(still, <BallObservation>[for (int i = 0; i < 5; i++) obs(33 * i, 0.5, 0.5)]);
      expect(still.clutterCells, 1);

      still.clearPaths();

      expect(still.active, isEmpty);
      expect(still.finished, isEmpty);
      expect(still.clutterCells, 1);
      still.reset();
      expect(still.clutterCells, 0);
    });
  });

  group('MultiBallTracker with a path that is not straight', () {
    test('keeps following a ball that bounces', () {
      final MultiBallTracker tracker = MultiBallTracker();
      final List<BallObservation> points = <BallObservation>[
        for (int i = 0; i < 8; i++) obs(33 * i, 0.5, 0.50 + 0.035 * i),
        for (int i = 1; i <= 8; i++) obs(33 * (7 + i), 0.5, 0.745 - 0.035 * i),
      ];

      feed(tracker, points);

      expect(tracker.active, hasLength(1));
      final TrackedBall best = tracker.best()!;
      expect(best.observations, hasLength(16));
      expect(best.quality, greaterThan(0.5));
    });
  });

  group('MultiBallTracker with other moving things', () {
    test('chooses the ball over a swaying head', () {
      final MultiBallTracker tracker = MultiBallTracker();
      const List<double> sway = <double>[0.0, 0.004, 0.006, 0.004, 0.0, -0.004, -0.006, -0.004];
      final List<BallObservation> ball = flyingBall();
      for (int i = 0; i < ball.length; i++) {
        tracker.step(ball[i].timestampMs, <BallObservation>[
          ball[i],
          obs(ball[i].timestampMs, 0.8 + sway[i % 8], 0.3, d: 0.05),
        ]);
      }

      expect(tracker.active, hasLength(2));
      final TrackedBall best = tracker.best()!;
      expect(best.observations, hasLength(10));
      expect(best.observations.first.y, closeTo(0.8, 1e-9));
      expect(best.observations.last.y, closeTo(0.53, 1e-9));
      final BallHypothesis head = tracker.active.firstWhere((BallHypothesis h) => h != best.hypothesis);
      expect(head.records, hasLength(10));
      expect(head.quality(), closeTo(0.451, 0.01));
      expect(head.quality(), lessThan(best.quality));
    });

    test('a detection far from every path starts a path of its own', () {
      final MultiBallTracker tracker = MultiBallTracker();
      feed(tracker, <BallObservation>[
        for (int i = 0; i < 5; i++) obs(33 * i, 0.3 + 0.01 * i, 0.8 - 0.03 * i),
      ]);

      tracker.step(165, <BallObservation>[obs(165, 0.35, 0.65), obs(165, 0.9, 0.2)]);

      expect(
        tracker.active.map((BallHypothesis h) => h.records.length).toList(),
        <int>[6, 1],
      );
    });

    test('a detection of a very different size is not the same ball', () {
      final MultiBallTracker tracker = MultiBallTracker();

      tracker.step(0, <BallObservation>[obs(0, 0.5, 0.5, d: 0.02)]);
      tracker.step(33, <BallObservation>[obs(33, 0.5, 0.5, d: 0.06)]);

      expect(tracker.active, hasLength(2));
      expect(tracker.active.every((BallHypothesis h) => h.records.length == 1), isTrue);
    });

    test('two detections on the same spot are one path', () {
      final MultiBallTracker tracker = MultiBallTracker();

      tracker.step(0, <BallObservation>[obs(0, 0.5, 0.5), obs(0, 0.5005, 0.5)]);

      expect(tracker.active, hasLength(1));
    });

    test('follows only so many paths at a time', () {
      final MultiBallTracker tracker = MultiBallTracker();

      tracker.step(0, <BallObservation>[
        for (int k = 0; k < 14; k++) obs(0, 0.05 + 0.07 * k, 0.5),
      ]);

      expect(tracker.active, hasLength(tracker.config.maxHypotheses));
    });

    test('something that stays where it is is followed once and never starts new paths', () {
      final MultiBallTracker tracker = MultiBallTracker();

      for (int i = 0; i < 30; i++) {
        tracker.step(33 * i, <BallObservation>[obs(33 * i, 0.5, 0.5)]);
        expect(tracker.active.length + tracker.finished.length, 1, reason: 'step $i');
      }
      expect(tracker.best(), isNull);
    });
  });

  group('StationaryClutterMap', () {
    test('calls a spot stationary once something has stayed there for 400 ms', () {
      final StationaryClutterMap map = StationaryClutterMap(const MultiTrackerConfig());

      for (int t = 0; t < 700; t += 33) {
        final BallObservation o = obs(t, 0.5, 0.5);
        // The question is asked before the picture is recorded, so the first yes comes one
        // picture after 400 ms have passed.
        expect(map.isStationary(o), t >= 462, reason: 'at $t ms');
        map.update(t, <BallObservation>[o]);
      }
      expect(map.cellCount, 1);
    });

    test('a neighbouring cell counts, a far one or one of another size does not', () {
      final StationaryClutterMap map = StationaryClutterMap(const MultiTrackerConfig());
      for (int t = 0; t < 700; t += 33) {
        map.update(t, <BallObservation>[obs(t, 0.5, 0.5)]);
      }

      expect(map.isStationary(obs(700, 0.5 + 1 / 160, 0.5)), isTrue);
      expect(map.isStationary(obs(700, 0.8, 0.5)), isFalse);
      expect(map.isStationary(obs(700, 0.5, 0.5, d: 0.06)), isFalse);
    });

    test('forgets a spot that has been quiet for half a second', () {
      final StationaryClutterMap map = StationaryClutterMap(const MultiTrackerConfig());
      for (int t = 0; t < 700; t += 33) {
        map.update(t, <BallObservation>[obs(t, 0.5, 0.5)]);
      }

      map.update(1300, const <BallObservation>[]);

      expect(map.cellCount, 0);
      expect(map.isStationary(obs(1300, 0.5, 0.5)), isFalse);
    });

    test('can be cleared', () {
      final StationaryClutterMap map = StationaryClutterMap(const MultiTrackerConfig());
      map.update(0, <BallObservation>[obs(0, 0.5, 0.5)]);

      map.clear();

      expect(map.cellCount, 0);
    });
  });
}
