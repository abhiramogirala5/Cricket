import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart' as mlkit;
import 'package:gully_umpire/cv/contracts/pose.dart' show PoseLandmarkIndex;
import 'package:gully_umpire/cv/live/batter_pose_estimator.dart';
import 'package:gully_umpire/cv/live/crop_pose.dart';

/// The body-pose model of Google ML Kit (the pre-trained, on-device "base" model).
///
/// No model of the app's own is trained: ML Kit finds the body landmarks, and the app's own code
/// does the measuring from them.
final class MlKitPoseModel implements PoseLandmarkModel {
  MlKitPoseModel()
      : _detector = mlkit.PoseDetector(
          options: mlkit.PoseDetectorOptions(
            mode: mlkit.PoseDetectionMode.stream,
            model: mlkit.PoseDetectionModel.base,
          ),
        );

  final mlkit.PoseDetector _detector;

  /// Where each landmark we use sits in the 33-point layout of [PoseLandmarkIndex].
  static const Map<mlkit.PoseLandmarkType, int> _indices = <mlkit.PoseLandmarkType, int>{
    mlkit.PoseLandmarkType.nose: PoseLandmarkIndex.nose,
    mlkit.PoseLandmarkType.leftEar: PoseLandmarkIndex.leftEar,
    mlkit.PoseLandmarkType.rightEar: PoseLandmarkIndex.rightEar,
    mlkit.PoseLandmarkType.leftShoulder: PoseLandmarkIndex.leftShoulder,
    mlkit.PoseLandmarkType.rightShoulder: PoseLandmarkIndex.rightShoulder,
    mlkit.PoseLandmarkType.leftElbow: PoseLandmarkIndex.leftElbow,
    mlkit.PoseLandmarkType.rightElbow: PoseLandmarkIndex.rightElbow,
    mlkit.PoseLandmarkType.leftWrist: PoseLandmarkIndex.leftWrist,
    mlkit.PoseLandmarkType.rightWrist: PoseLandmarkIndex.rightWrist,
    mlkit.PoseLandmarkType.leftHip: PoseLandmarkIndex.leftHip,
    mlkit.PoseLandmarkType.rightHip: PoseLandmarkIndex.rightHip,
    mlkit.PoseLandmarkType.leftKnee: PoseLandmarkIndex.leftKnee,
    mlkit.PoseLandmarkType.rightKnee: PoseLandmarkIndex.rightKnee,
    mlkit.PoseLandmarkType.leftAnkle: PoseLandmarkIndex.leftAnkle,
    mlkit.PoseLandmarkType.rightAnkle: PoseLandmarkIndex.rightAnkle,
    mlkit.PoseLandmarkType.leftHeel: PoseLandmarkIndex.leftHeel,
    mlkit.PoseLandmarkType.rightHeel: PoseLandmarkIndex.rightHeel,
    mlkit.PoseLandmarkType.leftFootIndex: PoseLandmarkIndex.leftFootIndex,
    mlkit.PoseLandmarkType.rightFootIndex: PoseLandmarkIndex.rightFootIndex,
  };

  @override
  Future<List<CropLandmark?>?> detect({
    required Uint8List nv21,
    required int width,
    required int height,
    required int rotationDegrees,
  }) async {
    final mlkit.InputImage image = mlkit.InputImage.fromBytes(
      bytes: nv21,
      metadata: mlkit.InputImageMetadata(
        size: Size(width.toDouble(), height.toDouble()),
        rotation: mlkit.InputImageRotationValue.fromRawValue(rotationDegrees) ??
            mlkit.InputImageRotation.rotation0deg,
        format: mlkit.InputImageFormat.nv21,
        bytesPerRow: width,
      ),
    );
    final List<mlkit.Pose> poses = await _detector.processImage(image);
    if (poses.isEmpty) {
      return null;
    }
    final List<CropLandmark?> landmarks = List<CropLandmark?>.filled(PoseLandmarkIndex.count, null);
    for (final MapEntry<mlkit.PoseLandmarkType, mlkit.PoseLandmark> entry in poses.first.landmarks.entries) {
      final int? index = _indices[entry.key];
      if (index != null) {
        landmarks[index] = CropLandmark(
          x: entry.value.x,
          y: entry.value.y,
          likelihood: entry.value.likelihood,
        );
      }
    }
    return landmarks;
  }

  @override
  Future<void> close() => _detector.close();
}
