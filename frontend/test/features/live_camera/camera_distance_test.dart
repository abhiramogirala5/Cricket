import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/cv/geometry/point2d.dart';
import 'package:gully_umpire/cv/geometry/polygon.dart';
import 'package:gully_umpire/cv/pipelines/ball_observation.dart';
import 'package:gully_umpire/domain/decisions/wicket_family.dart';
import 'package:gully_umpire/features/live_camera/camera_distance.dart';

void main() {
  group('parseDistanceFeet', () {
    test('nothing typed is no distance and no problem', () {
      for (final String raw in <String>['', '   ']) {
        final DistanceEntry entry = parseDistanceFeet(raw);
        expect(entry.feet, isNull, reason: raw);
        expect(entry.problem, isNull, reason: raw);
        expect(entry.isValid, isTrue, reason: raw);
      }
    });

    test('reads whole and part feet', () {
      expect(parseDistanceFeet('45').feet, 45);
      expect(parseDistanceFeet(' 38.5 ').feet, 38.5);
      expect(parseDistanceFeet('45').isValid, isTrue);
    });

    test('the ends of the range are allowed', () {
      expect(parseDistanceFeet('10').feet, 10);
      expect(parseDistanceFeet('130').feet, 130);
    });

    test('too short or too long a distance is refused with the range in the words', () {
      for (final String raw in <String>['9.9', '3', '130.1', '500']) {
        final DistanceEntry entry = parseDistanceFeet(raw);
        expect(entry.feet, isNull, reason: raw);
        expect(entry.isValid, isFalse, reason: raw);
        expect(entry.problem, contains('Between 10 and 130 feet'), reason: raw);
      }
    });

    test('something that is not a number is refused', () {
      for (final String raw in <String>['abc', '4.5.6', '.', '-']) {
        final DistanceEntry entry = parseDistanceFeet(raw);
        expect(entry.feet, isNull, reason: raw);
        expect(entry.problem, contains('number of feet'), reason: raw);
      }
    });
  });

  group('distanceText', () {
    test('shows a whole number of feet without decimals', () {
      expect(distanceText(45), '45');
      expect(distanceText(45.0), '45');
    });

    test('shows part feet with one decimal', () {
      expect(distanceText(38.5), '38.5');
      expect(distanceText(38.54), '38.5');
    });

    test('what is shown reads back as the same distance', () {
      for (final double feet in <double>[10, 22, 38.5, 130]) {
        expect(parseDistanceFeet(distanceText(feet)).feet, feet);
      }
    });
  });

  group('autoDetectWicketCorners', () {
    test('returns default pitch-corridor polygon when no candidates are present', () {
      final List<Point2D> corners = autoDetectWicketCorners();
      expect(corners, hasLength(4));
      // Traditional stumps width 0.08, height 0.16 centered at 0.50, ground 0.65
      expect(corners[0].x, closeTo(0.46, 1e-4));
      expect(corners[0].y, closeTo(0.49, 1e-4));
      expect(corners[2].x, closeTo(0.54, 1e-4));
      expect(corners[2].y, closeTo(0.65, 1e-4));
    });

    test('snaps to optical candidates in pitch corridor', () {
      const List<BallObservation> opticalBlobs = <BallObservation>[
        BallObservation(
          x: 0.42,
          y: 0.60,
          diameter: 0.02,
          confidence: 0.8,
          timestampMs: 100,
        ),
        BallObservation(
          x: 0.42,
          y: 0.70,
          diameter: 0.02,
          confidence: 0.8,
          timestampMs: 100,
        ),
      ];
      final List<Point2D> corners = autoDetectWicketCorners(
        candidates: opticalBlobs,
        family: WicketFamily.chair,
      );
      expect(corners, hasLength(4));
      // Center X snapped to candidate X (0.42)
      final double midX = (corners[0].x + corners[1].x) / 2;
      expect(midX, closeTo(0.42, 1e-4));
      // Base Y snapped near maxY (0.70 + 0.04 = 0.74)
      expect(corners[2].y, closeTo(0.74, 1e-4));
    });

    test('snaps to batter crease stance and scales height relative to detected batter', () {
      final List<Point2D> corners = autoDetectWicketCorners(
        batterGroundPoint: const Point2D(0.55, 0.70),
        batterHeightNorm: 0.35,
        family: WicketFamily.traditionalStumps,
      );
      expect(corners, hasLength(4));
      // Base Y anchored at batter ground point (0.70)
      expect(corners[2].y, closeTo(0.70, 1e-4));
      expect(corners[3].y, closeTo(0.70, 1e-4));
      // Mid X centered at batter crease (0.55)
      final double midX = (corners[0].x + corners[1].x) / 2;
      expect(midX, closeTo(0.55, 1e-4));
      // Height scaled accurately to 28-inch stumps relative to ~1.58m stance batter
      final double height = corners[2].y - corners[0].y;
      expect(height, closeTo((0.35 / 1.58) * 0.7112, 1e-3));
    });

    test('snaps to batter crease stance for chair wicket with chair aspect ratio', () {
      final List<Point2D> corners = autoDetectWicketCorners(
        batterGroundPoint: const Point2D(0.48, 0.72),
        batterHeightNorm: 0.30,
        family: WicketFamily.chair,
      );
      expect(corners, hasLength(4));
      expect(corners[2].y, closeTo(0.72, 1e-4));
      final double midX = (corners[0].x + corners[1].x) / 2;
      expect(midX, closeTo(0.48, 1e-4));
      final double height = corners[2].y - corners[0].y;
      final double width = corners[1].x - corners[0].x;
      expect(height, closeTo((0.30 / 1.58) * 0.78, 1e-3));
      expect(width, closeTo(height * (0.14 / 0.18), 1e-3));
    });

    test('ignores candidates outside the pitch corridor', () {
      const List<BallObservation> farEdgeBlobs = <BallObservation>[
        BallObservation(
          x: 0.05,
          y: 0.50, // far left boundary
          diameter: 0.02,
          confidence: 0.9,
          timestampMs: 100,
        ),
      ];
      final List<Point2D> corners = autoDetectWicketCorners(
        candidates: farEdgeBlobs,
      );
      // Stays at pitch corridor center
      final double midX = (corners[0].x + corners[1].x) / 2;
      expect(midX, closeTo(0.50, 1e-4));
    });
  });

  group('typicalWicketHeightMetres', () {
    test('returns standard physical heights for known wicket families', () {
      expect(typicalWicketHeightMetres(WicketFamily.traditionalStumps), 0.7112);
      expect(typicalWicketHeightMetres(WicketFamily.chair), 0.78);
      expect(typicalWicketHeightMetres(WicketFamily.bucket), 0.38);
      expect(typicalWicketHeightMetres(WicketFamily.brickStack), 0.45);
      expect(typicalWicketHeightMetres(WicketFamily.bottleStack), 0.40);
      expect(typicalWicketHeightMetres(WicketFamily.coneStack), 0.45);
      expect(typicalWicketHeightMetres(WicketFamily.wallTarget), 0.7112);
    });
  });

  group('estimateOpticalBatsmanHeightM', () {
    final Polygon standardStumps = Polygon(const <Point2D>[
      Point2D(0.46, 0.49),
      Point2D(0.54, 0.49),
      Point2D(0.54, 0.65),
      Point2D(0.46, 0.65),
    ]); // heightNorm = 0.16

    test('accurately identifies standing upright height with stance flex compensation', () {
      // 0.36 norm batter height vs 0.16 norm stumps -> stance = 1.60 m -> standing = 1.778 m
      final double? heightM = estimateOpticalBatsmanHeightM(
        batterHeightNorm: 0.36,
        wicket: standardStumps,
        family: WicketFamily.traditionalStumps,
      );
      expect(heightM, isNotNull);
      expect(heightM!, closeTo(1.778, 0.01));
    });

    test('returns null when batter is too small or invalid', () {
      expect(
        estimateOpticalBatsmanHeightM(
          batterHeightNorm: 0.02,
          wicket: standardStumps,
        ),
        isNull,
      );
    });

    test('returns null when estimated height is outside human bounds', () {
      // Way too tall (e.g. tree in frame)
      expect(
        estimateOpticalBatsmanHeightM(
          batterHeightNorm: 0.85,
          wicket: standardStumps,
        ),
        isNull,
      );
    });
  });
}
