import 'package:equatable/equatable.dart';
import 'package:gully_umpire/cv/geometry/bounding_box.dart';
import 'package:gully_umpire/cv/geometry/polygon.dart';
import 'package:gully_umpire/cv/util/math_utils.dart';

/// What stands in for the wicket in the mock picture.
enum MockWicketKind { stumps, chair, bricks, bottles, cones, bucket, wallTarget, none }

/// How clearly the mock scene detector sees the scene.
enum MockScanQuality {
  /// Almost every object is found every frame with high confidence.
  high,

  /// Noisy: objects are missed now and then and shake a little.
  moderate,

  /// Mostly missed. The wicket is usually not found at all.
  low,
}

/// How clearly the mock pose estimator sees the batter.
enum MockPoseQuality { high, moderate, low, none }

/// What the mock bowler does.
enum MockDeliveryKind {
  /// Pitches and goes on to hit the middle of the wicket.
  straightHit,

  /// Pitches and passes the off stump, within the batter's reach.
  offStumpMiss,

  /// Pitches far outside the batter's reach.
  wide,

  /// No bounce, above the waist.
  highFullToss,

  /// Pitches and rises to about chest height; legal unless the match counts such balls.
  bouncer,

  /// Hits the pad low in front of the wicket, heading for the wicket.
  lbwHitting,

  /// Hits the pad low in front, heading wide of the wicket.
  lbwMissing,

  /// Changes direction sharply near the bat, with a sound.
  edge,

  /// The detector loses the ball most of the time.
  lostBall,
}

/// Settings of one synthetic delivery. Everything the mock detectors return follows from these
/// settings and a seed, so a scenario always produces the same detections.
final class MockScenario extends Equatable {
  const MockScenario({
    this.seed = 1,
    this.wicketKind = MockWicketKind.stumps,
    this.scanQuality = MockScanQuality.high,
    this.poseQuality = MockPoseQuality.high,
    this.deliveryKind = MockDeliveryKind.straightHit,
    this.releaseMs = 2000,
    this.batsmanHeightM = 1.70,
    this.batsmanCenterX = 0.5,
    this.groundY = 0.66,
    this.topY = 0.34,
    this.batsmanShiftX = 0.0,
    this.ballConfidence = 0.95,
    this.ballJitter = 0.002,
    this.ballSizeNoise = 0.02,
    this.ballDropout,
  });

  /// Seed of the noise.
  final int seed;

  final MockWicketKind wicketKind;
  final MockScanQuality scanQuality;
  final MockPoseQuality poseQuality;
  final MockDeliveryKind deliveryKind;

  /// Time at which the ball leaves the bowler's hand.
  final int releaseMs;

  /// Real height of the batter.
  final double batsmanHeightM;

  /// Where the batter stands (normalised image x), and where his feet and head are (image y).
  final double batsmanCenterX;
  final double groundY;
  final double topY;

  /// How far (normalised x) the batter moves between 0.3 s and 0.9 s after the release.
  final double batsmanShiftX;

  final double ballConfidence;
  final double ballJitter;
  final double ballSizeNoise;

  /// Chance that the ball detector misses the ball in a frame; null means the default for the
  /// delivery kind (4%, or 70% for [MockDeliveryKind.lostBall]).
  final double? ballDropout;

  MockScenario copyWith({
    int? seed,
    MockWicketKind? wicketKind,
    MockScanQuality? scanQuality,
    MockPoseQuality? poseQuality,
    MockDeliveryKind? deliveryKind,
    int? releaseMs,
    double? batsmanHeightM,
    double? batsmanCenterX,
    double? batsmanShiftX,
    double? ballDropout,
  }) {
    return MockScenario(
      seed: seed ?? this.seed,
      wicketKind: wicketKind ?? this.wicketKind,
      scanQuality: scanQuality ?? this.scanQuality,
      poseQuality: poseQuality ?? this.poseQuality,
      deliveryKind: deliveryKind ?? this.deliveryKind,
      releaseMs: releaseMs ?? this.releaseMs,
      batsmanHeightM: batsmanHeightM ?? this.batsmanHeightM,
      batsmanCenterX: batsmanCenterX ?? this.batsmanCenterX,
      groundY: groundY,
      topY: topY,
      batsmanShiftX: batsmanShiftX ?? this.batsmanShiftX,
      ballConfidence: ballConfidence,
      ballJitter: ballJitter,
      ballSizeNoise: ballSizeNoise,
      ballDropout: ballDropout ?? this.ballDropout,
    );
  }

  @override
  List<Object?> get props => <Object?>[
        seed,
        wicketKind,
        scanQuality,
        poseQuality,
        deliveryKind,
        releaseMs,
        batsmanHeightM,
        batsmanCenterX,
        groundY,
        topY,
        batsmanShiftX,
        ballConfidence,
        ballJitter,
        ballSizeNoise,
        ballDropout,
      ];
}

/// Noise settings per scan quality.
final class MockScanNoise {
  const MockScanNoise({
    required this.detectionRate,
    required this.confidence,
    required this.confidenceSpread,
    required this.jitter,
    required this.sizeJitter,
  });

  final double detectionRate;
  final double confidence;
  final double confidenceSpread;
  final double jitter;
  final double sizeJitter;

  static MockScanNoise forQuality(MockScanQuality quality) {
    switch (quality) {
      case MockScanQuality.high:
        return const MockScanNoise(
          detectionRate: 0.97,
          confidence: 0.92,
          confidenceSpread: 0.03,
          jitter: 0.0015,
          sizeJitter: 0.02,
        );
      case MockScanQuality.moderate:
        return const MockScanNoise(
          detectionRate: 0.80,
          confidence: 0.62,
          confidenceSpread: 0.06,
          jitter: 0.010,
          sizeJitter: 0.15,
        );
      case MockScanQuality.low:
        return const MockScanNoise(
          detectionRate: 0.25,
          confidence: 0.45,
          confidenceSpread: 0.08,
          jitter: 0.020,
          sizeJitter: 0.30,
        );
    }
  }
}

/// Noise settings per pose quality.
final class MockPoseNoise {
  const MockPoseNoise({required this.confidence, required this.jitter, required this.visibility});

  final double confidence;
  final double jitter;
  final double visibility;

  static MockPoseNoise? forQuality(MockPoseQuality quality) {
    switch (quality) {
      case MockPoseQuality.high:
        return const MockPoseNoise(confidence: 0.90, jitter: 0.002, visibility: 0.95);
      case MockPoseQuality.moderate:
        return const MockPoseNoise(confidence: 0.75, jitter: 0.005, visibility: 0.80);
      case MockPoseQuality.low:
        return const MockPoseNoise(confidence: 0.50, jitter: 0.012, visibility: 0.55);
      case MockPoseQuality.none:
        return null;
    }
  }
}

/// One thing in the mock scene: a label and the box where it really is.
final class MockSceneObject {
  const MockSceneObject(this.label, this.box);

  final String label;
  final BoundingBox box;
}

/// Where the mock ball is at one moment.
final class MockBallState {
  const MockBallState({required this.x, required this.y, required this.diameter});

  final double x;
  final double y;

  /// Apparent diameter as a fraction of the picture height.
  final double diameter;
}

class _Key {
  const _Key(this.t, this.x, this.y);

  final double t;
  final double x;
  final double y;
}

/// The true state of the synthetic world: where the ball, the batter and the wicket are at any
/// time. The mock detectors read this and add noise.
///
/// The camera is imagined behind the bowler's end looking at the batter. The ball is released at
/// 3 m from the camera and reaches the batter's plane 18 m away after 0.9 s, so it shrinks in the
/// picture as 1 / distance. Distances are only used to size the ball; the picture is a flat
/// stand-in, not a 3D simulation.
final class MockWorld {
  const MockWorld(this.scenario);

  final MockScenario scenario;

  /// Distance of the batter's plane from the camera.
  static const double planeDistanceM = 18.0;

  /// Distance of the release point from the camera.
  static const double releaseDistanceM = 3.0;

  /// Time from release to the batter's plane.
  static const int arrivalMs = 900;

  /// Real diameter of the ball.
  static const double ballDiameterM = 0.07;

  /// Frame aspect ratio the mock world is drawn for (16:9).
  static const double aspectRatio = 16.0 / 9.0;

  /// Metres per image-height unit at the batter.
  double get metersPerUnitY =>
      scenario.batsmanHeightM / (scenario.groundY - scenario.topY);

  double _yForHeight(double heightM) => scenario.groundY - heightM / metersPerUnitY;

  /// Time of the contact for [MockDeliveryKind.lbwHitting], [MockDeliveryKind.lbwMissing] and
  /// [MockDeliveryKind.edge] deliveries.
  int get contactMs => scenario.releaseMs + arrivalMs;

  /// Whether the delivery ends with the ball hitting the pad or the bat.
  bool get hasContact =>
      scenario.deliveryKind == MockDeliveryKind.lbwHitting ||
      scenario.deliveryKind == MockDeliveryKind.lbwMissing ||
      scenario.deliveryKind == MockDeliveryKind.edge;

  List<_Key> _straight(List<_Key> before, _Key arrival) {
    final _Key last = before.last;
    final double vx = (arrival.x - last.x) / (arrival.t - last.t);
    final double vy = (arrival.y - last.y) / (arrival.t - last.t);
    return <_Key>[
      ...before,
      arrival,
      _Key(arrival.t + 100, arrival.x + vx * 100, arrival.y + vy * 100),
      _Key(arrival.t + 200, arrival.x + vx * 200, arrival.y + vy * 200),
    ];
  }

  List<_Key> _keys() {
    final double Function(double) g = _yForHeight;
    switch (scenario.deliveryKind) {
      case MockDeliveryKind.straightHit:
      case MockDeliveryKind.lostBall:
        return _straight(
          const <_Key>[_Key(0, 0.50, 0.19), _Key(540, 0.505, 0.75)],
          _Key(900, 0.51, g(0.74)),
        );
      case MockDeliveryKind.offStumpMiss:
        return _straight(
          const <_Key>[_Key(0, 0.52, 0.19), _Key(540, 0.54, 0.75)],
          _Key(900, 0.56, g(0.5)),
        );
      case MockDeliveryKind.wide:
        return _straight(
          const <_Key>[_Key(0, 0.55, 0.19), _Key(540, 0.65, 0.75)],
          _Key(900, 0.70, g(0.5)),
        );
      case MockDeliveryKind.highFullToss:
        return _straight(const <_Key>[_Key(0, 0.50, 0.19)], _Key(900, 0.50, g(1.35)));
      case MockDeliveryKind.bouncer:
        return _straight(
          const <_Key>[_Key(0, 0.50, 0.19), _Key(540, 0.50, 0.75)],
          _Key(900, 0.50, g(1.5)),
        );
      case MockDeliveryKind.lbwHitting:
        return <_Key>[
          const _Key(0, 0.50, 0.19),
          const _Key(540, 0.505, 0.75),
          _Key(900, 0.50, g(0.4)),
          _Key(1000, 0.495, g(0.4) + 0.09),
          _Key(1100, 0.49, g(0.4) + 0.18),
        ];
      case MockDeliveryKind.lbwMissing:
        return <_Key>[
          const _Key(0, 0.56, 0.19),
          const _Key(540, 0.575, 0.75),
          _Key(900, 0.575, g(0.4)),
          _Key(1000, 0.57, g(0.4) + 0.09),
          _Key(1100, 0.565, g(0.4) + 0.18),
        ];
      case MockDeliveryKind.edge:
        return <_Key>[
          const _Key(0, 0.50, 0.19),
          const _Key(540, 0.50, 0.75),
          _Key(900, 0.50, g(0.7)),
          _Key(1000, 0.65, g(0.7) - 0.02),
          _Key(1100, 0.80, g(0.7) - 0.06),
        ];
    }
  }

  /// Where the ball really is at [timestampMs], or null when it is not in flight.
  MockBallState? ballAt(int timestampMs) {
    final double dt = (timestampMs - scenario.releaseMs).toDouble();
    final List<_Key> keys = _keys();
    if (dt < 0 || dt > keys.last.t) {
      return null;
    }
    double x = keys.last.x;
    double y = keys.last.y;
    for (int i = 0; i + 1 < keys.length; i++) {
      final _Key a = keys[i];
      final _Key b = keys[i + 1];
      if (dt <= b.t) {
        final double u = (dt - a.t) / (b.t - a.t);
        x = a.x + (b.x - a.x) * u;
        y = a.y + (b.y - a.y) * u;
        break;
      }
    }
    final double planeDiameter = ballDiameterM / metersPerUnitY;
    final double depth = releaseDistanceM + (planeDistanceM - releaseDistanceM) * dt / arrivalMs;
    return MockBallState(x: x, y: y, diameter: planeDiameter * planeDistanceM / depth);
  }

  /// Where the middle of the batter is at [timestampMs].
  double batsmanCenterXAt(int timestampMs) {
    final double u = clamp01((timestampMs - scenario.releaseMs - 300) / 600);
    return scenario.batsmanCenterX + scenario.batsmanShiftX * u;
  }

  /// The objects that make up the wicket (before noise).
  List<MockSceneObject> wicketObjects() {
    const double cx = 0.5;
    BoundingBox box(double x, double y, double w, double h) =>
        BoundingBox.fromCenter(centerX: x, centerY: y, width: w, height: h);
    switch (scenario.wicketKind) {
      case MockWicketKind.stumps:
        return <MockSceneObject>[
          for (final double dx in const <double>[-0.017, 0.0, 0.017])
            MockSceneObject('traditional_stumps', box(cx + dx, 0.49, 0.012, 0.14)),
        ];
      case MockWicketKind.chair:
        return <MockSceneObject>[MockSceneObject('chair', box(cx, 0.5, 0.09, 0.16))];
      case MockWicketKind.bricks:
        return <MockSceneObject>[
          for (final double y in const <double>[0.549, 0.527, 0.505])
            MockSceneObject('brick', box(cx, y, 0.05, 0.022)),
        ];
      case MockWicketKind.bottles:
        return <MockSceneObject>[
          for (final double dx in const <double>[-0.02, 0.0, 0.02])
            MockSceneObject('bottle', box(cx + dx, 0.52, 0.016, 0.08)),
        ];
      case MockWicketKind.cones:
        return <MockSceneObject>[
          for (final double dx in const <double>[-0.04, 0.0, 0.04])
            MockSceneObject('cone', box(cx + dx, 0.535, 0.03, 0.05)),
        ];
      case MockWicketKind.bucket:
        return <MockSceneObject>[MockSceneObject('bucket', box(cx, 0.525, 0.05, 0.07))];
      case MockWicketKind.wallTarget:
        return <MockSceneObject>[MockSceneObject('wall_target', box(cx, 0.485, 0.05, 0.15))];
      case MockWicketKind.none:
        return const <MockSceneObject>[];
    }
  }

  /// The true wicket outline: the smallest box around the wicket objects, or null for none.
  Polygon? truthWicketPolygon() {
    final List<MockSceneObject> objects = wicketObjects();
    if (objects.isEmpty) {
      return null;
    }
    BoundingBox union = objects.first.box;
    for (int i = 1; i < objects.length; i++) {
      union = union.union(objects[i].box);
    }
    return Polygon.fromBox(union);
  }

  /// A chair at the side that is always in view (it must never be taken for the wicket).
  MockSceneObject get distractorChair =>
      MockSceneObject('chair', BoundingBox.fromCenter(centerX: 0.18, centerY: 0.7, width: 0.08, height: 0.14));
}
