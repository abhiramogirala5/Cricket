import 'package:gully_umpire/cv/adapters/mock/mock_scenario.dart';
import 'package:gully_umpire/cv/contracts/camera_frame_input.dart';
import 'package:gully_umpire/cv/contracts/cv_model_info.dart';
import 'package:gully_umpire/cv/contracts/detected_object.dart';
import 'package:gully_umpire/cv/contracts/scene_object_detector.dart';
import 'package:gully_umpire/cv/geometry/bounding_box.dart';
import 'package:gully_umpire/cv/util/math_utils.dart';
import 'package:gully_umpire/cv/util/seeded_random.dart';

/// A stand-in for the real scene model. It looks at nothing: it reports the objects of a
/// [MockScenario] with noise. The noise depends only on the scenario seed and the frame time, so
/// the same frame always gives the same answer.
///
/// Every result is labelled as a mock (`mock-` model version) so that nothing produced from it
/// can be mistaken for the result of a real model.
final class MockSceneObjectDetector implements SceneObjectDetector {
  MockSceneObjectDetector(this.scenario) : _world = MockWorld(scenario);

  final MockScenario scenario;
  final MockWorld _world;

  @override
  CvModelInfo get modelInfo => const CvModelInfo(name: 'Mock scene detector', version: 'mock-scene-1.0');

  @override
  Future<List<DetectedObject>> detect(CameraFrameInput frame) async => detectAt(frame.timestampMs);

  /// The detections of the frame at [timestampMs].
  List<DetectedObject> detectAt(int timestampMs) {
    final SeededRandom random = SeededRandom.derive(scenario.seed, timestampMs);
    final MockScanNoise noise = MockScanNoise.forQuality(scenario.scanQuality);
    final List<MockSceneObject> objects = <MockSceneObject>[
      ..._world.wicketObjects(),
      _world.distractorChair,
    ];
    final List<DetectedObject> result = <DetectedObject>[];
    for (int index = 0; index < objects.length; index++) {
      final bool isDistractor = index == objects.length - 1;
      final MockSceneObject object = objects[index];
      final double draw = random.nextDouble();
      final double detectionRate = isDistractor ? 1.0 : noise.detectionRate;
      if (draw >= detectionRate) {
        continue;
      }
      final double baseConfidence = isDistractor ? 0.8 : noise.confidence;
      final double confidence =
          clampDouble(baseConfidence + random.nextGaussian() * noise.confidenceSpread, 0.05, 0.99);
      final double jitterX = random.nextGaussian() * noise.jitter;
      final double jitterY = random.nextGaussian() * noise.jitter;
      final double scale = 1 + random.nextGaussian() * noise.sizeJitter;
      final double width = _atLeast(object.box.width * scale, 1e-4);
      final double height = _atLeast(object.box.height * scale, 1e-4);
      result.add(
        DetectedObject(
          label: object.label,
          confidence: confidence,
          boundingBox: BoundingBox.fromCenter(
            centerX: object.box.centerX + jitterX,
            centerY: object.box.centerY + jitterY,
            width: width,
            height: height,
          ),
        ),
      );
    }
    final double personJitter = random.nextGaussian() * 0.002;
    result.add(
      DetectedObject(
        label: SceneLabels.person,
        confidence: 0.9,
        boundingBox: BoundingBox.fromCenter(
          centerX: _world.batsmanCenterXAt(timestampMs) + personJitter,
          centerY: (scenario.groundY + scenario.topY) / 2,
          width: 0.09,
          height: scenario.groundY - scenario.topY,
        ),
      ),
    );
    return result;
  }

  double _atLeast(double value, double minimum) => value < minimum ? minimum : value;

  @override
  Future<void> dispose() async {}
}
