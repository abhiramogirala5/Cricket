import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gully_umpire/core/di/cv_providers.dart';
import 'package:gully_umpire/core/di/session_providers.dart';
import 'package:gully_umpire/cv/device/device_policy.dart';
import 'package:gully_umpire/cv/live/ball_kind.dart';
import 'package:gully_umpire/cv/live/platform/live_session_factory.dart';
import 'package:gully_umpire/cv/live/umpire_camera_controller.dart';
import 'package:gully_umpire/data/session/active_session.dart';
import 'package:gully_umpire/data/settings/live_settings.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// How the live camera is opened. Tests replace this with a stand-in.
final Provider<FrameSourceOpener> frameSourceOpenerProvider = Provider<FrameSourceOpener>((ref) {
  final DevicePolicy policy = ref.watch(devicePolicyProvider);
  return () => openPhoneCamera(fps: policy.cameraFps);
});

/// How the ball tracker is started. Tests replace this with a stand-in.
final Provider<LiveSessionOpener> liveSessionOpenerProvider =
    Provider<LiveSessionOpener>((ref) => openPhoneLiveSession);

/// Keeps the screen on while the camera is running (a sleeping screen would stop the umpiring in
/// the middle of an over).
final Provider<KeepAwake> keepAwakeProvider = Provider<KeepAwake>(
  (ref) => (bool enabled) => WakelockPlus.toggle(enable: enabled),
);

/// The small live-camera settings of the open account, or `null` when nobody is signed in.
final Provider<LiveSettings?> liveSettingsProvider = Provider<LiveSettings?>((ref) {
  final ActiveSession? active = ref.watch(activeSessionProvider);
  return active == null ? null : LiveSettings(active.store);
});

/// The ball that is bowled (it sets the size the tracker expects). Remembered on the phone.
final AsyncNotifierProvider<BallKindController, BallKind> ballKindProvider =
    AsyncNotifierProvider<BallKindController, BallKind>(BallKindController.new);

class BallKindController extends AsyncNotifier<BallKind> {
  @override
  Future<BallKind> build() async {
    final LiveSettings? settings = ref.watch(liveSettingsProvider);
    return settings == null ? BallKind.cricketBall : settings.ballKind();
  }

  /// Chooses the ball and remembers the choice.
  Future<void> choose(BallKind kind) async {
    state = AsyncData<BallKind>(kind);
    final LiveSettings? settings = ref.read(liveSettingsProvider);
    if (settings != null) {
      await settings.setBallKind(kind);
    }
  }
}

/// How far the phone stands from the batter in a match (feet), or `null` when none was entered.
/// Refreshed with `ref.invalidate` after it is saved.
final FutureProviderFamily<double?, String> cameraDistanceFeetProvider =
    FutureProvider.family<double?, String>((ref, String matchId) async {
  final LiveSettings? settings = ref.watch(liveSettingsProvider);
  return settings?.distanceFeetFor(matchId);
});
