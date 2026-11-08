import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/domain/decisions/decisions.dart';
import 'package:gully_umpire/domain/models/models.dart';
import 'package:gully_umpire/features/review/presentation/delivery_review_screen.dart';
import 'package:gully_umpire/features/review/review_data.dart';

void main() {
  group('HawkEye3DPainter', () {
    test('paints without error for typical delivery points and hitting stumps', () {
      final List<PathPoint> points = <PathPoint>[
        const PathPoint(timeMs: 0, x: 0.50, y: 0.85, confidence: 0.9),
        const PathPoint(timeMs: 50, x: 0.51, y: 0.70, confidence: 0.92),
        const PathPoint(timeMs: 100, x: 0.51, y: 0.55, confidence: 0.88),
        const PathPoint(timeMs: 150, x: 0.50, y: 0.45, confidence: 0.85),
        const PathPoint(timeMs: 200, x: 0.50, y: 0.38, confidence: 0.80),
      ];

      final DecisionRecord lbw = DecisionRecord(
        id: 'dec-1',
        deliveryId: 'del-1',
        decisionType: DeliveryDecisionType.lbw,
        decisionSource: DecisionSource.aiAssist,
        decisionStatus: DecisionStatus.reviewRecommended,
        automatedResult: 'LIKELY_HITTING',
        evidence: const <String, Object?>{
          'impact_in_line': true,
          'rays_hitting': 8,
          'rays_total': 10,
        },
        createdAt: DateTime.now(),
      );

      final HawkEye3DPainter painter = HawkEye3DPainter(
        points: points,
        wicketOutline: const <Offset>[
          Offset(0.48, 0.30),
          Offset(0.52, 0.30),
          Offset(0.52, 0.35),
          Offset(0.48, 0.35),
        ],
        lbwDecision: lbw,
        bounced: true,
      );

      final PictureRecorder recorder = PictureRecorder();
      final Canvas canvas = Canvas(recorder);
      painter.paint(canvas, const Size(400, 300));
      final Picture picture = recorder.endRecording();
      expect(picture, isNotNull);
    });

    test('paints without error for missing stumps and full toss', () {
      final List<PathPoint> points = <PathPoint>[
        const PathPoint(timeMs: 0, x: 0.45, y: 0.80, confidence: 0.9),
        const PathPoint(timeMs: 100, x: 0.42, y: 0.40, confidence: 0.85),
      ];

      final DecisionRecord lbw = DecisionRecord(
        id: 'dec-2',
        deliveryId: 'del-2',
        decisionType: DeliveryDecisionType.lbw,
        decisionSource: DecisionSource.aiAssist,
        decisionStatus: DecisionStatus.reviewRecommended,
        automatedResult: 'LIKELY_MISSING',
        evidence: const <String, Object?>{
          'impact_in_line': false,
          'rays_hitting': 0,
          'rays_total': 10,
        },
        createdAt: DateTime.now(),
      );

      final HawkEye3DPainter painter = HawkEye3DPainter(
        points: points,
        wicketOutline: const <Offset>[],
        lbwDecision: lbw,
        bounced: false,
      );

      final PictureRecorder recorder = PictureRecorder();
      final Canvas canvas = Canvas(recorder);
      painter.paint(canvas, const Size(400, 300));
      final Picture picture = recorder.endRecording();
      expect(picture, isNotNull);
    });
  });

  group('BallPathPainter', () {
    test('paints 2D path and wicket outline', () {
      final List<PathPoint> points = <PathPoint>[
        const PathPoint(timeMs: 0, x: 0.5, y: 0.2, confidence: 0.9),
        const PathPoint(timeMs: 40, x: 0.52, y: 0.3, confidence: 0.8),
      ];
      final BallPathPainter painter = BallPathPainter(
        points: points,
        wicketOutline: const <Offset>[Offset(0.4, 0.2), Offset(0.6, 0.2), Offset(0.5, 0.4)],
      );

      final PictureRecorder recorder = PictureRecorder();
      final Canvas canvas = Canvas(recorder);
      painter.paint(canvas, const Size(200, 200));
      final Picture picture = recorder.endRecording();
      expect(picture, isNotNull);
    });
  });
}
