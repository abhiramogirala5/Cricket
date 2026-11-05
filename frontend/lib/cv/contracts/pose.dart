import 'package:equatable/equatable.dart';

/// One body landmark. [x] and [y] are normalised 0..1 across the frame.
final class PoseLandmark extends Equatable {
  const PoseLandmark({required this.x, required this.y, this.z, this.visibility});

  final double x;
  final double y;

  /// Relative depth if the estimator provides it.
  final double? z;

  /// Probability 0..1 that the landmark is visible, if provided.
  final double? visibility;

  @override
  List<Object?> get props => <Object?>[x, y, z, visibility];
}

/// A full-body pose (spec §8 `PoseResult`): MediaPipe-style 33 landmarks.
final class PoseResult extends Equatable {
  const PoseResult({required this.landmarks, required this.confidence});

  /// Landmarks indexed by [PoseLandmarkIndex] (33 for MediaPipe).
  final List<PoseLandmark> landmarks;

  /// Overall pose confidence 0..1.
  final double confidence;

  /// The landmark at [index], or null when the pose has fewer landmarks.
  PoseLandmark? landmark(int index) =>
      index >= 0 && index < landmarks.length ? landmarks[index] : null;

  @override
  List<Object?> get props => <Object?>[landmarks, confidence];
}

/// Indices of the MediaPipe Pose Landmarker landmarks used by the core.
abstract final class PoseLandmarkIndex {
  static const int nose = 0;
  static const int leftEar = 7;
  static const int rightEar = 8;
  static const int leftShoulder = 11;
  static const int rightShoulder = 12;
  static const int leftElbow = 13;
  static const int rightElbow = 14;
  static const int leftWrist = 15;
  static const int rightWrist = 16;
  static const int leftHip = 23;
  static const int rightHip = 24;
  static const int leftKnee = 25;
  static const int rightKnee = 26;
  static const int leftAnkle = 27;
  static const int rightAnkle = 28;
  static const int leftHeel = 29;
  static const int rightHeel = 30;
  static const int leftFootIndex = 31;
  static const int rightFootIndex = 32;

  /// Number of landmarks in a full pose.
  static const int count = 33;
}
