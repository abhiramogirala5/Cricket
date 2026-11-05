import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/cv/contracts/pose.dart';
import 'package:gully_umpire/cv/live/crop_pose.dart';
import 'package:gully_umpire/cv/live/nv21_crop.dart';

List<CropLandmark?> allLandmarks({double likelihood = 0.9}) => <CropLandmark?>[
      for (int i = 0; i < PoseLandmarkIndex.count; i++)
        CropLandmark(x: 10.0 + i, y: 20.0 + i, likelihood: likelihood),
    ];

void main() {
  const PixelRect crop = PixelRect(100, 200, 200, 400);

  group('poseFromCrop', () {
    test('puts landmarks of the cut-out back into the whole picture', () {
      final PoseResult pose = poseFromCrop(
        landmarks: allLandmarks(),
        cropUpright: crop,
        uprightWidth: 400,
        uprightHeight: 800,
      );

      expect(pose.landmarks, hasLength(PoseLandmarkIndex.count));
      // Landmark 0 is at (10, 20) in the cut-out: (100 + 10) / 400 and (200 + 20) / 800.
      expect(pose.landmark(0)!.x, closeTo(110 / 400, 1e-12));
      expect(pose.landmark(0)!.y, closeTo(220 / 800, 1e-12));
      // Landmark 27 (left ankle) is at (37, 47).
      expect(pose.landmark(PoseLandmarkIndex.leftAnkle)!.x, closeTo(137 / 400, 1e-12));
      expect(pose.landmark(PoseLandmarkIndex.leftAnkle)!.y, closeTo(247 / 800, 1e-12));
    });

    test('keeps the likelihood as the visibility of each landmark', () {
      final PoseResult pose = poseFromCrop(
        landmarks: allLandmarks(likelihood: 0.7),
        cropUpright: crop,
        uprightWidth: 400,
        uprightHeight: 800,
      );

      expect(pose.landmark(5)!.visibility, 0.7);
    });

    test('the confidence is the mean likelihood of the landmarks the measurement needs', () {
      final PoseResult pose = poseFromCrop(
        landmarks: allLandmarks(likelihood: 0.9),
        cropUpright: crop,
        uprightWidth: 400,
        uprightHeight: 800,
      );

      expect(pose.confidence, closeTo(0.9, 1e-12));
    });

    test('missing landmarks count as not visible and pull the confidence down', () {
      final List<CropLandmark?> landmarks = allLandmarks(likelihood: 1.0);
      // Hide the feet: two of the seven landmarks the confidence is made of.
      landmarks[PoseLandmarkIndex.leftAnkle] = null;
      landmarks[PoseLandmarkIndex.rightAnkle] = null;

      final PoseResult pose = poseFromCrop(
        landmarks: landmarks,
        cropUpright: crop,
        uprightWidth: 400,
        uprightHeight: 800,
      );

      expect(pose.confidence, closeTo(5 / 7, 1e-12));
      expect(pose.landmark(PoseLandmarkIndex.leftAnkle)!.visibility, 0);
    });

    test('a short list is padded with missing landmarks', () {
      final PoseResult pose = poseFromCrop(
        landmarks: <CropLandmark?>[const CropLandmark(x: 1, y: 1, likelihood: 1)],
        cropUpright: crop,
        uprightWidth: 400,
        uprightHeight: 800,
      );

      expect(pose.landmarks, hasLength(PoseLandmarkIndex.count));
      expect(pose.landmark(0)!.visibility, 1);
      expect(pose.landmark(10)!.visibility, 0);
      expect(pose.confidence, closeTo(1 / 7, 1e-12));
    });

    test('no landmarks at all means no confidence', () {
      final PoseResult pose = poseFromCrop(
        landmarks: const <CropLandmark?>[],
        cropUpright: crop,
        uprightWidth: 400,
        uprightHeight: 800,
      );

      expect(pose.confidence, 0);
    });
  });
}
