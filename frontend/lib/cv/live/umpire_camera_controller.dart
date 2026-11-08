import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:gully_umpire/cv/geometry/point2d.dart';
import 'package:gully_umpire/cv/live/frame_source.dart';
import 'package:gully_umpire/cv/live/live_analysis.dart';
import 'package:gully_umpire/cv/live/live_session.dart';
import 'package:gully_umpire/cv/scene/optical_wicket_tracker.dart';
import 'package:gully_umpire/domain/decisions/wicket_family.dart';
import 'package:gully_umpire/features/live_camera/camera_distance.dart';

/// Opens the camera. Throws a [FrameSourceException] with a message for the person when it cannot.
typedef FrameSourceOpener = Future<FrameSource> Function();

/// Starts the tracker for a new camera run.
typedef LiveSessionOpener = Future<LiveSessionPort> Function(LiveInputs inputs);

/// Keeps the screen on (`true`) or lets it sleep again (`false`).
typedef KeepAwake = Future<void> Function(bool enabled);

/// What the camera is doing.
enum CameraPhase {
  /// Nothing is open.
  idle,

  /// The camera and the tracker are starting.
  starting,

  /// Pictures are being followed.
  running,

  /// The camera or the tracker could not be started; see [UmpireCameraController.error].
  failed,
}

/// Owns one run of the live umpire camera: the camera, the tracker that follows the ball, and
/// the screen wake lock, and tells the screen what is going on.
///
/// Screens create one with [FrameSourceOpener] and [LiveSessionOpener] (the phone versions are in
/// `live_providers.dart`), call [start] when they appear and [stop] (or let the controller be
/// disposed) when they leave. Delivery results arrive on [results], which keeps working across
/// [stop] and [start], so a screen that is paused and resumed does not lose its listener.
final class UmpireCameraController extends ChangeNotifier {
  UmpireCameraController({
    required FrameSourceOpener openCamera,
    required LiveSessionOpener openSession,
    required LiveInputs inputs,
    KeepAwake? keepAwake,
    double? initialZoom,
  })  : _openCamera = openCamera,
        _openSession = openSession,
        _inputs = inputs,
        _keepAwake = keepAwake,
        _initialZoom = initialZoom;

  final FrameSourceOpener _openCamera;
  final LiveSessionOpener _openSession;
  final KeepAwake? _keepAwake;
  double? _initialZoom;
  final StreamController<LiveDeliveryResult> _results =
      StreamController<LiveDeliveryResult>.broadcast();

  LiveInputs _inputs;
  CameraPhase _phase = CameraPhase.idle;
  String? _error;
  String? _streamProblem;
  LiveSessionStatus _status = const LiveSessionStatus();
  FrameSource? _camera;
  LiveSessionPort? _session;
  StreamSubscription<LiveSessionStatus>? _statusSub;
  StreamSubscription<LiveDeliveryResult>? _resultSub;
  int _generation = 0;
  bool _disposed = false;

  /// Completes when the latest [start] attempt has finished (opened, failed or given up).
  Future<void>? _opening;

  CameraPhase get phase => _phase;

  bool get isRunning => _phase == CameraPhase.running;

  /// Why the camera could not start (plain words), when [phase] is [CameraPhase.failed].
  String? get error => _error;

  /// The latest status of the tracker (the empty status while nothing runs).
  LiveSessionStatus get status => _status;

  /// A problem the person should know about: a camera problem first, then the tracker's own.
  String? get problem => _streamProblem ?? _status.problem;

  /// The camera that is open (for the preview), or null.
  FrameSource? get source => _camera;

  LiveInputs get inputs => _inputs;

  /// The zoom that is set (or will be set when the camera opens).
  double get zoom => _camera?.zoom ?? _initialZoom ?? 1;

  double get minZoom => _camera?.minZoom ?? 1;

  double get maxZoom => _camera?.maxZoom ?? 1;

  /// One result per delivery that was followed.
  Stream<LiveDeliveryResult> get results => _results.stream;

  /// Runs optical computer vision to detect the true physical boundaries of stumps / chairs.
  OpticalWicketResult detectOrRefineWicket({
    Point2D? searchCenter,
    WicketFamily family = WicketFamily.traditionalStumps,
    double? targetDistanceFeet,
    double zoom = 1.0,
  }) {
    final LiveSessionPort? session = _session;
    if (session == null) {
      return OpticalWicketResult(
        corners: smartWicketCorners(
          family: family,
          centerX: searchCenter?.x ?? 0.50,
          groundY: searchCenter?.y ?? 0.65,
          targetDistanceFeet: targetDistanceFeet,
          zoom: zoom,
        ),
        confidence: 0.50,
        isOpticallyRefined: false,
        family: family,
        statusMessage: 'Aligned with pitch corridor (${family.label})',
      );
    }
    return session.detectOrRefineWicket(
      searchCenter: searchCenter,
      family: family,
      targetDistanceFeet: targetDistanceFeet,
      zoom: zoom,
    );
  }

  /// Locks spatial anchor tracking so that camera motion keeps the polygon fixed on the physical object.
  void lockSpatialAnchor(List<Point2D> corners) {
    _session?.lockSpatialAnchor(corners);
  }

  /// Unlocks spatial anchor tracking (e.g. while the user is actively dragging corner handles).
  void unlockSpatialAnchor() {
    _session?.unlockSpatialAnchor();
  }

  /// Opens the camera and the tracker. Does nothing when they are already open or opening.
  Future<void> start() async {
    if (_disposed || _phase == CameraPhase.starting || _phase == CameraPhase.running) {
      return;
    }
    final int generation = ++_generation;
    _phase = CameraPhase.starting;
    _error = null;
    _streamProblem = null;
    _status = const LiveSessionStatus();
    notifyListeners();

    // A phone camera can only be opened once. When an earlier attempt was cancelled by [stop]
    // while it was still opening, it has to finish releasing the camera before this one opens it.
    final Future<void> earlier = _opening ?? Future<void>.value();
    final Completer<void> finished = Completer<void>();
    _opening = finished.future;
    try {
      await earlier;
      if (_isStale(generation)) {
        return;
      }
      await _open(generation);
    } finally {
      finished.complete();
    }
  }

  Future<void> _open(int generation) async {
    LiveSessionPort? session;
    FrameSource? camera;
    StreamSubscription<LiveSessionStatus>? statusSub;
    StreamSubscription<LiveDeliveryResult>? resultSub;
    Future<void> abandon() async {
      await statusSub?.cancel();
      await resultSub?.cancel();
      await _release(camera, session);
    }

    try {
      final LiveSessionPort openedSession = await _openSession(_inputs);
      session = openedSession;
      if (_isStale(generation)) {
        await abandon();
        return;
      }
      final FrameSource openedCamera = await _openCamera();
      camera = openedCamera;
      if (_isStale(generation)) {
        await abandon();
        return;
      }
      final double? wanted = _initialZoom;
      if (wanted != null) {
        await openedCamera.setZoom(wanted);
      }
      statusSub = openedSession.status.listen(_onStatus);
      resultSub = openedSession.results.listen(_onResult);
      await openedCamera.start(openedSession.onFrame, onProblem: _onCameraProblem);
      if (_isStale(generation)) {
        await abandon();
        return;
      }
      _statusSub = statusSub;
      _resultSub = resultSub;
      _camera = openedCamera;
      _session = openedSession;
      // The match facts may have changed while the camera was opening.
      openedSession.updateInputs(_inputs);
      _phase = CameraPhase.running;
      await _setAwake(true);
      _notify();
    } on Object catch (error) {
      await abandon();
      if (generation == _generation && !_disposed) {
        _phase = CameraPhase.failed;
        _error = _describe(error);
        _notify();
      }
    }
  }

  bool _isStale(int generation) => _disposed || generation != _generation;

  /// Closes the camera and the tracker. [start] opens them again.
  ///
  /// Listeners are told first (so a screen stops showing the preview) and the camera is released
  /// afterwards.
  Future<void> stop() async {
    final _Detached detached = _detach();
    if (!_disposed) {
      _phase = CameraPhase.idle;
      _error = null;
      _streamProblem = null;
      _status = const LiveSessionStatus();
      notifyListeners();
    }
    await _finish(detached);
  }

  /// The zoom to set the next time the camera opens (the zoom the stumps were marked at).
  void setStartZoom(double? zoom) {
    _initialZoom = zoom;
  }

  /// Replaces the match facts the tracker uses (the batter changed, the stumps were marked
  /// again, ...). Safe to call at any time.
  void updateInputs(LiveInputs inputs) {
    _inputs = inputs;
    _session?.updateInputs(inputs);
  }

  /// Sets the zoom and returns the value that was set.
  Future<double> setZoom(double level) async {
    final FrameSource? camera = _camera;
    if (camera == null) {
      return zoom;
    }
    final double applied = await camera.setZoom(level);
    _notify();
    return applied;
  }

  /// Makes the tracker learn the scene again (after the phone was moved on purpose).
  void relearn() => _session?.relearn();

  /// Says that the person has looked at the stumps after the scene changed.
  void acknowledgeSceneChange() => _session?.acknowledgeSceneChange();

  void _onStatus(LiveSessionStatus status) {
    _status = status;
    _notify();
  }

  void _onResult(LiveDeliveryResult result) {
    if (!_results.isClosed) {
      _results.add(result);
    }
  }

  void _onCameraProblem(String message) {
    _streamProblem = message;
    _notify();
  }

  /// Takes the running camera and tracker out of use at once (so nothing can reach them any more)
  /// and hands them back to be released by [_finish].
  _Detached _detach() {
    _generation += 1;
    final _Detached detached = _Detached(_camera, _session, _statusSub, _resultSub);
    _camera = null;
    _session = null;
    _statusSub = null;
    _resultSub = null;
    return detached;
  }

  Future<void> _finish(_Detached detached) async {
    await detached.statusSub?.cancel();
    await detached.resultSub?.cancel();
    await _release(detached.camera, detached.session);
    await _setAwake(false);
  }

  /// Closes what was opened, camera first so that no more pictures arrive.
  Future<void> _release(FrameSource? camera, LiveSessionPort? session) async {
    try {
      await camera?.dispose();
    } on Object catch (error) {
      debugPrint('Closing the camera failed: $error');
    }
    try {
      await session?.dispose();
    } on Object catch (error) {
      debugPrint('Closing the tracker failed: $error');
    }
  }

  Future<void> _setAwake(bool enabled) async {
    final KeepAwake? keepAwake = _keepAwake;
    if (keepAwake == null) {
      return;
    }
    try {
      await keepAwake(enabled);
    } on Object catch (error) {
      debugPrint('Keeping the screen awake failed: $error');
    }
  }

  static String _describe(Object error) {
    if (error is FrameSourceException) {
      return error.message;
    }
    if (error is StateError) {
      return error.message;
    }
    return 'The camera could not be started ($error).';
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    unawaited(_finish(_detach()).whenComplete(_results.close));
    super.dispose();
  }
}

/// What [UmpireCameraController._detach] took out of use.
final class _Detached {
  const _Detached(this.camera, this.session, this.statusSub, this.resultSub);

  final FrameSource? camera;
  final LiveSessionPort? session;
  final StreamSubscription<LiveSessionStatus>? statusSub;
  final StreamSubscription<LiveDeliveryResult>? resultSub;
}
