import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/cv/live/ball_kind.dart';
import 'package:gully_umpire/cv/live/frame_source.dart';
import 'package:gully_umpire/cv/live/live_analysis.dart';
import 'package:gully_umpire/cv/live/live_session.dart';
import 'package:gully_umpire/cv/live/live_tracker.dart';
import 'package:gully_umpire/cv/live/umpire_camera_controller.dart';

import '../../support/live_fixtures.dart';

void main() {
  late List<String> log;
  late List<FakeFrameSource> cameras;
  late List<FakeLiveSession> sessions;
  late List<bool> awake;

  /// A controller whose camera and tracker are fakes. [cameraGate] (when given) holds the camera
  /// back until the test completes it.
  UmpireCameraController makeController({
    Future<void> Function()? cameraGate,
    Object? cameraOpenError,
    Object? sessionOpenError,
    Object? cameraStartError,
    Object? keepAwakeError,
    double? initialZoom,
    LiveInputs? inputs,
  }) {
    return UmpireCameraController(
      inputs: inputs ?? makeLiveInputs(),
      initialZoom: initialZoom,
      openSession: (LiveInputs given) async {
        final Object? error = sessionOpenError;
        if (error != null) {
          throw error;
        }
        final FakeLiveSession session = FakeLiveSession('session${sessions.length + 1}', log, given);
        sessions.add(session);
        log.add('${session.name}.open');
        return session;
      },
      openCamera: () async {
        final Future<void> Function()? gate = cameraGate;
        if (gate != null) {
          await gate();
        }
        final Object? error = cameraOpenError;
        if (error != null) {
          throw error;
        }
        final FakeFrameSource camera = FakeFrameSource('camera${cameras.length + 1}', log);
        camera.startError = cameraStartError;
        cameras.add(camera);
        log.add('${camera.name}.open');
        return camera;
      },
      keepAwake: (bool enabled) async {
        awake.add(enabled);
        final Object? error = keepAwakeError;
        if (error != null) {
          throw error;
        }
      },
    );
  }

  setUp(() {
    log = <String>[];
    cameras = <FakeFrameSource>[];
    sessions = <FakeLiveSession>[];
    awake = <bool>[];
  });

  group('start and stop', () {
    test('opens the tracker and the camera, keeps the screen awake and runs', () async {
      final UmpireCameraController controller = makeController();
      expect(controller.phase, CameraPhase.idle);

      await controller.start();

      expect(controller.phase, CameraPhase.running);
      expect(controller.isRunning, isTrue);
      expect(controller.error, isNull);
      expect(controller.source, same(cameras.single));
      expect(cameras.single.started, isTrue);
      expect(awake, <bool>[true]);
      expect(log, <String>['session1.open', 'camera1.open', 'camera1.start']);
      controller.dispose();
      await pumpEventQueue();
    });

    test('pictures from the camera go to the tracker', () async {
      final UmpireCameraController controller = makeController();
      await controller.start();

      cameras.single.onFrame!(makeRawFrame());
      cameras.single.onFrame!(makeRawFrame(timestampMs: 33));

      expect(sessions.single.frames, 2);
      controller.dispose();
      await pumpEventQueue();
    });

    test('stop releases the camera first, then the tracker, and lets the screen sleep', () async {
      final UmpireCameraController controller = makeController();
      await controller.start();
      log.clear();

      await controller.stop();

      expect(controller.phase, CameraPhase.idle);
      expect(controller.source, isNull);
      expect(log, <String>['camera1.dispose', 'session1.dispose']);
      expect(awake, <bool>[true, false]);
      controller.dispose();
      await pumpEventQueue();
    });

    test('starting twice does not open a second camera', () async {
      final UmpireCameraController controller = makeController();

      await Future.wait<void>(<Future<void>>[controller.start(), controller.start()]);
      await controller.start();

      expect(cameras, hasLength(1));
      expect(sessions, hasLength(1));
      controller.dispose();
      await pumpEventQueue();
    });

    test('can be started again after it was stopped', () async {
      final UmpireCameraController controller = makeController();
      await controller.start();
      await controller.stop();

      await controller.start();

      expect(controller.phase, CameraPhase.running);
      expect(cameras, hasLength(2));
      expect(sessions, hasLength(2));
      expect(cameras.first.disposed, isTrue);
      expect(cameras.last.disposed, isFalse);
      controller.dispose();
      await pumpEventQueue();
    });

    test('stop without start does nothing harmful', () async {
      final UmpireCameraController controller = makeController();

      await controller.stop();

      expect(controller.phase, CameraPhase.idle);
      expect(cameras, isEmpty);
      controller.dispose();
      await pumpEventQueue();
    });

    test('tells its listeners about each change of phase', () async {
      final UmpireCameraController controller = makeController();
      final List<CameraPhase> seen = <CameraPhase>[];
      controller.addListener(() => seen.add(controller.phase));

      await controller.start();
      await controller.stop();

      expect(seen.first, CameraPhase.starting);
      expect(seen, contains(CameraPhase.running));
      expect(seen.last, CameraPhase.idle);
      controller.dispose();
      await pumpEventQueue();
    });
  });

  group('things going wrong', () {
    test('a camera that cannot be opened is reported in plain words and the tracker is closed',
        () async {
      final UmpireCameraController controller = makeController(
        cameraOpenError: const FrameSourceException('Allow the camera to use this feature.'),
      );

      await controller.start();

      expect(controller.phase, CameraPhase.failed);
      expect(controller.error, 'Allow the camera to use this feature.');
      expect(controller.source, isNull);
      expect(sessions.single.disposed, isTrue);
      expect(awake, isEmpty);
    });

    test('a camera that opens but cannot start is released', () async {
      final UmpireCameraController controller = makeController(
        cameraStartError: const FrameSourceException('The camera is busy.'),
      );

      await controller.start();

      expect(controller.phase, CameraPhase.failed);
      expect(controller.error, 'The camera is busy.');
      expect(cameras.single.disposed, isTrue);
      expect(sessions.single.disposed, isTrue);
    });

    test('a tracker that cannot start fails before the camera is opened', () async {
      final UmpireCameraController controller = makeController(
        sessionOpenError: StateError('The vision worker could not start.'),
      );

      await controller.start();

      expect(controller.phase, CameraPhase.failed);
      expect(controller.error, 'The vision worker could not start.');
      expect(cameras, isEmpty);
    });

    test('an unexpected error still gives a readable message', () async {
      final UmpireCameraController controller = makeController(
        cameraOpenError: Exception('boom'),
      );

      await controller.start();

      expect(controller.phase, CameraPhase.failed);
      expect(controller.error, startsWith('The camera could not be started'));
    });

    test('can be tried again after a failure', () async {
      bool fail = true;
      final UmpireCameraController controller = UmpireCameraController(
        inputs: makeLiveInputs(),
        openSession: (LiveInputs given) async => FakeLiveSession('s', log, given),
        openCamera: () async {
          if (fail) {
            throw const FrameSourceException('No camera.');
          }
          return FakeFrameSource('c', log);
        },
      );

      await controller.start();
      expect(controller.phase, CameraPhase.failed);
      fail = false;
      await controller.start();

      expect(controller.phase, CameraPhase.running);
      expect(controller.error, isNull);
      controller.dispose();
      await pumpEventQueue();
    });

    test('a screen that cannot be kept awake does not stop the camera', () async {
      final UmpireCameraController controller = makeController(
        keepAwakeError: StateError('no wake lock'),
      );

      await controller.start();

      expect(controller.phase, CameraPhase.running);
      controller.dispose();
      await pumpEventQueue();
    });

    test('a camera that fails to close does not stop the tracker from closing', () async {
      final UmpireCameraController controller = makeController();
      await controller.start();
      cameras.single.disposeError = StateError('already closed');

      await controller.stop();

      expect(controller.phase, CameraPhase.idle);
      expect(sessions.single.disposed, isTrue);
      controller.dispose();
      await pumpEventQueue();
    });
  });

  group('stopping while the camera is still opening', () {
    test('the camera that finishes opening afterwards is released at once', () async {
      final Completer<void> gate = Completer<void>();
      final UmpireCameraController controller = makeController(cameraGate: () => gate.future);

      final Future<void> starting = controller.start();
      await pumpEventQueue();
      expect(controller.phase, CameraPhase.starting);

      await controller.stop();
      gate.complete();
      await starting;

      expect(controller.phase, CameraPhase.idle);
      expect(controller.source, isNull);
      expect(cameras.single.disposed, isTrue);
      expect(cameras.single.started, isFalse);
      expect(sessions.single.disposed, isTrue);
      controller.dispose();
      await pumpEventQueue();
    });

    test('a new start waits until the cancelled attempt has released the camera', () async {
      final Completer<void> firstGate = Completer<void>();
      int calls = 0;
      final UmpireCameraController controller = makeController(
        cameraGate: () async {
          calls += 1;
          if (calls == 1) {
            await firstGate.future;
          }
        },
      );

      final Future<void> first = controller.start();
      await pumpEventQueue();
      await controller.stop();
      final Future<void> second = controller.start();
      await pumpEventQueue();

      // The second attempt must not have asked for a camera yet: the first one still holds it.
      expect(calls, 1);

      firstGate.complete();
      await first;
      await second;

      expect(controller.phase, CameraPhase.running);
      expect(cameras, hasLength(2));
      final int firstDisposed = log.indexOf('camera1.dispose');
      final int secondOpened = log.indexOf('camera2.open');
      expect(firstDisposed, isNonNegative);
      expect(secondOpened, greaterThan(firstDisposed));
      controller.dispose();
      await pumpEventQueue();
    });

    test('disposing while opening releases whatever was opened', () async {
      final Completer<void> gate = Completer<void>();
      final UmpireCameraController controller = makeController(cameraGate: () => gate.future);

      final Future<void> starting = controller.start();
      await pumpEventQueue();
      controller.dispose();
      gate.complete();
      await starting;
      await pumpEventQueue();

      expect(cameras.single.disposed, isTrue);
      expect(sessions.single.disposed, isTrue);
    });
  });

  group('match facts', () {
    test('new facts reach the running tracker', () async {
      final UmpireCameraController controller = makeController();
      await controller.start();
      final LiveInputs taller = makeLiveInputs(batsmanHeightM: 1.9);

      controller.updateInputs(taller);

      expect(controller.inputs, taller);
      expect(sessions.single.inputs, taller);
      controller.dispose();
      await pumpEventQueue();
    });

    test('facts that changed while the camera was opening are applied once it runs', () async {
      final Completer<void> gate = Completer<void>();
      final UmpireCameraController controller = makeController(cameraGate: () => gate.future);
      final Future<void> starting = controller.start();
      await pumpEventQueue();
      final LiveInputs tennis = makeLiveInputs(ballKind: BallKind.tennisBall);

      controller.updateInputs(tennis);
      gate.complete();
      await starting;

      expect(sessions.single.inputs, tennis);
      controller.dispose();
      await pumpEventQueue();
    });

    test('facts given while nothing runs are used by the next start', () async {
      final UmpireCameraController controller = makeController();
      final LiveInputs taller = makeLiveInputs(batsmanHeightM: 1.9);

      controller.updateInputs(taller);
      await controller.start();

      expect(sessions.single.inputs, taller);
      controller.dispose();
      await pumpEventQueue();
    });
  });

  group('zoom', () {
    test('the zoom the stumps were marked at is set before the pictures start', () async {
      final UmpireCameraController controller = makeController(initialZoom: 2.5);

      await controller.start();

      expect(controller.zoom, 2.5);
      expect(log.indexOf('camera1.zoom=2.5'), lessThan(log.indexOf('camera1.start')));
      controller.dispose();
      await pumpEventQueue();
    });

    test('setStartZoom changes what the next start uses', () async {
      final UmpireCameraController controller = makeController();
      controller.setStartZoom(3);
      expect(controller.zoom, 3);

      await controller.start();

      expect(controller.zoom, 3);
      controller.dispose();
      await pumpEventQueue();
    });

    test('a zoom beyond the camera is limited and reported back', () async {
      final UmpireCameraController controller = makeController();
      await controller.start();

      expect(await controller.setZoom(9), 4);
      expect(controller.zoom, 4);
      expect(controller.maxZoom, 4);
      expect(controller.minZoom, 1);
      controller.dispose();
      await pumpEventQueue();
    });

    test('without a camera the zoom is not changed', () async {
      final UmpireCameraController controller = makeController();

      expect(await controller.setZoom(2), 1);
      expect(controller.maxZoom, 1);
      controller.dispose();
      await pumpEventQueue();
    });
  });

  group('what the tracker reports', () {
    test('status updates reach the screen', () async {
      final UmpireCameraController controller = makeController();
      await controller.start();
      int notified = 0;
      controller.addListener(() => notified += 1);

      sessions.single.emitStatus(const LiveSessionStatus(watch: LiveWatchState.watching, fps: 29));
      await pumpEventQueue();

      expect(controller.status.watch, LiveWatchState.watching);
      expect(controller.status.fps, 29);
      expect(notified, greaterThan(0));
      controller.dispose();
      await pumpEventQueue();
    });

    test('a camera problem comes before the tracker problem', () async {
      final UmpireCameraController controller = makeController();
      await controller.start();

      sessions.single.emitStatus(const LiveSessionStatus(problem: 'The tracker is slow.'));
      await pumpEventQueue();
      expect(controller.problem, 'The tracker is slow.');

      cameras.single.onProblem!('The camera stopped sending pictures.');
      expect(controller.problem, 'The camera stopped sending pictures.');
      controller.dispose();
      await pumpEventQueue();
    });

    test('the status and the problem are cleared when the camera is stopped', () async {
      final UmpireCameraController controller = makeController();
      await controller.start();
      cameras.single.onProblem!('Trouble.');
      sessions.single.emitStatus(const LiveSessionStatus(fps: 30));
      await pumpEventQueue();

      await controller.stop();

      expect(controller.problem, isNull);
      expect(controller.status.fps, 0);
      controller.dispose();
      await pumpEventQueue();
    });

    test('commands reach the tracker', () async {
      final UmpireCameraController controller = makeController();
      await controller.start();

      controller.relearn();
      controller.acknowledgeSceneChange();
      controller.acknowledgeSceneChange();

      expect(sessions.single.relearned, 1);
      expect(sessions.single.acknowledged, 2);
      controller.dispose();
      await pumpEventQueue();
    });

    test('commands without a tracker are ignored', () {
      final UmpireCameraController controller = makeController();

      controller.relearn();
      controller.acknowledgeSceneChange();

      expect(sessions, isEmpty);
      controller.dispose();
    });
  });

  group('delivery results', () {
    test('every followed delivery arrives on the results stream', () async {
      final UmpireCameraController controller = makeController();
      final List<int> received = <int>[];
      final StreamSubscription<LiveDeliveryResult> subscription =
          controller.results.listen((LiveDeliveryResult r) => received.add(r.receivedAtMs));
      await controller.start();

      sessions.single.resultController.add(makeLiveResult(receivedAtMs: 10));
      sessions.single.resultController.add(makeLiveResult(receivedAtMs: 20));
      await pumpEventQueue();

      expect(received, <int>[10, 20]);
      await subscription.cancel();
      controller.dispose();
      await pumpEventQueue();
    });

    test('one listener keeps hearing results across a stop and a start', () async {
      final UmpireCameraController controller = makeController();
      final List<int> received = <int>[];
      final StreamSubscription<LiveDeliveryResult> subscription =
          controller.results.listen((LiveDeliveryResult r) => received.add(r.receivedAtMs));
      await controller.start();
      sessions.last.resultController.add(makeLiveResult(receivedAtMs: 1));
      await pumpEventQueue();

      await controller.stop();
      await controller.start();
      sessions.last.resultController.add(makeLiveResult(receivedAtMs: 2));
      await pumpEventQueue();

      expect(received, <int>[1, 2]);
      await subscription.cancel();
      controller.dispose();
      await pumpEventQueue();
    });

    test('a result from a tracker that was closed is not delivered', () async {
      final UmpireCameraController controller = makeController();
      final List<int> received = <int>[];
      final StreamSubscription<LiveDeliveryResult> subscription =
          controller.results.listen((LiveDeliveryResult r) => received.add(r.receivedAtMs));
      await controller.start();
      final FakeLiveSession old = sessions.single;
      await controller.stop();

      // The old tracker's stream is closed, so nothing more can arrive from it.
      expect(old.resultController.isClosed, isTrue);
      expect(received, isEmpty);
      await subscription.cancel();
      controller.dispose();
      await pumpEventQueue();
    });
  });

  group('dispose', () {
    test('releases the camera and the tracker and ends the results stream', () async {
      final UmpireCameraController controller = makeController();
      final Future<void> ended = controller.results.drain<void>();
      await controller.start();

      controller.dispose();
      await ended.timeout(const Duration(seconds: 5));

      expect(cameras.single.disposed, isTrue);
      expect(sessions.single.disposed, isTrue);
      expect(awake.last, isFalse);
    });

    test('start after dispose does nothing', () async {
      final UmpireCameraController controller = makeController();
      controller.dispose();

      await controller.start();

      expect(cameras, isEmpty);
      expect(sessions, isEmpty);
    });

    test('disposing twice is harmless', () async {
      final UmpireCameraController controller = makeController();
      await controller.start();

      controller.dispose();
      controller.dispose();
      await pumpEventQueue();

      expect(cameras.single.disposed, isTrue);
    });
  });
}
