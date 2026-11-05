import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:gully_umpire/cv/util/json_read.dart';

/// A 2D point or vector. In image space `x` grows to the right and `y` grows
/// downwards, both normalised to 0..1 across the frame.
final class Point2D extends Equatable {
  const Point2D(this.x, this.y);

  /// Parses `{x, y}`.
  factory Point2D.fromJson(Map<String, Object?> json) =>
      Point2D(readDouble(json, 'x'), readDouble(json, 'y'));

  /// The origin.
  static const Point2D zero = Point2D(0, 0);

  final double x;
  final double y;

  Point2D operator +(Point2D other) => Point2D(x + other.x, y + other.y);

  Point2D operator -(Point2D other) => Point2D(x - other.x, y - other.y);

  Point2D operator *(double scale) => Point2D(x * scale, y * scale);

  Point2D operator /(double divisor) => Point2D(x / divisor, y / divisor);

  /// Euclidean length of this point seen as a vector.
  double get length => math.sqrt(x * x + y * y);

  /// Angle of this vector in radians (`atan2(y, x)`).
  double get angle => math.atan2(y, x);

  /// False when either coordinate is NaN or infinite.
  bool get isFinite => x.isFinite && y.isFinite;

  double distanceTo(Point2D other) {
    final double dx = x - other.x;
    final double dy = y - other.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  double dot(Point2D other) => x * other.x + y * other.y;

  /// Z component of the 3D cross product: `x * o.y - y * o.x`.
  double cross(Point2D other) => x * other.y - y * other.x;

  /// Unit vector in the same direction; the zero vector stays zero.
  Point2D normalized() {
    final double len = length;
    if (len < 1e-12) {
      return Point2D.zero;
    }
    return Point2D(x / len, y / len);
  }

  /// `this` at `t = 0`, [other] at `t = 1`.
  Point2D lerp(Point2D other, double t) =>
      Point2D(x + (other.x - x) * t, y + (other.y - y) * t);

  /// Counter-clockwise rotation (in a y-up frame) by [radians] about the origin.
  Point2D rotated(double radians) {
    final double c = math.cos(radians);
    final double s = math.sin(radians);
    return Point2D(x * c - y * s, x * s + y * c);
  }

  Map<String, Object?> toJson() => <String, Object?>{'x': x, 'y': y};

  @override
  List<Object?> get props => <Object?>[x, y];

  @override
  String toString() => 'Point2D(${x.toStringAsFixed(4)}, ${y.toStringAsFixed(4)})';
}
