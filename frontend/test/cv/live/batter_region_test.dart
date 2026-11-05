import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/cv/geometry/point2d.dart';
import 'package:gully_umpire/cv/geometry/polygon.dart';
import 'package:gully_umpire/cv/live/batter_region.dart';
import 'package:gully_umpire/cv/live/nv21_crop.dart';

Polygon box(double left, double top, double right, double bottom) => Polygon(<Point2D>[
      Point2D(left, top),
      Point2D(right, top),
      Point2D(right, bottom),
      Point2D(left, bottom),
    ]);

void main() {
  group('BatterRegion.forWicket', () {
    test('is centred on the wicket and reaches well above it', () {
      // Binary fractions, so that every number below is exact.
      final PixelRect? region = BatterRegion.forWicket(
        wicket: box(0.4375, 0.5, 0.5625, 0.625),
        uprightWidth: 320,
        uprightHeight: 640,
      );

      // Wicket 40 x 80 pixels centred at x = 160. Half width is max(2.5 * 40, 1.5 * 80) = 120.
      // Top is 320 - 4 * 80 = 0, bottom is 400 + 0.8 * 80 = 464.
      expect(region, const PixelRect(40, 0, 280, 464));
    });

    test('is limited to the picture', () {
      final PixelRect? region = BatterRegion.forWicket(
        wicket: box(0.25, 0.25, 0.75, 0.5),
        uprightWidth: 360,
        uprightHeight: 640,
      );

      expect(region, isNotNull);
      expect(region!.left, 0);
      expect(region.top, 0);
      expect(region.right, 360);
      expect(region.bottom, lessThanOrEqualTo(640));
    });

    test('a wicket marked as unusable gives no region', () {
      // Three points on a line have no area.
      final Polygon line = Polygon(const <Point2D>[
        Point2D(0.2, 0.2),
        Point2D(0.4, 0.4),
        Point2D(0.6, 0.6),
      ]);

      expect(BatterRegion.forWicket(wicket: line, uprightWidth: 360, uprightHeight: 640), isNull);
    });

    test('a wicket thinner than a pixel gives no region', () {
      final PixelRect? region = BatterRegion.forWicket(
        wicket: box(0.5, 0.5, 0.501, 0.7),
        uprightWidth: 360,
        uprightHeight: 640,
      );

      expect(region, isNull);
    });

    test('a region smaller than 32 pixels gives none', () {
      final PixelRect? region = BatterRegion.forWicket(
        wicket: box(0.25, 0.25, 0.75, 0.5),
        uprightWidth: 30,
        uprightHeight: 640,
      );

      expect(region, isNull);
    });

    test('a picture without a size gives none', () {
      final Polygon wicket = box(0.4, 0.4, 0.6, 0.6);

      expect(BatterRegion.forWicket(wicket: wicket, uprightWidth: 0, uprightHeight: 640), isNull);
      expect(BatterRegion.forWicket(wicket: wicket, uprightWidth: 360, uprightHeight: 0), isNull);
    });
  });
}
