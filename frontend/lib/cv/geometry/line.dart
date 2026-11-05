import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:gully_umpire/cv/geometry/point2d.dart';
import 'package:gully_umpire/cv/util/math_utils.dart';

/// Below this magnitude a cross product is treated as zero (parallel lines).
const double _parallelEpsilon = 1e-12;

/// A straight segment between two points.
final class LineSegment extends Equatable {
  const LineSegment(this.a, this.b);

  final Point2D a;
  final Point2D b;

  double get length => a.distanceTo(b);

  /// Unit direction from [a] to [b] (zero for a degenerate segment).
  Point2D get direction => (b - a).normalized();

  /// `a` at `t = 0`, `b` at `t = 1`.
  Point2D pointAt(double t) => a.lerp(b, t);

  /// Closest point on the segment to [p].
  Point2D closestPointTo(Point2D p) {
    final Point2D ab = b - a;
    final double lenSq = ab.dot(ab);
    if (lenSq < _parallelEpsilon) {
      return a;
    }
    final double t = clamp01((p - a).dot(ab) / lenSq);
    return a.lerp(b, t);
  }

  double distanceToPoint(Point2D p) => closestPointTo(p).distanceTo(p);

  /// Crossing point with [other], or null when they do not touch or are parallel.
  Point2D? intersection(LineSegment other) {
    final Point2D r = b - a;
    final Point2D s = other.b - other.a;
    final double denom = r.cross(s);
    if (denom.abs() < _parallelEpsilon) {
      return null;
    }
    final Point2D qp = other.a - a;
    final double t = qp.cross(s) / denom;
    final double u = qp.cross(r) / denom;
    if (t < 0 || t > 1 || u < 0 || u > 1) {
      return null;
    }
    return a + r * t;
  }

  @override
  List<Object?> get props => <Object?>[a, b];

  @override
  String toString() => 'LineSegment($a -> $b)';
}

/// A half-line starting at [origin] and heading along [direction]
/// (any non-zero length; `pointAt(t)` is `origin + direction * t`).
final class Ray2D extends Equatable {
  const Ray2D(this.origin, this.direction);

  /// A ray from [from] through [through].
  factory Ray2D.through(Point2D from, Point2D through) => Ray2D(from, (through - from).normalized());

  final Point2D origin;
  final Point2D direction;

  Point2D pointAt(double t) => origin + direction * t;

  /// A copy turned by [radians] around [origin].
  Ray2D rotated(double radians) => Ray2D(origin, direction.rotated(radians));

  /// Smallest `t` in `0..maxT` at which the ray touches [segment], or null.
  double? intersectSegment(LineSegment segment, {double maxT = double.infinity}) {
    final Point2D e = segment.b - segment.a;
    final double denom = direction.cross(e);
    if (denom.abs() < _parallelEpsilon) {
      return null;
    }
    final Point2D ao = segment.a - origin;
    final double t = ao.cross(e) / denom;
    final double u = ao.cross(direction) / denom;
    if (t < 0 || t > maxT || u < 0 || u > 1) {
      return null;
    }
    return t;
  }

  @override
  List<Object?> get props => <Object?>[origin, direction];

  @override
  String toString() => 'Ray2D($origin, $direction)';
}

/// Result of a least-squares straight-line fit through timed points.
final class LineFit2D extends Equatable {
  const LineFit2D({
    required this.origin,
    required this.velocity,
    required this.residual,
    required this.originTimeMs,
    required this.pointCount,
  });

  /// Fitted position at [originTimeMs].
  final Point2D origin;

  /// Fitted velocity in normalised units per second.
  final Point2D velocity;

  /// Root-mean-square distance of the points from the fitted line.
  final double residual;

  /// Time the fit is anchored at.
  final int originTimeMs;

  final int pointCount;

  /// Fitted position at [timestampMs].
  Point2D positionAt(int timestampMs) =>
      origin + velocity * ((timestampMs - originTimeMs) / 1000.0);

  @override
  List<Object?> get props => <Object?>[origin, velocity, residual, originTimeMs, pointCount];
}

/// Least-squares fit of `position(t) = origin + velocity * t` through
/// ([timestampsMs], [points]). Returns null with fewer than two points or when
/// every timestamp is the same.
LineFit2D? fitLineOverTime(List<int> timestampsMs, List<Point2D> points) {
  final int n = points.length;
  if (n < 2 || timestampsMs.length != n) {
    return null;
  }
  final int t0 = timestampsMs.first;
  double sumT = 0;
  double sumX = 0;
  double sumY = 0;
  for (int i = 0; i < n; i++) {
    sumT += (timestampsMs[i] - t0) / 1000.0;
    sumX += points[i].x;
    sumY += points[i].y;
  }
  final double meanT = sumT / n;
  final double meanX = sumX / n;
  final double meanY = sumY / n;
  double sTT = 0;
  double sTX = 0;
  double sTY = 0;
  for (int i = 0; i < n; i++) {
    final double dt = (timestampsMs[i] - t0) / 1000.0 - meanT;
    sTT += dt * dt;
    sTX += dt * (points[i].x - meanX);
    sTY += dt * (points[i].y - meanY);
  }
  if (sTT < 1e-12) {
    return null;
  }
  final double vx = sTX / sTT;
  final double vy = sTY / sTT;
  final double x0 = meanX - vx * meanT;
  final double y0 = meanY - vy * meanT;
  double sumSq = 0;
  for (int i = 0; i < n; i++) {
    final double t = (timestampsMs[i] - t0) / 1000.0;
    final double ex = points[i].x - (x0 + vx * t);
    final double ey = points[i].y - (y0 + vy * t);
    sumSq += ex * ex + ey * ey;
  }
  return LineFit2D(
    origin: Point2D(x0, y0),
    velocity: Point2D(vx, vy),
    residual: math.sqrt(sumSq / n),
    originTimeMs: t0,
    pointCount: n,
  );
}
