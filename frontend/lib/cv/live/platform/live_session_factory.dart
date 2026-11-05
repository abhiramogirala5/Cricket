import 'dart:math' as math;

import 'package:gully_umpire/cv/audio/acoustic_impulse_detector.dart';
import 'package:gully_umpire/cv/live/batter_pose_estimator.dart';
import 'package:gully_umpire/cv/live/frame_source.dart';
import 'package:gully_umpire/cv/live/live_analysis.dart';
import 'package:gully_umpire/cv/live/live_session.dart';
import 'package:gully_umpire/cv/live/platform/camera_rig.dart';
import 'package:gully_umpire/cv/live/platform/mlkit_pose_model.dart';
import 'package:gully_umpire/cv/live/vision_worker.dart';

/// Opens the phone's back camera asking for [fps] pictures a second.
Future<FrameSource> openPhoneCamera({int fps = 30}) => CameraRig.open(fps: fps);

/// Starts the ball tracker (in its own isolate) and the batter measuring for the phone.
///
/// Throws a [StateError] with a message for the person when the tracker cannot start.
Future<LiveSessionPort> openPhoneLiveSession(LiveInputs inputs) async {
  final int fps = math.max(15, math.min(60, inputs.policy.cameraFps));
  final VisionWorker worker = await VisionWorker.start(config: VisionWorkerConfig(nominalFps: fps));
  try {
    return LiveVisionSession(
      worker: worker,
      poseEstimator: BatterPoseEstimator(MlKitPoseModel()),
      audioAnalyzer: AcousticImpulseDetector(),
      inputs: inputs,
    );
  } on Object {
    await worker.dispose();
    rethrow;
  }
}
