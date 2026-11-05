import 'package:gully_umpire/cv/adapters/mock/mock_scenario.dart';
import 'package:gully_umpire/cv/contracts/camera_frame_input.dart';
import 'package:gully_umpire/cv/contracts/cv_model_info.dart';
import 'package:gully_umpire/cv/contracts/pose.dart';
import 'package:gully_umpire/cv/contracts/pose_estimator.dart';
import 'package:gully_umpire/cv/util/math_utils.dart';
import 'package:gully_umpire/cv/util/seeded_random.dart';

/// Where each pose landmark is relative to the batter's middle (sideways, in picture units) and
/// how far up the body it is (fraction of the batter's height). Landmarks that are not listed are
/// placed at mid-height and reported as not visible.
const Map<int, List<double>> _mockLandmarkLayout = <int, List<double>>{
  PoseLandmarkIndex.nose: <double>[0, 0.92],
  PoseLandmarkIndex.leftEar: <double>[-0.012, 0.93],
  PoseLandmarkIndex.rightEar: <double>[0.012, 0.93],
  PoseLandmarkIndex.leftShoulder: <double>[-0.030, 0.82],
  PoseLandmarkIndex.rightShoulder: <double>[0.030, 0.82],
  PoseLandmarkIndex.leftElbow: <double>[-0.045, 0.65],
  PoseLandmarkIndex.rightElbow: <double>[0.045, 0.65],
  PoseLandmarkIndex.leftWrist: <double>[-0.05, 0.50],
  PoseLandmarkIndex.rightWrist: <double>[0.05, 0.50],
  PoseLandmarkIndex.leftHip: <double>[-0.025, 0.52],
  PoseLandmarkIndex.rightHip: <double>[0.025, 0.52],
  PoseLandmarkIndex.leftKnee: <double>[-0.025, 0.28],
  PoseLandmarkIndex.rightKnee: <double>[0.025, 0.28],
  PoseLandmarkIndex.leftAnkle: <double>[-0.025, 0.04],
  PoseLandmarkIndex.rightAnkle: <double>[0.025, 0.04],
  PoseLandmarkIndex.leftHeel: <double>[-0.026, 0.02],
  PoseLandmarkIndex.rightHeel: <double>[0.026, 0.02],
  PoseLandmarkIndex.leftFootIndex: <double>[-0.03, 0.0],
  PoseLandmarkIndex.rightFootIndex: <double>[0.03, 0.0],
};

/// A stand-in for the real pose model: reports a standing batter at the position given by a
/// [MockScenario], with noise. Deterministic for a given scenario and frame time.
final class MockPoseEstimator implements PoseEstimator {
  MockPoseEstimator(this.scenario) : _world = MockWorld(scenario);

  final MockScenario scenario;
  final MockWorld _world;

  @override
  CvModelInfo get modelInfo => const CvModelInfo(name: 'Mock pose estimator', version: 'mock-pose-1.0');

  @override
  Future<PoseResult?> estimate(CameraFrameInput frame) async => estimateAt(frame.timestampMs);

  /// The pose at [timestampMs], or null when the scenario hides the batter.
  PoseResult? estimateAt(int timestampMs) {
    final MockPoseNoise? noise = MockPoseNoise.forQuality(scenario.poseQuality);
    if (noise == null) {
      return null;
    }
    final SeededRandom random = SeededRandom.derive(scenario.seed, timestampMs + 7);
    final double confidence = clampDouble(noise.confidence + random.nextGaussian() * 0.02, 0, 0.99);
    final double centerX = _world.batsmanCenterXAt(timestampMs);
    final double height = scenario.groundY - scenario.topY;
    final List<PoseLandmark> landmarks = <PoseLandmark>[];
    for (int index = 0; index < PoseLandmarkIndex.count; index++) {
      final List<double>? layout = _mockLandmarkLayout[index];
      final double dx = layout == null ? 0.0 : layout[0];
      final double fraction = layout == null ? 0.5 : layout[1];
      final double visibility = layout == null ? 0.0 : noise.visibility;
      final double x = centerX + dx + random.nextGaussian() * noise.jitter;
      final double y = scenario.groundY - fraction * height + random.nextGaussian() * noise.jitter;
      landmarks.add(PoseLandmark(x: x, y: y, visibility: visibility));
    }
    return PoseResult(landmarks: landmarks, confidence: confidence);
  }

  @override
  Future<void> dispose() async {}
}
