import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gully_umpire/core/config/app_config.dart';
import 'package:gully_umpire/core/di/core_providers.dart';
import 'package:gully_umpire/cv/device/device_policy.dart';
import 'package:gully_umpire/cv/engine/cv_engine.dart';

/// The live camera needs the Android camera and body-pose plugins; other platforms (and the
/// desktop machines that run the tests) are plain scorers.
final Provider<bool> liveCameraSupportedProvider = Provider<bool>((ref) => Platform.isAndroid);

/// The class of this phone, guessed from the number of processor cores (the memory size is not
/// available without a plugin). It only ever makes the app more careful, never less.
final Provider<DeviceProfile> deviceProfileProvider = Provider<DeviceProfile>((ref) {
  return DeviceProfile.classify(processorCount: Platform.numberOfProcessors);
});

/// Which engine runs: the live camera when it is switched on, supported and the phone is able to
/// keep up; the simulation only when a development build asks for it; otherwise scoring only.
CvMode chooseCvMode({
  required AppConfig config,
  required bool liveSupported,
  required DeviceProfile profile,
}) {
  if (config.simulateCv && !config.isProduction) {
    return CvMode.simulated;
  }
  if (config.enableLiveCv && liveSupported && profile != DeviceProfile.scoreOnly) {
    return CvMode.live;
  }
  return CvMode.scoreOnly;
}

final Provider<CvMode> cvModeProvider = Provider<CvMode>((ref) {
  return chooseCvMode(
    config: ref.watch(appConfigProvider),
    liveSupported: ref.watch(liveCameraSupportedProvider),
    profile: ref.watch(deviceProfileProvider),
  );
});

/// What this phone is allowed to do with computer vision.
final Provider<DevicePolicy> devicePolicyProvider = Provider<DevicePolicy>((ref) {
  final DeviceProfile profile = ref.watch(deviceProfileProvider);
  if (ref.watch(cvModeProvider) == CvMode.live) {
    return DevicePolicy.live(profile);
  }
  return DevicePolicy.forProfile(profile);
});

/// The computer-vision engine (see [chooseCvMode]).
///
/// The live engine only describes the capability; the camera itself belongs to the screens that
/// show it, so that it is released as soon as they close.
final Provider<CvEngine> cvEngineProvider = Provider<CvEngine>((ref) {
  final CvEngine engine = switch (ref.watch(cvModeProvider)) {
    CvMode.simulated => SimulatedCvEngine(),
    CvMode.live => const LiveCvEngine(),
    CvMode.scoreOnly => const ScoreOnlyCvEngine(),
  };
  ref.onDispose(engine.dispose);
  return engine;
});
