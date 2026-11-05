import 'package:gully_umpire/cv/geometry/point2d.dart';

/// The index of the corner of [corners] closest to [at] (all in 0..1 picture coordinates), or
/// `null` when none is within [maxDistance].
int? nearestCorner(List<Point2D> corners, Point2D at, {double maxDistance = 0.12}) {
  int? best;
  double bestDistance = maxDistance;
  for (int i = 0; i < corners.length; i++) {
    final double distance = corners[i].distanceTo(at);
    if (distance <= bestDistance) {
      bestDistance = distance;
      best = i;
    }
  }
  return best;
}

double _unit(double value) {
  if (value.isNaN) {
    return 0.0;
  }
  return value < 0 ? 0.0 : (value > 1 ? 1.0 : value);
}

/// A copy of [corners] with corner [index] moved to [to] (kept inside the picture).
List<Point2D> movedCorner(List<Point2D> corners, int index, Point2D to) {
  return <Point2D>[
    for (int i = 0; i < corners.length; i++)
      if (i == index) Point2D(_unit(to.x), _unit(to.y)) else corners[i],
  ];
}

/// A copy of [corners] moved as a whole by [dx], [dy] (stopping at the edge of the picture so
/// the shape never changes).
List<Point2D> shiftedCorners(List<Point2D> corners, double dx, double dy) {
  if (corners.isEmpty) {
    return corners;
  }
  double minX = corners.first.x;
  double maxX = corners.first.x;
  double minY = corners.first.y;
  double maxY = corners.first.y;
  for (final Point2D corner in corners) {
    minX = corner.x < minX ? corner.x : minX;
    maxX = corner.x > maxX ? corner.x : maxX;
    minY = corner.y < minY ? corner.y : minY;
    maxY = corner.y > maxY ? corner.y : maxY;
  }
  final double sx = dx < -minX ? -minX : (dx > 1 - maxX ? 1 - maxX : dx);
  final double sy = dy < -minY ? -minY : (dy > 1 - maxY ? 1 - maxY : dy);
  return <Point2D>[for (final Point2D corner in corners) Point2D(corner.x + sx, corner.y + sy)];
}
