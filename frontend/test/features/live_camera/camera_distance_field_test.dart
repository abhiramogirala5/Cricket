import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/cv/geometry/point2d.dart';
import 'package:gully_umpire/domain/decisions/wicket_family.dart';
import 'package:gully_umpire/features/live_camera/camera_distance.dart';
import 'package:gully_umpire/features/live_camera/presentation/camera_distance_field.dart';

void main() {
  Future<void> show(
    WidgetTester tester, {
    required TextEditingController controller,
    DistanceEntry entry = DistanceEntry.empty,
    ValueChanged<String>? onChanged,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CameraDistanceField(
              controller: controller,
              entry: entry,
              onChanged: onChanged ?? (String _) {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('asks for the distance in feet and says what an empty box means', (tester) async {
    final TextEditingController controller = TextEditingController();
    addTearDown(controller.dispose);

    await show(tester, controller: controller);

    expect(find.text('How far is the phone from the batter?'), findsOneWidget);
    expect(find.text('Distance in feet'), findsOneWidget);
    expect(find.textContaining('heel to toe'), findsOneWidget);
    expect(find.textContaining('no speed is shown'), findsOneWidget);
  });

  testWidgets('reports what is typed and lets only digits and a point in', (tester) async {
    final TextEditingController controller = TextEditingController();
    addTearDown(controller.dispose);
    final List<String> typed = <String>[];

    await show(tester, controller: controller, onChanged: typed.add);
    await tester.enterText(find.byType(TextField), '4a5');

    expect(typed.last, '45');
    expect(controller.text, '45');
  });

  testWidgets('shows why what was typed cannot be used', (tester) async {
    final TextEditingController controller = TextEditingController(text: '500');
    addTearDown(controller.dispose);

    await show(tester, controller: controller, entry: parseDistanceFeet('500'));

    expect(find.text('Between 10 and 130 feet, please.'), findsOneWidget);
  });

  testWidgets('shows no problem for a good distance', (tester) async {
    final TextEditingController controller = TextEditingController(text: '45');
    addTearDown(controller.dispose);

    await show(tester, controller: controller, entry: parseDistanceFeet('45'));

    expect(find.textContaining('please'), findsNothing);
  });

  testWidgets('shows auto-calculated badge when distance is auto-derived', (tester) async {
    final TextEditingController controller = TextEditingController(text: '36');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CameraDistanceField(
            controller: controller,
            entry: parseDistanceFeet('36'),
            onChanged: (String _) {},
            isAutoCalculated: true,
          ),
        ),
      ),
    );

    expect(find.text('Auto-calculated'), findsOneWidget);
    expect(find.textContaining('wicket optical height'), findsOneWidget);
  });

  group('estimateDistanceFeetFromWicket & smartWicketCorners', () {
    test('estimates realistic pitch distance from wicket height in pixels', () {
      // 12m pitch with 28-inch stumps (0.7112m) spans h_norm ~= 0.0622
      const List<Point2D> corners = <Point2D>[
        Point2D(0.48, 0.50),
        Point2D(0.52, 0.50),
        Point2D(0.52, 0.5622),
        Point2D(0.48, 0.5622),
      ];
      final double feet = estimateDistanceFeetFromWicket(corners, zoom: 1.0);
      expect(feet, closeTo(39.0, 2.0));
    });

    test('scales distance with camera zoom factor', () {
      // At 2x zoom, object looks twice as tall for the same distance
      const List<Point2D> corners = <Point2D>[
        Point2D(0.48, 0.50),
        Point2D(0.52, 0.50),
        Point2D(0.52, 0.6244),
        Point2D(0.48, 0.6244),
      ];
      final double feet = estimateDistanceFeetFromWicket(corners, zoom: 2.0);
      expect(feet, closeTo(39.0, 2.0));
    });

    test('adapts distance to physical height of chair', () {
      // Chair is 0.78m tall vs 0.71m stumps
      const List<Point2D> corners = <Point2D>[
        Point2D(0.45, 0.50),
        Point2D(0.55, 0.50),
        Point2D(0.55, 0.60),
        Point2D(0.45, 0.60),
      ];
      final double feetStumps = estimateDistanceFeetFromWicket(corners, family: WicketFamily.traditionalStumps);
      final double feetChair = estimateDistanceFeetFromWicket(corners, family: WicketFamily.chair);
      expect(feetChair, greaterThan(feetStumps));
    });

    test('smartWicketCorners returns valid 4-corner polygon', () {
      final List<Point2D> stumps = smartWicketCorners(family: WicketFamily.traditionalStumps);
      expect(stumps, hasLength(4));
      expect(stumps[3].y - stumps[0].y, closeTo(0.16, 1e-6));

      final List<Point2D> chair = smartWicketCorners(family: WicketFamily.chair);
      expect(chair, hasLength(4));
      expect(chair[1].x - chair[0].x, greaterThan(stumps[1].x - stumps[0].x));
    });

    test('scales corners and calculates distance accurately for a 66 ft long pitch', () {
      final List<Point2D> longPitchCorners = smartWicketCorners(
        family: WicketFamily.traditionalStumps,
        targetDistanceFeet: 66.0,
      );
      expect(longPitchCorners, hasLength(4));
      // Apparent vertical height on 66 ft pitch is much smaller than 15 ft starter box
      final double h = longPitchCorners[3].y - longPitchCorners[0].y;
      expect(h, lessThan(0.05));
      expect(h, greaterThan(0.03));

      // Calculating distance back from these corners yields 66 ft
      final double calculatedFeet = estimateDistanceFeetFromWicket(
        longPitchCorners,
        family: WicketFamily.traditionalStumps,
      );
      expect(calculatedFeet, closeTo(66.0, 1.0));
    });

    test('autoDetectWicketCorners supports distant long pitch with target distance', () {
      final List<Point2D> autoCorners = autoDetectWicketCorners(
        family: WicketFamily.traditionalStumps,
        targetDistanceFeet: 66.0,
      );
      expect(autoCorners, hasLength(4));
      final double calculatedFeet = estimateDistanceFeetFromWicket(
        autoCorners,
        family: WicketFamily.traditionalStumps,
      );
      expect(calculatedFeet, closeTo(66.0, 1.0));
    });
  });
}

