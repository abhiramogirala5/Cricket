import 'package:equatable/equatable.dart';
import 'package:gully_umpire/cv/geometry/line.dart';
import 'package:gully_umpire/cv/geometry/point2d.dart';
import 'package:gully_umpire/cv/live/replay_meta.dart';
import 'package:gully_umpire/cv/pipelines/pose_sample.dart';

/// Where the lines that mark the batter's body sit in the picture (0..1, y grows downwards).
final class BatterLines {
  const BatterLines({
    required this.centerX,
    required this.groundY,
    required this.waistY,
    required this.shoulderY,
    required this.headY,
  });

  final double centerX;
  final double groundY;
  final double waistY;
  final double shoulderY;
  final double headY;
}

/// The pose measured closest in time to [timestampMs], or null when nothing was measured.
PoseSample? nearestPose(List<PoseSample> poses, int timestampMs) {
  PoseSample? best;
  int bestGap = 0;
  for (final PoseSample pose in poses) {
    final int gap = (pose.timestampMs - timestampMs).abs();
    if (best == null || gap < bestGap) {
      best = pose;
      bestGap = gap;
    }
  }
  return best;
}

/// The waist, shoulder and head lines of the batter for the picture taken at [timestampMs].
///
/// The batter is only measured every few pictures and stands almost still while the ball comes,
/// so the pose measured closest in time is used. `null` when the batter was never measured.
BatterLines? batterLinesAt(ReplayMeta meta, int timestampMs) {
  final PoseSample? pose = nearestPose(meta.poses, timestampMs);
  if (pose == null || pose.heightNorm <= 0) {
    return null;
  }
  final double height = pose.heightNorm;
  return BatterLines(
    centerX: pose.centerX,
    groundY: pose.groundY,
    waistY: pose.groundY - meta.waistRatio * height,
    shoulderY: pose.groundY - meta.shoulderRatio * height,
    headY: pose.topY,
  );
}

/// The ball positions up to and including the picture taken at [timestampMs].
List<ReplayBallPoint> trailUpTo(ReplayMeta meta, int timestampMs) {
  return <ReplayBallPoint>[
    for (final ReplayBallPoint point in meta.track)
      if (point.timestampMs <= timestampMs) point,
  ];
}

/// The ball position at [timestampMs]: a tracked point taken at that moment, or a point between
/// two tracked points when they are close enough in time (never a guess across a long gap).
ReplayBallPoint? replayBallAt(ReplayMeta meta, int timestampMs, {int maxGapMs = 120}) {
  ReplayBallPoint? before;
  ReplayBallPoint? after;
  for (final ReplayBallPoint point in meta.track) {
    if (point.timestampMs <= timestampMs) {
      before = point;
    } else {
      after = point;
      break;
    }
  }
  if (before == null) {
    return null;
  }
  if (before.timestampMs == timestampMs) {
    return before;
  }
  if (after == null) {
    // Just after the last tracked point the ball is still shown there; later it is not shown.
    return timestampMs - before.timestampMs <= maxGapMs ~/ 2 ? before : null;
  }
  if (after.timestampMs - before.timestampMs > maxGapMs) {
    // Across a gap the ball is not shown: the path is never guessed.
    return null;
  }
  final double t = (timestampMs - before.timestampMs) / (after.timestampMs - before.timestampMs);
  return ReplayBallPoint(
    timestampMs: timestampMs,
    x: before.x + (after.x - before.x) * t,
    y: before.y + (after.y - before.y) * t,
    diameter: before.diameter + (after.diameter - before.diameter) * t,
    confidence: before.confidence < after.confidence ? before.confidence : after.confidence,
  );
}

/// The tracked point closest in time to [timestampMs] (for the "bounce" and "at the batter"
/// marks), or null when [timestampMs] is null or nothing was tracked.
ReplayBallPoint? trackPointNear(ReplayMeta meta, int? timestampMs) {
  if (timestampMs == null || meta.track.isEmpty) {
    return null;
  }
  ReplayBallPoint best = meta.track.first;
  int bestGap = (best.timestampMs - timestampMs).abs();
  for (final ReplayBallPoint point in meta.track) {
    final int gap = (point.timestampMs - timestampMs).abs();
    if (gap < bestGap) {
      best = point;
      bestGap = gap;
    }
  }
  return best;
}

/// Metres as text, `1.05 m`.
String metresLabel(double metres) => '${metres.toStringAsFixed(2)} m';

/// "about 1.10 m, give or take 0.30 m", or `null` when the height at the batter was not worked
/// out.
String? ballHeightText(ReplayMeta meta) {
  final double? height = meta.ballHeightM;
  if (height == null || !height.isFinite) {
    return null;
  }
  final double? margin = meta.heightUncertaintyM;
  final String base = 'about ${metresLabel(height < 0 ? 0.0 : height)}';
  if (margin == null || !margin.isFinite || margin <= 0) {
    return base;
  }
  return '$base, give or take ${metresLabel(margin)}';
}

/// Whether the ball bounced before the batter, in words.
String bounceText(ReplayMeta meta) {
  final bool? bounced = meta.bounced;
  if (bounced == null) {
    return 'Not sure whether it bounced';
  }
  return bounced ? 'Bounced before the batter' : 'Reached the batter without bouncing';
}

/// The straight line the ball was following in the picture just before a moment, to be drawn as
/// "where it was heading".
final class HeadingLine extends Equatable {
  const HeadingLine({required this.from, required this.direction, required this.cutMs});

  /// The last ball point the line is based on (picture coordinates, 0..1).
  final Point2D from;

  /// Unit vector of the direction the ball was moving in.
  final Point2D direction;

  /// The time the line is cut at: the path change when one was seen, otherwise the arrival at the
  /// batter. The line is drawn only from this moment on.
  final int cutMs;

  /// Where the line ends: [length] picture units from [from], stopped at the edge of the picture.
  Point2D endAt(double length) {
    double scale = length;
    void limit(double start, double step) {
      if (step > 1e-9) {
        scale = scale < (1 - start) / step ? scale : (1 - start) / step;
      } else if (step < -1e-9) {
        scale = scale < -start / step ? scale : -start / step;
      }
    }

    limit(from.x, direction.x);
    limit(from.y, direction.y);
    final double reach = scale < 0 ? 0.0 : scale;
    return Point2D(from.x + direction.x * reach, from.y + direction.y * reach);
  }

  @override
  List<Object?> get props => <Object?>[from, direction, cutMs];
}

/// The fewest ball points (and the shortest stretch of time) a heading line is fitted to.
const int headingMinPoints = 4;
const int headingMaxPoints = 8;
const int headingMinSpanMs = 90;

/// Largest spread of the points around their line (picture units) that still counts as straight.
const double headingMaxResidual = 0.02;

/// Slowest picture speed (picture units per second) that still gives a direction.
const double headingMinSpeed = 0.05;

/// Where the ball was heading in the picture before the path changed (or, with no change seen,
/// before it reached the batter).
///
/// Only the last [headingMaxPoints] ball points up to that moment are used, and only those after
/// the bounce when the ball bounced. A path with too few points, one that is not straight, or one
/// that hardly moves in the picture gives `null`: no line is better than a made-up one.
///
/// Seen from one camera this line shows a direction and nothing about depth: a line that crosses
/// the stumps in the picture does not prove the ball would have hit them.
HeadingLine? headingLineOf(ReplayMeta meta) {
  final int? cutMs = meta.contactMs ?? meta.arrivalMs;
  if (cutMs == null) {
    return null;
  }
  final int? bounceMs = meta.bounced == true ? meta.bounceMs : null;
  final List<ReplayBallPoint> upTo = <ReplayBallPoint>[
    for (final ReplayBallPoint p in meta.track)
      if (p.timestampMs <= cutMs && (bounceMs == null || p.timestampMs >= bounceMs)) p,
  ];
  if (upTo.length < headingMinPoints) {
    return null;
  }
  final List<ReplayBallPoint> used =
      upTo.length > headingMaxPoints ? upTo.sublist(upTo.length - headingMaxPoints) : upTo;
  if (used.last.timestampMs - used.first.timestampMs < headingMinSpanMs) {
    return null;
  }
  final LineFit2D? fit = fitLineOverTime(
    <int>[for (final ReplayBallPoint p in used) p.timestampMs],
    <Point2D>[for (final ReplayBallPoint p in used) Point2D(p.x, p.y)],
  );
  if (fit == null || fit.residual > headingMaxResidual || fit.velocity.length < headingMinSpeed) {
    return null;
  }
  return HeadingLine(
    from: Point2D(used.last.x, used.last.y),
    direction: fit.velocity.normalized(),
    cutMs: cutMs,
  );
}

/// What was seen of the path near the batter, in words, or `null` when no sudden change was seen
/// (or the check was not made: the notes of the delivery say which). A missing change never means
/// that nothing touched the ball, because a touch that moves it along the line of sight hardly
/// shows in the picture.
String? pathChangeText(ReplayMeta meta) {
  final int? contactMs = meta.contactMs;
  if (contactMs == null) {
    return null;
  }
  final int? arrivalMs = meta.arrivalMs;
  if (arrivalMs == null) {
    return 'The path changed suddenly (bat, pad or glove)';
  }
  final int offset = contactMs - arrivalMs;
  if (offset.abs() < 20) {
    return 'The path changed suddenly as the ball reached the batter (bat, pad or glove)';
  }
  final String when = offset < 0 ? '${-offset} ms before' : '$offset ms after';
  return 'The path changed suddenly $when the ball reached the batter (bat, pad or glove)';
}
