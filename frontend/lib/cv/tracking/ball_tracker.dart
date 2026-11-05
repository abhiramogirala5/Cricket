import 'package:equatable/equatable.dart';
import 'package:gully_umpire/cv/geometry/point2d.dart';
import 'package:gully_umpire/cv/tracking/ball_track_point.dart';
import 'package:gully_umpire/cv/tracking/trajectory_ring_buffer.dart';

/// Tuning of the [BallTracker]. All distances are normalised image units,
/// times are seconds unless a name ends in `Ms`.
final class BallTrackerConfig extends Equatable {
  const BallTrackerConfig({
    this.measurementNoise = 0.005,
    this.accelerationNoise = 20.0,
    this.initialVelocityStd = 2.0,
    this.gateChiSquare = 13.8,
    this.maxStepSpeed = 6.0,
    this.maxGapMs = 500,
    this.minConfidence = 0.2,
  });

  /// Standard deviation of a position measurement at confidence 1.
  final double measurementNoise;

  /// Process noise: how much the ball's velocity may change (units / s^2).
  /// Large on purpose, because bounces and bat/pad contact change it abruptly.
  final double accelerationNoise;

  /// Prior standard deviation of the velocity when a segment starts (units / s).
  final double initialVelocityStd;

  /// Mahalanobis (chi-square, 2 degrees of freedom) gate; 13.8 is the 99.9% point.
  final double gateChiSquare;

  /// Largest plausible ball speed in the image (units / s). Two consecutive
  /// outliers closer together than this start a new segment.
  final double maxStepSpeed;

  /// A silence longer than this ends the track and the next detection starts a new one.
  final int maxGapMs;

  /// Detections below this confidence are ignored.
  final double minConfidence;

  @override
  List<Object?> get props => <Object?>[
        measurementNoise,
        accelerationNoise,
        initialVelocityStd,
        gateChiSquare,
        maxStepSpeed,
        maxGapMs,
        minConfidence,
      ];
}

/// What [BallTracker.update] did with a measurement.
enum BallTrackStatus {
  /// First measurement of a (new) track.
  started,

  /// Measurement agreed with the prediction and was filtered in.
  accepted,

  /// Measurement was an outlier (or too weak) and was ignored.
  rejected,

  /// Two consistent measurements disagreed with the prediction, so the motion
  /// model was restarted (bounce, bat or pad contact).
  resegmented,
}

/// A small tracker for one ball: a constant-velocity Kalman filter with a
/// Mahalanobis outlier gate (spec §11).
///
/// The x and y axes are independent and share the same covariance, so the
/// 4x4 covariance of `[x, y, vx, vy]` reduces to one 2x2 block. The model is
/// not forced through a whole delivery: after two consecutive outliers that
/// agree with each other, the tracker restarts at the new motion (see
/// [BallTrackStatus.resegmented]).
final class BallTracker {
  BallTracker({this.config = const BallTrackerConfig(), int capacity = 512})
      : _buffer = TrajectoryRingBuffer(capacity);

  final BallTrackerConfig config;
  final TrajectoryRingBuffer _buffer;

  bool _hasTrack = false;
  int _lastMs = 0;
  double _x = 0;
  double _y = 0;
  double _vx = 0;
  double _vy = 0;
  // Shared 2x2 covariance [[_pp, _pv], [_pv, _vv]].
  double _pp = 0;
  double _pv = 0;
  double _vv = 0;

  // Last rejected measurement (candidate start of a new segment).
  bool _hasPending = false;
  int _pendingMs = 0;
  double _pendingX = 0;
  double _pendingY = 0;
  double _pendingConfidence = 0;

  int _acceptedCount = 0;
  int _rejectedCount = 0;
  int _segmentCount = 0;

  /// True once at least one measurement was accepted.
  bool get hasTrack => _hasTrack;

  /// Filtered position, or null without a track.
  Point2D? get position => _hasTrack ? Point2D(_x, _y) : null;

  /// Filtered velocity in units / s, or null without a track.
  Point2D? get velocity => _hasTrack ? Point2D(_vx, _vy) : null;

  /// Time of the last accepted measurement, or null without a track.
  int? get lastTimestampMs => _hasTrack ? _lastMs : null;

  /// Measurements accepted since the last [reset].
  int get acceptedCount => _acceptedCount;

  /// Measurements rejected as outliers since the last [reset].
  int get rejectedCount => _rejectedCount;

  /// Number of motion segments started (1 for a delivery without a bounce
  /// or contact, more after each re-segmentation or long gap).
  int get segmentCount => _segmentCount;

  /// The accepted, filtered points, oldest first (a copy).
  List<BallTrackPoint> get points => _buffer.toList();

  /// The newest accepted point, or null.
  BallTrackPoint? get latestPoint => _buffer.last;

  /// Predicted position at [timestampMs] (constant velocity), or null when
  /// there is no track or the gap exceeds [BallTrackerConfig.maxGapMs].
  Point2D? predictedPosition(int timestampMs) {
    if (!_hasTrack) {
      return null;
    }
    final int gapMs = timestampMs - _lastMs;
    if (gapMs < 0 || gapMs > config.maxGapMs) {
      return null;
    }
    final double dt = gapMs / 1000.0;
    return Point2D(_x + _vx * dt, _y + _vy * dt);
  }

  /// Squared Mahalanobis distance of a measurement at [timestampMs] from the
  /// prediction, or null when there is no usable prediction. Smaller is closer;
  /// compare with [BallTrackerConfig.gateChiSquare].
  double? gateDistanceSquared(int timestampMs, double x, double y, {double confidence = 1}) {
    final Point2D? predicted = predictedPosition(timestampMs);
    if (predicted == null) {
      return null;
    }
    final double dt = (timestampMs - _lastMs) / 1000.0;
    final double s = _predictedPositionVariance(dt) + _measurementVariance(confidence);
    final double dx = x - predicted.x;
    final double dy = y - predicted.y;
    return (dx * dx + dy * dy) / s;
  }

  /// Feeds one measurement.
  BallTrackStatus update({
    required int timestampMs,
    required double x,
    required double y,
    required double confidence,
  }) {
    if (confidence < config.minConfidence || !x.isFinite || !y.isFinite) {
      return BallTrackStatus.rejected;
    }
    if (!_hasTrack) {
      _beginSegment(timestampMs, x, y, confidence);
      return BallTrackStatus.started;
    }
    if (timestampMs <= _lastMs) {
      // Out of order or duplicate timestamp: ignore.
      return BallTrackStatus.rejected;
    }
    if (timestampMs - _lastMs > config.maxGapMs) {
      _hasPending = false;
      _beginSegment(timestampMs, x, y, confidence);
      return BallTrackStatus.started;
    }
    final double distance = gateDistanceSquared(timestampMs, x, y, confidence: confidence) ?? double.infinity;
    if (distance <= config.gateChiSquare) {
      _hasPending = false;
      _filterIn(timestampMs, x, y, confidence);
      return BallTrackStatus.accepted;
    }
    // Outlier. If the previous outlier is close enough in space and time the
    // ball has probably changed course; otherwise remember this one and wait.
    if (_hasPending && _isConsistentWithPending(timestampMs, x, y)) {
      final int startMs = _pendingMs;
      final double startX = _pendingX;
      final double startY = _pendingY;
      final double startConfidence = _pendingConfidence;
      _hasPending = false;
      _beginSegment(startMs, startX, startY, startConfidence);
      _filterIn(timestampMs, x, y, confidence);
      return BallTrackStatus.resegmented;
    }
    _hasPending = true;
    _pendingMs = timestampMs;
    _pendingX = x;
    _pendingY = y;
    _pendingConfidence = confidence;
    _rejectedCount += 1;
    return BallTrackStatus.rejected;
  }

  /// Forgets the track and every stored point.
  void reset() {
    _buffer.clear();
    _hasTrack = false;
    _hasPending = false;
    _lastMs = 0;
    _x = 0;
    _y = 0;
    _vx = 0;
    _vy = 0;
    _pp = 0;
    _pv = 0;
    _vv = 0;
    _acceptedCount = 0;
    _rejectedCount = 0;
    _segmentCount = 0;
  }

  bool _isConsistentWithPending(int timestampMs, double x, double y) {
    final double dt = (timestampMs - _pendingMs) / 1000.0;
    if (dt <= 0 || timestampMs - _pendingMs > config.maxGapMs) {
      return false;
    }
    final double dx = x - _pendingX;
    final double dy = y - _pendingY;
    final double distance = Point2D(dx, dy).length;
    return distance <= config.maxStepSpeed * dt;
  }

  double _measurementVariance(double confidence) {
    final double c = confidence < 0.1 ? 0.1 : confidence;
    return config.measurementNoise * config.measurementNoise / c;
  }

  double _predictedPositionVariance(double dt) {
    final double q = config.accelerationNoise * config.accelerationNoise;
    final double dt2 = dt * dt;
    return _pp + 2 * dt * _pv + dt2 * _vv + q * dt2 * dt2 / 4;
  }

  void _beginSegment(int timestampMs, double x, double y, double confidence) {
    _hasTrack = true;
    _lastMs = timestampMs;
    _x = x;
    _y = y;
    _vx = 0;
    _vy = 0;
    _pp = _measurementVariance(confidence);
    _pv = 0;
    _vv = config.initialVelocityStd * config.initialVelocityStd;
    _segmentCount += 1;
    _acceptedCount += 1;
    _buffer.push(timestampMs, x, y, confidence);
  }

  void _filterIn(int timestampMs, double x, double y, double confidence) {
    final double dt = (timestampMs - _lastMs) / 1000.0;
    final double q = config.accelerationNoise * config.accelerationNoise;
    final double dt2 = dt * dt;
    // Predict.
    final double px = _x + _vx * dt;
    final double py = _y + _vy * dt;
    final double ppp = _pp + 2 * dt * _pv + dt2 * _vv + q * dt2 * dt2 / 4;
    final double ppv = _pv + dt * _vv + q * dt2 * dt / 2;
    final double pvv = _vv + q * dt2;
    // Update.
    final double s = ppp + _measurementVariance(confidence);
    final double kp = ppp / s;
    final double kv = ppv / s;
    final double ix = x - px;
    final double iy = y - py;
    _x = px + kp * ix;
    _y = py + kp * iy;
    _vx = _vx + kv * ix;
    _vy = _vy + kv * iy;
    _pp = (1 - kp) * ppp;
    _pv = (1 - kp) * ppv;
    _vv = pvv - kv * ppv;
    _lastMs = timestampMs;
    _acceptedCount += 1;
    _buffer.push(timestampMs, _x, _y, confidence);
  }
}
