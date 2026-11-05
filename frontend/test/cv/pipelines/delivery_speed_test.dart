import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/cv/pipelines/ball_observation.dart';
import 'package:gully_umpire/cv/pipelines/delivery_geometry.dart';
import 'package:gully_umpire/cv/pipelines/delivery_speed.dart';
import 'package:gully_umpire/cv/tracking/speed_estimator.dart';
import 'package:gully_umpire/cv/util/length_units.dart';

// These tests use an exact pinhole camera, worked out from the geometry (no noise, no random
// numbers): a ball of 7.2 cm flies from 2.5 m in front of the camera at a steady velocity, and each
// picture is what that camera would see. A focal length of 1.9 picture heights and a batter 40 feet
// away are used; the batter is the ruler, so the ball looks `focal * ball / distance` wide there.

const double _ball = 0.072;
const double _focal = 1.9;
const double _aspect = 0.5625;
const List<double> _start = <double>[0.2, -0.3, 2.5];
const List<double> _velocity = <double>[1.5, 2.0, 25.0];

final double _distanceM = feetToMetres(40);
final double _planeDiameter = _focal * _ball / _distanceM;

double _kmph(List<double> v) => math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]) * 3.6;

BallObservation _seen(int t, List<double> p, {double sizeFactor = 1}) {
  return BallObservation(
    timestampMs: t,
    x: 0.5 + _focal * p[0] / p[2] / _aspect,
    y: 0.5 + _focal * p[1] / p[2],
    confidence: 0.9,
    diameter: _focal * _ball / p[2] * sizeFactor,
  );
}

/// The pictures of the flight, one every 33 ms, until the ball is 1.5 m past the batter. After
/// [bounceMs] the ball moves with [velocityAfter] instead (when given).
List<BallObservation> _flight({
  List<double> velocity = _velocity,
  List<double>? velocityAfter,
  int bounceMs = 200,
  List<double> sizeFactors = const <double>[1],
}) {
  final List<BallObservation> out = <BallObservation>[];
  for (int t = 0;; t += 33) {
    final double s = t / 1000;
    final double tb = bounceMs / 1000;
    final List<double> p = <double>[
      for (int i = 0; i < 3; i++)
        velocityAfter != null && t > bounceMs
            ? _start[i] + velocity[i] * tb + velocityAfter[i] * (s - tb)
            : _start[i] + velocity[i] * s,
    ];
    if (p[2] >= _distanceM + 1.5) {
      return out;
    }
    out.add(_seen(t, p, sizeFactor: sizeFactors[out.length % sizeFactors.length]));
  }
}

/// When the ball reaches the batter on the straight flight.
final double _arrivalMs = 1000 * (_distanceM - _start[2]) / _velocity[2];

SpeedEstimate? _estimate(
  List<BallObservation> observations, {
  double? arrivalMs,
  BounceInfo? bounce = const BounceInfo(bounced: false),
  double? distanceM,
  double tracking = 0.9,
  DepthSpeedConfig config = const DepthSpeedConfig(),
}) {
  return estimateDepthSpeed(
    observations: observations,
    arrivalMs: arrivalMs ?? _arrivalMs,
    bounce: bounce,
    planeDiameter: _planeDiameter,
    cameraToBatterM: distanceM ?? _distanceM,
    ballDiameterM: _ball,
    aspectRatio: _aspect,
    trackingConfidence: tracking,
    config: config,
  );
}

void main() {
  group('feet and metres', () {
    test('a foot is 0.3048 m', () {
      expect(feetToMetres(1), 0.3048);
      expect(feetToMetres(40), closeTo(12.192, 1e-9));
      expect(metresToFeet(12.192), closeTo(40, 1e-9));
    });
  });

  group('estimateDepthSpeed on an exact pinhole camera', () {
    test('gets the speed of a ball flying away, sideways and downwards at once', () {
      final SpeedEstimate estimate = _estimate(_flight())!;

      expect(estimate.kmph, closeTo(_kmph(_velocity), 0.01));
    });

    test('says how far out it may be: what the entered distance and the batter height allow', () {
      final SpeedEstimate estimate = _estimate(_flight())!;

      // The points lie exactly on a line, so only the two allowances are left:
      // sqrt(0.04^2 + 0.04^2) = 5.66% of the speed.
      expect(estimate.uncertaintyKmph! / estimate.kmph, closeTo(0.0566, 0.0005));
    });

    test('is as sure as the track was, less what the uncertainty takes, and never above the cap', () {
      final SpeedEstimate estimate = _estimate(_flight())!;
      expect(estimate.confidence, closeTo(0.9 * (1 - 0.0566 / 0.25), 0.002));

      final SpeedEstimate perfectTrack = _estimate(_flight(), tracking: 1)!;
      expect(perfectTrack.confidence, SpeedEstimator.maxConfidence);
    });

    test('works from six points', () {
      final SpeedEstimate estimate = _estimate(_flight().take(6).toList())!;

      expect(estimate.kmph, closeTo(_kmph(_velocity), 0.01));
    });

    test('a distance that is 10% too long makes the straight-away part of the speed 10% too fast', () {
      final SpeedEstimate estimate = _estimate(_flight(), distanceM: _distanceM * 1.1)!;

      // 27.5 m/s away from the camera, 1.5 m/s sideways and 2 m/s downwards.
      expect(estimate.kmph, closeTo(_kmph(<double>[1.5, 2.0, 27.5]), 0.01));
    });

    test('after a bounce only the flight before it counts, because the ball is slower afterwards', () {
      final List<BallObservation> observations =
          _flight(velocityAfter: const <double>[1.0, -1.0, 15.0]);
      final double arrival = 1000 * ((_distanceM - (_start[2] + 25.0 * 0.2)) / 15 + 0.2);

      // The last picture at or before 200 ms is the one at 198 ms (the lowest point).
      final SpeedEstimate before = _estimate(
        observations,
        arrivalMs: arrival,
        bounce: const BounceInfo(bounced: true, timestampMs: 198),
      )!;
      expect(before.kmph, closeTo(_kmph(_velocity), 0.01));

      // Told that it did not bounce, the slower flight after it is mixed in: far too slow.
      final SpeedEstimate mixed = _estimate(observations, arrivalMs: arrival)!;
      expect(mixed.kmph, lessThan(80));
    });

    test('gives no speed when the bounce came before enough points were followed', () {
      final List<BallObservation> observations =
          _flight(velocityAfter: const <double>[1.0, -1.0, 15.0]);

      expect(
        _estimate(observations, bounce: const BounceInfo(bounced: true, timestampMs: 99)),
        isNull,
      );
    });

    test('gives no speed when it is not known whether the ball bounced', () {
      expect(_estimate(_flight(), bounce: null), isNull);
    });

    test('gives no speed from too few points, or from too short a stretch of the flight', () {
      expect(_estimate(_flight().take(5).toList()), isNull);
      expect(_estimate(_flight().take(6).toList(), config: const DepthSpeedConfig(minSpanMs: 200)), isNull);
    });

    test('gives no speed for a distance that cannot be right', () {
      expect(_estimate(_flight(), distanceM: 2), isNull);
      expect(_estimate(_flight(), distanceM: 50), isNull);
      expect(_estimate(_flight(), distanceM: double.nan), isNull);
    });

    test('gives no speed for a ball that gets bigger (flying towards the camera)', () {
      final List<BallObservation> flight = _flight();
      final List<BallObservation> reversed = <BallObservation>[
        for (int i = 0; i < flight.length; i++)
          BallObservation(
            timestampMs: flight[i].timestampMs,
            x: flight[i].x,
            y: flight[i].y,
            confidence: flight[i].confidence,
            diameter: flight[(flight.length - 1) - i].diameter,
          ),
      ];

      expect(_estimate(reversed), isNull);
    });

    test('the more the measured sizes jump about, the more it says it may be out', () {
      final SpeedEstimate clean = _estimate(_flight())!;
      final SpeedEstimate small = _estimate(_flight(sizeFactors: const <double>[1.1, 0.9]))!;
      final SpeedEstimate large = _estimate(_flight(sizeFactors: const <double>[1.2, 0.8]))!;

      expect(small.uncertaintyKmph!, greaterThan(clean.uncertaintyKmph! * 1.5));
      expect(large.uncertaintyKmph!, greaterThan(small.uncertaintyKmph!));
      expect(large.confidence, lessThan(small.confidence));
      // The truth is inside the stated give or take, even though the middle is off.
      final double truth = _kmph(_velocity);
      expect((small.kmph - truth).abs(), lessThan(small.uncertaintyKmph!));
      expect((large.kmph - truth).abs(), lessThan(large.uncertaintyKmph!));
    });

    test('gives no speed at all when the sizes are too unsteady to say it within a quarter', () {
      expect(_estimate(_flight(sizeFactors: const <double>[1.5, 0.5])), isNull);
    });
  });

  group('estimateTimeOfFlightSpeed (research-backed gully/tennis ball estimator)', () {
    SpeedEstimate? estimateTof(
      List<BallObservation> observations, {
      double? arrivalMs,
      BounceInfo? bounce = const BounceInfo(bounced: false),
      double? distanceM,
      double tracking = 0.9,
      DepthSpeedConfig config = const DepthSpeedConfig(),
    }) {
      return estimateTimeOfFlightSpeed(
        observations: observations,
        arrivalMs: arrivalMs ?? _arrivalMs,
        bounce: bounce,
        planeDiameter: _planeDiameter,
        cameraToBatterM: distanceM ?? _distanceM,
        ballDiameterM: _ball,
        aspectRatio: _aspect,
        trackingConfidence: tracking,
        config: config,
      );
    }

    test('measures speed accurately from flight time and distance', () {
      final SpeedEstimate tof = estimateTof(_flight())!;
      final double truth = _kmph(_velocity);
      expect(tof.kmph, closeTo(truth, 3.0));
      expect(tof.confidence, greaterThan(0.5));
    });

    test('rescues noisy tennis ball sizes where diameter fitting fails', () {
      final List<BallObservation> noisyFlight = _flight(sizeFactors: const <double>[1.5, 0.5]);
      // Pure depth-by-diameter fails due to high fit residual
      expect(_estimate(noisyFlight), isNull);

      // Time-Of-Flight succeeds because flight time and entered distance are preserved
      final SpeedEstimate tof = estimateTof(noisyFlight)!;
      final double truth = _kmph(_velocity);
      expect(tof.kmph, closeTo(truth, 5.0));
      expect(tof.confidence, greaterThan(0.4));
    });

    test('handles bounced balls with deceleration adjustment', () {
      final List<BallObservation> observations =
          _flight(velocityAfter: const <double>[1.0, -1.0, 15.0]);
      final double arrival = 1000 * ((_distanceM - (_start[2] + 25.0 * 0.2)) / 15 + 0.2);
      final SpeedEstimate tof = estimateTof(
        observations,
        arrivalMs: arrival,
        bounce: const BounceInfo(bounced: true, timestampMs: 198),
      )!;
      final double truth = _kmph(_velocity);
      expect(tof.kmph, closeTo(truth, 8.0));
    });

    test('returns null when bounce is unknown or distance is invalid', () {
      expect(estimateTof(_flight(), bounce: null), isNull);
      expect(estimateTof(_flight(), distanceM: 2.0), isNull);
      expect(estimateTof(_flight(), distanceM: 50.0), isNull);
    });
  });
}
