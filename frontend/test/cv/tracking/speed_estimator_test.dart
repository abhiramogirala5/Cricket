import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/cv/tracking/speed_estimator.dart';

void main() {
  group('calculateSpeedKmph', () {
    test('converts metres and milliseconds to km/h', () {
      expect(calculateSpeedKmph(18, 0, 900), closeTo(72, 1e-9));
    });

    test('is zero when time does not move forward', () {
      expect(calculateSpeedKmph(18, 900, 900), 0);
      expect(calculateSpeedKmph(18, 900, 100), 0);
    });
  });

  group('SpeedEstimator', () {
    test('estimates speed and confidence', () {
      final SpeedEstimate? estimate = SpeedEstimator.estimate(
        releaseMs: 0,
        arrivalMs: 900,
        flightDistanceM: 15,
        trackingConfidence: 0.8,
        frameIntervalMs: 42,
      );
      expect(estimate, isNotNull);
      expect(estimate!.kmph, closeTo(60, 1e-9));
      // timing score = 1 - 2 * 42 / 900
      expect(estimate.confidence, closeTo(0.8 * (1 - 84 / 900), 1e-9));
    });

    test('never claims more than the maximum confidence', () {
      final SpeedEstimate? estimate = SpeedEstimator.estimate(
        releaseMs: 0,
        arrivalMs: 900,
        flightDistanceM: 15,
        trackingConfidence: 1.0,
        frameIntervalMs: 10,
      );
      expect(estimate!.confidence, SpeedEstimator.maxConfidence);
    });

    test('refuses very short flights and implausible speeds', () {
      expect(
        SpeedEstimator.estimate(
          releaseMs: 0,
          arrivalMs: 100,
          flightDistanceM: 15,
          trackingConfidence: 0.9,
          frameIntervalMs: 10,
        ),
        isNull,
      );
      // 15 m in 270 ms is 200 km/h.
      expect(
        SpeedEstimator.estimate(
          releaseMs: 0,
          arrivalMs: 270,
          flightDistanceM: 15,
          trackingConfidence: 0.9,
          frameIntervalMs: 10,
        ),
        isNull,
      );
      // 3 m in 900 ms is 12 km/h.
      expect(
        SpeedEstimator.estimate(
          releaseMs: 0,
          arrivalMs: 900,
          flightDistanceM: 3,
          trackingConfidence: 0.9,
          frameIntervalMs: 10,
        ),
        isNull,
      );
    });

    test('refuses a missing distance', () {
      expect(
        SpeedEstimator.estimate(
          releaseMs: 0,
          arrivalMs: 900,
          flightDistanceM: 0,
          trackingConfidence: 0.9,
          frameIntervalMs: 10,
        ),
        isNull,
      );
    });
  });
}
