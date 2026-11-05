import 'package:flutter/material.dart';
import 'package:gully_umpire/app/theme/app_colors.dart';
import 'package:gully_umpire/cv/geometry/point2d.dart';
import 'package:gully_umpire/cv/live/replay_meta.dart';
import 'package:gully_umpire/features/replay/replay_geometry.dart';

/// Draws what the camera worked out on top of one replay picture: the batter's waist, shoulder
/// and head lines, the wicket, the path of the ball so far, and where it bounced and reached the
/// batter.
class ReplayOverlayPainter extends CustomPainter {
  const ReplayOverlayPainter({
    required this.meta,
    required this.timestampMs,
    this.showBodyLines = true,
  });

  final ReplayMeta meta;

  /// Capture time of the picture that is shown.
  final int timestampMs;

  final bool showBodyLines;

  static const double _lineHalfWidth = 0.2;

  /// How far the "where it was heading" line is drawn (picture heights).
  static const double _headingLength = 0.3;

  @override
  void paint(Canvas canvas, Size size) {
    _paintWicket(canvas, size);
    if (showBodyLines) {
      _paintBodyLines(canvas, size);
    }
    _paintPath(canvas, size);
    _paintHeading(canvas, size);
    _paintMarks(canvas, size);
  }

  Offset _at(double x, double y, Size size) => Offset(x * size.width, y * size.height);

  void _paintWicket(Canvas canvas, Size size) {
    final List<Point2D> vertices = meta.wicket?.vertices ?? const <Point2D>[];
    if (vertices.length < 3) {
      return;
    }
    final Path path = Path();
    for (int i = 0; i < vertices.length; i++) {
      final Offset point = _at(vertices[i].x, vertices[i].y, size);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = AppColors.creaseAmber,
    );
  }

  void _paintBodyLines(Canvas canvas, Size size) {
    final BatterLines? lines = batterLinesAt(meta, timestampMs);
    if (lines == null) {
      return;
    }
    final double height = meta.batterHeightM;
    _line(canvas, size, lines, lines.headY, Colors.white, 'Head ${metresLabel(height)}');
    _line(
      canvas,
      size,
      lines,
      lines.shoulderY,
      AppColors.skyBlue,
      'Shoulder ${metresLabel(height * meta.shoulderRatio)}',
    );
    _line(
      canvas,
      size,
      lines,
      lines.waistY,
      AppColors.creaseAmber,
      'Waist ${metresLabel(height * meta.waistRatio)}',
    );
    _line(canvas, size, lines, lines.groundY, Colors.white70, 'Ground');
  }

  void _line(Canvas canvas, Size size, BatterLines lines, double y, Color color, String label) {
    final double left = (lines.centerX - _lineHalfWidth).clamp(0.0, 1.0).toDouble();
    final double right = (lines.centerX + _lineHalfWidth).clamp(0.0, 1.0).toDouble();
    final Offset a = _at(left, y, size);
    final Offset b = _at(right, y, size);
    canvas.drawLine(
      a,
      b,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    _text(canvas, label, Offset(b.dx + 4, b.dy - 7), color, size);
  }

  void _paintPath(Canvas canvas, Size size) {
    final List<ReplayBallPoint> trail = trailUpTo(meta, timestampMs);
    if (trail.length >= 2) {
      final Path path = Path();
      for (int i = 0; i < trail.length; i++) {
        final Offset point = _at(trail[i].x, trail[i].y, size);
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = AppColors.ballRed.withValues(alpha: 0.85),
      );
    }
    final ReplayBallPoint? ball = replayBallAt(meta, timestampMs);
    if (ball != null) {
      final double radius = (ball.diameter * size.height / 2).clamp(5.0, 30.0).toDouble();
      final Offset centre = _at(ball.x, ball.y, size);
      canvas
        ..drawCircle(centre, radius + 2, Paint()..color = Colors.white)
        ..drawCircle(centre, radius, Paint()..color = AppColors.ballRed);
    }
  }

  /// The straight line the ball was following, from the moment its path changed (or it reached the
  /// batter) on: set against the real path it shows how much the ball moved off its line.
  void _paintHeading(Canvas canvas, Size size) {
    final HeadingLine? line = headingLineOf(meta);
    if (line == null || timestampMs < line.cutMs) {
      return;
    }
    final Offset from = _at(line.from.x, line.from.y, size);
    final Point2D end = line.endAt(_headingLength);
    final Offset to = _at(end.x, end.y, size);
    final double length = (to - from).distance;
    if (length < 4) {
      return;
    }
    final Offset step = (to - from) / length;
    final Paint paint = Paint()
      ..color = AppColors.skyBlue
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    const double dash = 8;
    const double gap = 6;
    for (double at = 0; at < length; at += dash + gap) {
      final double stop = at + dash < length ? at + dash : length;
      canvas.drawLine(from + step * at, from + step * stop, paint);
    }
    _text(canvas, 'Where it was heading', Offset(to.dx + 4, to.dy - 7), AppColors.skyBlue, size);
  }

  void _paintMarks(Canvas canvas, Size size) {
    final int? bounceMs = meta.bounceMs;
    if (meta.bounced == true && bounceMs != null && timestampMs >= bounceMs) {
      _mark(canvas, size, trackPointNear(meta, bounceMs), 'Bounce', AppColors.creaseAmber);
    }
    final int? arrivalMs = meta.arrivalMs;
    if (arrivalMs != null && timestampMs >= arrivalMs) {
      _mark(canvas, size, trackPointNear(meta, arrivalMs), 'At the batter', Colors.white);
    }
    final int? contactMs = meta.contactMs;
    if (contactMs != null && timestampMs >= contactMs) {
      _mark(
        canvas,
        size,
        trackPointNear(meta, contactMs),
        'Path changed',
        AppColors.skyBlue,
        labelDy: 8,
      );
    }
  }

  void _mark(
    Canvas canvas,
    Size size,
    ReplayBallPoint? point,
    String label,
    Color color, {
    double labelDy = -6,
  }) {
    if (point == null) {
      return;
    }
    final Offset centre = _at(point.x, point.y, size);
    canvas.drawCircle(
      centre,
      10,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = color,
    );
    _text(canvas, label, Offset(centre.dx + 14, centre.dy + labelDy), color, size);
  }

  void _text(Canvas canvas, String text, Offset at, Color color, Size size) {
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          shadows: const <Shadow>[Shadow(color: Colors.black87, blurRadius: 3)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    // Keep the label inside the picture.
    final double x = at.dx + painter.width > size.width ? size.width - painter.width : at.dx;
    painter.paint(canvas, Offset(x < 0 ? 0 : x, at.dy));
  }

  @override
  bool shouldRepaint(ReplayOverlayPainter old) {
    return !identical(old.meta, meta) ||
        old.timestampMs != timestampMs ||
        old.showBodyLines != showBodyLines;
  }
}
