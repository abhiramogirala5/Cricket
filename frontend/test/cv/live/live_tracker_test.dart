import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/cv/live/live_tracker.dart';
import 'package:gully_umpire/cv/live/replay_codec.dart';
import 'package:gully_umpire/cv/pipelines/ball_observation.dart';
import 'package:gully_umpire/cv/vision/luma_frame.dart';

import '../../support/synthetic_scene.dart';

// These scenes were also run through a line-by-line Python port of the tracker, which found the
// delivery in every one of them with the numbers used below (the margins are generous).

/// Index of the first picture in which the ball is visible.
const int ballStart = 12;

/// Number of pictures in which the ball is visible.
const int ballFrames = 22;

List<SceneDisc> ballDiscs(
  int index, {
  int start = ballStart,
  int frames = ballFrames,
  int startDiameter = 12,
  int endDiameter = 7,
  int value = 230,
}) {
  final int step = index - start;
  if (step < 0 || step >= frames) {
    return const <SceneDisc>[];
  }
  return <SceneDisc>[
    SyntheticScene.ball(
      step,
      frames,
      startDiameter: startDiameter,
      endDiameter: endDiameter,
      value: value,
    ),
  ];
}

List<LiveFrameReport> feed(LiveTracker tracker, int count, LumaFrame Function(int index) make) {
  return <LiveFrameReport>[
    for (int i = 0; i < count; i++) tracker.process(make(i)),
  ];
}

List<int> captureIndexes(List<LiveFrameReport> reports) {
  return <int>[
    for (int i = 0; i < reports.length; i++)
      if (reports[i].capture != null) i,
  ];
}

bool everTracking(List<LiveFrameReport> reports) {
  return reports.any((LiveFrameReport r) => r.state == LiveWatchState.tracking);
}

/// Every observation is where the ball really was in that picture.
void expectOnTheBall(LiveDeliveryCapture capture, {double tolerancePx = 1.5}) {
  for (final BallObservation o in capture.observations) {
    final int index = SyntheticScene.indexOfTime(o.timestampMs);
    final SceneDisc truth = SyntheticScene.ball(index - ballStart, ballFrames);
    expect(o.x * SyntheticScene.width, closeTo(truth.cx + 0.5, tolerancePx), reason: 'x at picture $index');
    expect(o.y * SyntheticScene.height, closeTo(truth.cy + 0.5, tolerancePx), reason: 'y at picture $index');
  }
}

LumaFrame plainDelivery(int index) => SyntheticScene.frame(index, discs: ballDiscs(index));

void main() {
  group('LiveTracker with a delivery', () {
    late LiveTracker tracker;
    late List<LiveFrameReport> reports;

    setUp(() {
      tracker = LiveTracker();
      reports = feed(tracker, ballStart + ballFrames + 30, plainDelivery);
    });

    test('learns the empty scene first and then watches', () {
      expect(reports[0].state, LiveWatchState.learning);
      expect(reports[1].state, LiveWatchState.learning);
      expect(reports[2].state, LiveWatchState.watching);
      expect(reports[ballStart - 1].state, LiveWatchState.watching);
      expect(reports[ballStart - 1].candidates, isEmpty);
    });

    test('sees the ball as a candidate in every picture in which it is visible', () {
      for (int i = ballStart; i < ballStart + ballFrames; i++) {
        expect(reports[i].candidates, isNotEmpty, reason: 'picture $i');
      }
    });

    test('starts following the delivery once it clearly flies away', () {
      final int first = reports.indexWhere((LiveFrameReport r) => r.state == LiveWatchState.tracking);

      expect(first, inInclusiveRange(ballStart + 5, ballStart + 14));
    });

    test('hands over exactly one capture, a short while after the ball has gone', () {
      final List<int> indexes = captureIndexes(reports);

      expect(indexes, hasLength(1));
      // The ball is last seen in picture 33 (1100 ms); the delivery ends after 500 ms of quiet.
      expect(indexes.single, inInclusiveRange(44, 52));
      expect(reports[indexes.single].state, LiveWatchState.cooldown);
      expect(reports.last.state, LiveWatchState.cooldown);
    });

    test('the capture holds the whole flight at the right places', () {
      final LiveDeliveryCapture capture = reports[captureIndexes(reports).single].capture!;

      expect(capture.isUsable, isTrue);
      expect(capture.observations.length, inInclusiveRange(15, ballFrames));
      expect(capture.trackQuality, greaterThan(0.5));
      expect(capture.startMs, closeTo(SyntheticScene.timestampOf(ballStart), 100));
      expect(capture.endMs, closeTo(SyntheticScene.timestampOf(ballStart + ballFrames - 1), 100));
      expect(capture.frameTimesMs.length, greaterThanOrEqualTo(15));
      expect(capture.frameWidth, SyntheticScene.width);
      expect(capture.frameHeight, SyntheticScene.height);
      expect(capture.aspectRatio, closeTo(180 / 320, 1e-9));
      expect(capture.framesProcessed, greaterThan(40));
      expectOnTheBall(capture);
    });

    test('the observations are in time order with believable confidence and size', () {
      final LiveDeliveryCapture capture = reports[captureIndexes(reports).single].capture!;
      final List<BallObservation> observations = capture.observations;

      for (int i = 1; i < observations.length; i++) {
        expect(observations[i].timestampMs, greaterThan(observations[i - 1].timestampMs));
      }
      for (final BallObservation o in observations) {
        expect(o.confidence, inInclusiveRange(0.5, 1.0));
      }
      // The ball shrinks from about 12 to about 7 pixels while it flies away.
      expect(observations.first.diameter * SyntheticScene.height, closeTo(12, 2));
      expect(observations.last.diameter * SyntheticScene.height, closeTo(7, 2));
    });

    test('every frame reports the camera rate and the noise level', () {
      final LiveFrameReport last = reports.last;

      expect(last.fps, closeTo(30, 1.0));
      expect(last.threshold, inInclusiveRange(12, 60));
      expect(last.noise, greaterThan(0.4));
      expect(last.foregroundFraction, inInclusiveRange(0.0, 0.01));
    });

    test('the live trail follows the ball and is empty before it is clear what moves', () {
      final List<int> withTrail = <int>[
        for (int i = 0; i < reports.length; i++)
          if (reports[i].trail.isNotEmpty) i,
      ];

      expect(withTrail, isNotEmpty);
      expect(withTrail.first, inInclusiveRange(ballStart + 3, ballStart + 8));
      for (final LiveFrameReport report in reports) {
        expect(report.trail.length, lessThanOrEqualTo(12));
        for (int i = 1; i < report.trail.length; i++) {
          expect(report.trail[i].timestampMs, greaterThan(report.trail[i - 1].timestampMs));
        }
      }
    });
  });

  group('LiveTracker replay', () {
    test('packs the pictures around the delivery, with the ball in them', () {
      final LiveTracker tracker = LiveTracker();
      LiveDeliveryCapture? capture;
      Uint8List? pack;
      for (int i = 0; i < ballStart + ballFrames + 30; i++) {
        final LiveFrameReport report = tracker.process(plainDelivery(i));
        final LiveDeliveryCapture? found = report.capture;
        if (found != null) {
          capture = found;
          // The ring is overwritten by later pictures, so the pack is made right away.
          pack = tracker.encodeReplay(found);
        }
      }

      expect(capture, isNotNull);
      expect(pack, isNotNull);
      final ReplayReader reader = ReplayReader.parse(pack!);
      expect(reader.width, SyntheticScene.width);
      expect(reader.height, SyntheticScene.height);
      expect(reader.frameCount, inInclusiveRange(ballFrames, 60));
      expect(reader.timestampOf(0), greaterThanOrEqualTo(capture!.startMs - 400));
      expect(reader.timestampOf(reader.frameCount - 1), lessThanOrEqualTo(capture.endMs + 500));

      // A picture from the middle of the flight, decoded, is the picture that was filmed.
      final int middle = reader.indexAt(capture.startMs + 330);
      final int source = SyntheticScene.indexOfTime(reader.timestampOf(middle));
      final LumaFrame original = SyntheticScene.frame(source, discs: ballDiscs(source));
      final Uint8List decoded = reader.frame(middle);
      int worst = 0;
      for (int i = 0; i < decoded.length; i++) {
        final int difference = (decoded[i] - original.pixels[i]).abs();
        if (difference > worst) {
          worst = difference;
        }
      }
      expect(worst, lessThanOrEqualTo(ReplayCodec.maxError));
    });

    test('has nothing to pack before any picture was seen', () {
      final LiveTracker tracker = LiveTracker();
      const LiveDeliveryCapture capture = LiveDeliveryCapture(
        observations: <BallObservation>[],
        frameTimesMs: <int>[],
        aspectRatio: 0.5625,
        framesProcessed: 0,
        frameWidth: 180,
        frameHeight: 320,
        trackQuality: 0,
        startMs: 0,
        endMs: 100,
      );

      expect(tracker.encodeReplay(capture), isNull);
    });
  });

  group('LiveTracker with a harder camera', () {
    test('finds the delivery in a noisy picture', () {
      final LiveTracker tracker = LiveTracker();

      final List<LiveFrameReport> reports = feed(
        tracker,
        ballStart + ballFrames + 30,
        (int i) => SyntheticScene.frame(i, discs: ballDiscs(i), noisy: true),
      );

      final List<int> indexes = captureIndexes(reports);
      expect(indexes, hasLength(1));
      final LiveDeliveryCapture capture = reports[indexes.single].capture!;
      expect(capture.isUsable, isTrue);
      expect(capture.observations.length, greaterThanOrEqualTo(15));
      expectOnTheBall(capture);
    });

    test('finds the delivery when the frame times wobble', () {
      final LiveTracker tracker = LiveTracker();

      // Every third picture arrives 3 ms late and the next one 3 ms early.
      final List<LiveFrameReport> reports = feed(tracker, ballStart + ballFrames + 30, (int i) {
        final int wobble = i % 3 == 1 ? 3 : (i % 3 == 2 ? -3 : 0);
        return SyntheticScene.frame(
          i,
          discs: ballDiscs(i),
          timestampMs: SyntheticScene.timestampOf(i) + wobble,
        );
      });

      final List<int> indexes = captureIndexes(reports);
      expect(indexes, hasLength(1));
      final LiveDeliveryCapture capture = reports[indexes.single].capture!;
      expect(capture.isUsable, isTrue);
      expect(capture.endMs - capture.startMs, closeTo(700, 60));
      expectOnTheBall(capture);
    });

    test('finds the delivery with a dark ball in a noisy picture', () {
      final LiveTracker tracker = LiveTracker();

      final List<LiveFrameReport> reports = feed(
        tracker,
        ballStart + ballFrames + 30,
        (int i) => SyntheticScene.frame(i, discs: ballDiscs(i, value: 40), noisy: true),
      );

      final List<int> indexes = captureIndexes(reports);
      expect(indexes, hasLength(1));
      expect(reports[indexes.single].capture!.isUsable, isTrue);
    });

    test('is not fooled by a swaying head in the same picture', () {
      final LiveTracker tracker = LiveTracker();
      const List<int> sway = <int>[0, 2, 3, 2, 0, -2, -3, -2];

      final List<LiveFrameReport> reports = feed(tracker, ballStart + ballFrames + 30, (int i) {
        return SyntheticScene.frame(
          i,
          discs: <SceneDisc>[
            SceneDisc(cx: 140 + sway[i % 8], cy: 120, diameter: 14, value: 200),
            ...ballDiscs(i),
          ],
        );
      });

      final List<int> indexes = captureIndexes(reports);
      expect(indexes, hasLength(1));
      final LiveDeliveryCapture capture = reports[indexes.single].capture!;
      expect(capture.isUsable, isTrue);
      expect(capture.observations.length, greaterThanOrEqualTo(15));
      // Every point of the chosen path is on the ball, none is on the head.
      expectOnTheBall(capture);
    });

    test('finds the ball when it passes a motionless person and a motionless blob', () {
      final LiveTracker tracker = LiveTracker();

      final List<LiveFrameReport> reports = feed(tracker, ballStart + ballFrames + 30, (int i) {
        return SyntheticScene.frame(
          i,
          discs: <SceneDisc>[
            const SceneDisc(cx: 60, cy: 200, diameter: 10, value: 230),
            ...ballDiscs(i),
          ],
          rects: const <SceneRect>[SceneRect(x: 70, y: 120, width: 30, height: 80, value: 60)],
        );
      });

      final List<int> indexes = captureIndexes(reports);
      expect(indexes, hasLength(1));
      expectOnTheBall(reports[indexes.single].capture!);
    });

    test('finds the next delivery after the cool-down, and only that', () {
      final LiveTracker tracker = LiveTracker();
      const int second = ballStart + ballFrames + 80;

      final List<LiveFrameReport> reports = feed(tracker, second + ballFrames + 30, (int i) {
        return SyntheticScene.frame(
          i,
          discs: <SceneDisc>[...ballDiscs(i), ...ballDiscs(i, start: second)],
        );
      });

      final List<int> indexes = captureIndexes(reports);
      expect(indexes, hasLength(2));
      expect(indexes[0], inInclusiveRange(44, 52));
      expect(indexes[1], inInclusiveRange(second + 32, second + 40));
      expect(reports[indexes[1] - 1].state, LiveWatchState.tracking);
      expect(
        reports[indexes[1]].capture!.startMs,
        closeTo(SyntheticScene.timestampOf(second), 100),
      );
    });

    test('starts again from scratch after a reset', () {
      final LiveTracker tracker = LiveTracker();
      feed(tracker, ballStart + ballFrames + 30, plainDelivery);

      tracker.reset();
      expect(tracker.state, LiveWatchState.learning);
      final List<LiveFrameReport> reports = feed(
        tracker,
        ballStart + ballFrames + 30,
        (int i) => SyntheticScene.frame(
          i,
          discs: ballDiscs(i),
          timestampMs: SyntheticScene.timestampOf(i) + 10000,
        ),
      );

      expect(reports[0].state, LiveWatchState.learning);
      expect(reports[1].state, LiveWatchState.learning);
      expect(reports[2].state, LiveWatchState.watching);
      expect(captureIndexes(reports), hasLength(1));
    });
  });

  group('LiveTracker with things that are not a delivery', () {
    const int total = 64;

    test('an empty scene gives no candidates, no capture and stays watching', () {
      final LiveTracker tracker = LiveTracker();

      final List<LiveFrameReport> reports = feed(tracker, total, (int i) => SyntheticScene.frame(i));

      expect(captureIndexes(reports), isEmpty);
      expect(everTracking(reports), isFalse);
      expect(reports.every((LiveFrameReport r) => r.candidates.isEmpty), isTrue);
      expect(reports.last.state, LiveWatchState.watching);
    });

    test('a blob that appears and stays is no delivery and is not drawn as a ball path', () {
      final LiveTracker tracker = LiveTracker();

      final List<LiveFrameReport> reports = feed(tracker, total, (int i) {
        return SyntheticScene.frame(
          i,
          discs: i >= 20
              ? const <SceneDisc>[SceneDisc(cx: 60, cy: 200, diameter: 10, value: 230)]
              : const <SceneDisc>[],
        );
      });

      expect(reports.skip(22).any((LiveFrameReport r) => r.candidates.isNotEmpty), isTrue);
      expect(captureIndexes(reports), isEmpty);
      expect(everTracking(reports), isFalse);
      expect(reports.every((LiveFrameReport r) => r.trail.isEmpty), isTrue);
    });

    test('a person walking slowly across is no delivery', () {
      final LiveTracker tracker = LiveTracker();

      final List<LiveFrameReport> reports = feed(tracker, total, (int i) {
        return SyntheticScene.frame(
          i,
          rects: i >= 14
              ? <SceneRect>[SceneRect(x: 20 + (i - 14), y: 100, width: 30, height: 80, value: 60)]
              : const <SceneRect>[],
        );
      });

      expect(captureIndexes(reports), isEmpty);
      expect(everTracking(reports), isFalse);
    });

    test('a ball that grows is coming towards the camera and is no delivery', () {
      final LiveTracker tracker = LiveTracker();

      final List<LiveFrameReport> reports = feed(
        tracker,
        total,
        (int i) => SyntheticScene.frame(
          i,
          discs: ballDiscs(i, startDiameter: 6, endDiameter: 12),
        ),
      );

      expect(reports.any((LiveFrameReport r) => r.candidates.isNotEmpty), isTrue);
      expect(captureIndexes(reports), isEmpty);
      expect(everTracking(reports), isFalse);
    });

    test('a sudden change of exposure makes it learn again instead of seeing a delivery', () {
      final LiveTracker tracker = LiveTracker();

      final List<LiveFrameReport> reports = feed(
        tracker,
        total,
        (int i) => SyntheticScene.frame(i, brightness: i >= 20 ? 25 : 0),
      );

      expect(captureIndexes(reports), isEmpty);
      expect(everTracking(reports), isFalse);
      expect(reports.skip(21).any((LiveFrameReport r) => r.state == LiveWatchState.learning), isTrue);
      expect(reports.last.state, LiveWatchState.watching);
    });

    test('handheld tremor oscillating horizontally is rejected as a delivery', () {
      final LiveTracker tracker = LiveTracker();
      // Simulates handheld tremor: oscillates left-right every 2 frames
      final List<LiveFrameReport> reports = feed(tracker, total, (int i) {
        final int dx = (i % 4 == 0 || i % 4 == 1) ? 6 : -6;
        return SyntheticScene.frame(
          i,
          discs: i >= 15
              ? <SceneDisc>[SceneDisc(cx: 100 + dx, cy: 80 + (i - 15) * 2, diameter: 8, value: 230)]
              : const <SceneDisc>[],
        );
      });

      expect(captureIndexes(reports), isEmpty);
      expect(everTracking(reports), isFalse);
    });

    test('very slow hand drift or sway is rejected by minimum speed floor', () {
      final LiveTracker tracker = LiveTracker();
      // Moving only 0.5 pixel per frame (15 px / 30 frames = 0.5 px/frame = ~0.047 units/sec)
      final List<LiveFrameReport> reports = feed(tracker, total, (int i) {
        return SyntheticScene.frame(
          i,
          discs: i >= 15
              ? <SceneDisc>[SceneDisc(cx: 60 + ((i - 15) * 0.5).round(), cy: 120 + ((i - 15) * 0.5).round(), diameter: 8, value: 230)]
              : const <SceneDisc>[],
        );
      });

      expect(captureIndexes(reports), isEmpty);
      expect(everTracking(reports), isFalse);
    });

    test('pre-arming motion does not trigger delivery immediately upon enabling tracking', () {
      final LiveTracker tracker = LiveTracker();
      tracker.deliveryTrackingEnabled = false;

      // Feed frames with motion while tracking is disabled
      feed(tracker, 30, (int i) {
        return SyntheticScene.frame(
          i,
          discs: i >= 5
              ? <SceneDisc>[SceneDisc(cx: 90, cy: 300 - (i - 5) * 4, diameter: 10, value: 230)]
              : const <SceneDisc>[],
        );
      });

      // Now enable tracking (simulates user tapping "Start Delivery")
      tracker.deliveryTrackingEnabled = true;

      // Next frame must NOT produce a capture or immediately enter cooldown
      final LiveFrameReport nextReport = tracker.process(
        SyntheticScene.frame(31, discs: const <SceneDisc>[]),
      );

      expect(nextReport.capture, isNull);
      expect(nextReport.state, isNot(LiveWatchState.cooldown));
    });

    test('an object falling downward near the camera is not accepted as a delivery', () {
      final LiveTracker tracker = LiveTracker();
      // Moving downwards (cy increasing: 100 -> 220)
      final List<LiveFrameReport> reports = feed(tracker, total, (int i) {
        return SyntheticScene.frame(
          i,
          discs: i >= 15 && i < 35
              ? <SceneDisc>[SceneDisc(cx: 90, cy: 100 + (i - 15) * 6, diameter: 10, value: 230)]
              : const <SceneDisc>[],
        );
      });

      expect(captureIndexes(reports), isEmpty);
      expect(everTracking(reports), isFalse);
    });

    test('objects at extreme frame margins outside the pitch corridor are rejected', () {
      final LiveTracker tracker = LiveTracker();
      // cx = 8 (extreme left edge: 8 / 180 = 0.044)
      final List<LiveFrameReport> reports = feed(tracker, total, (int i) {
        return SyntheticScene.frame(
          i,
          discs: i >= 15 && i < 35
              ? <SceneDisc>[SceneDisc(cx: 8, cy: 260 - (i - 15) * 4, diameter: 10, value: 230)]
              : const <SceneDisc>[],
        );
      });

      expect(captureIndexes(reports), isEmpty);
      expect(everTracking(reports), isFalse);
    });
  });
}
