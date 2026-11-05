import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/cv/contracts/pose.dart';
import 'package:gully_umpire/cv/geometry/point2d.dart';
import 'package:gully_umpire/cv/geometry/polygon.dart';
import 'package:gully_umpire/cv/live/ball_kind.dart';
import 'package:gully_umpire/cv/live/batter_pose_estimator.dart';
import 'package:gully_umpire/cv/live/crop_pose.dart';
import 'package:gully_umpire/cv/live/live_analysis.dart';
import 'package:gully_umpire/cv/live/live_session.dart';
import 'package:gully_umpire/cv/live/live_tracker.dart';
import 'package:gully_umpire/cv/live/replay_codec.dart';
import 'package:gully_umpire/cv/live/replay_meta.dart';
import 'package:gully_umpire/cv/live/vision_worker.dart';
import 'package:gully_umpire/cv/live/zoom_advice.dart';
import 'package:gully_umpire/cv/pipelines/ball_observation.dart';
import 'package:gully_umpire/cv/vision/luma_frame.dart';

import '../../support/live_fixtures.dart';
import '../../support/synthetic_scene.dart';

// The pictures are the synthetic scene of the tracker tests, and the tracker states the tests
// expect (learning for two pictures, then watching; a delivery at pictures 12..33 is handed over
// at picture 48) were checked against a line-by-line Python port of the tracker.

const int ballStart = 12;
const int ballFrames = 22;

/// Picture [index] of a scene in which one ball is thrown at [ballAt] (and, when given, another
/// one at [secondBallAt]). Everything from picture [brightenAt] on is [brightness] levels brighter.
LumaFrame scenePicture(
  int index, {
  int ballAt = ballStart,
  int? secondBallAt,
  int? brightenAt,
  int brightness = 25,
}) {
  final List<SceneDisc> discs = <SceneDisc>[];
  for (final int? start in <int?>[ballAt, secondBallAt]) {
    if (start == null) {
      continue;
    }
    final int step = index - start;
    if (step >= 0 && step < ballFrames) {
      discs.add(SyntheticScene.ball(step, ballFrames));
    }
  }
  return SyntheticScene.frame(
    index,
    discs: discs,
    brightness: brightenAt != null && index >= brightenAt ? brightness : 0,
  );
}

/// The picture as the camera hands it over (NV21, upright, no row padding).
RawCameraFrame cameraPicture(LumaFrame frame) {
  final int count = frame.width * frame.height;
  final Uint8List nv21 = Uint8List(count * 3 ~/ 2);
  nv21.setRange(0, count, frame.pixels);
  nv21.fillRange(count, nv21.length, 128);
  return RawCameraFrame(
    nv21: nv21,
    width: frame.width,
    height: frame.height,
    rowStride: frame.width,
    rotationDegrees: 0,
    timestampMs: frame.timestampMs,
  );
}

/// The wicket as the umpire marks it: a small outline in the middle of the picture.
Polygon markedWicket() {
  return Polygon(const <Point2D>[
    Point2D(0.46, 0.50),
    Point2D(0.54, 0.50),
    Point2D(0.54, 0.62),
    Point2D(0.46, 0.62),
  ]);
}

/// A pose model that always "sees" a batter standing upright in the cut-out it is given (or
/// nobody, or fails).
final class FakePoseModel implements PoseLandmarkModel {
  bool findsBatter = true;
  Object? failure;
  int calls = 0;
  int closed = 0;
  int lastWidth = 0;
  int lastHeight = 0;

  @override
  Future<List<CropLandmark?>?> detect({
    required Uint8List nv21,
    required int width,
    required int height,
    required int rotationDegrees,
  }) async {
    calls += 1;
    lastWidth = width;
    lastHeight = height;
    final Object? error = failure;
    if (error != null) {
      throw error;
    }
    if (!findsBatter) {
      return null;
    }
    CropLandmark at(double fractionX, double fractionY) =>
        CropLandmark(x: fractionX * width, y: fractionY * height, likelihood: 0.9);
    final List<CropLandmark?> landmarks = <CropLandmark?>[
      for (int i = 0; i < PoseLandmarkIndex.count; i++) at(0.5, 0.5),
    ];
    landmarks[PoseLandmarkIndex.nose] = at(0.5, 0.15);
    landmarks[PoseLandmarkIndex.leftHip] = at(0.45, 0.5);
    landmarks[PoseLandmarkIndex.rightHip] = at(0.55, 0.5);
    landmarks[PoseLandmarkIndex.leftAnkle] = at(0.47, 0.95);
    landmarks[PoseLandmarkIndex.rightAnkle] = at(0.53, 0.95);
    return landmarks;
  }

  @override
  Future<void> close() async {
    closed += 1;
  }
}

/// A live session on a real worker isolate, fed one picture at a time.
final class Harness {
  Harness._(this.worker, this.pose, this.session) {
    _statusSub = session.status.listen(statuses.add);
    _resultSub = session.results.listen(results.add);
  }

  final VisionWorker worker;
  final FakePoseModel pose;
  final LiveVisionSession session;
  final List<LiveSessionStatus> statuses = <LiveSessionStatus>[];
  final List<LiveDeliveryResult> results = <LiveDeliveryResult>[];
  late final StreamSubscription<LiveSessionStatus> _statusSub;
  late final StreamSubscription<LiveDeliveryResult> _resultSub;
  int _handedOver = 0;

  static Future<Harness> start({
    bool wicketMarked = true,
    FakePoseModel? pose,
    LiveInputs? inputs,
  }) async {
    final VisionWorker worker = await VisionWorker.start();
    final FakePoseModel model = pose ?? FakePoseModel();
    final LiveInputs base = inputs ?? makeLiveInputs();
    final LiveVisionSession session = LiveVisionSession(
      worker: worker,
      poseEstimator: BatterPoseEstimator(model),
      inputs: wicketMarked ? base.copyWith(wicket: markedWicket()) : base,
      uiIntervalMs: 0,
      poseIntervalMs: 100,
    );
    return Harness._(worker, model, session);
  }

  /// Hands one picture to the session and waits until the worker has answered it, so that no
  /// picture is dropped.
  Future<void> feed(LumaFrame frame) async {
    session.onFrame(cameraPicture(frame));
    _handedOver += 1;
    while (session.current.framesAnalysed < _handedOver) {
      await session.status.first.timeout(const Duration(seconds: 20));
    }
  }

  Future<void> feedAll(int count, LumaFrame Function(int index) picture) async {
    for (int i = 0; i < count; i++) {
      await feed(picture(i));
    }
  }

  Future<void> waitForResults(int count) async {
    final Stopwatch clock = Stopwatch()..start();
    while (results.length < count) {
      if (clock.elapsed > const Duration(seconds: 20)) {
        fail('Only ${results.length} of $count results arrived.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  Future<void> close() async {
    await _statusSub.cancel();
    await _resultSub.cancel();
    await session.dispose();
  }
}

Future<Harness> startHarness({
  bool wicketMarked = true,
  FakePoseModel? pose,
  LiveInputs? inputs,
}) async {
  final Harness harness = await Harness.start(wicketMarked: wicketMarked, pose: pose, inputs: inputs);
  addTearDown(harness.close);
  return harness;
}

void main() {
  group('LiveSessionStatus', () {
    test('starts out learning the scene, with nothing seen yet', () {
      const LiveSessionStatus status = LiveSessionStatus();

      expect(status.watch, LiveWatchState.learning);
      expect(status.isWatching, isFalse);
      expect(status.fps, 0);
      expect(status.framesAnalysed, 0);
      expect(status.framesDropped, 0);
      expect(status.candidates, isEmpty);
      expect(status.trail, isEmpty);
      expect(status.poseSeen, isFalse);
      expect(status.zoom.level, FramingLevel.unknown);
      expect(status.sceneChanged, isFalse);
      expect(status.problem, isNull);
      expect(status.deliveries, 0);
    });

    test('is watching while it waits for a ball and while it follows one', () {
      for (final LiveWatchState state in LiveWatchState.values) {
        final bool expected = state == LiveWatchState.watching || state == LiveWatchState.tracking;

        expect(const LiveSessionStatus().copyWith(watch: state).isWatching, expected, reason: '$state');
      }
    });

    test('copyWith changes only what it is given', () {
      final LiveSessionStatus status = const LiveSessionStatus().copyWith(
        watch: LiveWatchState.watching,
        fps: 29.5,
        framesAnalysed: 10,
        pictureWidth: 180,
        pictureHeight: 320,
        problem: 'Trouble',
        deliveries: 2,
      );

      final LiveSessionStatus changed = status.copyWith(fps: 30);

      expect(changed.fps, 30);
      expect(changed.watch, LiveWatchState.watching);
      expect(changed.framesAnalysed, 10);
      expect(changed.pictureWidth, 180);
      expect(changed.pictureHeight, 320);
      expect(changed.problem, 'Trouble');
      expect(changed.deliveries, 2);
    });

    test('a problem stays until it is cleared on purpose', () {
      final LiveSessionStatus status = const LiveSessionStatus().copyWith(problem: 'Trouble');

      expect(status.copyWith(deliveries: 1).problem, 'Trouble');
      expect(status.copyWith(clearProblem: true).problem, isNull);
      expect(status.copyWith(clearProblem: true, problem: 'Other').problem, isNull);
    });
  });

  group('LiveVisionSession (on a real worker)', () {
    test('learns the scene, then watches, and reports the picture size and the camera speed', () async {
      final Harness harness = await startHarness();

      await harness.feedAll(30, (int i) => scenePicture(i, ballAt: 1000));

      final LiveSessionStatus status = harness.session.current;
      expect(status.watch, LiveWatchState.watching);
      expect(status.isWatching, isTrue);
      expect(status.pictureWidth, SyntheticScene.width);
      expect(status.pictureHeight, SyntheticScene.height);
      expect(status.fps, closeTo(30, 2));
      expect(status.framesAnalysed, 30);
      expect(status.framesDropped, 0);
      expect(status.deliveries, 0);
      expect(status.sceneChanged, isFalse);
      expect(harness.results, isEmpty);
      expect(harness.statuses.first.watch, LiveWatchState.learning);
    });

    test('follows a delivery and hands over one result with its replay', () async {
      final Harness harness = await startHarness();

      await harness.feedAll(64, scenePicture);
      await harness.waitForResults(1);

      expect(harness.results, hasLength(1));
      final LiveDeliveryResult result = harness.results.single;
      expect(result.capture.isUsable, isTrue);
      expect(result.capture.observations.length, greaterThanOrEqualTo(15));
      expect(result.analysis.isMock, isFalse);
      expect(result.analysis.modelVersion, liveModelVersion);
      expect(result.receivedAtMs, greaterThan(0));
      expect(harness.session.current.deliveries, 1);

      // What the overlay showed while it happened.
      expect(harness.statuses.any((LiveSessionStatus s) => s.watch == LiveWatchState.tracking), isTrue);
      expect(harness.statuses.any((LiveSessionStatus s) => s.candidates.isNotEmpty), isTrue);
      expect(harness.statuses.any((LiveSessionStatus s) => s.trail.length >= 3), isTrue);
      expect(harness.statuses.last.watch, LiveWatchState.cooldown);
    });

    test('puts the replay and what was concluded into one file', () async {
      final Harness harness = await startHarness();

      await harness.feedAll(64, scenePicture);
      await harness.waitForResults(1);

      final LiveDeliveryResult result = harness.results.single;
      expect(result.replay, isNotNull);
      final ReplayReader reader = ReplayReader.parse(result.replay!);
      expect(reader.width, SyntheticScene.width);
      expect(reader.height, SyntheticScene.height);
      expect(reader.frameCount, greaterThanOrEqualTo(ballFrames));
      final Map<String, Object?>? stored = reader.meta;
      expect(stored, isNotNull);
      final ReplayMeta meta = ReplayMeta.fromJson(stored!);
      expect(meta.ballKind, BallKind.cricketBall.wire);
      expect(meta.wicket, isNotNull);
      expect(meta.ballKind, result.meta.ballKind);
    });

    test('measures the batter while it waits and uses the poses for the delivery', () async {
      final Harness harness = await startHarness();

      await harness.feedAll(64, scenePicture);
      await harness.waitForResults(1);

      expect(harness.pose.calls, greaterThan(3));
      expect(harness.pose.lastWidth, greaterThan(0));
      expect(harness.pose.lastHeight, greaterThan(0));
      expect(harness.results.single.analysis.poses, isNotEmpty);
      expect(harness.statuses.any((LiveSessionStatus s) => s.poseSeen), isTrue);
      expect(
        harness.statuses.any((LiveSessionStatus s) => s.zoom.level != FramingLevel.unknown),
        isTrue,
      );
    });

    test('does not look for the batter before the wicket has been marked', () async {
      final Harness harness = await startHarness(wicketMarked: false);

      await harness.feedAll(40, (int i) => scenePicture(i, ballAt: 1000));

      expect(harness.pose.calls, 0);
      expect(harness.session.current.poseSeen, isFalse);
      expect(harness.session.current.zoom.level, FramingLevel.unknown);
    });

    test('starts measuring the batter once the wicket is marked', () async {
      final Harness harness = await startHarness(wicketMarked: false);
      await harness.feedAll(20, (int i) => scenePicture(i, ballAt: 1000));

      harness.session.updateInputs(harness.session.inputs.copyWith(wicket: markedWicket()));
      for (int i = 20; i < 40; i++) {
        await harness.feed(scenePicture(i, ballAt: 1000));
      }

      expect(harness.session.inputs.wicket, isNotNull);
      expect(harness.pose.calls, greaterThan(0));
      expect(harness.session.current.poseSeen, isTrue);
    });

    test('says the batter has not been seen when the model finds nobody', () async {
      final FakePoseModel nobody = FakePoseModel()..findsBatter = false;
      final Harness harness = await startHarness(pose: nobody);

      await harness.feedAll(30, (int i) => scenePicture(i, ballAt: 1000));

      expect(nobody.calls, greaterThan(0));
      expect(harness.session.current.poseSeen, isFalse);
      expect(harness.session.current.zoom.level, FramingLevel.unknown);
      expect(harness.session.current.problem, isNull);
    });

    test('shows a pose model that fails as a problem and keeps watching', () async {
      final FakePoseModel broken = FakePoseModel()..failure = StateError('model broke');
      final Harness harness = await startHarness(pose: broken);

      await harness.feedAll(30, (int i) => scenePicture(i, ballAt: 1000));

      final LiveSessionStatus status = harness.session.current;
      expect(status.problem, startsWith('The batter could not be measured'));
      expect(status.problem, contains('model broke'));
      expect(status.poseSeen, isFalse);
      expect(status.watch, LiveWatchState.watching);
    });

    test('still hands over the delivery when the batter could not be measured, and says so', () async {
      final FakePoseModel broken = FakePoseModel()..failure = StateError('model broke');
      final Harness harness = await startHarness(pose: broken);

      await harness.feedAll(64, scenePicture);
      await harness.waitForResults(1);

      final LiveDeliveryResult result = harness.results.single;
      expect(result.analysis.poses, isEmpty);
      expect(result.analysis.notes, contains('The batter was not visible enough to measure.'));
      expect(result.capture.isUsable, isTrue);
    });

    test('uses the match facts it was given last for the next delivery', () async {
      final Harness harness = await startHarness();
      await harness.feedAll(20, (int i) => scenePicture(i, ballAt: 12));
      final LiveInputs tennis = harness.session.inputs.copyWith(ballKind: BallKind.tennisBall);

      harness.session.updateInputs(tennis);
      for (int i = 20; i < 64; i++) {
        await harness.feed(scenePicture(i));
      }
      await harness.waitForResults(1);

      expect(harness.session.inputs, tennis);
      expect(harness.results.single.meta.ballKind, BallKind.tennisBall.wire);
    });

    test('hands over two deliveries one after the other, in the order they were bowled', () async {
      final Harness harness = await startHarness();

      await harness.feedAll(150, (int i) => scenePicture(i, secondBallAt: 92));
      await harness.waitForResults(2);

      expect(harness.results, hasLength(2));
      final LiveDeliveryResult first = harness.results[0];
      final LiveDeliveryResult second = harness.results[1];
      expect(first.capture.startMs, lessThan(second.capture.startMs));
      expect(first.capture.endMs, lessThan(second.capture.startMs));
      expect(first.receivedAtMs, lessThanOrEqualTo(second.receivedAtMs));
      expect(first.capture.isUsable, isTrue);
      expect(second.capture.isUsable, isTrue);
      expect(harness.session.current.deliveries, 2);
    });

    test('notices when the picture changed so much that the stumps may have moved', () async {
      final Harness harness = await startHarness();

      await harness.feedAll(64, (int i) => scenePicture(i, ballAt: 1000, brightenAt: 20));

      final LiveSessionStatus status = harness.session.current;
      expect(harness.statuses.any((LiveSessionStatus s) => s.watch == LiveWatchState.learning && s.sceneChanged), isTrue);
      expect(status.sceneChanged, isTrue);
      // It learned the new picture and is watching again, but waits for the person to say that
      // the stumps are still where they were marked.
      expect(status.watch, LiveWatchState.watching);
      expect(harness.results, isEmpty);
    });

    test('does not call the first learning of the scene a change', () async {
      final Harness harness = await startHarness();

      await harness.feedAll(30, (int i) => scenePicture(i, ballAt: 1000));

      expect(harness.statuses.any((LiveSessionStatus s) => s.sceneChanged), isFalse);
    });

    test('the person can say the stumps are fine after a change', () async {
      final Harness harness = await startHarness();
      await harness.feedAll(40, (int i) => scenePicture(i, ballAt: 1000, brightenAt: 20));
      expect(harness.session.current.sceneChanged, isTrue);

      harness.session.acknowledgeSceneChange();

      expect(harness.session.current.sceneChanged, isFalse);
      expect(harness.session.current.watch, LiveWatchState.watching);
    });

    test('still follows a delivery after the picture changed', () async {
      final Harness harness = await startHarness();

      await harness.feedAll(
        110,
        (int i) => scenePicture(i, ballAt: 44, brightenAt: 20),
      );
      await harness.waitForResults(1);

      expect(harness.results.single.capture.isUsable, isTrue);
      expect(harness.session.current.sceneChanged, isTrue);
    });

    test('can be told to learn the scene again', () async {
      final Harness harness = await startHarness();
      await harness.feedAll(20, (int i) => scenePicture(i, ballAt: 1000));
      expect(harness.session.current.watch, LiveWatchState.watching);

      harness.session.relearn();

      expect(harness.session.current.watch, LiveWatchState.learning);
      expect(harness.session.current.sceneChanged, isFalse);
      for (int i = 20; i < 30; i++) {
        await harness.feed(scenePicture(i, ballAt: 1000));
      }
      // Learning on request is not "the picture changed", and it ends like the first learning.
      expect(harness.session.current.watch, LiveWatchState.watching);
      expect(harness.session.current.sceneChanged, isFalse);
    });

    test('stops cleanly: it closes its streams, the pose model and the worker', () async {
      final Harness harness = await startHarness();
      await harness.feedAll(10, (int i) => scenePicture(i, ballAt: 1000));
      final Future<void> statusEnded = harness.session.status.drain<void>();
      final Future<void> resultsEnded = harness.session.results.drain<void>();

      await harness.session.dispose();

      await statusEnded.timeout(const Duration(seconds: 5));
      await resultsEnded.timeout(const Duration(seconds: 5));
      expect(harness.worker.isRunning, isFalse);
      expect(harness.pose.closed, 1);
    });

    test('ignores pictures after it was stopped and can be stopped twice', () async {
      final Harness harness = await startHarness();
      await harness.feedAll(10, (int i) => scenePicture(i, ballAt: 1000));
      await harness.session.dispose();
      final int calls = harness.pose.calls;

      harness.session.onFrame(cameraPicture(scenePicture(11, ballAt: 1000)));
      await harness.session.dispose();

      expect(harness.pose.calls, calls);
      expect(harness.pose.closed, 1);
    });
  });

  group('A ball path in the status', () {
    test('every candidate in the status is a position inside the picture', () async {
      final Harness harness = await startHarness();

      await harness.feedAll(64, scenePicture);

      for (final LiveSessionStatus status in harness.statuses) {
        for (final BallObservation o in <BallObservation>[...status.candidates, ...status.trail]) {
          expect(o.x, inInclusiveRange(0, 1));
          expect(o.y, inInclusiveRange(0, 1));
          expect(o.diameter, greaterThan(0));
        }
      }
    });
  });
}
