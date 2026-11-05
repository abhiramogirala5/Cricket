import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/cv/geometry/point2d.dart';
import 'package:gully_umpire/cv/live/manual_wicket.dart';
import 'package:gully_umpire/cv/pipelines/scene_scan_pipeline.dart';
import 'package:gully_umpire/domain/decisions/wicket_family.dart';

void main() {
  // A tall narrow box in the middle: 0.1 wide, 0.3 high (area 0.03).
  const List<Point2D> good = <Point2D>[
    Point2D(0.45, 0.35),
    Point2D(0.55, 0.35),
    Point2D(0.55, 0.65),
    Point2D(0.45, 0.65),
  ];

  group('wicketCornersProblem', () {
    test('accepts the default corners and a normal marking', () {
      expect(wicketCornersProblem(defaultWicketCorners()), isNull);
      expect(wicketCornersProblem(good), isNull);
    });

    test('accepts the corners in either direction', () {
      expect(wicketCornersProblem(good.reversed.toList()), isNull);
    });

    test('accepts a slightly slanted four-sided shape', () {
      expect(
        wicketCornersProblem(const <Point2D>[
          Point2D(0.44, 0.35),
          Point2D(0.56, 0.36),
          Point2D(0.55, 0.66),
          Point2D(0.45, 0.65),
        ]),
        isNull,
      );
    });

    test('needs exactly four corners', () {
      expect(wicketCornersProblem(good.sublist(0, 3)), isNotNull);
      expect(wicketCornersProblem(<Point2D>[...good, const Point2D(0.5, 0.5)]), isNotNull);
      expect(wicketCornersProblem(const <Point2D>[]), isNotNull);
    });

    test('every corner must be inside the picture', () {
      expect(
        wicketCornersProblem(const <Point2D>[
          Point2D(-0.01, 0.35),
          Point2D(0.55, 0.35),
          Point2D(0.55, 0.65),
          Point2D(0.45, 0.65),
        ]),
        isNotNull,
      );
      expect(
        wicketCornersProblem(const <Point2D>[
          Point2D(0.45, 0.35),
          Point2D(0.55, 0.35),
          Point2D(0.55, 1.01),
          Point2D(0.45, 0.65),
        ]),
        isNotNull,
      );
      expect(
        wicketCornersProblem(const <Point2D>[
          Point2D(double.nan, 0.35),
          Point2D(0.55, 0.35),
          Point2D(0.55, 0.65),
          Point2D(0.45, 0.65),
        ]),
        isNotNull,
      );
    });

    test('a speck is too small', () {
      // 0.01 x 0.01 = 0.0001, below the 0.0004 limit.
      expect(
        wicketCornersProblem(const <Point2D>[
          Point2D(0.50, 0.50),
          Point2D(0.51, 0.50),
          Point2D(0.51, 0.51),
          Point2D(0.50, 0.51),
        ]),
        contains('too small'),
      );
    });

    test('a shape filling most of the picture is too big', () {
      expect(
        wicketCornersProblem(const <Point2D>[
          Point2D(0.05, 0.05),
          Point2D(0.95, 0.05),
          Point2D(0.95, 0.95),
          Point2D(0.05, 0.95),
        ]),
        contains('too big'),
      );
    });

    test('corners that cross over each other are refused', () {
      // The bow tie: corners 1 and 2 swapped.
      final String? problem = wicketCornersProblem(const <Point2D>[
        Point2D(0.45, 0.35),
        Point2D(0.55, 0.65),
        Point2D(0.55, 0.35),
        Point2D(0.45, 0.65),
      ]);
      expect(problem, isNotNull);
    });

    test('a dented shape is refused', () {
      expect(
        wicketCornersProblem(const <Point2D>[
          Point2D(0.30, 0.30),
          Point2D(0.70, 0.30),
          Point2D(0.50, 0.50),
          Point2D(0.70, 0.70),
        ]),
        isNotNull,
      );
    });
  });

  group('manualWicketOutcome', () {
    test('describes the marked shape as a scan outcome that is not a mock', () {
      final SceneScanOutcome outcome = manualWicketOutcome(
        corners: good,
        family: WicketFamily.traditionalStumps,
      );

      expect(outcome.isMock, isFalse);
      expect(outcome.skipped, isFalse);
      expect(outcome.modelVersion, manualMarkModelVersion);
      expect(outcome.framesScanned, 1);
      expect(outcome.result.foundWicket, isTrue);
      expect(outcome.result.confidence, closeTo(0.9, 1e-12));
      expect(outcome.result.best?.family, WicketFamily.traditionalStumps);
      expect(outcome.result.best?.polygon.vertices, good);
      expect(outcome.result.alternatives, isEmpty);
    });

    test('throws when the corners are not usable', () {
      expect(
        () => manualWicketOutcome(corners: good.sublist(0, 2), family: WicketFamily.traditionalStumps),
        throwsArgumentError,
      );
    });
  });

  group('defaultWicketCorners', () {
    test('are inside the picture and taller than wide', () {
      final List<Point2D> corners = defaultWicketCorners();
      expect(corners, hasLength(4));
      final double width = (corners[1].x - corners[0].x).abs();
      final double height = (corners[2].y - corners[1].y).abs();
      expect(height, greaterThan(width));
    });
  });
}
