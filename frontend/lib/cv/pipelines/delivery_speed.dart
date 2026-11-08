import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:gully_umpire/cv/pipelines/ball_observation.dart';
import 'package:gully_umpire/cv/pipelines/delivery_geometry.dart';
import 'package:gully_umpire/cv/tracking/speed_estimator.dart';
import 'package:gully_umpire/cv/util/math_utils.dart';

/// Limits and error allowances of the ball-speed measurement. None of them were tuned on footage:
/// the allowances are the size of the errors the umpire's own inputs are expected to carry.
final class DepthSpeedConfig extends Equatable {
  const DepthSpeedConfig({
    this.minPoints = 6,
    this.minSpanMs = 150,
    this.maxRelativeUncertainty = 0.25,
    this.distanceRelativeError = 0.04,
    this.heightRelativeError = 0.04,
    this.minDistanceM = 3,
    this.maxDistanceM = 40,
  });

  /// Fewest ball points (before the bounce, and before the batter) the speed is worked out from.
  final int minPoints;

  /// Shortest stretch of the flight (first to last point) the speed is worked out from.
  final int minSpanMs;

  /// A speed that may be out by more than this share of itself is not shown at all.
  final double maxRelativeUncertainty;

  /// Share of the speed that an entered phone-to-batter distance can be out by (a distance
  /// measured by walking it is good to about half a metre in twelve).
  final double distanceRelativeError;

  /// Share of the speed that the batter's height can be out by (the batter is the ruler that
  /// tells how big a ball looks at the wicket, and nobody measured him).
  final double heightRelativeError;

  /// Entered distances outside this range (metres) are not believed.
  final double minDistanceM;
  final double maxDistanceM;

  @override
  List<Object?> get props => <Object?>[
        minPoints,
        minSpanMs,
        maxRelativeUncertainty,
        distanceRelativeError,
        heightRelativeError,
        minDistanceM,
        maxDistanceM,
      ];
}

/// The speed of the ball from how fast it shrinks in the picture.
///
/// The camera is behind the bowler, so the ball flies away from it. A ball of known size looks
/// `d = f * ball / Z` wide at a depth of `Z`, so `1 / d` grows in a straight line with time when the
/// ball flies at a steady speed, and its slope is the speed along the line of sight divided by
/// `f * ball`. The focal length `f` is not known, but the batter is a ruler: he stands
/// [cameraToBatterM] away and the ball looks [planeDiameter] wide at his plane, which gives
/// `f * ball = planeDiameter * cameraToBatterM`. The sideways and up-down movement then follow from
/// where the ball is in the picture (the centre of the picture is taken as straight ahead), and the
/// speed is the length of the three together. It does not depend on which way the phone is tilted.
///
/// Only the part of the flight before the bounce is used (the ball is slower after it), and only
/// when the ball was followed for at least [DepthSpeedConfig.minPoints] points over
/// [DepthSpeedConfig.minSpanMs]. The uncertainty combines how well the points lie on a line with
/// what the entered distance and the batter's height can be out by. A speed that may be out by more
/// than [DepthSpeedConfig.maxRelativeUncertainty] is not returned: no number is better than a
/// loose one.
///
/// [bounce] tells whether the ball bounced (null when that is not known, which gives no speed).
SpeedEstimate? estimateDepthSpeed({
  required List<BallObservation> observations,
  required double arrivalMs,
  required BounceInfo? bounce,
  required double planeDiameter,
  required double cameraToBatterM,
  required double ballDiameterM,
  required double aspectRatio,
  required double trackingConfidence,
  DepthSpeedConfig config = const DepthSpeedConfig(),
}) {
  if (bounce == null) {
    return null;
  }
  if (!(cameraToBatterM >= config.minDistanceM && cameraToBatterM <= config.maxDistanceM)) {
    return null;
  }
  if (!(planeDiameter > 0) || !(ballDiameterM > 0) || !(aspectRatio > 0)) {
    return null;
  }
  final int? bounceMs = bounce.bounced ? bounce.timestampMs : null;
  if (bounce.bounced && bounceMs == null) {
    return null;
  }
  final List<BallObservation> segment = observations
      .where(
        (BallObservation o) =>
            o.diameter >= planeDiameter &&
            o.timestampMs <= arrivalMs &&
            (bounceMs == null || o.timestampMs <= bounceMs),
      )
      .toList();
  final int n = segment.length;
  if (n < math.max(3, config.minPoints)) {
    return null;
  }
  if (segment.last.timestampMs - segment.first.timestampMs < config.minSpanMs) {
    return null;
  }

  final int t0 = segment.first.timestampMs;
  final List<double> seconds =
      segment.map<double>((BallObservation o) => (o.timestampMs - t0) / 1000.0).toList();
  final LinearFit? depth = fitLinear(
    seconds,
    segment.map<double>((BallObservation o) => 1.0 / o.diameter).toList(),
  );
  if (depth == null || !(depth.slope > 0)) {
    return null;
  }
  final List<double> fitted = seconds.map<double>(depth.valueAt).toList();
  if (fitted.any((double value) => !(value > 0))) {
    return null;
  }

  // How well the points lie on the line: the standard error of its slope, as a share of the slope.
  final double meanSeconds = meanOf(seconds);
  double spread = 0;
  for (final double s in seconds) {
    spread += (s - meanSeconds) * (s - meanSeconds);
  }
  if (!(spread > 0)) {
    return null;
  }
  final double sigma = depth.rms * math.sqrt(n / (n - 2));
  final double slopeError = sigma / math.sqrt(spread);
  final double fitUncertainty = slopeError / depth.slope;
  if (fitUncertainty > config.maxRelativeUncertainty) {
    return null;
  }

  final double alongM = depth.slope * planeDiameter * cameraToBatterM;
  final LinearFit? sideways = fitLinear(seconds, <double>[
    for (int i = 0; i < n; i++) ballDiameterM * (segment[i].x - 0.5) * aspectRatio * fitted[i],
  ]);
  final LinearFit? upDown = fitLinear(seconds, <double>[
    for (int i = 0; i < n; i++) ballDiameterM * (segment[i].y - 0.5) * fitted[i],
  ]);
  if (sideways == null || upDown == null) {
    return null;
  }
  final double metresPerSecond = math.sqrt(
    alongM * alongM + sideways.slope * sideways.slope + upDown.slope * upDown.slope,
  );
  final double kmph = metresPerSecond * 3.6;
  if (!kmph.isFinite || kmph < SpeedEstimator.minPlausibleKmph || kmph > SpeedEstimator.maxPlausibleKmph) {
    return null;
  }

  final double relative = math.sqrt(
    fitUncertainty * fitUncertainty +
        config.distanceRelativeError * config.distanceRelativeError +
        config.heightRelativeError * config.heightRelativeError,
  );
  if (!relative.isFinite || relative > config.maxRelativeUncertainty) {
    return null;
  }
  final double confidence = clampDouble(
    trackingConfidence * (1 - relative / config.maxRelativeUncertainty),
    0,
    SpeedEstimator.maxConfidence,
  );
  final double releaseKmph = kmph * 1.06;
  final double creaseKmph = kmph * (bounce.bounced ? 0.78 : 0.92);
  return SpeedEstimate(
    kmph: kmph,
    confidence: confidence,
    uncertaintyKmph: kmph * relative,
    releaseKmph: releaseKmph,
    creaseKmph: creaseKmph,
  );
}

/// Estimates the ball speed from the Time-Of-Flight (TOF) between release and arrival,
/// using the entered camera-to-batter distance and perspective geometry.
///
/// Grounded in monocular sports tracking research (Ghimire et al., TechRxiv; Arora et al., PeerJ):
/// While apparent diameter is sensitive to motion blur on fast tennis balls, elapsed flight time
/// over distance provides an extremely robust speed estimate.
SpeedEstimate? estimateTimeOfFlightSpeed({
  required List<BallObservation> observations,
  required double arrivalMs,
  required BounceInfo? bounce,
  required double planeDiameter,
  required double cameraToBatterM,
  required double ballDiameterM,
  required double aspectRatio,
  required double trackingConfidence,
  DepthSpeedConfig config = const DepthSpeedConfig(),
}) {
  if (bounce == null) {
    return null;
  }
  if (!(cameraToBatterM >= config.minDistanceM && cameraToBatterM <= config.maxDistanceM)) {
    return null;
  }
  if (!(planeDiameter > 0) || !(ballDiameterM > 0) || !(aspectRatio > 0)) {
    return null;
  }
  final int? bounceMs = bounce.bounced ? bounce.timestampMs : null;
  if (bounce.bounced && bounceMs == null) {
    return null;
  }

  // Pre-bounce flight segment
  final List<BallObservation> preBounce = observations
      .where(
        (BallObservation o) =>
            o.timestampMs <= arrivalMs &&
            (bounceMs == null || o.timestampMs <= bounceMs),
      )
      .toList();
  if (preBounce.length < 3) {
    return null;
  }

  final int tFirst = preBounce.first.timestampMs;
  final double totalSpanMs = arrivalMs - tFirst;
  if (totalSpanMs < 100) {
    return null;
  }

  // Determine starting depth Z0 from initial diameter observations (median of first 3)
  final List<double> firstDiameters = preBounce
      .take(3)
      .map<double>((BallObservation o) => o.diameter)
      .where((double d) => d > 0)
      .toList();
  if (firstDiameters.isEmpty) {
    return null;
  }
  final double medianFirstDiameter = medianOf(firstDiameters);
  if (!(medianFirstDiameter > 0)) {
    return null;
  }

  // Perspective ratio Z0 / Z_batter = planeDiameter / d_start
  // A bowling release point occurs at the bowling crease (typically 1.2 to 2.8 m ahead of camera).
  // Clamping within [0.05, 0.45] preserves realistic bowling geometry while preventing noisy/small
  // diameter readings from assuming the ball started 80% down the pitch.
  final double depthRatio = clampDouble(
    planeDiameter / medianFirstDiameter,
    0.05,
    0.45,
  );
  final double zStart = cameraToBatterM * depthRatio;
  final double deltaZ = cameraToBatterM - zStart;
  if (!(deltaZ > 0)) {
    return null;
  }

  // Account for bounce deceleration: post-bounce velocity is ~75% of pre-bounce
  final double effectiveSeconds;
  if (bounce.bounced && bounceMs != null && arrivalMs > bounceMs) {
    final double preBounceSeconds = (bounceMs - tFirst) / 1000.0;
    final double postBounceSeconds = (arrivalMs - bounceMs) / 1000.0;
    effectiveSeconds = preBounceSeconds + 0.75 * postBounceSeconds;
  } else {
    effectiveSeconds = totalSpanMs / 1000.0;
  }

  if (!(effectiveSeconds > 0)) {
    return null;
  }

  final double vz = deltaZ / effectiveSeconds;

  // Transverse velocity components
  final double dtPre = math.max(
    0.05,
    (preBounce.last.timestampMs - preBounce.first.timestampMs) / 1000.0,
  );
  final double dxNorm = (preBounce.last.x - preBounce.first.x).abs();
  final double dyNorm = (preBounce.last.y - preBounce.first.y).abs();
  final double vx = (dxNorm * aspectRatio * cameraToBatterM) / dtPre;
  final double vy = (dyNorm * cameraToBatterM) / dtPre;

  final double metresPerSecond = math.sqrt(vz * vz + vx * vx + vy * vy);
  final double kmph = metresPerSecond * 3.6;

  if (!kmph.isFinite ||
      kmph < SpeedEstimator.minPlausibleKmph ||
      kmph > SpeedEstimator.maxPlausibleKmph) {
    return null;
  }

  // Uncertainty from timing jitter (~33ms) + entered distance error + depth tolerance
  final double timingUncertainty = 0.033 / effectiveSeconds;
  final double relative = math.sqrt(
    timingUncertainty * timingUncertainty +
        config.distanceRelativeError * config.distanceRelativeError +
        config.heightRelativeError * config.heightRelativeError +
        0.05 * 0.05,
  );

  if (!relative.isFinite || relative > 0.35) {
    return null;
  }

  final double confidence = clampDouble(
    trackingConfidence * (1.0 - relative / 0.35) * 0.90,
    0,
    SpeedEstimator.maxConfidence,
  );

  final double releaseKmph = kmph * 1.06;
  final double creaseKmph = kmph * (bounce.bounced ? 0.78 : 0.92);
  return SpeedEstimate(
    kmph: kmph,
    confidence: confidence,
    uncertaintyKmph: kmph * relative,
    releaseKmph: releaseKmph,
    creaseKmph: creaseKmph,
  );
}

