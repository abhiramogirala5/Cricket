import 'package:gully_umpire/cv/contracts/pose.dart';
import 'package:gully_umpire/cv/live/nv21_crop.dart';

/// One body landmark as the pose model reports it for a cut-out: pixels of the upright cut-out
/// and the probability (0..1) that the point is really in the picture.
final class CropLandmark {
  const CropLandmark({required this.x, required this.y, required this.likelihood});

  final double x;
  final double y;
  final double likelihood;
}

/// Landmarks whose likelihood makes up the confidence of a pose: the ones the measurement needs.
const List<int> _confidenceLandmarks = <int>[
  PoseLandmarkIndex.nose,
  PoseLandmarkIndex.leftShoulder,
  PoseLandmarkIndex.rightShoulder,
  PoseLandmarkIndex.leftHip,
  PoseLandmarkIndex.rightHip,
  PoseLandmarkIndex.leftAnkle,
  PoseLandmarkIndex.rightAnkle,
];

/// Puts the landmarks of a cut-out back into the whole upright picture (0..1 across it).
///
/// [landmarks] are indexed like [PoseLandmarkIndex] (33 entries; a missing one is null).
/// [cropUpright] is where the cut-out lies in the upright picture of [uprightWidth] x
/// [uprightHeight] pixels. The confidence is the mean likelihood of the landmarks the height
/// measurement relies on.
PoseResult poseFromCrop({
  required List<CropLandmark?> landmarks,
  required PixelRect cropUpright,
  required int uprightWidth,
  required int uprightHeight,
}) {
  final List<PoseLandmark> mapped = <PoseLandmark>[];
  for (int i = 0; i < PoseLandmarkIndex.count; i++) {
    final CropLandmark? point = i < landmarks.length ? landmarks[i] : null;
    if (point == null) {
      mapped.add(const PoseLandmark(x: 0, y: 0, visibility: 0));
    } else {
      mapped.add(
        PoseLandmark(
          x: (cropUpright.left + point.x) / uprightWidth,
          y: (cropUpright.top + point.y) / uprightHeight,
          visibility: point.likelihood,
        ),
      );
    }
  }
  double sum = 0;
  for (final int index in _confidenceLandmarks) {
    sum += mapped[index].visibility ?? 0;
  }
  return PoseResult(landmarks: mapped, confidence: sum / _confidenceLandmarks.length);
}
