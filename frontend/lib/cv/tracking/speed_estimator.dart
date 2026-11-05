import 'package:equatable/equatable.dart';
import 'package:gully_umpire/cv/util/math_utils.dart';

/// Speed in km/h from a distance and two timestamps (spec §9 `calculateSpeedKmph`).
/// Returns 0 when the end is not after the start.
double calculateSpeedKmph(double distanceMeters, int startTimestampMs, int endTimestampMs) {
  final double seconds = (endTimestampMs - startTimestampMs) / 1000.0;
  if (seconds <= 0) {
    return 0;
  }
  return (distanceMeters / seconds) * 3.6;
}

/// An estimated ball speed. Always an estimate: the UI should show
/// `Estimated 68 km/h`.
final class SpeedEstimate extends Equatable {
  const SpeedEstimate({required this.kmph, required this.confidence, this.uncertaintyKmph});

  final double kmph;

  /// 0..1; never above [SpeedEstimator.maxConfidence].
  final double confidence;

  /// How far the speed may be out (km/h, "give or take"), when the estimate can say. Null for an
  /// estimate that has no way of measuring its own error.
  final double? uncertaintyKmph;

  @override
  List<Object?> get props => <Object?>[kmph, confidence, uncertaintyKmph];

  @override
  String toString() {
    final double? give = uncertaintyKmph;
    return 'SpeedEstimate(${kmph.toStringAsFixed(1)} km/h'
        '${give == null ? '' : ' +/- ${give.toStringAsFixed(1)}'}, ${confidence.toStringAsFixed(2)})';
  }
}

/// Estimates ball speed from the flight time between release and arrival at
/// the batsman plane, assuming a known flight distance.
///
/// A single camera cannot measure that distance, so the caller supplies an
/// assumption (for example the pitch length minus the release distance). The
/// confidence is capped accordingly. The live camera does not use this: it
/// measures the speed from the ball's changing size instead (see
/// `estimateDepthSpeed`), because no distance is known to be right on a street
/// or a turf. Only the simulator, whose pitch is invented anyway, still uses it.
abstract final class SpeedEstimator {
  /// Highest confidence any speed estimate can have.
  static const double maxConfidence = 0.75;

  /// Flights shorter than this are not trusted.
  static const double minFlightMs = 150;

  /// Anything outside this range is treated as a tracking error.
  static const double minPlausibleKmph = 15;
  static const double maxPlausibleKmph = 170;

  /// Returns null when the flight is too short or the speed implausible.
  ///
  /// [frameIntervalMs] is the time between detector samples (it limits the
  /// timing accuracy) and [trackingConfidence] is the 0..1 quality of the track.
  static SpeedEstimate? estimate({
    required int releaseMs,
    required int arrivalMs,
    required double flightDistanceM,
    required double trackingConfidence,
    required double frameIntervalMs,
  }) {
    final int durationMs = arrivalMs - releaseMs;
    if (durationMs < minFlightMs || !(flightDistanceM > 0)) {
      return null;
    }
    final double kmph = calculateSpeedKmph(flightDistanceM, releaseMs, arrivalMs);
    if (kmph < minPlausibleKmph || kmph > maxPlausibleKmph) {
      return null;
    }
    final double timingScore = clamp01(1 - 2 * frameIntervalMs / durationMs);
    final double confidence = clampDouble(trackingConfidence * timingScore, 0, maxConfidence);
    return SpeedEstimate(kmph: kmph, confidence: confidence);
  }
}
