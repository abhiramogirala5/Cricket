import 'dart:async';
import 'dart:typed_data';

import 'package:gully_umpire/cv/device/device_policy.dart';
import 'package:gully_umpire/cv/live/ball_kind.dart';
import 'package:gully_umpire/cv/live/batter_pose_estimator.dart';
import 'package:gully_umpire/cv/live/frame_source.dart';
import 'package:gully_umpire/cv/live/live_analysis.dart';
import 'package:gully_umpire/cv/live/live_session.dart';
import 'package:gully_umpire/cv/live/live_tracker.dart';
import 'package:gully_umpire/cv/pipelines/delivery_context.dart';
import 'package:gully_umpire/cv/rules/umpiring_rules.dart';

import 'replay_fixtures.dart';

/// Match facts for the live camera: a mid-range phone, a 1.70 m batter and a cricket ball.
LiveInputs makeLiveInputs({
  double batsmanHeightM = 1.70,
  BallKind ballKind = BallKind.cricketBall,
}) {
  return LiveInputs(
    policy: DevicePolicy.live(DeviceProfile.mid),
    rules: const UmpiringRuleConfig(),
    batsmanHeightM: batsmanHeightM,
    ballKind: ballKind,
  );
}

/// A finished delivery without any pictures kept (or with [replay] bytes when given).
LiveDeliveryResult makeLiveResult({int receivedAtMs = 1000, Uint8List? replay}) {
  return LiveDeliveryResult(
    capture: const LiveDeliveryCapture(
      observations: [],
      frameTimesMs: <int>[],
      aspectRatio: 0.5625,
      framesProcessed: 0,
      frameWidth: 360,
      frameHeight: 640,
      trackQuality: 0,
      startMs: 0,
      endMs: 0,
    ),
    analysis: DeliveryAnalysis.none(modelVersion: 'live-test', isMock: false),
    meta: makeMeta(),
    replay: replay,
    receivedAtMs: receivedAtMs,
  );
}

/// A camera picture that is never looked at (the fakes only count them).
RawCameraFrame makeRawFrame({int timestampMs = 0}) => RawCameraFrame(
      nv21: Uint8List(6),
      width: 2,
      height: 2,
      rowStride: 2,
      rotationDegrees: 0,
      timestampMs: timestampMs,
    );

/// A stand-in for the phone's camera. Everything it is asked to do is written to [log].
final class FakeFrameSource implements FrameSource {
  FakeFrameSource(this.name, this.log, {this.minZoom = 1, this.maxZoom = 4});

  final String name;
  final List<String> log;

  @override
  final double minZoom;

  @override
  final double maxZoom;

  double _zoom = 1;
  bool started = false;
  bool disposed = false;
  Object? disposeError;
  Object? startError;
  void Function(RawCameraFrame frame)? onFrame;
  void Function(String message)? onProblem;

  @override
  double get zoom => _zoom;

  @override
  Future<void> start(
    void Function(RawCameraFrame frame) onFrame, {
    void Function(String message)? onProblem,
  }) async {
    log.add('$name.start');
    final Object? error = startError;
    if (error != null) {
      throw error;
    }
    started = true;
    this.onFrame = onFrame;
    this.onProblem = onProblem;
  }

  @override
  Future<double> setZoom(double level) async {
    _zoom = level < minZoom ? minZoom : (level > maxZoom ? maxZoom : level);
    log.add('$name.zoom=$_zoom');
    return _zoom;
  }

  @override
  Future<void> dispose() async {
    log.add('$name.dispose');
    disposed = true;
    final Object? error = disposeError;
    if (error != null) {
      throw error;
    }
  }
}

/// A stand-in for the tracker.
final class FakeLiveSession implements LiveSessionPort {
  FakeLiveSession(this.name, this.log, LiveInputs inputs) : _inputs = inputs;

  final String name;
  final List<String> log;
  final StreamController<LiveSessionStatus> statusController =
      StreamController<LiveSessionStatus>.broadcast();
  final StreamController<LiveDeliveryResult> resultController =
      StreamController<LiveDeliveryResult>.broadcast();

  LiveInputs _inputs;
  LiveSessionStatus _current = const LiveSessionStatus();
  bool disposed = false;
  int frames = 0;
  int relearned = 0;
  int acknowledged = 0;
  final List<LiveInputs> inputHistory = <LiveInputs>[];

  @override
  Stream<LiveSessionStatus> get status => statusController.stream;

  @override
  Stream<LiveDeliveryResult> get results => resultController.stream;

  @override
  LiveSessionStatus get current => _current;

  @override
  LiveInputs get inputs => _inputs;

  void emitStatus(LiveSessionStatus status) {
    _current = status;
    statusController.add(status);
  }

  @override
  void updateInputs(LiveInputs inputs) {
    _inputs = inputs;
    inputHistory.add(inputs);
  }

  @override
  void onFrame(RawCameraFrame frame) {
    frames += 1;
  }

  @override
  void relearn() => relearned += 1;

  @override
  void acknowledgeSceneChange() => acknowledged += 1;

  @override
  Future<void> dispose() async {
    log.add('$name.dispose');
    disposed = true;
    await statusController.close();
    await resultController.close();
  }
}
