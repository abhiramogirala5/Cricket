import 'package:gully_umpire/cv/adapters/mock/mock_scenario.dart';
import 'package:gully_umpire/cv/contracts/ball_detector.dart';
import 'package:gully_umpire/cv/contracts/camera_frame_input.dart';
import 'package:gully_umpire/cv/contracts/cv_model_info.dart';
import 'package:gully_umpire/cv/contracts/detected_object.dart';
import 'package:gully_umpire/cv/geometry/bounding_box.dart';
import 'package:gully_umpire/cv/util/math_utils.dart';
import 'package:gully_umpire/cv/util/seeded_random.dart';

/// A stand-in for the real ball model: reports the ball of a [MockScenario] with noise, misses it
/// now and then and adds false "balls" at random places. Deterministic for a given scenario and
/// frame time.
final class MockBallDetector implements BallDetector {
  MockBallDetector(this.scenario) : _world = MockWorld(scenario);

  final MockScenario scenario;
  final MockWorld _world;

  @override
  CvModelInfo get modelInfo => const CvModelInfo(name: 'Mock ball detector', version: 'mock-ball-1.0');

  @override
  Future<List<DetectedObject>> detect(CameraFrameInput frame) async => detectAt(frame.timestampMs);

  /// The detections of the frame at [timestampMs].
  List<DetectedObject> detectAt(int timestampMs) {
    final SeededRandom random = SeededRandom.derive(scenario.seed, timestampMs + 13);
    final MockBallState? state = _world.ballAt(timestampMs);
    final double dropout = scenario.ballDropout ??
        (scenario.deliveryKind == MockDeliveryKind.lostBall ? 0.7 : 0.04);
    final List<DetectedObject> result = <DetectedObject>[];
    final double draw = random.nextDouble();
    if (state != null && draw >= dropout) {
      final double confidence =
          clampDouble(scenario.ballConfidence + random.nextGaussian() * 0.02, 0.5, 0.99);
      final double jitterX = random.nextGaussian() * scenario.ballJitter;
      final double jitterY = random.nextGaussian() * scenario.ballJitter;
      final double scale = 1 + random.nextGaussian() * scenario.ballSizeNoise;
      final double diameter = state.diameter * scale;
      result.add(
        DetectedObject(
          label: SceneLabels.ball,
          confidence: confidence,
          boundingBox: BoundingBox.fromCenter(
            centerX: state.x + jitterX,
            centerY: state.y + jitterY,
            width: diameter / MockWorld.aspectRatio,
            height: diameter,
          ),
        ),
      );
    }
    if (random.nextBool(0.15)) {
      final double dx = random.nextDouble();
      final double dy = random.nextDouble();
      final double confidence = random.nextRange(0.35, 0.65);
      result.add(
        DetectedObject(
          label: SceneLabels.ball,
          confidence: confidence,
          boundingBox: BoundingBox.fromCenter(
            centerX: 0.05 + 0.9 * dx,
            centerY: 0.1 + 0.8 * dy,
            width: 0.012 / MockWorld.aspectRatio,
            height: 0.012,
          ),
        ),
      );
    }
    return result;
  }

  @override
  Future<void> dispose() async {}
}
