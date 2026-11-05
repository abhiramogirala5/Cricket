import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:gully_umpire/cv/contracts/audio_impulse.dart';
import 'package:gully_umpire/cv/device/device_policy.dart';
import 'package:gully_umpire/cv/geometry/polygon.dart';
import 'package:gully_umpire/cv/live/ball_kind.dart';
import 'package:gully_umpire/cv/live/live_tracker.dart';
import 'package:gully_umpire/cv/live/replay_codec.dart';
import 'package:gully_umpire/cv/live/replay_meta.dart';
import 'package:gully_umpire/cv/live/vision_protocol.dart';
import 'package:gully_umpire/cv/pipelines/delivery_context.dart';
import 'package:gully_umpire/cv/pipelines/delivery_interpreter.dart';
import 'package:gully_umpire/cv/pipelines/delivery_pipeline_config.dart';
import 'package:gully_umpire/cv/pipelines/pose_sample.dart';
import 'package:gully_umpire/cv/rules/umpiring_rules.dart';
import 'package:gully_umpire/cv/scene/scan_readiness.dart';
import 'package:gully_umpire/domain/decisions/wicket_family.dart';

/// Version label stored with the suggestions that the live camera produced.
const String liveModelVersion = 'live-motion-1';

/// What the live analysis needs to know about the match right now.
final class LiveInputs extends Equatable {
  const LiveInputs({
    required this.policy,
    required this.rules,
    required this.batsmanHeightM,
    required this.ballKind,
    this.wicket,
    this.wicketConfidence = 0.9,
    this.wicketFamily,
    this.cameraToBatterM,
    this.trackDeliveries = true,
  });

  /// What this phone may do.
  final DevicePolicy policy;

  /// The rules of the match.
  final UmpiringRuleConfig rules;

  /// Height of the batter who is facing (metres).
  final double batsmanHeightM;

  /// The ball that is bowled.
  final BallKind ballKind;

  /// The marked wicket in picture coordinates (0..1), or null when it has not been marked yet.
  final Polygon? wicket;

  /// How sure the app is about the wicket outline (an outline the umpire marked is trusted).
  final double wicketConfidence;

  final WicketFamily? wicketFamily;

  /// How far the phone stands from the batter (metres), or null when the umpire has not said. The
  /// ball speed is measured from it; without it no speed is shown.
  final double? cameraToBatterM;

  /// Whether delivery tracking is active (disabled while marking the wicket).
  final bool trackDeliveries;

  /// The context the interpreter works with.
  DeliveryContext toContext() {
    final Polygon? outline = wicket;
    return DeliveryContext(
      policy: policy,
      rules: rules,
      batsmanHeightM: batsmanHeightM,
      wicket: outline == null
          ? null
          : WicketTarget(polygon: outline, confidence: wicketConfidence, family: wicketFamily),
      readiness: outline == null
          ? ScanReadiness.reposition
          : ScanReadiness.fromConfidence(wicketConfidence),
      cameraToBatterM: cameraToBatterM,
    );
  }

  LiveInputs copyWith({
    DevicePolicy? policy,
    UmpiringRuleConfig? rules,
    double? batsmanHeightM,
    BallKind? ballKind,
    Polygon? wicket,
    double? wicketConfidence,
    WicketFamily? wicketFamily,
    double? cameraToBatterM,
    bool? trackDeliveries,
    bool withoutDistance = false,
  }) {
    return LiveInputs(
      policy: policy ?? this.policy,
      rules: rules ?? this.rules,
      batsmanHeightM: batsmanHeightM ?? this.batsmanHeightM,
      ballKind: ballKind ?? this.ballKind,
      wicket: wicket ?? this.wicket,
      wicketConfidence: wicketConfidence ?? this.wicketConfidence,
      wicketFamily: wicketFamily ?? this.wicketFamily,
      cameraToBatterM: withoutDistance ? null : cameraToBatterM ?? this.cameraToBatterM,
      trackDeliveries: trackDeliveries ?? this.trackDeliveries,
    );
  }

  @override
  List<Object?> get props => <Object?>[
        policy,
        rules,
        batsmanHeightM,
        ballKind,
        wicket,
        wicketConfidence,
        wicketFamily,
        cameraToBatterM,
        trackDeliveries,
      ];
}

/// One delivery that the camera followed, with what the app made of it.
final class LiveDeliveryResult {
  const LiveDeliveryResult({
    required this.capture,
    required this.analysis,
    required this.meta,
    required this.receivedAtMs,
    this.replay,
  });

  /// What the tracker saw.
  final LiveDeliveryCapture capture;

  /// What the interpreter concluded.
  final DeliveryAnalysis analysis;

  /// What the replay draws on top of the pictures.
  final ReplayMeta meta;

  /// The replay file (pictures plus [meta]), or null when no pictures were kept.
  final Uint8List? replay;

  /// Time the result was ready (milliseconds since the session started).
  final int receivedAtMs;
}

/// Interprets a delivery that the worker handed over and packs its replay.
///
/// [poses] are the batter poses measured before and during the delivery.
Future<LiveDeliveryResult> analyseLiveDelivery({
  required DecodedCapture decoded,
  required List<PoseSample> poses,
  required LiveInputs inputs,
  required int nowMs,
  Future<List<AudioImpulse>> Function(int fromMs, int toMs)? impulseLookup,
}) async {
  final LiveDeliveryCapture capture = decoded.capture;
  final DeliveryPipelineConfig config =
      DeliveryPipelineConfig.live(ballDiameterM: inputs.ballKind.diameterM);
  final DeliveryAnalysis analysis = await interpretDelivery(
    observations: capture.observations,
    detectorRunTimes: capture.frameTimesMs,
    poses: poses,
    aspectRatio: capture.aspectRatio,
    context: inputs.toContext(),
    modelVersion: liveModelVersion,
    isMock: false,
    framesProcessed: capture.framesProcessed,
    impulseLookup: impulseLookup,
    config: config,
  );
  final ReplayMeta meta = ReplayMeta.fromAnalysis(
    analysis: analysis,
    ballKind: inputs.ballKind,
    aspectRatio: capture.aspectRatio,
    batterHeightM: inputs.batsmanHeightM,
    wicket: inputs.wicket,
    heightUncertaintyM: config.heightUncertaintyM,
    waistRatio: inputs.rules.height.waistHeightRatio,
    shoulderRatio: inputs.rules.height.shoulderHeightRatio,
  );
  final Uint8List? pack = decoded.replay;
  return LiveDeliveryResult(
    capture: capture,
    analysis: analysis,
    meta: meta,
    replay: pack == null ? null : ReplayCodec.attachMeta(pack, meta.toJson()),
    receivedAtMs: nowMs,
  );
}
