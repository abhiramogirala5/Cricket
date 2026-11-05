import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:gully_umpire/app/theme/app_colors.dart';
import 'package:gully_umpire/cv/geometry/point2d.dart';
import 'package:gully_umpire/cv/geometry/polygon.dart';
import 'package:gully_umpire/cv/pipelines/ball_observation.dart';

/// Draws what the tracker sees on top of the camera preview: the marked wicket, every ball-like
/// patch in the latest picture, and the path of the ball being followed.
///
/// All positions are 0..1 in the picture, so the painter must be given exactly the area of the
/// preview.
class LiveOverlayPainter extends CustomPainter {
  const LiveOverlayPainter({
    this.candidates = const <BallObservation>[],
    this.trail = const <BallObservation>[],
    this.wicket,
    this.corners,
    this.activeCorner,
  });

  /// Ball-like patches in the latest picture (thin white rings).
  final List<BallObservation> candidates;

  /// The path of the ball being followed (a red line and a filled mark at its latest point).
  final List<BallObservation> trail;

  /// The marked wicket, drawn as an amber outline.
  final Polygon? wicket;

  /// The four draggable corners while the stumps are being marked (drawn as handles).
  final List<Point2D>? corners;

  /// The corner being dragged, drawn bigger.
  final int? activeCorner;

  @override
  void paint(Canvas canvas, Size size) {
    _paintWicket(canvas, size);
    _paintCandidates(canvas, size);
    _paintTrail(canvas, size);
    _paintHandles(canvas, size);
  }

  Offset _at(Point2D point, Size size) => Offset(point.x * size.width, point.y * size.height);

  void _paintWicket(Canvas canvas, Size size) {
    final List<Point2D>? marking = corners;
    final List<Point2D> vertices = marking ?? wicket?.vertices ?? const <Point2D>[];
    if (vertices.length < 3) {
      return;
    }
    final Path path = Path()..moveTo(_at(vertices.first, size).dx, _at(vertices.first, size).dy);
    for (int i = 1; i < vertices.length; i++) {
      final Offset point = _at(vertices[i], size);
      path.lineTo(point.dx, point.dy);
    }
    path.close();

    final Rect bounds = path.getBounds();
    final Offset center = bounds.center;

    // 1. Thermal / Heatmap Aura Glow: Soft radiant dispersion around the wicket target
    final double auraRadius = math.max(bounds.width, bounds.height) * 1.1;
    if (auraRadius > 0) {
      final Paint auraPaint = Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            AppColors.pitchGreen.withValues(alpha: 0.32),
            AppColors.creaseAmber.withValues(alpha: 0.20),
            AppColors.creaseAmber.withValues(alpha: 0.06),
            Colors.transparent,
          ],
          stops: const <double>[0.0, 0.40, 0.75, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: auraRadius));
      canvas.drawCircle(center, auraRadius, auraPaint);
    }

    // 2. Heatmap Core Fill: gradient from top (active) to bottom (ground)
    final Paint fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          AppColors.pitchGreen.withValues(alpha: 0.25),
          AppColors.creaseAmber.withValues(alpha: 0.18),
          AppColors.creaseAmber.withValues(alpha: 0.10),
        ],
      ).createShader(bounds);
    canvas.drawPath(path, fillPaint);

    // 3. Vertical Thermal Intensity Ribs (simulating stump thermal presence)
    if (vertices.length == 4) {
      final Offset topL = _at(vertices[0], size);
      final Offset topR = _at(vertices[1], size);
      final Offset botR = _at(vertices[2], size);
      final Offset botL = _at(vertices[3], size);
      for (final double frac in const <double>[0.25, 0.50, 0.75]) {
        final Offset t = Offset.lerp(topL, topR, frac)!;
        final Offset b = Offset.lerp(botL, botR, frac)!;
        canvas.drawLine(
          t,
          b,
          Paint()
            ..color = AppColors.pitchGreen.withValues(alpha: 0.35)
            ..strokeWidth = 2.0
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    // 4. Perimeter Contour
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..color = AppColors.creaseAmber,
    );

    // 5. Target Lock HUD Brackets at each corner
    for (int i = 0; i < vertices.length; i++) {
      final Offset curr = _at(vertices[i], size);
      final Offset prev = _at(vertices[(i - 1 + vertices.length) % vertices.length], size);
      final Offset next = _at(vertices[(i + 1) % vertices.length], size);

      final Offset dPrev = prev - curr;
      final Offset dNext = next - curr;
      final double lenPrev = dPrev.distance;
      final double lenNext = dNext.distance;

      if (lenPrev > 0 && lenNext > 0) {
        const double bracketLen = 14.0;
        final Offset p1 = curr + dPrev * math.min(bracketLen / lenPrev, 0.45);
        final Offset p2 = curr + dNext * math.min(bracketLen / lenNext, 0.45);

        final Paint bracketPaint = Paint()
          ..color = AppColors.pitchGreen
          ..strokeWidth = 3.0
          ..strokeCap = StrokeCap.square;
        canvas.drawLine(curr, p1, bracketPaint);
        canvas.drawLine(curr, p2, bracketPaint);
      }
    }

    // 6. Target Lock Badge ("⌖ WICKET ZONE") above the wicket
    final Offset topCenter = Offset(center.dx, bounds.top - 12);
    if (topCenter.dy >= 14) {
      final TextPainter tp = TextPainter(
        text: const TextSpan(
          text: '⌖ WICKET ZONE',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w900,
            color: AppColors.pitchGreen,
            letterSpacing: 0.8,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final Rect pillRect = Rect.fromCenter(
        center: topCenter,
        width: tp.width + 10,
        height: tp.height + 4,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(pillRect, const Radius.circular(3)),
        Paint()..color = Colors.black.withValues(alpha: 0.65),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(pillRect, const Radius.circular(3)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = AppColors.pitchGreen.withValues(alpha: 0.70),
      );
      tp.paint(canvas, Offset(topCenter.dx - tp.width / 2, topCenter.dy - tp.height / 2));
    }
  }

  double _radiusFor(BallObservation observation, Size size) {
    final double fromSize = observation.diameter * size.height / 2;
    return fromSize < 5 ? 5 : (fromSize > 40 ? 40 : fromSize);
  }

  void _paintCandidates(Canvas canvas, Size size) {
    final Paint ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.white.withValues(alpha: 0.75);
    for (final BallObservation candidate in candidates) {
      canvas.drawCircle(
        _at(candidate.position, size),
        _radiusFor(candidate, size) + 3,
        ring,
      );
    }
  }

  void _paintTrail(Canvas canvas, Size size) {
    if (trail.isEmpty) {
      return;
    }
    if (trail.length >= 2) {
      final Path path = Path()
        ..moveTo(_at(trail.first.position, size).dx, _at(trail.first.position, size).dy);
      for (int i = 1; i < trail.length; i++) {
        final Offset point = _at(trail[i].position, size);
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = AppColors.ballRed,
      );
    }
    final BallObservation last = trail.last;
    final Offset centre = _at(last.position, size);
    canvas
      ..drawCircle(centre, _radiusFor(last, size) + 2, Paint()..color = Colors.white)
      ..drawCircle(centre, _radiusFor(last, size), Paint()..color = AppColors.ballRed);
  }

  void _paintHandles(Canvas canvas, Size size) {
    final List<Point2D>? marking = corners;
    if (marking == null) {
      return;
    }
    for (int i = 0; i < marking.length; i++) {
      final Offset centre = _at(marking[i], size);
      final double radius = i == activeCorner ? 15 : 11;
      canvas
        ..drawCircle(centre, radius + 2, Paint()..color = Colors.white)
        ..drawCircle(centre, radius, Paint()..color = AppColors.creaseAmber)
        ..drawCircle(
          centre,
          radius,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = AppColors.creaseAmberInk,
        );
    }
  }

  @override
  bool shouldRepaint(LiveOverlayPainter old) {
    return !identical(old.candidates, candidates) ||
        !identical(old.trail, trail) ||
        old.wicket != wicket ||
        !identical(old.corners, corners) ||
        old.activeCorner != activeCorner;
  }
}
