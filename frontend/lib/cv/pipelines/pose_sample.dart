import 'package:equatable/equatable.dart';
import 'package:gully_umpire/cv/contracts/pose.dart';

/// The batter's position and size in the picture at one moment, from a pose estimate.
final class PoseSample extends Equatable {
  const PoseSample({
    required this.timestampMs,
    required this.centerX,
    required this.groundY,
    required this.topY,
    required this.confidence,
  });

  final int timestampMs;

  /// Normalised x of the middle of the hips.
  final double centerX;

  /// Normalised y of the feet.
  final double groundY;

  /// Normalised y of the top of the head (estimated from the nose).
  final double topY;

  final double confidence;

  /// Height of the batter in the picture (normalised).
  double get heightNorm => groundY - topY;

  @override
  List<Object?> get props => <Object?>[timestampMs, centerX, groundY, topY, confidence];
}

/// The nose is about this far up the body (fraction of the standing height).
const double noseHeightFraction = 0.92;

/// Turns a pose estimate into a [PoseSample], or null when the batter is not clearly visible:
/// the pose is weak, a hip, the nose or every foot landmark is hidden, or the result is implausibly
/// small. A landmark without a visibility value counts as visible.
PoseSample? poseSampleFrom(
  PoseResult pose,
  int timestampMs, {
  double minPoseConfidence = 0.5,
  double minVisibility = 0.5,
  double minFootVisibility = 0.3,
}) {
  if (pose.confidence < minPoseConfidence) {
    return null;
  }
  bool visible(PoseLandmark? landmark) {
    return landmark != null && (landmark.visibility ?? 1.0) >= minVisibility;
  }
  bool visibleFoot(PoseLandmark? landmark) {
    return landmark != null && (landmark.visibility ?? 1.0) >= minFootVisibility;
  }

  final PoseLandmark? leftHip = pose.landmark(PoseLandmarkIndex.leftHip);
  final PoseLandmark? rightHip = pose.landmark(PoseLandmarkIndex.rightHip);
  final PoseLandmark? nose = pose.landmark(PoseLandmarkIndex.nose);
  if (leftHip == null ||
      rightHip == null ||
      nose == null ||
      !visible(leftHip) ||
      !visible(rightHip) ||
      !visible(nose)) {
    return null;
  }
  double? ground;
  for (final int index in const <int>[
    PoseLandmarkIndex.leftAnkle,
    PoseLandmarkIndex.rightAnkle,
    PoseLandmarkIndex.leftHeel,
    PoseLandmarkIndex.rightHeel,
    PoseLandmarkIndex.leftFootIndex,
    PoseLandmarkIndex.rightFootIndex,
  ]) {
    final PoseLandmark? foot = pose.landmark(index);
    if (foot != null && visibleFoot(foot) && foot.y.isFinite) {
      if (ground == null || foot.y > ground) {
        ground = foot.y;
      }
    }
  }
  if (ground == null) {
    return null;
  }
  final double top = ground - (ground - nose.y) / noseHeightFraction;
  final double centerX = (leftHip.x + rightHip.x) / 2;
  if (!(ground - top > 0.05) || !centerX.isFinite || !top.isFinite) {
    return null;
  }
  return PoseSample(
    timestampMs: timestampMs,
    centerX: centerX,
    groundY: ground,
    topY: top,
    confidence: pose.confidence,
  );
}
