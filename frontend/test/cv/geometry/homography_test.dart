import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/cv/geometry/homography.dart';
import 'package:gully_umpire/cv/geometry/point2d.dart';

void main() {
  group('HomographyMatrix', () {
    test('identity matrix preserves coordinates', () {
      const HomographyMatrix h = HomographyMatrix.identity;
      const Point2D p = Point2D(0.45, 0.65);
      final Point2D projected = h.project(p);
      expect(projected.x, closeTo(p.x, 1e-6));
      expect(projected.y, closeTo(p.y, 1e-6));
    });

    test('reconstructs metric pitch plane coordinates from 4 perspective corners', () {
      // Perspective trapezoid representing a pitch viewed from behind bowler:
      // Front width = 0.40, Back width = 0.16
      const List<Point2D> src = <Point2D>[
        Point2D(0.30, 0.85), // front-left
        Point2D(0.70, 0.85), // front-right
        Point2D(0.58, 0.45), // back-right (stumps)
        Point2D(0.42, 0.45), // back-left (stumps)
      ];

      // Metric ground plane (X: meters from pitch centerline, Y: meters down pitch)
      // Pitch width = 3.05m, Pitch length = 20.12m
      const List<Point2D> dst = <Point2D>[
        Point2D(-1.525, 0.0),
        Point2D(1.525, 0.0),
        Point2D(1.525, 20.12),
        Point2D(-1.525, 20.12),
      ];

      final HomographyMatrix? h = HomographyMatrix.from4Points(src: src, dst: dst);
      expect(h, isNotNull);

      // Verify that all 4 source corners map exactly to their destination metric coordinates
      for (int i = 0; i < 4; i++) {
        final Point2D mapped = h!.project(src[i]);
        expect(mapped.x, closeTo(dst[i].x, 0.01), reason: 'Corner $i X failed');
        expect(mapped.y, closeTo(dst[i].y, 0.01), reason: 'Corner $i Y failed');
      }

      // Mid-pitch point projection (centerline X should remain ~0.0)
      const Point2D centerScreen = Point2D(0.50, 0.65);
      final Point2D centerMetric = h!.project(centerScreen);
      expect(centerMetric.x, closeTo(0.0, 0.05));
      expect(centerMetric.y, inInclusiveRange(5.0, 15.0));
    });

    test('returns null for fewer than 4 points', () {
      final HomographyMatrix? h = HomographyMatrix.from4Points(
        src: const <Point2D>[Point2D(0, 0), Point2D(1, 0)],
        dst: const <Point2D>[Point2D(0, 0), Point2D(1, 0)],
      );
      expect(h, isNull);
    });
  });
}

