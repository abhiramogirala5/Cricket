import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/cv/adapters/mock/mock.dart';
import 'package:gully_umpire/cv/contracts/pose.dart';
import 'package:gully_umpire/cv/pipelines/pose_sample.dart';

/// A complete, clean pose: feet on y 0.66, nose at y 0.35, hips in the middle.
PoseResult pose({
  double confidence = 0.9,
  double? visibility = 0.95,
  Map<int, PoseLandmark> overrides = const <int, PoseLandmark>{},
}) {
  final List<PoseLandmark> landmarks = List<PoseLandmark>.generate(
    PoseLandmarkIndex.count,
    (int index) => PoseLandmark(x: 0.5, y: 0.5, visibility: visibility),
  );
  landmarks[PoseLandmarkIndex.nose] = PoseLandmark(x: 0.5, y: 0.35, visibility: visibility);
  landmarks[PoseLandmarkIndex.leftHip] = PoseLandmark(x: 0.49, y: 0.5, visibility: visibility);
  landmarks[PoseLandmarkIndex.rightHip] = PoseLandmark(x: 0.51, y: 0.5, visibility: visibility);
  landmarks[PoseLandmarkIndex.leftFootIndex] = PoseLandmark(x: 0.49, y: 0.66, visibility: visibility);
  landmarks[PoseLandmarkIndex.rightFootIndex] = PoseLandmark(x: 0.51, y: 0.66, visibility: visibility);
  overrides.forEach((int index, PoseLandmark landmark) {
    landmarks[index] = landmark;
  });
  return PoseResult(landmarks: landmarks, confidence: confidence);
}

void main() {
  group('poseSampleFrom', () {
    test('turns a clean pose into ground, head top and centre', () {
      final PoseSample? sample = poseSampleFrom(pose(), 1234);
      expect(sample, isNotNull);
      expect(sample!.timestampMs, 1234);
      expect(sample.groundY, closeTo(0.66, 1e-9));
      // The nose is at 92% of the standing height, so the head top is a little higher.
      expect(sample.topY, closeTo(0.66 - (0.66 - 0.35) / 0.92, 1e-9));
      expect(sample.centerX, closeTo(0.5, 1e-9));
      expect(sample.confidence, 0.9);
      expect(sample.heightNorm, closeTo((0.66 - 0.35) / 0.92, 1e-9));
    });

    test('the lowest visible foot landmark gives the ground', () {
      final PoseResult result = pose(
        overrides: <int, PoseLandmark>{
          PoseLandmarkIndex.leftAnkle: const PoseLandmark(x: 0.49, y: 0.64, visibility: 0.9),
          PoseLandmarkIndex.rightFootIndex: const PoseLandmark(x: 0.51, y: 0.67, visibility: 0.9),
          // Not visible, so it must be ignored even though it is the lowest.
          PoseLandmarkIndex.leftHeel: const PoseLandmark(x: 0.49, y: 0.9, visibility: 0.1),
        },
      );
      expect(poseSampleFrom(result, 0)!.groundY, closeTo(0.67, 1e-9));
    });

    test('a landmark without a visibility value counts as visible', () {
      expect(poseSampleFrom(pose(visibility: null), 0), isNotNull);
    });

    test('a weak pose is rejected', () {
      expect(poseSampleFrom(pose(confidence: 0.49), 0), isNull);
      expect(poseSampleFrom(pose(confidence: 0.5), 0), isNotNull);
    });

    test('a barely visible nose is rejected', () {
      final PoseResult result = pose(
        overrides: <int, PoseLandmark>{
          PoseLandmarkIndex.nose: const PoseLandmark(x: 0.5, y: 0.35, visibility: 0.3),
        },
      );
      expect(poseSampleFrom(result, 0), isNull);
    });

    test('a barely visible hip is rejected', () {
      final PoseResult result = pose(
        overrides: <int, PoseLandmark>{
          PoseLandmarkIndex.rightHip: const PoseLandmark(x: 0.51, y: 0.5, visibility: 0.2),
        },
      );
      expect(poseSampleFrom(result, 0), isNull);
    });

    test('a pose with no visible foot is rejected', () {
      final PoseResult result = pose(
        overrides: <int, PoseLandmark>{
          for (final int index in <int>[
            PoseLandmarkIndex.leftAnkle,
            PoseLandmarkIndex.rightAnkle,
            PoseLandmarkIndex.leftHeel,
            PoseLandmarkIndex.rightHeel,
            PoseLandmarkIndex.leftFootIndex,
            PoseLandmarkIndex.rightFootIndex,
          ])
            index: const PoseLandmark(x: 0.5, y: 0.66, visibility: 0.1),
        },
      );
      expect(poseSampleFrom(result, 0), isNull);
    });

    test('an implausibly small person is rejected', () {
      final PoseResult result = pose(
        overrides: <int, PoseLandmark>{
          PoseLandmarkIndex.nose: const PoseLandmark(x: 0.5, y: 0.65, visibility: 0.95),
        },
      );
      expect(poseSampleFrom(result, 0), isNull);
    });

    test('a pose that is too short to hold the landmarks is rejected', () {
      expect(
        poseSampleFrom(const PoseResult(landmarks: <PoseLandmark>[], confidence: 0.9), 0),
        isNull,
      );
    });

    test('the mock estimator gives a sample close to the truth', () {
      final PoseResult result = MockPoseEstimator(const MockScenario()).estimateAt(2000)!;
      final PoseSample sample = poseSampleFrom(result, 2000)!;
      expect(sample.groundY, closeTo(0.66, 0.01));
      expect(sample.topY, closeTo(0.34, 0.01));
      expect(sample.centerX, closeTo(0.5, 0.01));
    });
  });
}
