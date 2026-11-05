import 'package:equatable/equatable.dart';
import 'package:gully_umpire/cv/geometry/bounding_box.dart';
import 'package:gully_umpire/cv/geometry/line.dart';
import 'package:gully_umpire/cv/geometry/point2d.dart';
import 'package:gully_umpire/cv/util/json_read.dart';

/// A simple polygon (the visible target of a wicket, a bat zone, ...).
final class Polygon extends Equatable {
  /// Copies [vertices]; the polygon is implicitly closed.
  Polygon(List<Point2D> vertices) : vertices = List<Point2D>.unmodifiable(vertices);

  /// The four corners of [box].
  factory Polygon.fromBox(BoundingBox box) => Polygon(box.toPolygon());

  /// The convex hull of [points] (may have fewer than 3 vertices for
  /// degenerate input; check [isValid]).
  factory Polygon.convexHullOf(Iterable<Point2D> points) => Polygon(convexHull(points));

  /// Parses a JSON array of `{x, y}` objects.
  factory Polygon.fromJson(List<Object?> json) => Polygon(
        json.map<Point2D>((Object? e) => Point2D.fromJson(asStringMap(e))).toList(),
      );

  final List<Point2D> vertices;

  int get length => vertices.length;

  /// True for a non-degenerate polygon: at least 3 vertices and a real area.
  bool get isValid => vertices.length >= 3 && area > 1e-12;

  /// Shoelace signed area (sign depends on winding and on the y direction).
  double get signedArea {
    final int n = vertices.length;
    if (n < 3) {
      return 0;
    }
    double sum = 0;
    for (int i = 0; i < n; i++) {
      final Point2D a = vertices[i];
      final Point2D b = vertices[(i + 1) % n];
      sum += a.x * b.y - b.x * a.y;
    }
    return sum / 2;
  }

  double get area => signedArea.abs();

  /// Area centroid; the mean of the vertices for degenerate polygons; the
  /// origin for an empty one.
  Point2D get centroid {
    final int n = vertices.length;
    if (n == 0) {
      return Point2D.zero;
    }
    final double a = signedArea;
    if (n < 3 || a.abs() < 1e-12) {
      double sx = 0;
      double sy = 0;
      for (final Point2D v in vertices) {
        sx += v.x;
        sy += v.y;
      }
      return Point2D(sx / n, sy / n);
    }
    double cx = 0;
    double cy = 0;
    for (int i = 0; i < n; i++) {
      final Point2D p = vertices[i];
      final Point2D q = vertices[(i + 1) % n];
      final double f = p.x * q.y - q.x * p.y;
      cx += (p.x + q.x) * f;
      cy += (p.y + q.y) * f;
    }
    return Point2D(cx / (6 * a), cy / (6 * a));
  }

  /// Smallest axis-aligned box around the polygon. Throws [StateError] when empty.
  BoundingBox get bounds => BoundingBox.enclosing(vertices);

  List<LineSegment> get edges {
    final int n = vertices.length;
    final List<LineSegment> result = <LineSegment>[];
    if (n < 2) {
      return result;
    }
    for (int i = 0; i < n; i++) {
      result.add(LineSegment(vertices[i], vertices[(i + 1) % n]));
    }
    return result;
  }

  /// Even-odd containment test.
  bool containsPoint(Point2D p) {
    final int n = vertices.length;
    if (n < 3) {
      return false;
    }
    bool inside = false;
    for (int i = 0, j = n - 1; i < n; j = i++) {
      final Point2D a = vertices[i];
      final Point2D b = vertices[j];
      if ((a.y > p.y) != (b.y > p.y)) {
        final double xAtY = (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x;
        if (p.x < xAtY) {
          inside = !inside;
        }
      }
    }
    return inside;
  }

  /// Distance from [p] to the polygon: 0 when inside, otherwise the distance to
  /// the nearest edge. Infinity for an empty polygon.
  double distanceToPoint(Point2D p) {
    if (containsPoint(p)) {
      return 0;
    }
    double best = double.infinity;
    for (final LineSegment edge in edges) {
      final double d = edge.distanceToPoint(p);
      if (d < best) {
        best = d;
      }
    }
    return best;
  }

  /// Smallest `t` in `0..maxT` at which [ray] enters or touches the polygon
  /// (0 when the ray starts inside), or null when it never does.
  double? firstRayHit(Ray2D ray, {double maxT = double.infinity}) {
    if (containsPoint(ray.origin)) {
      return 0;
    }
    double? best;
    for (final LineSegment edge in edges) {
      final double? t = ray.intersectSegment(edge, maxT: maxT);
      if (t != null && (best == null || t < best)) {
        best = t;
      }
    }
    return best;
  }

  /// A copy pushed outwards by about [amount] (each vertex moves along the
  /// direction from the centroid). Exact for regular shapes, a good
  /// approximation for the small convex targets used here.
  Polygon inflated(double amount) {
    final Point2D c = centroid;
    return Polygon(
      vertices.map<Point2D>((Point2D v) {
        final Point2D out = (v - c).normalized();
        return v + out * amount;
      }).toList(),
    );
  }

  List<Object?> toJson() => vertices.map<Object?>((Point2D v) => v.toJson()).toList();

  @override
  List<Object?> get props => <Object?>[vertices];

  @override
  String toString() => 'Polygon(${vertices.length} vertices)';
}

/// Convex hull (Andrew's monotone chain) of [input], returned without a
/// repeated first vertex. Fewer than 3 distinct points are returned as is.
List<Point2D> convexHull(Iterable<Point2D> input) {
  final List<Point2D> sorted = List<Point2D>.of(input);
  sorted.sort((Point2D a, Point2D b) {
    final int byX = a.x.compareTo(b.x);
    return byX != 0 ? byX : a.y.compareTo(b.y);
  });
  final List<Point2D> unique = <Point2D>[];
  for (final Point2D p in sorted) {
    if (unique.isEmpty || unique.last != p) {
      unique.add(p);
    }
  }
  if (unique.length < 3) {
    return unique;
  }
  final List<Point2D> hull = <Point2D>[];
  for (final Point2D p in unique) {
    while (hull.length >= 2 && _turn(hull[hull.length - 2], hull[hull.length - 1], p) <= 0) {
      hull.removeLast();
    }
    hull.add(p);
  }
  final int lowerSize = hull.length + 1;
  for (int i = unique.length - 2; i >= 0; i--) {
    final Point2D p = unique[i];
    while (hull.length >= lowerSize && _turn(hull[hull.length - 2], hull[hull.length - 1], p) <= 0) {
      hull.removeLast();
    }
    hull.add(p);
  }
  hull.removeLast();
  return hull;
}

double _turn(Point2D o, Point2D a, Point2D b) => (a - o).cross(b - o);
