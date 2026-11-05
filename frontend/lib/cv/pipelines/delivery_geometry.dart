import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:gully_umpire/cv/geometry/point2d.dart';
import 'package:gully_umpire/cv/pipelines/ball_observation.dart';

/// Tuning of the single-camera measurements. All values were chosen with the synthetic mock
/// camera and have not been checked against real footage.
final class DeliveryGeometryConfig extends Equatable {
  const DeliveryGeometryConfig({
    this.farDiameterFactor = 1.10,
    this.arrivalFitPoints = 12,
    this.minArrivalFitPoints = 4,
    this.maxArrivalResidual = 0.15,
    this.maxArrivalExtrapolationMs = 400,
    this.maxPositionExtrapolationMs = 150,
    this.minBouncePoints = 6,
    this.minBounceRise = 0.05,
    this.minBounceDrop = 0.03,
    this.contactWindowBeforeMs = 80,
    this.contactWindowAfterMs = 250,
    this.contactMinSpeedChange = 0.8,
    this.minBounceViewRatio = 0,
  });

  /// Only observations at least this much larger than the ball at the batter are used to find the
  /// arrival time (the ball is clearly nearer than the batter there).
  final double farDiameterFactor;

  /// Most recent observations used for the depth fit.
  final int arrivalFitPoints;

  final int minArrivalFitPoints;

  /// Largest accepted relative residual (rms / mean) of the depth fit.
  final double maxArrivalResidual;

  /// How far past the last fitted observation the arrival may lie.
  final int maxArrivalExtrapolationMs;

  /// How far past the last observation a position may be extrapolated.
  final int maxPositionExtrapolationMs;

  /// Fewest observations before the batter needed to say whether the ball bounced.
  final int minBouncePoints;

  /// Smallest fall (normalised) of the ball between release and the lowest point of a bounce.
  final double minBounceRise;

  /// Smallest rise (normalised) of the ball between the lowest point and the batter.
  final double minBounceDrop;

  final int contactWindowBeforeMs;
  final int contactWindowAfterMs;

  /// Smallest change of image velocity (normalised units per second) that counts as a contact.
  final double contactMinSpeedChange;

  /// When the ball was first seen smaller than this many times its size at the batter, it was
  /// first seen so far down the pitch that a bounce may have happened before the track began, so
  /// "did not bounce" cannot be said. 0 switches the check off.
  final double minBounceViewRatio;

  @override
  List<Object?> get props => <Object?>[
        farDiameterFactor,
        arrivalFitPoints,
        minArrivalFitPoints,
        maxArrivalResidual,
        maxArrivalExtrapolationMs,
        maxPositionExtrapolationMs,
        minBouncePoints,
        minBounceRise,
        minBounceDrop,
        contactWindowBeforeMs,
        contactWindowAfterMs,
        contactMinSpeedChange,
        minBounceViewRatio,
      ];
}

/// Result of a least-squares line fit `y = intercept + slope * x`.
final class LinearFit extends Equatable {
  const LinearFit({
    required this.slope,
    required this.intercept,
    required this.rms,
    required this.meanY,
  });

  final double slope;
  final double intercept;

  /// Root mean square of the residuals.
  final double rms;

  final double meanY;

  double valueAt(double x) => intercept + slope * x;

  @override
  List<Object?> get props => <Object?>[slope, intercept, rms, meanY];
}

/// Fits a line to the points; null when there are fewer than two points or all `xs` are equal.
LinearFit? fitLinear(List<double> xs, List<double> ys) {
  final int n = xs.length;
  if (n < 2 || ys.length != n) {
    return null;
  }
  double meanX = 0;
  double meanY = 0;
  for (int i = 0; i < n; i++) {
    meanX += xs[i];
    meanY += ys[i];
  }
  meanX /= n;
  meanY /= n;
  double sxx = 0;
  double sxy = 0;
  for (int i = 0; i < n; i++) {
    final double dx = xs[i] - meanX;
    sxx += dx * dx;
    sxy += dx * (ys[i] - meanY);
  }
  if (!(sxx > 0)) {
    return null;
  }
  final double slope = sxy / sxx;
  final double intercept = meanY - slope * meanX;
  double sumSquares = 0;
  for (int i = 0; i < n; i++) {
    final double residual = ys[i] - (intercept + slope * xs[i]);
    sumSquares += residual * residual;
  }
  return LinearFit(slope: slope, intercept: intercept, rms: math.sqrt(sumSquares / n), meanY: meanY);
}

/// The time (ms) at which the ball reached the batter's plane, or null when it cannot be found.
///
/// A ball of known size looks smaller the further away it is, so `1 / apparent diameter` grows
/// linearly with time while the ball flies at a steady speed away from the camera. A line is fitted
/// to the most recent observations in which the ball is still clearly nearer than the batter, and
/// the time at which it reaches [planeDiameter] (the ball's apparent size at the batter) is the
/// arrival. The fit is only trusted when the ball was seen for long enough, the line is a good fit
/// and the crossing is close to the last fitted observation.
double? estimateArrivalMs(
  List<BallObservation> observations, {
  required double planeDiameter,
  DeliveryGeometryConfig config = const DeliveryGeometryConfig(),
}) {
  if (!(planeDiameter > 0) || observations.isEmpty) {
    return null;
  }
  final double nearLimit = planeDiameter * config.farDiameterFactor;
  final List<BallObservation> near = observations
      .where((BallObservation o) => o.diameter > 0 && o.diameter >= nearLimit)
      .toList();
  if (near.length >= config.minArrivalFitPoints) {
    final List<BallObservation> used = near.length > config.arrivalFitPoints
        ? near.sublist(near.length - config.arrivalFitPoints)
        : near;
    final int t0 = used.first.timestampMs;
    final LinearFit? fit = fitLinear(
      used.map<double>((BallObservation o) => (o.timestampMs - t0).toDouble()).toList(),
      used.map<double>((BallObservation o) => 1.0 / o.diameter).toList(),
    );
    if (fit != null && (fit.slope > 0) && fit.rms <= config.maxArrivalResidual * fit.meanY) {
      final double crossing = t0 + (1.0 / planeDiameter - fit.intercept) / fit.slope;
      final int lastUsedMs = used.last.timestampMs;
      if (crossing >= lastUsedMs - 50 && crossing <= lastUsedMs + config.maxArrivalExtrapolationMs) {
        return crossing;
      }
    }
  }

  // Robust fallback for distant pitches or small optical ball diameters:
  // When farDiameterFactor filter leaves too few points (e.g. ball was small throughout long flight),
  // fit across all pre-batter observations where diameter is trending away.
  final List<BallObservation> valid = observations.where((BallObservation o) => o.diameter > 0).toList();
  if (valid.length >= config.minArrivalFitPoints) {
    final int t0 = valid.first.timestampMs;
    final LinearFit? fit = fitLinear(
      valid.map<double>((BallObservation o) => (o.timestampMs - t0).toDouble()).toList(),
      valid.map<double>((BallObservation o) => 1.0 / o.diameter).toList(),
    );
    if (fit != null && (fit.slope > 0) && fit.rms <= config.maxArrivalResidual * 1.5 * fit.meanY) {
      final double crossing = t0 + (1.0 / planeDiameter - fit.intercept) / fit.slope;
      final int lastMs = valid.last.timestampMs;
      if (crossing >= valid.first.timestampMs && crossing <= lastMs + config.maxArrivalExtrapolationMs) {
        return crossing;
      }
    }
  }
  return null;
}

/// The ball position at [timestampMs]: interpolated between observations, or extended from the
/// last two observations by at most [DeliveryGeometryConfig.maxPositionExtrapolationMs].
Point2D? ballPositionAt(
  List<BallObservation> observations,
  double timestampMs, {
  DeliveryGeometryConfig config = const DeliveryGeometryConfig(),
}) {
  for (int i = 0; i + 1 < observations.length; i++) {
    final BallObservation a = observations[i];
    final BallObservation b = observations[i + 1];
    if (a.timestampMs <= timestampMs && timestampMs <= b.timestampMs) {
      final int span = math.max(1, b.timestampMs - a.timestampMs);
      final double u = (timestampMs - a.timestampMs) / span;
      return a.position.lerp(b.position, u);
    }
  }
  if (observations.length >= 2) {
    final BallObservation a = observations[observations.length - 2];
    final BallObservation b = observations[observations.length - 1];
    final double gap = timestampMs - b.timestampMs;
    if (gap > 0 && gap <= config.maxPositionExtrapolationMs) {
      final int span = math.max(1, b.timestampMs - a.timestampMs);
      final double scale = gap / span;
      return Point2D(b.x + (b.x - a.x) * scale, b.y + (b.y - a.y) * scale);
    }
  }
  return null;
}

/// Where the ball bounced before the batter.
final class BounceInfo extends Equatable {
  const BounceInfo({required this.bounced, this.timestampMs});

  final bool bounced;

  /// Time of the lowest point of the bounce (null when the ball did not bounce).
  final int? timestampMs;

  @override
  List<Object?> get props => <Object?>[bounced, timestampMs];
}

/// Did the ball bounce before reaching the batter?
///
/// [beforeArrival] are the observations up to the arrival and [arrivalY] the image height of the
/// ball at the arrival. The camera is assumed to be behind the bowler's end, so a bounce shows up
/// as an interior maximum of the image y (the ball falls towards the pitch and rises again). At
/// least [DeliveryGeometryConfig.minBouncePoints] observations are needed, with two on each side of
/// the lowest point. Returns null when there is too little data to say, because a wrong "full toss"
/// would turn a legal bouncer into a no-ball.
BounceInfo? detectBounce(
  List<BallObservation> beforeArrival, {
  required double arrivalY,
  DeliveryGeometryConfig config = const DeliveryGeometryConfig(),
}) {
  final int n = beforeArrival.length;
  if (n < config.minBouncePoints) {
    return null;
  }
  int? best;
  for (int i = 2; i < n - 2; i++) {
    if (best == null || beforeArrival[i].y > beforeArrival[best].y) {
      best = i;
    }
  }
  if (best == null) {
    return const BounceInfo(bounced: false);
  }
  final double lowest = beforeArrival[best].y;
  final double fall = lowest - beforeArrival.first.y;
  final double rebound = lowest - arrivalY;

  // Primary check: clear fall towards pitch and rebound rise
  bool bounced = fall >= config.minBounceRise && rebound >= config.minBounceDrop;

  // Physics-informed check (for skidding balls on hard turf or asphalt):
  // When a substantial drop occurred, verify vertical velocity reversal
  // (downward into pitch, upward/level post-impact) even if rebound angle is shallow.
  if (!bounced && fall >= config.minBounceRise * 1.5 && rebound >= config.minBounceDrop * 0.60) {
    final double dyBefore = lowest - beforeArrival[math.max(0, best - 2)].y;
    final double dyAfter = beforeArrival[math.min(n - 1, best + 2)].y - lowest;
    if (dyBefore > 0 && dyAfter <= 0) {
      bounced = true;
    }
  }

  return BounceInfo(bounced: bounced, timestampMs: bounced ? beforeArrival[best].timestampMs : null);
}

/// A sudden change of the ball's image velocity near the batter (a bat or pad contact).
final class ContactInfo extends Equatable {
  const ContactInfo({required this.timestampMs, required this.speedChange});

  final int timestampMs;

  /// Size of the velocity change in normalised units per second.
  final double speedChange;

  @override
  List<Object?> get props => <Object?>[timestampMs, speedChange];
}

/// Looks for the sharpest kink of the ball path shortly around the arrival.
///
/// For every observation in the window the velocity over the previous four and the next four
/// observations (at least three each) is fitted and compared. The largest change wins and counts
/// only if it is at least [DeliveryGeometryConfig.contactMinSpeedChange]. [afterBounceMs] limits the
/// search to the part of the path after the bounce, whose velocity change would otherwise look like
/// a contact.
ContactInfo? detectContact(
  List<BallObservation> observations, {
  required double arrivalMs,
  int? afterBounceMs,
  DeliveryGeometryConfig config = const DeliveryGeometryConfig(),
}) {
  final List<BallObservation> path = observations
      .where((BallObservation o) => afterBounceMs == null || o.timestampMs >= afterBounceMs)
      .toList();
  ContactInfo? best;
  for (int i = 0; i < path.length; i++) {
    final int ts = path[i].timestampMs;
    if (ts < arrivalMs - config.contactWindowBeforeMs || ts > arrivalMs + config.contactWindowAfterMs) {
      continue;
    }
    final List<BallObservation> before = path.sublist(math.max(0, i - 3), i + 1);
    final List<BallObservation> after = path.sublist(i, math.min(path.length, i + 4));
    if (before.length < 3 || after.length < 3) {
      continue;
    }
    final Point2D? velocityBefore = _velocity(before);
    final Point2D? velocityAfter = _velocity(after);
    if (velocityBefore == null || velocityAfter == null) {
      continue;
    }
    final double change = (velocityAfter - velocityBefore).length;
    if (best == null || change > best.speedChange) {
      best = ContactInfo(timestampMs: ts, speedChange: change);
    }
  }
  if (best == null || best.speedChange < config.contactMinSpeedChange) {
    return null;
  }
  return best;
}

/// Image velocity (normalised units per second) over a short stretch of the path.
Point2D? _velocity(List<BallObservation> stretch) {
  final int t0 = stretch.first.timestampMs;
  final List<double> seconds =
      stretch.map<double>((BallObservation o) => (o.timestampMs - t0) / 1000.0).toList();
  final LinearFit? fitX = fitLinear(seconds, stretch.map<double>((BallObservation o) => o.x).toList());
  final LinearFit? fitY = fitLinear(seconds, stretch.map<double>((BallObservation o) => o.y).toList());
  if (fitX == null || fitY == null) {
    return null;
  }
  return Point2D(fitX.slope, fitY.slope);
}
