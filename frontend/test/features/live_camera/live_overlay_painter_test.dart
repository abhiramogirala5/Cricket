import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/cv/geometry/point2d.dart';
import 'package:gully_umpire/cv/geometry/polygon.dart';
import 'package:gully_umpire/cv/pipelines/ball_observation.dart';
import 'package:gully_umpire/features/live_camera/presentation/live_overlay_painter.dart';

void main() {
  group('LiveOverlayPainter', () {
    testWidgets('paints wicket heatmap, target brackets, and handles without throwing', (
      WidgetTester tester,
    ) async {
      final List<Point2D> corners = <Point2D>[
        const Point2D(0.45, 0.45),
        const Point2D(0.55, 0.45),
        const Point2D(0.55, 0.65),
        const Point2D(0.45, 0.65),
      ];
      final List<BallObservation> candidates = <BallObservation>[
        const BallObservation(
          x: 0.50,
          y: 0.55,
          diameter: 0.02,
          confidence: 0.9,
          timestampMs: 100,
        ),
      ];
      final List<BallObservation> trail = <BallObservation>[
        const BallObservation(
          x: 0.50,
          y: 0.30,
          diameter: 0.02,
          confidence: 0.9,
          timestampMs: 100,
        ),
        const BallObservation(
          x: 0.50,
          y: 0.40,
          diameter: 0.02,
          confidence: 0.9,
          timestampMs: 133,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 640,
              child: CustomPaint(
                painter: LiveOverlayPainter(
                  corners: corners,
                  activeCorner: 1,
                  candidates: candidates,
                  trail: trail,
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('paints locked wicket without corners (during scoring live camera)', (
      WidgetTester tester,
    ) async {
      final Polygon wicket = Polygon(const <Point2D>[
        Point2D(0.45, 0.45),
        Point2D(0.55, 0.45),
        Point2D(0.55, 0.65),
        Point2D(0.45, 0.65),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 640,
              child: CustomPaint(
                painter: LiveOverlayPainter(
                  wicket: wicket,
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(CustomPaint), findsWidgets);
    });

    test('shouldRepaint returns true when inputs change', () {
      const LiveOverlayPainter p1 = LiveOverlayPainter(
        corners: <Point2D>[Point2D(0, 0), Point2D(1, 0), Point2D(1, 1), Point2D(0, 1)],
      );
      const LiveOverlayPainter p2 = LiveOverlayPainter(
        corners: <Point2D>[Point2D(0.1, 0), Point2D(1, 0), Point2D(1, 1), Point2D(0, 1)],
      );
      expect(p2.shouldRepaint(p1), isTrue);
    });
  });
}
