import 'package:equatable/equatable.dart';
import 'package:gully_umpire/cv/geometry/point2d.dart';
import 'package:gully_umpire/cv/util/json_read.dart';
import 'package:gully_umpire/cv/util/math_utils.dart';

/// An axis-aligned box. Coordinates are normalised 0..1 across the frame
/// (`x`, `y` is the top-left corner). The JSON keys are exactly
/// `x, y, width, height` as required by the API `bounding_box` field.
final class BoundingBox extends Equatable {
  const BoundingBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  factory BoundingBox.fromLTRB(double left, double top, double right, double bottom) =>
      BoundingBox(x: left, y: top, width: right - left, height: bottom - top);

  factory BoundingBox.fromCenter({
    required double centerX,
    required double centerY,
    required double width,
    required double height,
  }) =>
      BoundingBox(x: centerX - width / 2, y: centerY - height / 2, width: width, height: height);

  /// Smallest box containing every point. Throws [StateError] when empty.
  factory BoundingBox.enclosing(Iterable<Point2D> points) {
    double? left;
    double? top;
    double? right;
    double? bottom;
    for (final Point2D p in points) {
      left = left == null || p.x < left ? p.x : left;
      top = top == null || p.y < top ? p.y : top;
      right = right == null || p.x > right ? p.x : right;
      bottom = bottom == null || p.y > bottom ? p.y : bottom;
    }
    if (left == null || top == null || right == null || bottom == null) {
      throw StateError('Cannot build a BoundingBox from no points');
    }
    return BoundingBox.fromLTRB(left, top, right, bottom);
  }

  /// Parses `{x, y, width, height}`.
  factory BoundingBox.fromJson(Map<String, Object?> json) => BoundingBox(
        x: readDouble(json, 'x'),
        y: readDouble(json, 'y'),
        width: readDouble(json, 'width'),
        height: readDouble(json, 'height'),
      );

  /// The whole frame.
  static const BoundingBox unit = BoundingBox(x: 0, y: 0, width: 1, height: 1);

  final double x;
  final double y;
  final double width;
  final double height;

  double get left => x;
  double get top => y;
  double get right => x + width;
  double get bottom => y + height;
  double get centerX => x + width / 2;
  double get centerY => y + height / 2;
  Point2D get center => Point2D(centerX, centerY);

  /// Area, never negative.
  double get area => (width > 0 && height > 0) ? width * height : 0;

  /// True when the box has no area.
  bool get isEmpty => !(width > 0 && height > 0);

  /// True when the whole box lies inside the unit square (with a tiny tolerance).
  bool get isNormalised =>
      left >= -1e-9 && top >= -1e-9 && right <= 1 + 1e-9 && bottom <= 1 + 1e-9;

  bool containsPoint(Point2D p) => p.x >= left && p.x <= right && p.y >= top && p.y <= bottom;

  /// Overlapping part, or null when the boxes do not overlap.
  BoundingBox? intersection(BoundingBox other) {
    final double l = left > other.left ? left : other.left;
    final double t = top > other.top ? top : other.top;
    final double r = right < other.right ? right : other.right;
    final double b = bottom < other.bottom ? bottom : other.bottom;
    if (r <= l || b <= t) {
      return null;
    }
    return BoundingBox.fromLTRB(l, t, r, b);
  }

  /// Intersection over union, 0 when disjoint.
  double iou(BoundingBox other) {
    final BoundingBox? overlap = intersection(other);
    if (overlap == null) {
      return 0;
    }
    final double inter = overlap.area;
    final double union = area + other.area - inter;
    if (union <= 0) {
      return 0;
    }
    return inter / union;
  }

  /// Smallest box containing both boxes.
  BoundingBox union(BoundingBox other) => BoundingBox.fromLTRB(
        left < other.left ? left : other.left,
        top < other.top ? top : other.top,
        right > other.right ? right : other.right,
        bottom > other.bottom ? bottom : other.bottom,
      );

  /// Grows the box by [dx] on the left and right and [dy] (default [dx]) on the
  /// top and bottom. Negative values shrink it.
  BoundingBox inflate(double dx, [double? dy]) {
    final double vertical = dy ?? dx;
    return BoundingBox.fromLTRB(left - dx, top - vertical, right + dx, bottom + vertical);
  }

  /// This box clipped to the unit square (may become empty).
  BoundingBox clampedToUnit() => BoundingBox.fromLTRB(
        clamp01(left),
        clamp01(top),
        clamp01(right),
        clamp01(bottom),
      );

  /// Distance from [p] to the box (0 when inside).
  double distanceToPoint(Point2D p) {
    final double dx = p.x < left ? left - p.x : (p.x > right ? p.x - right : 0);
    final double dy = p.y < top ? top - p.y : (p.y > bottom ? p.y - bottom : 0);
    return Point2D(dx, dy).length;
  }

  /// Corners in the order top-left, top-right, bottom-right, bottom-left.
  List<Point2D> toPolygon() => <Point2D>[
        Point2D(left, top),
        Point2D(right, top),
        Point2D(right, bottom),
        Point2D(left, bottom),
      ];

  Map<String, Object?> toJson() => <String, Object?>{
        'x': x,
        'y': y,
        'width': width,
        'height': height,
      };

  @override
  List<Object?> get props => <Object?>[x, y, width, height];

  @override
  String toString() =>
      'BoundingBox(x: ${x.toStringAsFixed(4)}, y: ${y.toStringAsFixed(4)}, '
      'w: ${width.toStringAsFixed(4)}, h: ${height.toStringAsFixed(4)})';
}
