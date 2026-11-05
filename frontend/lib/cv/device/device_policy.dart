import 'package:equatable/equatable.dart';
import 'package:gully_umpire/domain/decisions/decision_status.dart';
import 'package:gully_umpire/domain/decisions/delivery_decision.dart';
import 'package:gully_umpire/domain/decisions/delivery_decision_type.dart';

/// Capability class of the phone (spec §12).
enum DeviceProfile {
  high('HIGH', 'High-end'),
  mid('MID', 'Mid-range'),
  low('LOW', 'Entry-level'),
  scoreOnly('SCORE_ONLY', 'Score only');

  const DeviceProfile(this.wire, this.label);

  final String wire;
  final String label;

  /// Parses a wire value; unknown values fall back to [DeviceProfile.scoreOnly] (the safe choice).
  static DeviceProfile fromWire(String? raw) {
    for (final DeviceProfile value in DeviceProfile.values) {
      if (value.wire == raw) {
        return value;
      }
    }
    return DeviceProfile.scoreOnly;
  }

  /// A coarse guess from the processor count and (when known) the memory in MB.
  ///
  /// This is only a starting point: the real cost of the models can only be measured on a
  /// device. When in doubt the guess is the lower profile, which keeps the app responsive.
  static DeviceProfile classify({required int processorCount, int? memoryMb}) {
    final bool plentyOfMemory = memoryMb == null || memoryMb >= 6000;
    final bool goodMemory = memoryMb == null || memoryMb >= 3500;
    if (processorCount >= 8 && plentyOfMemory) {
      return DeviceProfile.high;
    }
    if (processorCount >= 6 && goodMemory) {
      return DeviceProfile.mid;
    }
    if (processorCount >= 4 && (memoryMb == null || memoryMb >= 2000)) {
      return DeviceProfile.low;
    }
    return DeviceProfile.scoreOnly;
  }
}

enum SceneScanMode { full, reducedResolution, sparse, disabled }

enum OpticalFlowMode { enabled, smallRegion, optional, disabled }

enum SpeedMode { enabled, ifCalibrated, relativeOnly, disabled }

/// How wide / no-ball suggestions may be used.
enum WideNoBallMode {
  /// Calls allowed as the rules produce them.
  enabled,

  /// Only results that are `AUTO_CALL` are shown; everything weaker is dropped.
  highConfidenceOnly,

  /// Never an `AUTO_CALL`: shown as "review recommended" only.
  reviewOnly,

  /// No suggestions; the umpire scores manually.
  manual,
}

/// How edge, LBW and wicket-hit review assistance may be used.
enum ReviewAssistMode { review, reviewWithEnoughPoints, disabledByDefault, disabled }

enum ReplayMode { enabled, optional, disabled }

/// What a [DeviceProfile] allows (the spec §11 processing budget and §12 device table).
final class DevicePolicy extends Equatable {
  const DevicePolicy({
    required this.profile,
    required this.cameraFps,
    required this.ballDetectorFps,
    required this.poseFps,
    required this.uiUpdatesPerSecond,
    required this.ballHistorySeconds,
    required this.modelFrameWidth,
    required this.minTrackPointsForReview,
    required this.sceneScan,
    required this.opticalFlow,
    required this.speed,
    required this.wideNoBall,
    required this.reviewAssist,
    required this.replay,
  });

  factory DevicePolicy.forProfile(DeviceProfile profile) {
    switch (profile) {
      case DeviceProfile.high:
        return const DevicePolicy(
          profile: DeviceProfile.high,
          cameraFps: 60,
          ballDetectorFps: 24,
          poseFps: 12,
          uiUpdatesPerSecond: 10,
          ballHistorySeconds: 2,
          modelFrameWidth: 960,
          minTrackPointsForReview: 6,
          sceneScan: SceneScanMode.full,
          opticalFlow: OpticalFlowMode.enabled,
          speed: SpeedMode.enabled,
          wideNoBall: WideNoBallMode.enabled,
          reviewAssist: ReviewAssistMode.review,
          replay: ReplayMode.enabled,
        );
      case DeviceProfile.mid:
        return const DevicePolicy(
          profile: DeviceProfile.mid,
          cameraFps: 30,
          ballDetectorFps: 12,
          poseFps: 8,
          uiUpdatesPerSecond: 8,
          ballHistorySeconds: 2,
          modelFrameWidth: 640,
          minTrackPointsForReview: 10,
          sceneScan: SceneScanMode.reducedResolution,
          opticalFlow: OpticalFlowMode.smallRegion,
          speed: SpeedMode.ifCalibrated,
          wideNoBall: WideNoBallMode.highConfidenceOnly,
          reviewAssist: ReviewAssistMode.reviewWithEnoughPoints,
          replay: ReplayMode.optional,
        );
      case DeviceProfile.low:
        return const DevicePolicy(
          profile: DeviceProfile.low,
          cameraFps: 30,
          ballDetectorFps: 8,
          poseFps: 4,
          uiUpdatesPerSecond: 5,
          ballHistorySeconds: 1,
          modelFrameWidth: 640,
          minTrackPointsForReview: 12,
          sceneScan: SceneScanMode.sparse,
          opticalFlow: OpticalFlowMode.optional,
          speed: SpeedMode.relativeOnly,
          wideNoBall: WideNoBallMode.reviewOnly,
          reviewAssist: ReviewAssistMode.disabledByDefault,
          replay: ReplayMode.disabled,
        );
      case DeviceProfile.scoreOnly:
        return const DevicePolicy(
          profile: DeviceProfile.scoreOnly,
          cameraFps: 0,
          ballDetectorFps: 0,
          poseFps: 0,
          uiUpdatesPerSecond: 5,
          ballHistorySeconds: 0,
          modelFrameWidth: 0,
          minTrackPointsForReview: 0,
          sceneScan: SceneScanMode.disabled,
          opticalFlow: OpticalFlowMode.disabled,
          speed: SpeedMode.disabled,
          wideNoBall: WideNoBallMode.manual,
          reviewAssist: ReviewAssistMode.disabled,
          replay: ReplayMode.disabled,
        );
    }
  }

  /// The policy of the live camera engine for a phone of class [profile].
  ///
  /// The live engine does its own light-weight tracking (no trained models), so what a phone may do
  /// no longer depends on the weight of a model. Every phone that can run it gets the same
  /// checks; only a phone classified as "score only" (too few processor cores to keep up with the
  /// camera) stays without the assistant. The camera is asked for 30 pictures a second on every
  /// phone: that is what the tracker is tuned for, and what has been measured to be affordable.
  factory DevicePolicy.live(DeviceProfile profile) {
    if (profile == DeviceProfile.scoreOnly) {
      return DevicePolicy.forProfile(profile);
    }
    return DevicePolicy(
      profile: profile,
      cameraFps: 30,
      ballDetectorFps: 30,
      poseFps: profile == DeviceProfile.high ? 6 : 4,
      uiUpdatesPerSecond: 15,
      ballHistorySeconds: 4,
      modelFrameWidth: 640,
      minTrackPointsForReview: 6,
      sceneScan: SceneScanMode.disabled,
      opticalFlow: OpticalFlowMode.disabled,
      // A speed is measured from how fast the ball shrinks and needs the phone-to-batter distance
      // that the umpire enters; without it the interpreter shows none (see `estimateDepthSpeed`).
      speed: SpeedMode.ifCalibrated,
      wideNoBall: WideNoBallMode.enabled,
      reviewAssist: ReviewAssistMode.review,
      replay: ReplayMode.enabled,
    );
  }

  final DeviceProfile profile;

  /// Camera frame rate to request.
  final int cameraFps;

  /// Target number of ball-detector runs per second.
  final int ballDetectorFps;

  /// Target number of pose-estimator runs per second.
  final int poseFps;

  /// Upper limit for overlay / UI refreshes per second.
  final int uiUpdatesPerSecond;

  /// How much ball history is kept (seconds).
  final int ballHistorySeconds;

  /// Width of the frames given to the models (640x480 or 960x540 class, never 1080p).
  final int modelFrameWidth;

  /// Fewest accepted ball points for edge / LBW / wicket-hit review on this device.
  final int minTrackPointsForReview;

  final SceneScanMode sceneScan;
  final OpticalFlowMode opticalFlow;
  final SpeedMode speed;
  final WideNoBallMode wideNoBall;
  final ReviewAssistMode reviewAssist;
  final ReplayMode replay;

  /// Computer vision may run at all.
  bool get isUmpiringAvailable => profile != DeviceProfile.scoreOnly;

  /// Minimum milliseconds between two ball-detector runs (0 = no detector).
  int get ballIntervalMs => ballDetectorFps <= 0 ? 0 : (1000 / ballDetectorFps).round();

  /// Minimum milliseconds between two pose-estimator runs (0 = no estimator).
  int get poseIntervalMs => poseFps <= 0 ? 0 : (1000 / poseFps).round();

  /// Applies this device's rules to an automated result.
  ///
  /// Returns `null` when the result must not be shown at all on this device, otherwise the
  /// (possibly weakened) decision. A decision is never strengthened.
  DeliveryDecision? apply(DeliveryDecision decision) {
    switch (decision.type) {
      case DeliveryDecisionType.wide:
      case DeliveryDecisionType.noBallHeight:
      case DeliveryDecisionType.noBallFrontFoot:
        switch (wideNoBall) {
          case WideNoBallMode.enabled:
            return decision;
          case WideNoBallMode.highConfidenceOnly:
            return decision.status == DecisionStatus.autoCall ? decision : null;
          case WideNoBallMode.reviewOnly:
            if (decision.status == DecisionStatus.autoCall) {
              return decision.copyWith(status: DecisionStatus.reviewRecommended);
            }
            return decision;
          case WideNoBallMode.manual:
            return null;
        }
      case DeliveryDecisionType.edge:
      case DeliveryDecisionType.lbw:
      case DeliveryDecisionType.wicketHit:
        switch (reviewAssist) {
          case ReviewAssistMode.review:
          case ReviewAssistMode.reviewWithEnoughPoints:
            return decision;
          case ReviewAssistMode.disabledByDefault:
          case ReviewAssistMode.disabled:
            return null;
        }
    }
  }

  @override
  List<Object?> get props => <Object?>[
        profile,
        cameraFps,
        ballDetectorFps,
        poseFps,
        uiUpdatesPerSecond,
        ballHistorySeconds,
        modelFrameWidth,
        minTrackPointsForReview,
        sceneScan,
        opticalFlow,
        speed,
        wideNoBall,
        reviewAssist,
        replay,
      ];
}
