import 'package:gully_umpire/cv/live/batter_pose_estimator.dart';

/// Why the camera could not be used (already in plain words for the person).
class FrameSourceException implements Exception {
  const FrameSourceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Something that delivers camera pictures: the phone's camera, or a stand-in in tests.
abstract interface class FrameSource {
  /// Smallest and largest zoom the camera supports (1.0 = no zoom).
  double get minZoom;
  double get maxZoom;

  /// The zoom that is set now.
  double get zoom;

  /// Starts delivering pictures to [onFrame]. [onProblem] hears about trouble in plain words.
  Future<void> start(
    void Function(RawCameraFrame frame) onFrame, {
    void Function(String message)? onProblem,
  });

  /// Sets the zoom (clamped to what the camera supports) and returns the value that was set.
  Future<double> setZoom(double level);

  /// Stops the pictures and releases the camera. Safe to call more than once.
  Future<void> dispose();
}
