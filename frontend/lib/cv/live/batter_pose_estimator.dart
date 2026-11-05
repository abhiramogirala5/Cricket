import 'dart:typed_data';

import 'package:gully_umpire/cv/contracts/pose.dart';
import 'package:gully_umpire/cv/geometry/polygon.dart';
import 'package:gully_umpire/cv/live/batter_region.dart';
import 'package:gully_umpire/cv/live/crop_pose.dart';
import 'package:gully_umpire/cv/live/nv21_crop.dart';

/// One picture from the camera, exactly as the camera delivered it.
final class RawCameraFrame {
  const RawCameraFrame({
    required this.nv21,
    required this.width,
    required this.height,
    required this.rowStride,
    required this.rotationDegrees,
    required this.timestampMs,
  });

  /// The whole NV21 picture: the brightness plane followed by the interleaved colour plane.
  final Uint8List nv21;

  /// Size of the picture as the camera delivers it (not turned upright).
  final int width;
  final int height;

  /// Bytes from one brightness row to the next.
  final int rowStride;

  /// Clockwise turn that makes the picture upright (0, 90, 180 or 270).
  final int rotationDegrees;

  /// Arrival time in milliseconds on a steady clock.
  final int timestampMs;

  /// The brightness plane only (a view, not a copy).
  Uint8List get yPlane {
    final int end = rowStride * height;
    return Uint8List.sublistView(nv21, 0, end > nv21.length ? nv21.length : end);
  }
}

/// A body-pose model that works on one cut-out picture. The phone implementation wraps ML Kit.
abstract interface class PoseLandmarkModel {
  /// Finds the most prominent person in the NV21 picture [nv21] of [width] x [height] pixels (in
  /// the camera's own orientation; [rotationDegrees] turns it upright) and returns the 33 landmarks
  /// in pixels of the *upright* picture, indexed like [PoseLandmarkIndex]. Null when nobody is
  /// found.
  Future<List<CropLandmark?>?> detect({
    required Uint8List nv21,
    required int width,
    required int height,
    required int rotationDegrees,
  });

  Future<void> close();
}

/// Measures the batter's pose on a cut-out around the wicket.
///
/// Running the pose model on the whole picture finds the most prominent person, which at a ground
/// is often the bowler or an umpire. The batter stands in front of his wicket, so the picture is cut
/// down to that area first: the model then sees the right person, and more pixels of him.
final class BatterPoseEstimator {
  BatterPoseEstimator(this._model);

  final PoseLandmarkModel _model;

  /// The pose of the batter at [wicket] (0..1 picture coordinates) in [frame], with landmarks in
  /// 0..1 coordinates of the whole upright picture. Null when the batter is not found.
  ///
  /// The cut-out is made before the first `await`, so the frame's buffer may be reused as soon as
  /// this returns a future.
  Future<PoseResult?> estimate(RawCameraFrame frame, Polygon wicket) async {
    final ({int width, int height}) upright =
        Nv21Cropper.uprightSize(frame.width, frame.height, frame.rotationDegrees);
    final PixelRect? region = BatterRegion.forWicket(
      wicket: wicket,
      uprightWidth: upright.width,
      uprightHeight: upright.height,
      halfWidthFactor: 3.5,
      heightFactor: 2.2,
      bottomFactor: 1.6,
      topFactor: 4.8,
    );
    if (region == null) {
      return null;
    }
    final Nv21Crop? crop = Nv21Cropper.crop(
      source: frame.nv21,
      rawWidth: frame.width,
      rawHeight: frame.height,
      rowStride: frame.rowStride,
      rotationDegrees: frame.rotationDegrees,
      upright: region,
    );
    if (crop == null) {
      return null;
    }
    final List<CropLandmark?>? landmarks = await _model.detect(
      nv21: crop.bytes,
      width: crop.width,
      height: crop.height,
      rotationDegrees: frame.rotationDegrees,
    );
    if (landmarks == null) {
      return null;
    }
    return poseFromCrop(
      landmarks: landmarks,
      cropUpright: crop.upright,
      uprightWidth: upright.width,
      uprightHeight: upright.height,
    );
  }

  Future<void> close() => _model.close();
}
