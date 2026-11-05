import 'package:gully_umpire/cv/contracts/camera_frame_input.dart';
import 'package:gully_umpire/cv/contracts/cv_model_info.dart';
import 'package:gully_umpire/cv/contracts/detected_object.dart';

/// Finds the cricket ball (label [SceneLabels.ball]) in a frame.
///
/// May return several candidates (the tracker picks one) or none.
abstract interface class BallDetector {
  /// Who produced the detections. Mock adapters report a `mock-` version.
  CvModelInfo get modelInfo;

  /// Detects ball candidates in [frame].
  Future<List<DetectedObject>> detect(CameraFrameInput frame);

  /// Releases native resources.
  Future<void> dispose();
}
