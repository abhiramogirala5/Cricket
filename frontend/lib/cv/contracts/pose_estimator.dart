import 'package:gully_umpire/cv/contracts/camera_frame_input.dart';
import 'package:gully_umpire/cv/contracts/cv_model_info.dart';
import 'package:gully_umpire/cv/contracts/pose.dart';

/// Estimates the batsman's body pose in a frame.
abstract interface class PoseEstimator {
  /// Who produced the pose. Mock adapters report a `mock-` version.
  CvModelInfo get modelInfo;

  /// The batsman's pose, or null when nobody is visible.
  Future<PoseResult?> estimate(CameraFrameInput frame);

  /// Releases native resources.
  Future<void> dispose();
}
