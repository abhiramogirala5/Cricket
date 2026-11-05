import 'dart:typed_data';

import 'package:gully_umpire/cv/tracking/ball_track_point.dart';

/// Fixed-capacity ring buffer of ball positions (spec §11 "Required ball
/// trajectory buffer"). Typed arrays, O(1) insert, no per-frame allocation and
/// no growth during long matches. When full, the oldest point is overwritten.
final class TrajectoryRingBuffer {
  TrajectoryRingBuffer(this.capacity)
      : assert(capacity > 0, 'capacity must be positive'),
        _timestamps = Float64List(capacity),
        _xs = Float64List(capacity),
        _ys = Float64List(capacity),
        _confidences = Float64List(capacity);

  /// Maximum number of points kept.
  final int capacity;

  final Float64List _timestamps;
  final Float64List _xs;
  final Float64List _ys;
  final Float64List _confidences;
  int _start = 0;
  int _count = 0;

  /// Number of points currently stored.
  int get size => _count;

  bool get isEmpty => _count == 0;

  bool get isFull => _count == capacity;

  /// Appends a point, overwriting the oldest when full.
  void push(int timestampMs, double x, double y, double confidence) {
    final int index = (_start + _count) % capacity;
    _timestamps[index] = timestampMs.toDouble();
    _xs[index] = x;
    _ys[index] = y;
    _confidences[index] = confidence;
    if (_count < capacity) {
      _count += 1;
    } else {
      _start = (_start + 1) % capacity;
    }
  }

  /// Appends [point].
  void add(BallTrackPoint point) => push(point.timestampMs, point.x, point.y, point.confidence);

  /// The point [offset] places after the oldest, or null when out of range.
  BallTrackPoint? getAt(int offset) {
    if (offset < 0 || offset >= _count) {
      return null;
    }
    final int index = (_start + offset) % capacity;
    return BallTrackPoint(
      timestampMs: _timestamps[index].toInt(),
      x: _xs[index],
      y: _ys[index],
      confidence: _confidences[index],
    );
  }

  /// The oldest point, or null when empty.
  BallTrackPoint? get first => getAt(0);

  /// The newest point, or null when empty.
  BallTrackPoint? get last => getAt(_count - 1);

  /// Copies the stored points, oldest first.
  List<BallTrackPoint> toList() {
    final List<BallTrackPoint> result = <BallTrackPoint>[];
    for (int i = 0; i < _count; i++) {
      final BallTrackPoint? point = getAt(i);
      if (point != null) {
        result.add(point);
      }
    }
    return result;
  }

  /// Forgets every point (the memory is reused).
  void clear() {
    _start = 0;
    _count = 0;
  }
}
