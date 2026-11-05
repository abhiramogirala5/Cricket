import 'dart:math' as math;
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:gully_umpire/cv/live/frame_clock.dart';
import 'package:gully_umpire/cv/live/frame_ring.dart';
import 'package:gully_umpire/cv/live/replay_codec.dart';
import 'package:gully_umpire/cv/pipelines/ball_observation.dart';
import 'package:gully_umpire/cv/tracking/multi_ball_tracker.dart';
import 'package:gully_umpire/cv/vision/background_model.dart';
import 'package:gully_umpire/cv/vision/luma_frame.dart';
import 'package:gully_umpire/cv/vision/motion_ball_detector.dart';

/// Tuning of the [LiveTracker].
final class LiveTrackerConfig extends Equatable {
  const LiveTrackerConfig({
    this.minPoints = 6,
    this.minQuality = 0.25,
    this.maxShrinkRatio = 0.90,
    this.minPathLength = 0.08,
    this.minDeliverySpeed = 0.12,
    this.maxDirectionReversals = 1,
    this.maxBallDiameter = 0.12,
    this.endQuietMs = 500,
    this.maxDeliveryMs = 5000,
    this.cooldownMs = 1200,
    this.preRollMs = 400,
    this.postRollMs = 500,
    this.replayBudgetBytes = 24 * 1024 * 1024,
    this.maxReplayFrames = 150,
    this.detector = const MotionDetectorConfig(),
    this.tracker = const MultiTrackerConfig(),
  });

  /// Fewest ball points before a path can count as a delivery.
  final int minPoints;

  /// Lowest path quality (0..1) that can count as a delivery.
  final double minQuality;

  /// A delivery flies away from a camera behind the bowler, so the ball looks smaller at the end
  /// than at the start: last size divided by first size must be at most this.
  final double maxShrinkRatio;

  /// The ball must travel at least this far across the picture (picture units).
  final double minPathLength;

  /// Minimum delivery speed in normalized picture units per second.
  /// Rejects slow hand drift and body sway (< 0.12 units/sec) while allowing slow spin.
  final double minDeliverySpeed;

  /// Maximum horizontal direction reversals allowed in the trajectory.
  /// High-frequency hand tremor oscillates left-and-right (>= 2 reversals), whereas
  /// a bowled ball moves unidirectionally across the frame.
  final int maxDirectionReversals;

  /// Maximum ball candidate diameter as a fraction of picture height.
  /// Rejects close-up hands, arms, or passing bodies (> 0.12 frame height).
  final double maxBallDiameter;

  /// A delivery is over when no ball-like path has moved for this long.
  final int endQuietMs;

  /// Longest time one delivery is followed.
  final int maxDeliveryMs;

  /// Time after a delivery during which nothing new is started (the follow-through, the fielder).
  final int cooldownMs;

  /// The replay starts this long before the first ball point ...
  final int preRollMs;

  /// ... and ends this long after the last one.
  final int postRollMs;

  /// Memory reserved for the pictures of the last few seconds.
  final int replayBudgetBytes;

  final int maxReplayFrames;

  final MotionDetectorConfig detector;
  final MultiTrackerConfig tracker;

  @override
  List<Object?> get props => <Object?>[
        minPoints,
        minQuality,
        maxShrinkRatio,
        minPathLength,
        minDeliverySpeed,
        maxDirectionReversals,
        maxBallDiameter,
        endQuietMs,
        maxDeliveryMs,
        cooldownMs,
        preRollMs,
        postRollMs,
        replayBudgetBytes,
        maxReplayFrames,
        detector,
        tracker,
      ];
}

/// What the tracker is doing right now.
enum LiveWatchState {
  /// Learning the empty scene (just started, or the camera moved).
  learning,

  /// Waiting for a ball to be thrown.
  watching,

  /// A delivery is being followed.
  tracking,

  /// A delivery has just finished.
  cooldown,
}

/// One delivery as the camera saw it: everything [interpretDelivery] needs from the pictures.
final class LiveDeliveryCapture {
  const LiveDeliveryCapture({
    required this.observations,
    required this.frameTimesMs,
    required this.aspectRatio,
    required this.framesProcessed,
    required this.frameWidth,
    required this.frameHeight,
    required this.trackQuality,
    required this.startMs,
    required this.endMs,
  });

  /// The accepted ball positions, oldest first (picture units; the diameter is a share of the height).
  final List<BallObservation> observations;

  /// Times of the frames in which the ball could have been seen (for the hit rate).
  final List<int> frameTimesMs;

  final double aspectRatio;

  /// Frames analysed since the previous delivery.
  final int framesProcessed;

  /// Size of the analysed pictures.
  final int frameWidth;
  final int frameHeight;

  /// 0..1 how much the chosen path looks like a thrown ball.
  final double trackQuality;

  /// First and last ball time.
  final int startMs;
  final int endMs;

  /// Enough points and quality to be worth interpreting.
  bool get isUsable => observations.length >= 6 && trackQuality >= 0.3;
}

/// What happened in one frame (also used to draw the live overlay).
final class LiveFrameReport {
  const LiveFrameReport({
    required this.timestampMs,
    required this.state,
    required this.candidates,
    required this.trail,
    required this.fps,
    required this.noise,
    required this.threshold,
    required this.foregroundFraction,
    this.capture,
  });

  final int timestampMs;
  final LiveWatchState state;

  /// Ball-like patches in this frame.
  final List<BallObservation> candidates;

  /// The most promising ball path so far (oldest first, at most a dozen points).
  final List<BallObservation> trail;

  /// Measured camera frame rate.
  final double fps;

  final double noise;
  final int threshold;
  final double foregroundFraction;

  /// Set in the frame in which a delivery has just ended.
  final LiveDeliveryCapture? capture;
}

/// Watches a stream of pictures from a fixed camera and cuts out every delivery.
///
/// Everything here is plain Dart that works on one picture at a time. Per picture it
///
/// 1. locks the frame time to the camera's real rate ([FrameClock]),
/// 2. stores the picture in a ring for the replay ([FrameRing]),
/// 3. finds ball-like moving patches ([MotionBallDetector]),
/// 4. follows several candidate paths at once ([MultiBallTracker]),
/// 5. decides when a delivery starts and ends and hands it over as a [LiveDeliveryCapture].
///
/// It runs in a background isolate on the phone (see `VisionWorker`), but it has no dependency on
/// Flutter, so it is tested on any machine.
final class LiveTracker {
  LiveTracker({this.config = const LiveTrackerConfig(), double nominalFps = 30})
      : _detector = MotionBallDetector(config: config.detector),
        _tracker = MultiBallTracker(config: config.tracker),
        _clock = FrameClock(nominalIntervalMs: 1000 / nominalFps);

  /// A path must have moved at least this far (picture units) to be drawn as the ball's trail.
  static const double _minTrailPath = 0.02;

  final LiveTrackerConfig config;
  final MotionBallDetector _detector;
  final MultiBallTracker _tracker;
  final FrameClock _clock;

  FrameRing? _ring;
  final List<int> _frameTimes = <int>[];
  LiveWatchState _state = LiveWatchState.learning;
  int _startedMs = 0;
  int _cooldownUntilMs = 0;
  int _framesSinceDelivery = 0;
  int _width = 0;
  int _height = 0;

  /// When false, deliveries are not detected or captured (for example while marking the wicket).
  bool _deliveryTrackingEnabled = true;
  bool _needsArmClear = false;
  int _armedAtMs = 0;

  bool get deliveryTrackingEnabled => _deliveryTrackingEnabled;

  set deliveryTrackingEnabled(bool enabled) {
    if (_deliveryTrackingEnabled == enabled) {
      return;
    }
    _deliveryTrackingEnabled = enabled;
    if (enabled) {
      _needsArmClear = true;
    } else {
      _armedAtMs = 0;
      _tracker.clearPaths();
      if (_state == LiveWatchState.tracking) {
        _state = LiveWatchState.watching;
      }
    }
  }

  LiveWatchState get state => _state;

  /// Forgets the scene and every path (for example when the camera is restarted).
  void reset() {
    _detector.reset();
    _tracker.reset();
    _clock.reset();
    _ring?.clear();
    _frameTimes.clear();
    _state = LiveWatchState.learning;
    _framesSinceDelivery = 0;
    _needsArmClear = false;
    _armedAtMs = 0;
  }

  /// Processes the next picture. [frame] carries the raw arrival time of the picture.
  LiveFrameReport process(LumaFrame frame) {
    final int time = _clock.regularise(frame.timestampMs);
    if (_needsArmClear) {
      _needsArmClear = false;
      _tracker.clearPaths();
      _framesSinceDelivery = 0;
      // 150ms settling guard to isolate and ignore physical phone tap vibration
      _armedAtMs = time + 150;
      _state = LiveWatchState.watching;
    }
    if (!_deliveryTrackingEnabled) {
      _tracker.clearPaths();
    }
    final LumaFrame clocked = LumaFrame(
      width: frame.width,
      height: frame.height,
      timestampMs: time,
      pixels: frame.pixels,
    );
    _width = frame.width;
    _height = frame.height;
    _store(clocked);

    final MotionDetection detection = _detector.process(clocked);
    if (detection.state != BackgroundState.ok) {
      if (detection.state == BackgroundState.restarted) {
        _tracker.clearPaths();
        _state = LiveWatchState.learning;
      } else if (_state != LiveWatchState.cooldown && _state != LiveWatchState.tracking) {
        _state = LiveWatchState.learning;
      }
      return _report(time, detection, const <BallObservation>[], null);
    }
    if (_state == LiveWatchState.learning) {
      _state = LiveWatchState.watching;
    }

    _framesSinceDelivery += 1;
    _frameTimes.add(time);
    while (_frameTimes.isNotEmpty && time - _frameTimes.first > 8000) {
      _frameTimes.removeAt(0);
    }

    int gap = (2.2 * _clock.periodMs).round();
    gap = gap < 100 ? 100 : (gap > 400 ? 400 : gap);
    _tracker.gapMs = gap;
    _tracker.step(time, detection.candidates);

    LiveDeliveryCapture? capture;
    switch (_state) {
      case LiveWatchState.cooldown:
        if (time >= _cooldownUntilMs) {
          _state = LiveWatchState.watching;
        }
      case LiveWatchState.watching:
        if (deliveryTrackingEnabled) {
          final TrackedBall? best = _bestDelivery();
          if (best != null) {
            _state = LiveWatchState.tracking;
            _startedMs = best.observations.first.timestampMs;
          }
        }
      case LiveWatchState.tracking:
        final int idleSince = _lastActivityMs();
        if (time - idleSince >= config.endQuietMs || time - _startedMs >= config.maxDeliveryMs) {
          capture = _finish(time);
        }
      case LiveWatchState.learning:
        _state = LiveWatchState.watching;
    }
    return _report(time, detection, _trail(), capture);
  }

  /// Packs the pictures around [capture] into a replay file, or null when no picture is stored.
  ///
  /// Call it right after the frame that produced the capture: the ring is overwritten by later
  /// frames.
  Uint8List? encodeReplay(LiveDeliveryCapture capture) {
    final FrameRing? ring = _ring;
    if (ring == null) {
      return null;
    }
    final List<LumaFrame> frames = ring.window(
      capture.startMs - config.preRollMs,
      capture.endMs + config.postRollMs,
    );
    if (frames.isEmpty) {
      return null;
    }
    final List<LumaFrame> limited = frames.length > ReplayCodec.maxFrames
        ? frames.sublist(frames.length - ReplayCodec.maxFrames)
        : frames;
    return ReplayCodec.encode(limited);
  }

  void _store(LumaFrame frame) {
    FrameRing? ring = _ring;
    if (ring == null || ring.width != frame.width || ring.height != frame.height) {
      final int fit = FrameRing.capacityFor(
        maxBytes: config.replayBudgetBytes,
        width: frame.width,
        height: frame.height,
      );
      ring = FrameRing(
        capacity: math.min(fit, config.maxReplayFrames),
        width: frame.width,
        height: frame.height,
      );
      _ring = ring;
    }
    ring.push(frame);
  }

  /// The best path that flies like a thrown ball, or null.
  TrackedBall? _bestDelivery() {
    bool anyLong = false;
    for (final BallHypothesis h in _tracker.active) {
      if (h.records.length >= config.minPoints) {
        anyLong = true;
        break;
      }
    }
    if (!anyLong) {
      return null;
    }
    return _tracker.best(
      minPoints: config.minPoints,
      minQuality: config.minQuality,
      accept: _looksLikeDelivery,
    );
  }

  bool _looksLikeDelivery(List<BallObservation> observations) {
    if (observations.length < config.minPoints) {
      return false;
    }
    final BallObservation first = observations.first;
    final BallObservation last = observations.last;
    if (_armedAtMs > 0 && first.timestampMs < _armedAtMs) {
      return false;
    }
    if (!(first.diameter > 0) || last.diameter / first.diameter > config.maxShrinkRatio) {
      return false;
    }
    // Reject close-up hand, arm, or body blobs that exceed the maximum ball size.
    for (final BallObservation o in observations) {
      if (o.diameter > config.maxBallDiameter) {
        return false;
      }
    }
    // Pitch corridor constraint: deliveries are bowled down the corridor towards the wicket.
    // Exclude extreme frame borders (trees, roadside bystanders) and sky.
    if (first.x < 0.10 || first.x > 0.90 || last.x < 0.10 || last.x > 0.90) {
      return false;
    }
    if (first.y < 0.10 && last.y < 0.10) {
      return false;
    }
    final double netDx = last.x - first.x;
    final double netDy = last.y - first.y;

    // Dropped item rejection: an object falling straight down right near the camera
    // without significant forward shrink or horizontal travel is a dropped item.
    if (netDy > 0.35 && netDx.abs() < 0.04) {
      return false;
    }
    final double netDisplacement = math.sqrt(netDx * netDx + netDy * netDy);
    if (netDisplacement < config.minPathLength) {
      return false;
    }
    // Reject slow handheld sway or wandering objects via metric speed floor.
    final int dtMs = last.timestampMs - first.timestampMs;
    if (dtMs <= 0) {
      return false;
    }
    final double speedUnitsPerSec = netDisplacement / (dtMs / 1000.0);
    if (speedUnitsPerSec < config.minDeliverySpeed) {
      return false;
    }
    final double path = _pathLength(observations);
    if (path <= 0 || netDisplacement / path < 0.60) {
      return false;
    }
    // Reject physiological hand shake & tremor: handheld tremor oscillates back and forth
    // horizontally, whereas a bowled ball travels unidirectionally towards the wickets.
    int horizontalReversals = 0;
    double lastDx = 0;
    for (int i = 1; i < observations.length; i++) {
      final double dx = observations[i].x - observations[i - 1].x;
      if (dx.abs() > 0.003) {
        if (lastDx != 0 && (dx > 0) != (lastDx > 0)) {
          horizontalReversals++;
        }
        lastDx = dx;
      }
    }
    if (horizontalReversals > config.maxDirectionReversals) {
      return false;
    }
    return true;
  }

  /// How far the ball travelled across the picture along [observations] (picture units).
  static double _pathLength(List<BallObservation> observations) {
    double path = 0;
    for (int i = 1; i < observations.length; i++) {
      final double dx = observations[i].x - observations[i - 1].x;
      final double dy = observations[i].y - observations[i - 1].y;
      path += math.sqrt(dx * dx + dy * dy);
    }
    return path;
  }

  /// The latest time at which any path that flies like a delivery still moved.
  int _lastActivityMs() {
    int latest = _startedMs;
    for (final BallHypothesis h in <BallHypothesis>[..._tracker.active, ..._tracker.finished]) {
      if (h.lastTimestampMs > latest &&
          h.records.length >= config.minPoints &&
          _looksLikeDelivery(h.records)) {
        latest = h.lastTimestampMs;
      }
    }
    return latest;
  }

  LiveDeliveryCapture? _finish(int time) {
    final TrackedBall? best = _tracker.best(
      minPoints: config.minPoints,
      minQuality: config.minQuality,
      accept: _looksLikeDelivery,
    );
    LiveDeliveryCapture? capture;
    if (best != null) {
      final List<BallObservation> observations = best.observations;
      final int startMs = observations.first.timestampMs;
      final int endMs = observations.last.timestampMs;
      final List<int> times = <int>[
        for (final int t in _frameTimes)
          if (t >= startMs && t <= endMs) t,
      ];
      capture = LiveDeliveryCapture(
        observations: observations,
        frameTimesMs: times,
        aspectRatio: _height == 0 ? 16 / 9 : _width / _height,
        framesProcessed: _framesSinceDelivery,
        frameWidth: _width,
        frameHeight: _height,
        trackQuality: best.quality,
        startMs: startMs,
        endMs: endMs,
      );
    }
    _tracker.clearPaths();
    _framesSinceDelivery = 0;
    if (capture != null && capture.isUsable) {
      _state = LiveWatchState.cooldown;
      _cooldownUntilMs = time + config.cooldownMs;
      return capture;
    }
    // No usable delivery was found: false trigger or transient noise.
    // Return to watching without announcing "Ball finished" or locking into cooldown.
    _state = LiveWatchState.watching;
    return null;
  }

  /// The most promising live path, for the overlay.
  List<BallObservation> _trail() {
    BallHypothesis? chosen;
    double chosenQuality = 0.1;
    for (final BallHypothesis h in _tracker.active) {
      // Something that stays where it is (a head, a post) is not drawn as a ball path.
      if (h.records.length < 3 || _pathLength(h.records) < _minTrailPath) {
        continue;
      }
      final double q = h.quality();
      if (q > chosenQuality) {
        chosen = h;
        chosenQuality = q;
      }
    }
    if (chosen == null) {
      return const <BallObservation>[];
    }
    final List<BallObservation> records = chosen.records;
    final int from = records.length > 12 ? records.length - 12 : 0;
    return List<BallObservation>.of(records.sublist(from));
  }

  LiveFrameReport _report(
    int time,
    MotionDetection detection,
    List<BallObservation> trail,
    LiveDeliveryCapture? capture,
  ) {
    return LiveFrameReport(
      timestampMs: time,
      state: _state,
      candidates: detection.candidates,
      trail: trail,
      fps: _clock.fps,
      noise: detection.noise,
      threshold: detection.threshold,
      foregroundFraction: detection.foregroundFraction,
      capture: capture,
    );
  }
}
