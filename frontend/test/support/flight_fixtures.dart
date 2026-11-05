import 'package:gully_umpire/cv/geometry/point2d.dart';
import 'package:gully_umpire/cv/geometry/polygon.dart';
import 'package:gully_umpire/cv/pipelines/ball_observation.dart';
import 'package:gully_umpire/cv/pipelines/pose_sample.dart';

import 'replay_fixtures.dart';

/// Height of the batter in the fixtures (metres).
const double batterHeightM = 1.7;

/// Real diameter of the ball in the fixtures (metres), a cricket ball.
const double ballDiameterM = 0.072;

/// The batter stands with the feet at 0.9 and the head at 0.3 of the picture height.
const double batterGroundY = 0.9;
const double batterTopY = 0.3;

/// Metres per picture height at the batter.
const double metersPerUnitY = batterHeightM / (batterGroundY - batterTopY);

/// How big the ball looks (share of the picture height) when it is at the batter.
const double planeDiameter = ballDiameterM / metersPerUnitY;

/// The ball reaches the batter at this time in every flight below.
const int flightArrivalMs = 1000;

/// A flight towards the batter, as the live tracker would deliver it: one picture every 33 ms from
/// [startMs] to 1060 ms, flying straight away from the camera.
///
/// The ball looks smaller and smaller so that `1 / diameter` grows by exactly 0.032 per
/// millisecond and equals `1 / planeDiameter` at [flightArrivalMs], which is what a ball in steady
/// flight does. With [bounce] the ball is seen to fall in the picture until 700 ms, to hit the
/// ground there (the lowest point in the picture) and to rise again until it reaches the batter at
/// about 0.58 of the picture height (a height of about 0.9 m). Without a bounce it sinks slowly
/// from 0.40 to 0.55 (a full toss, about 1.0 m high at the batter).
List<BallObservation> flight({int startMs = 400, bool bounce = true, double confidence = 0.9}) {
  final List<BallObservation> observations = <BallObservation>[];
  for (int t = startMs; t <= 1060; t += 33) {
    final double inverse = 1 / planeDiameter - 0.032 * (flightArrivalMs - t);
    final double y;
    if (bounce) {
      y = t <= 700 ? 0.40 + 0.30 * (t - 400) / 300 : 0.70 - 0.0004 * (t - 700);
    } else {
      y = 0.40 + 0.15 * (t - 400) / 600;
    }
    observations.add(
      BallObservation(
        timestampMs: t,
        x: 0.5,
        y: y,
        confidence: confidence,
        diameter: 1 / inverse,
      ),
    );
  }
  return observations;
}

/// Times of the pictures in which the ball could have been seen.
List<int> timesOf(List<BallObservation> observations) {
  return <int>[for (final BallObservation o in observations) o.timestampMs];
}

/// The batter standing still for the whole flight.
List<PoseSample> standingBatter({int startMs = 400}) {
  return <PoseSample>[
    for (int i = 0; i < 6; i++)
      poseAt(startMs + i * 100, groundY: batterGroundY, topY: batterTopY),
  ];
}

/// The wicket as an outline around the middle of the picture.
Polygon wicketOutline() {
  return Polygon(const <Point2D>[
    Point2D(0.46, 0.30),
    Point2D(0.54, 0.30),
    Point2D(0.54, 0.62),
    Point2D(0.46, 0.62),
  ]);
}
