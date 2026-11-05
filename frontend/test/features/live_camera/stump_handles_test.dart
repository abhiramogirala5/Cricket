import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/cv/geometry/point2d.dart';
import 'package:gully_umpire/features/live_camera/stump_handles.dart';

void main() {
  const List<Point2D> box = <Point2D>[
    Point2D(0.45, 0.35),
    Point2D(0.55, 0.35),
    Point2D(0.55, 0.65),
    Point2D(0.45, 0.65),
  ];

  group('nearestCorner', () {
    test('picks the corner closest to the touch', () {
      expect(nearestCorner(box, const Point2D(0.46, 0.36)), 0);
      expect(nearestCorner(box, const Point2D(0.56, 0.34)), 1);
      expect(nearestCorner(box, const Point2D(0.54, 0.66)), 2);
      expect(nearestCorner(box, const Point2D(0.40, 0.70)), 3);
    });

    test('is null when the touch is far from every corner', () {
      // The middle of the box is 0.158 from each corner, more than the 0.12 reach.
      expect(nearestCorner(box, const Point2D(0.5, 0.5)), isNull);
      expect(nearestCorner(box, const Point2D(0.05, 0.05)), isNull);
    });

    test('the reach can be changed', () {
      expect(nearestCorner(box, const Point2D(0.5, 0.5), maxDistance: 0.2), isNotNull);
      expect(nearestCorner(box, const Point2D(0.46, 0.36), maxDistance: 0.001), isNull);
    });

    test('no corners, no answer', () {
      expect(nearestCorner(const <Point2D>[], const Point2D(0.5, 0.5)), isNull);
    });
  });

  group('movedCorner', () {
    test('moves only the chosen corner and leaves the others alone', () {
      final List<Point2D> moved = movedCorner(box, 2, const Point2D(0.60, 0.70));
      expect(moved[0], box[0]);
      expect(moved[1], box[1]);
      expect(moved[2], const Point2D(0.60, 0.70));
      expect(moved[3], box[3]);
      expect(box[2], const Point2D(0.55, 0.65), reason: 'the original list is not changed');
    });

    test('keeps the corner inside the picture', () {
      final List<Point2D> moved = movedCorner(box, 0, const Point2D(-0.3, 1.7));
      expect(moved[0], const Point2D(0, 1));
    });

    test('a corner that is not a number goes to the edge instead of breaking the shape', () {
      final List<Point2D> moved = movedCorner(box, 1, const Point2D(double.nan, double.nan));
      expect(moved[1].isFinite, isTrue);
    });
  });

  group('shiftedCorners', () {
    test('moves the whole shape', () {
      final List<Point2D> moved = shiftedCorners(box, 0.1, -0.05);
      for (int i = 0; i < box.length; i++) {
        expect(moved[i].x, closeTo(box[i].x + 0.1, 1e-12));
        expect(moved[i].y, closeTo(box[i].y - 0.05, 1e-12));
      }
    });

    test('stops at the edge without squashing the shape', () {
      // The right edge is at 0.55, so at most 0.45 can be moved to the right.
      final List<Point2D> moved = shiftedCorners(box, 0.9, 0);
      expect(moved[1].x, closeTo(1.0, 1e-12));
      expect(moved[0].x, closeTo(0.9, 1e-12));
      // The top edge is at 0.35, so at most 0.35 can be moved up.
      final List<Point2D> up = shiftedCorners(box, 0, -0.9);
      expect(up[0].y, closeTo(0.0, 1e-12));
      expect(up[3].y, closeTo(0.30, 1e-12));
    });

    test('an empty shape stays empty', () {
      expect(shiftedCorners(const <Point2D>[], 0.1, 0.1), isEmpty);
    });
  });
}
