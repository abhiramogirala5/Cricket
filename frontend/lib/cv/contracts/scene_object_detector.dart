import 'package:gully_umpire/cv/contracts/camera_frame_input.dart';
import 'package:gully_umpire/cv/contracts/cv_model_info.dart';
import 'package:gully_umpire/cv/contracts/detected_object.dart';

/// Finds scene objects (stumps, chair, bottles, bricks, cones, bucket, bag,
/// wall target, people ...) in a frame.
///
/// Implement this with a real on-device model to replace the mock. Detections
/// use the [SceneLabels] names and normalised boxes.
abstract interface class SceneObjectDetector {
  /// Who produced the detections. Mock adapters report a `mock-` version.
  CvModelInfo get modelInfo;

  /// Detects objects in [frame]. Must not throw for an ordinary empty scene.
  Future<List<DetectedObject>> detect(CameraFrameInput frame);

  /// Releases native resources.
  Future<void> dispose();
}
