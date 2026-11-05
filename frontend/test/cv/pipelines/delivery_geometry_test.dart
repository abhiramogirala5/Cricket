import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/cv/geometry/point2d.dart';
import 'package:gully_umpire/cv/pipelines/ball_observation.dart';
import 'package:gully_umpire/cv/pipelines/delivery_geometry.dart';

const double planeDiameter = 0.0132;

/// The ball's apparent diameter at [ms] after release in the mock world: it is 3 m from the
/// camera at the release and 18 m (the batter plane) at 900 ms, flying at a steady speed.
double diameterAt(int ms) => planeDiameter * 18 / (3 + 15 * ms / 900);

BallObservation obs(int ms, {double x = 0.5, double y = 0.5, double? diameter}) {
  return BallObservation(
    timestampMs: ms,
    x: x,
    y: y,
    confidence: 0.9,
    diameter: diameter ?? diameterAt(ms),
  );
}

List<BallObservation> flight(int fromMs, int toMs, {double noise = 0}) {
  final List<BallObservation> list = <BallObservation>[];
  int index = 0;
  for (int ms = fromMs; ms <= toMs; ms += 50) {
    final double sign = index.isEven ? 1 : -1;
    list.add(obs(ms, diameter: diameterAt(ms) * (1 + noise * sign)));
    index += 1;
  }
  return list;
}

void main() {
  group('fitLinear', () {
    test('fits an exact line with no residual', () {
      final LinearFit fit = fitLinear(<double>[0, 1, 2, 3], <double>[1, 3, 5, 7])!;
      expect(fit.slope, closeTo(2, 1e-12));
      expect(fit.intercept, closeTo(1, 1e-12));
      expect(fit.rms, closeTo(0, 1e-12));
      expect(fit.meanY, closeTo(4, 1e-12));
      expect(fit.valueAt(10), closeTo(21, 1e-12));
    });

    test('reports the residual of noisy data', () {
      final LinearFit fit = fitLinear(<double>[0, 1, 2, 3], <double>[0, 1.2, 1.8, 3.1])!;
      expect(fit.slope, closeTo(0.99, 1e-9));
      expect(fit.rms, closeTo(0.1475, 1e-3));
      expect(fit.rms, greaterThan(0));
      expect(fit.rms, lessThan(0.2));
    });

    test('returns null for too little or degenerate data', () {
      expect(fitLinear(<double>[1], <double>[1]), isNull);
      expect(fitLinear(<double>[2, 2, 2], <double>[1, 2, 3]), isNull);
      expect(fitLinear(<double>[1, 2], <double>[1]), isNull);
    });
  });

  group('estimateArrivalMs', () {
    test('finds the time the ball reaches the batter plane', () {
      final double? arrival = estimateArrivalMs(flight(0, 800), planeDiameter: planeDiameter);
      expect(arrival, isNotNull);
      expect(arrival!, closeTo(900, 1e-6));
    });

    test('only the diameter at the batter matters, not observations beyond it', () {
      final double? arrival = estimateArrivalMs(flight(0, 900), planeDiameter: planeDiameter);
      expect(arrival!, closeTo(900, 1e-6));
    });

    test('tolerates a little size noise', () {
      final double? arrival =
          estimateArrivalMs(flight(0, 800, noise: 0.02), planeDiameter: planeDiameter);
      expect(arrival, isNotNull);
      expect(arrival!, closeTo(900, 30));
    });

    test('needs enough observations where the ball is clearly nearer than the batter', () {
      expect(estimateArrivalMs(flight(0, 100), planeDiameter: planeDiameter), isNull);
    });

    test('does not extrapolate far past the last observation', () {
      // The ball was only seen early in its flight.
      expect(estimateArrivalMs(flight(0, 250), planeDiameter: planeDiameter), isNull);
    });

    test('a ball that grows (comes towards the camera) has no arrival', () {
      final List<BallObservation> growing = <BallObservation>[
        for (int ms = 0; ms <= 400; ms += 50) obs(ms, diameter: 0.02 + 0.0001 * ms),
      ];
      expect(estimateArrivalMs(growing, planeDiameter: planeDiameter), isNull);
    });

    test('an invalid plane diameter has no arrival', () {
      expect(estimateArrivalMs(flight(0, 800), planeDiameter: 0), isNull);
      expect(estimateArrivalMs(flight(0, 800), planeDiameter: -1), isNull);
    });
  });

  group('ballPositionAt', () {
    final List<BallObservation> track = <BallObservation>[
      obs(0, x: 0.5, y: 0.2),
      obs(100, x: 0.6, y: 0.4),
    ];

    test('interpolates between observations', () {
      final Point2D position = ballPositionAt(track, 50)!;
      expect(position.x, closeTo(0.55, 1e-12));
      expect(position.y, closeTo(0.3, 1e-12));
    });

    test('returns the observation itself at its own time', () {
      final Point2D position = ballPositionAt(track, 100)!;
      expect(position.x, closeTo(0.6, 1e-12));
      expect(position.y, closeTo(0.4, 1e-12));
    });

    test('extends the last two observations a short way', () {
      final Point2D position = ballPositionAt(track, 150)!;
      expect(position.x, closeTo(0.65, 1e-12));
      expect(position.y, closeTo(0.5, 1e-12));
    });

    test('does not extrapolate far or backwards', () {
      expect(ballPositionAt(track, 300), isNull);
      expect(ballPositionAt(track, -10), isNull);
    });

    test('needs two observations to extrapolate', () {
      expect(ballPositionAt(<BallObservation>[obs(0)], 50), isNull);
      expect(ballPositionAt(const <BallObservation>[], 50), isNull);
    });
  });

  group('detectBounce', () {
    List<BallObservation> bouncing() {
      return <BallObservation>[
        for (int ms = 0; ms <= 700; ms += 50)
          obs(ms, y: ms <= 500 ? 0.2 + 0.55 * ms / 500 : 0.75 - 0.15 * (ms - 500) / 200),
      ];
    }

    test('sees the lowest point of a bounce', () {
      final BounceInfo? bounce = detectBounce(bouncing(), arrivalY: 0.6);
      expect(bounce, isNotNull);
      expect(bounce!.bounced, isTrue);
      expect(bounce.timestampMs, 500);
    });

    test('a ball that only falls towards the batter did not bounce', () {
      final List<BallObservation> fullToss = <BallObservation>[
        for (int ms = 0; ms <= 700; ms += 50) obs(ms, y: 0.2 + 0.3 * ms / 700),
      ];
      final BounceInfo? bounce = detectBounce(fullToss, arrivalY: 0.5);
      expect(bounce, isNotNull);
      expect(bounce!.bounced, isFalse);
      expect(bounce.timestampMs, isNull);
    });

    test('is not sure with too few observations', () {
      expect(detectBounce(bouncing().sublist(0, 5), arrivalY: 0.6), isNull);
    });

    test('a tiny dip is not a bounce', () {
      final List<BallObservation> flat = <BallObservation>[
        for (int ms = 0; ms <= 700; ms += 50) obs(ms, y: ms == 350 ? 0.23 : 0.2),
      ];
      expect(detectBounce(flat, arrivalY: 0.2)!.bounced, isFalse);
    });

    test('detects a skidding ball on turf where drop is substantial and velocity reverses', () {
      final List<BallObservation> skidding = <BallObservation>[
        obs(0, y: 0.20),
        obs(100, y: 0.32),
        obs(200, y: 0.45),
        obs(300, y: 0.58),
        obs(400, y: 0.70),
        obs(500, y: 0.69),
        obs(600, y: 0.68),
      ];
      final BounceInfo? bounce = detectBounce(skidding, arrivalY: 0.68);
      expect(bounce, isNotNull);
      expect(bounce!.bounced, isTrue);
      expect(bounce.timestampMs, 400);
    });
  });

  group('detectContact', () {
    List<BallObservation> kinked() {
      return <BallObservation>[
        for (int ms = 0; ms <= 400; ms += 50) obs(ms, x: 0.5, y: 0.75 - 0.5 * ms / 1000),
        for (int ms = 450; ms <= 600; ms += 50) obs(ms, x: 0.5 + 1.5 * (ms - 400) / 1000, y: 0.55),
      ];
    }

    test('finds a sharp change of direction near the arrival', () {
      final ContactInfo? contact = detectContact(kinked(), arrivalMs: 400);
      expect(contact, isNotNull);
      expect(contact!.timestampMs, 400);
      // |(1.5, 0) - (0, -0.5)|
      expect(contact.speedChange, closeTo(1.58114, 1e-4));
    });

    test('a straight path has no contact', () {
      final List<BallObservation> straight = <BallObservation>[
        for (int ms = 0; ms <= 600; ms += 50) obs(ms, x: 0.5, y: 0.75 - 0.5 * ms / 1000),
      ];
      expect(detectContact(straight, arrivalMs: 400), isNull);
    });

    test('a gentle bend is below the threshold', () {
      final List<BallObservation> gentle = <BallObservation>[
        for (int ms = 0; ms <= 400; ms += 50) obs(ms, x: 0.5, y: 0.75 - 0.5 * ms / 1000),
        for (int ms = 450; ms <= 600; ms += 50)
          obs(ms, x: 0.5 + 0.4 * (ms - 400) / 1000, y: 0.55 - 0.5 * (ms - 400) / 1000),
      ];
      expect(detectContact(gentle, arrivalMs: 400), isNull);
    });

    test('a kink far from the arrival is ignored', () {
      expect(detectContact(kinked(), arrivalMs: 1500), isNull);
    });

    test('observations before the bounce are not used', () {
      expect(detectContact(kinked(), arrivalMs: 400, afterBounceMs: 450), isNull);
    });
  });
}
