import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/cv/geometry/geometry.dart';

void main() {
  group('Point2D', () {
    test('basic arithmetic', () {
      expect(const Point2D(3, 4).length, closeTo(5, 1e-12));
      expect(const Point2D(1, 2) + const Point2D(3, 4), const Point2D(4, 6));
      expect(const Point2D(3, 4) - const Point2D(1, 1), const Point2D(2, 3));
      expect(const Point2D(0, 0).lerp(const Point2D(10, 20), 0.25), const Point2D(2.5, 5));
    });

    test('rotation by a quarter turn', () {
      final Point2D rotated = const Point2D(1, 0).rotated(math.pi / 2);
      expect(rotated.x, closeTo(0, 1e-12));
      expect(rotated.y, closeTo(1, 1e-12));
    });

    test('JSON round trip', () {
      const Point2D point = Point2D(0.25, 0.75);
      expect(Point2D.fromJson(point.toJson()), point);
    });
  });

  group('BoundingBox', () {
    test('sides, centre and area', () {
      final BoundingBox box = BoundingBox.fromLTRB(0.1, 0.2, 0.5, 0.6);
      expect(box.width, closeTo(0.4, 1e-12));
      expect(box.height, closeTo(0.4, 1e-12));
      expect(box.area, closeTo(0.16, 1e-12));
      expect(box.center.x, closeTo(0.3, 1e-12));
      expect(box.center.y, closeTo(0.4, 1e-12));
    });

    test('intersection over union', () {
      const BoundingBox a = BoundingBox(x: 0, y: 0, width: 2, height: 2);
      const BoundingBox b = BoundingBox(x: 1, y: 0, width: 2, height: 2);
      expect(a.iou(a), closeTo(1, 1e-12));
      expect(a.iou(b), closeTo(1 / 3, 1e-12));
      expect(a.iou(const BoundingBox(x: 5, y: 5, width: 1, height: 1)), 0);
    });

    test('union and clamping', () {
      final BoundingBox union = BoundingBox.fromLTRB(0, 0, 1, 1).union(BoundingBox.fromLTRB(2, 2, 3, 3));
      expect(union, BoundingBox.fromLTRB(0, 0, 3, 3));
      final BoundingBox clamped = BoundingBox.fromLTRB(-0.2, -0.1, 1.3, 1.1).clampedToUnit();
      expect(clamped, BoundingBox.unit);
    });

    test('an empty box has no area', () {
      const BoundingBox empty = BoundingBox(x: 0.5, y: 0.5, width: 0, height: 0.2);
      expect(empty.isEmpty, isTrue);
      expect(empty.area, 0);
    });

    test('distance from a point', () {
      final BoundingBox box = BoundingBox.fromLTRB(0.2, 0.2, 0.4, 0.4);
      expect(box.distanceToPoint(const Point2D(0.3, 0.3)), 0);
      expect(box.distanceToPoint(const Point2D(0.7, 0.3)), closeTo(0.3, 1e-12));
    });

    test('JSON round trip', () {
      final BoundingBox box = BoundingBox.fromLTRB(0.1, 0.2, 0.5, 0.6);
      final BoundingBox restored = BoundingBox.fromJson(box.toJson());
      expect(restored.x, closeTo(box.x, 1e-12));
      expect(restored.width, closeTo(box.width, 1e-12));
    });
  });

  group('Polygon', () {
    final Polygon square = Polygon.fromBox(BoundingBox.fromLTRB(0, 0, 1, 1));

    test('area, centroid and validity', () {
      expect(square.area, closeTo(1, 1e-12));
      expect(square.centroid.x, closeTo(0.5, 1e-12));
      expect(square.centroid.y, closeTo(0.5, 1e-12));
      expect(square.isValid, isTrue);
      expect(Polygon(const <Point2D>[Point2D(0, 0), Point2D(1, 1)]).isValid, isFalse);
    });

    test('containment and distance', () {
      expect(square.containsPoint(const Point2D(0.5, 0.5)), isTrue);
      expect(square.containsPoint(const Point2D(1.5, 0.5)), isFalse);
      expect(square.distanceToPoint(const Point2D(0.5, 0.5)), 0);
      expect(square.distanceToPoint(const Point2D(2, 0.5)), closeTo(1, 1e-12));
    });

    test('a ray towards the polygon hits it at the right distance', () {
      final double? hit =
          square.firstRayHit(const Ray2D(Point2D(-1, 0.5), Point2D(1, 0)));
      expect(hit, isNotNull);
      expect(hit!, closeTo(1, 1e-9));
    });

    test('a ray pointing away never hits', () {
      expect(square.firstRayHit(const Ray2D(Point2D(-1, 0.5), Point2D(-1, 0))), isNull);
    });

    test('the convex hull drops interior points', () {
      final Polygon hull = Polygon.convexHullOf(const <Point2D>[
        Point2D(0, 0),
        Point2D(1, 0),
        Point2D(1, 1),
        Point2D(0, 1),
        Point2D(0.5, 0.5),
        Point2D(0.2, 0.7),
      ]);
      expect(hull.length, 4);
      expect(hull.area, closeTo(1, 1e-12));
    });

    test('inflating moves the outline outwards', () {
      final Polygon grown = square.inflated(0.1);
      expect(grown.area, greaterThan(square.area));
      expect(grown.containsPoint(const Point2D(-0.02, 0.5)), isTrue);
    });

    test('JSON round trip', () {
      final Polygon restored = Polygon.fromJson(square.toJson());
      expect(restored.vertices, square.vertices);
    });
  });

  group('lines', () {
    test('segments cross in the middle', () {
      final Point2D? cross = const LineSegment(Point2D(0, 0), Point2D(1, 1))
          .intersection(const LineSegment(Point2D(0, 1), Point2D(1, 0)));
      expect(cross, isNotNull);
      expect(cross!.x, closeTo(0.5, 1e-12));
      expect(cross.y, closeTo(0.5, 1e-12));
    });

    test('parallel segments do not cross', () {
      expect(
        const LineSegment(Point2D(0, 0), Point2D(1, 0))
            .intersection(const LineSegment(Point2D(0, 1), Point2D(1, 1))),
        isNull,
      );
    });

    test('a line fit recovers position and velocity', () {
      final LineFit2D? fit = fitLineOverTime(
        <int>[0, 100, 200, 300],
        const <Point2D>[Point2D(0.1, 0.2), Point2D(0.15, 0.2), Point2D(0.2, 0.2), Point2D(0.25, 0.2)],
      );
      expect(fit, isNotNull);
      expect(fit!.velocity.x, closeTo(0.5, 1e-9));
      expect(fit.velocity.y, closeTo(0, 1e-9));
      expect(fit.origin.x, closeTo(0.1, 1e-9));
      expect(fit.residual, closeTo(0, 1e-9));
      expect(fit.positionAt(500).x, closeTo(0.35, 1e-9));
    });

    test('a line fit needs two different times', () {
      expect(fitLineOverTime(<int>[0], const <Point2D>[Point2D(0, 0)]), isNull);
      expect(
        fitLineOverTime(<int>[5, 5], const <Point2D>[Point2D(0, 0), Point2D(1, 1)]),
        isNull,
      );
    });
  });

  group('ReferencePlane', () {
    final ReferencePlane plane = ReferencePlane.fromSubject(
      centerX: 0.5,
      groundY: 0.66,
      topY: 0.34,
      subjectHeightM: 1.7,
      aspectRatio: 16 / 9,
    );

    test('scales follow from the subject height', () {
      expect(plane.metersPerUnitY, closeTo(1.7 / 0.32, 1e-9));
      expect(plane.metersPerUnitX, closeTo(1.7 / 0.32 * 16 / 9, 1e-9));
    });

    test('converts between image and metres', () {
      expect(plane.lateralMeters(0.6), closeTo(0.1 * 1.7 / 0.32 * 16 / 9, 1e-9));
      expect(plane.heightMeters(0.5), closeTo(0.16 * 1.7 / 0.32, 1e-9));
      expect(plane.heightMeters(0.34), closeTo(1.7, 1e-9));
      expect(plane.xForLateralMeters(plane.lateralMeters(0.62)), closeTo(0.62, 1e-12));
      expect(plane.yForHeightMeters(1.7), closeTo(0.34, 1e-12));
    });

    test('moving the origin keeps the scale', () {
      final ReferencePlane moved = plane.withCenterX(0.7);
      expect(moved.lateralMeters(0.7), 0);
      expect(moved.metersPerUnitX, plane.metersPerUnitX);
    });

    test('rejects an impossible subject', () {
      expect(
        () => ReferencePlane.fromSubject(
          centerX: 0.5,
          groundY: 0.5,
          topY: 0.5,
          subjectHeightM: 1.7,
          aspectRatio: 1.7,
        ),
        throwsArgumentError,
      );
    });
  });
}
