import 'dart:async';

import 'package:gully_umpire/cv/contracts/audio_analyzer.dart';
import 'package:gully_umpire/cv/contracts/pose.dart';
import 'package:gully_umpire/cv/geometry/polygon.dart';
import 'package:gully_umpire/cv/live/batter_pose_estimator.dart';
import 'package:gully_umpire/cv/live/live_analysis.dart';
import 'package:gully_umpire/cv/live/live_tracker.dart';
import 'package:gully_umpire/cv/live/pose_buffer.dart';
import 'package:gully_umpire/cv/live/vision_protocol.dart';
import 'package:gully_umpire/cv/live/vision_worker.dart';
import 'package:gully_umpire/cv/live/zoom_advice.dart';
import 'package:gully_umpire/cv/pipelines/ball_observation.dart';
import 'package:gully_umpire/cv/pipelines/pose_sample.dart';
import 'package:gully_umpire/domain/decisions/wicket_family.dart';
import 'package:gully_umpire/features/live_camera/camera_distance.dart';

/// What the live camera is doing right now (for the overlay and the status line).
final class LiveSessionStatus {
  const LiveSessionStatus({
    this.watch = LiveWatchState.learning,
    this.fps = 0,
    this.latencyMs = 0,
    this.framesAnalysed = 0,
    this.framesDropped = 0,
    this.pictureWidth = 0,
    this.pictureHeight = 0,
    this.candidates = const <BallObservation>[],
    this.trail = const <BallObservation>[],
    this.poseSeen = false,
    this.zoom = const ZoomAdvice(level: FramingLevel.unknown, message: 'Waiting for the camera.'),
    this.sceneChanged = false,
    this.problem,
    this.deliveries = 0,
    this.batterHeightM,
  });

  final LiveWatchState watch;

  /// Pictures per second the camera really delivers.
  final double fps;

  /// Average time from handing a picture over to having its report (ms).
  final double latencyMs;

  final int framesAnalysed;
  final int framesDropped;

  /// Size of the analysed pictures (for placing the overlay).
  final int pictureWidth;
  final int pictureHeight;

  /// Ball-like patches in the latest picture.
  final List<BallObservation> candidates;

  /// The most promising ball path so far.
  final List<BallObservation> trail;

  /// The batter was measured within the last moments.
  final bool poseSeen;

  /// Whether the camera is close enough to the batter.
  final ZoomAdvice zoom;

  /// The picture changed so much that the scene had to be learned again: the phone may have been
  /// moved, so the marked stumps may no longer be where they were.
  final bool sceneChanged;

  /// Something went wrong that the person should know about.
  final String? problem;

  /// Deliveries followed since the session started.
  final int deliveries;

  /// Real standing height of the detected batter (metres), estimated from perspective or profile.
  final double? batterHeightM;

  /// The tracker is ready to see a delivery.
  bool get isWatching => watch == LiveWatchState.watching || watch == LiveWatchState.tracking;

  LiveSessionStatus copyWith({
    LiveWatchState? watch,
    double? fps,
    double? latencyMs,
    int? framesAnalysed,
    int? framesDropped,
    int? pictureWidth,
    int? pictureHeight,
    List<BallObservation>? candidates,
    List<BallObservation>? trail,
    bool? poseSeen,
    ZoomAdvice? zoom,
    bool? sceneChanged,
    String? problem,
    bool clearProblem = false,
    int? deliveries,
    double? batterHeightM,
  }) {
    return LiveSessionStatus(
      watch: watch ?? this.watch,
      fps: fps ?? this.fps,
      latencyMs: latencyMs ?? this.latencyMs,
      framesAnalysed: framesAnalysed ?? this.framesAnalysed,
      framesDropped: framesDropped ?? this.framesDropped,
      pictureWidth: pictureWidth ?? this.pictureWidth,
      pictureHeight: pictureHeight ?? this.pictureHeight,
      candidates: candidates ?? this.candidates,
      trail: trail ?? this.trail,
      poseSeen: poseSeen ?? this.poseSeen,
      zoom: zoom ?? this.zoom,
      sceneChanged: sceneChanged ?? this.sceneChanged,
      problem: clearProblem ? null : (problem ?? this.problem),
      deliveries: deliveries ?? this.deliveries,
      batterHeightM: batterHeightM ?? this.batterHeightM,
    );
  }
}

/// What the camera controller needs from a live session (so tests can stand in for the real one).
abstract interface class LiveSessionPort {
  /// Status updates for the overlay.
  Stream<LiveSessionStatus> get status;

  /// One result per delivery that was followed.
  Stream<LiveDeliveryResult> get results;

  LiveSessionStatus get current;

  LiveInputs get inputs;

  /// Replaces the match facts (the batter changed, the wicket was marked again, ...).
  void updateInputs(LiveInputs inputs);

  /// Handles one camera picture.
  void onFrame(RawCameraFrame frame);

  /// Makes the tracker learn the scene again.
  void relearn();

  /// The person has checked the stumps after a scene change.
  void acknowledgeSceneChange();

  Future<void> dispose();
}

/// The live umpire camera: pictures in, deliveries and suggestions out.
///
/// It owns the background [VisionWorker] (which finds and follows the ball), measures the batter's
/// pose on the main isolate, and interprets every finished delivery with the same rules the rest
/// of the app uses. The camera itself is not part of this class: whoever owns the camera calls
/// [onFrame] for every picture.
final class LiveVisionSession implements LiveSessionPort {
  LiveVisionSession({
    required VisionWorker worker,
    required BatterPoseEstimator poseEstimator,
    required LiveInputs inputs,
    AudioAnalyzer? audioAnalyzer,
    this.uiIntervalMs = 66,
    this.poseIntervalMs = 200,
  })  : _worker = worker,
        _pose = poseEstimator,
        _audio = audioAnalyzer,
        _inputs = inputs {
    _reportSub = _worker.reports.listen(_onReport);
    _captureSub = _worker.captures.listen((DecodedCapture c) => unawaited(_onCapture(c)));
    _errorSub = _worker.errors.listen(_onWorkerError);
    _worker.setTrackingEnabled(_inputs.trackDeliveries);
  }

  /// Fewest milliseconds between two status updates.
  final int uiIntervalMs;

  /// Fewest milliseconds between two pose measurements.
  final int poseIntervalMs;

  final VisionWorker _worker;
  final BatterPoseEstimator _pose;
  final AudioAnalyzer? _audio;
  final PoseBuffer _poses = PoseBuffer();
  final StreamController<LiveSessionStatus> _statusController =
      StreamController<LiveSessionStatus>.broadcast();
  final StreamController<LiveDeliveryResult> _resultController =
      StreamController<LiveDeliveryResult>.broadcast();
  late final StreamSubscription<DecodedReport> _reportSub;
  late final StreamSubscription<DecodedCapture> _captureSub;
  late final StreamSubscription<String> _errorSub;

  LiveInputs _inputs;
  LiveSessionStatus _status = const LiveSessionStatus();
  bool _disposed = false;
  bool _poseBusy = false;
  bool _everWatching = false;
  int _lastPoseMs = -1000000;
  int _lastPoseOkMs = -1000000;
  int _lastFrameMs = 0;
  int _lastEmitMs = -1000000;
  int _reportsSinceProblem = 0;
  Future<void> _analysisQueue = Future<void>.value();

  /// Status updates (at most one every [uiIntervalMs], and at once when the state changes).
  @override
  Stream<LiveSessionStatus> get status => _statusController.stream;

  /// One result per delivery that was followed.
  @override
  Stream<LiveDeliveryResult> get results => _resultController.stream;

  @override
  LiveSessionStatus get current => _status;

  @override
  LiveInputs get inputs => _inputs;

  /// Replaces the match facts (the batter changed, the wicket was marked again, ...).
  @override
  void updateInputs(LiveInputs inputs) {
    _inputs = inputs;
    _worker.setTrackingEnabled(inputs.trackDeliveries);
  }

  /// Handles one camera picture. Cheap: it hands the brightness plane to the worker and, every
  /// [poseIntervalMs], starts a pose measurement.
  @override
  void onFrame(RawCameraFrame frame) {
    if (_disposed) {
      return;
    }
    _lastFrameMs = frame.timestampMs;
    _worker.offerFrame(
      yPlane: frame.yPlane,
      width: frame.width,
      height: frame.height,
      rowStride: frame.rowStride,
      rotationDegrees: frame.rotationDegrees,
      timestampMs: frame.timestampMs,
    );
    _maybeMeasurePose(frame);
  }

  /// Makes the tracker learn the scene again (and forgets that the scene changed).
  @override
  void relearn() {
    _worker.reset();
    _everWatching = false;
    _poses.clear();
    _status = _status.copyWith(sceneChanged: false, watch: LiveWatchState.learning);
    _emit(force: true);
  }

  /// The person has checked the stumps after a scene change.
  @override
  void acknowledgeSceneChange() {
    _status = _status.copyWith(sceneChanged: false);
    _emit(force: true);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _reportSub.cancel();
    await _captureSub.cancel();
    await _errorSub.cancel();
    await _worker.dispose();
    await _pose.close();
    await _audio?.dispose();
    await _statusController.close();
    await _resultController.close();
  }

  // ---- worker messages ---------------------------------------------------------------------

  void _onReport(DecodedReport decoded) {
    if (_disposed) {
      return;
    }
    final LiveFrameReport report = decoded.report;
    bool sceneChanged = _status.sceneChanged;
    if (report.state == LiveWatchState.learning) {
      if (_everWatching) {
        sceneChanged = true;
        _poses.clear();
        _everWatching = false;
      }
    } else {
      _everWatching = true;
    }
    final LiveWatchState watchState =
        _inputs.trackDeliveries ? report.state : LiveWatchState.watching;
    final bool stateChanged = watchState != _status.watch;
    if (_status.problem != null) {
      _reportsSinceProblem += 1;
    }
    final bool clearProblem = _status.problem != null && _reportsSinceProblem >= 60;
    final bool poseSeen = _lastFrameMs - _lastPoseOkMs < 2500;
    double? batterHeightM;
    if (poseSeen) {
      final PoseSample? latest = _poses.latest;
      final Polygon? wicket = _inputs.wicket;
      if (latest != null && wicket != null && wicket.isValid) {
        batterHeightM = estimateOpticalBatsmanHeightM(
          batterHeightNorm: latest.heightNorm,
          wicket: wicket,
          family: _inputs.wicketFamily ?? WicketFamily.traditionalStumps,
        );
      }
      batterHeightM ??= _inputs.batsmanHeightM > 0 ? _inputs.batsmanHeightM : null;
    }
    _status = _status.copyWith(
      watch: watchState,
      fps: report.fps,
      latencyMs: _worker.averageLatencyMs,
      framesAnalysed: _worker.processedFrames,
      framesDropped: _worker.droppedFrames,
      pictureWidth: decoded.width,
      pictureHeight: decoded.height,
      candidates: report.candidates,
      trail: report.trail,
      poseSeen: poseSeen,
      batterHeightM: batterHeightM,
      zoom: _zoomAdvice(decoded.height),
      sceneChanged: sceneChanged,
      clearProblem: clearProblem,
    );
    _emit(force: stateChanged);
  }

  void _onWorkerError(String message) {
    if (_disposed) {
      return;
    }
    _reportsSinceProblem = 0;
    _status = _status.copyWith(problem: message);
    _emit(force: true);
  }

  Future<void> _onCapture(DecodedCapture decoded) {
    if (!_inputs.trackDeliveries) {
      return Future<void>.value();
    }
    // One delivery at a time, in the order they were bowled.
    _analysisQueue = _analysisQueue.then((_) => _analyse(decoded));
    return _analysisQueue;
  }

  Future<void> _analyse(DecodedCapture decoded) async {
    if (_disposed || !decoded.capture.isUsable) {
      return;
    }
    try {
      // A picture that no longer matches the one the stumps were marked on means the phone may have
      // been moved: the stumps are less sure, and the entered distance to the batter is no longer
      // known to be right, so no speed is worked out.
      final LiveInputs effective = _status.sceneChanged
          ? _inputs.copyWith(wicketConfidence: 0.6, withoutDistance: true)
          : _inputs;
      final LiveDeliveryResult result = await analyseLiveDelivery(
        decoded: decoded,
        poses: _poses.window(decoded.capture.startMs - 2500, decoded.capture.endMs),
        inputs: effective,
        nowMs: _lastFrameMs,
        impulseLookup: _audio?.getRecentImpulses,
      );
      if (_disposed) {
        return;
      }
      _status = _status.copyWith(deliveries: _status.deliveries + 1);
      _resultController.add(result);
      _emit(force: true);
    } on Object catch (error) {
      if (_disposed) {
        return;
      }
      _status = _status.copyWith(problem: 'A delivery could not be analysed: $error');
      _reportsSinceProblem = 0;
      _emit(force: true);
    }
  }

  // ---- batter pose --------------------------------------------------------------------------

  void _maybeMeasurePose(RawCameraFrame frame) {
    final Polygon? wicket = _inputs.wicket;
    if (wicket == null || _poseBusy) {
      return;
    }
    // While the ball is in flight the processor is needed for tracking, and the stance measured
    // before the delivery is what counts.
    if (_status.watch == LiveWatchState.tracking || _status.watch == LiveWatchState.learning) {
      return;
    }
    if (frame.timestampMs - _lastPoseMs < poseIntervalMs) {
      return;
    }
    _poseBusy = true;
    _lastPoseMs = frame.timestampMs;
    unawaited(_measurePose(frame, wicket));
  }

  Future<void> _measurePose(RawCameraFrame frame, Polygon wicket) async {
    try {
      final PoseResult? pose = await _pose.estimate(frame, wicket);
      if (_disposed || pose == null) {
        return;
      }
      final PoseSample? sample = poseSampleFrom(pose, frame.timestampMs);
      if (sample != null) {
        _poses.add(sample);
        _lastPoseOkMs = frame.timestampMs;
      }
    } on Object catch (error) {
      if (!_disposed) {
        _status = _status.copyWith(problem: 'The batter could not be measured: $error');
        _reportsSinceProblem = 0;
      }
    } finally {
      _poseBusy = false;
    }
  }

  ZoomAdvice _zoomAdvice(int pictureHeight) {
    final PoseSample? latest = _poses.latest;
    if (latest == null || _lastFrameMs - latest.timestampMs > 3000) {
      return const ZoomAdvice(
        level: FramingLevel.unknown,
        message: 'Waiting to see the batter. Keep the whole batter and the stumps in the picture.',
      );
    }
    return ZoomAdvisor.advise(
      batterShare: latest.heightNorm,
      pictureHeightPx: pictureHeight,
      ballDiameterM: _inputs.ballKind.diameterM,
      batterHeightM: _inputs.batsmanHeightM,
    );
  }

  void _emit({bool force = false}) {
    if (_disposed || _statusController.isClosed) {
      return;
    }
    if (!force && _lastFrameMs - _lastEmitMs < uiIntervalMs) {
      return;
    }
    _lastEmitMs = _lastFrameMs;
    _statusController.add(_status);
  }
}
