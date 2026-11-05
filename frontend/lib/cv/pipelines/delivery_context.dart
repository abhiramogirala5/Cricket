import 'package:equatable/equatable.dart';
import 'package:gully_umpire/cv/device/device_policy.dart';
import 'package:gully_umpire/cv/geometry/plane.dart';
import 'package:gully_umpire/cv/geometry/polygon.dart';
import 'package:gully_umpire/cv/pipelines/ball_observation.dart';
import 'package:gully_umpire/cv/pipelines/pose_sample.dart';
import 'package:gully_umpire/cv/rules/umpiring_rules.dart';
import 'package:gully_umpire/cv/scene/scan_readiness.dart';
import 'package:gully_umpire/cv/tracking/ball_track_point.dart';
import 'package:gully_umpire/cv/tracking/speed_estimator.dart';
import 'package:gully_umpire/domain/decisions/delivery_decision.dart';
import 'package:gully_umpire/domain/decisions/wicket_family.dart';

/// The wicket as found by the scene scan, in normalised image coordinates.
final class WicketTarget extends Equatable {
  const WicketTarget({required this.polygon, required this.confidence, this.family});

  final Polygon polygon;

  /// Final confidence (0..1) of the scan that found it.
  final double confidence;

  final WicketFamily? family;

  @override
  List<Object?> get props => <Object?>[polygon, confidence, family];
}

/// Everything the delivery pipeline needs to know about the match and the scan.
final class DeliveryContext extends Equatable {
  const DeliveryContext({
    required this.policy,
    required this.rules,
    required this.batsmanHeightM,
    this.wicket,
    this.readiness = ScanReadiness.ready,
    this.cameraToBatterM,
    this.assumedFlightDistanceM,
  });

  /// What this phone may do.
  final DevicePolicy policy;

  /// Which rules the match uses.
  final UmpiringRuleConfig rules;

  /// Height of the batter in metres (a default of 1.70 is used when nobody entered one).
  final double batsmanHeightM;

  /// The scanned wicket, or null when none was found.
  final WicketTarget? wicket;

  /// How well the scan went.
  final ScanReadiness readiness;

  /// How far the phone is from the batter, in metres, as the umpire entered it. The ball speed is
  /// worked out from it; without it no speed is shown.
  final double? cameraToBatterM;

  /// A distance the ball is simply assumed to fly between release and the batter. Only the
  /// simulator sets this (its pitch is invented too); the live camera never does, because nothing
  /// measures it and a guessed length would make the speed up.
  final double? assumedFlightDistanceM;

  @override
  List<Object?> get props => <Object?>[
        policy,
        rules,
        batsmanHeightM,
        wicket,
        readiness,
        cameraToBatterM,
        assumedFlightDistanceM,
      ];
}

/// Lets the screen stop a running analysis (for example when the umpire leaves the page).
final class CancellationFlag {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
  }
}

/// What the pipeline learned about one delivery.
final class DeliveryAnalysis {
  const DeliveryAnalysis({
    required this.trajectory,
    required this.trackingConfidence,
    required this.poseConfidence,
    required this.decisions,
    required this.modelVersion,
    required this.isMock,
    required this.samplingFps,
    required this.framesProcessed,
    this.speed,
    this.arrivalMs,
    this.bounced,
    this.ballHeightM,
    this.ballLateralM,
    this.wasCancelled = false,
    this.notes = const <String>[],
    this.observations = const <BallObservation>[],
    this.bounceMs,
    this.contactMs,
    this.plane,
    this.poses = const <PoseSample>[],
  });

  /// The accepted ball positions, oldest first.
  final List<BallTrackPoint> trajectory;

  /// 0..1 quality of the ball track.
  final double trackingConfidence;

  /// 0..1 mean confidence of the batter pose, 0 when it was never seen.
  final double poseConfidence;

  /// Estimated ball speed, when it could be worked out.
  final SpeedEstimate? speed;

  /// Suggestions for the umpire (already filtered by the device policy).
  final List<DeliveryDecision> decisions;

  /// Version string of the models used; starts with `mock-` when any of them is a mock.
  final String modelVersion;

  final bool isMock;

  /// Effective ball detections per second.
  final double samplingFps;

  /// Number of camera frames that were handed to the pipeline.
  final int framesProcessed;

  /// Time at which the ball reached the batter, when it could be found.
  final int? arrivalMs;

  /// Whether the ball bounced before the batter; null when that is not known.
  final bool? bounced;

  /// Height of the ball above the ground at the batter in metres.
  final double? ballHeightM;

  /// Sideways position of the ball at the batter in metres from the batter (positive = right).
  final double? ballLateralM;

  /// The analysis was stopped early.
  final bool wasCancelled;

  /// Plain-language remarks about what was and was not possible.
  final List<String> notes;

  /// The ball detections behind [trajectory], with the apparent size of the ball (for the replay).
  final List<BallObservation> observations;

  /// Time of the lowest point of the bounce, when the ball bounced.
  final int? bounceMs;

  /// Time at which the ball's path changed suddenly near the batter (a touch of bat, pad or glove
  /// cannot be told apart from behind the bowler), when such a change was seen. Null when none
  /// was seen or the check was not made; that never means the ball touched nothing.
  final int? contactMs;

  /// The scale that turned picture positions into metres at the batter (null when it was not
  /// possible to work it out).
  final ReferencePlane? plane;

  /// The batter poses that were used (for the replay figure).
  final List<PoseSample> poses;

  /// Empty result for a delivery that could not be analysed at all.
  factory DeliveryAnalysis.none({
    required String modelVersion,
    required bool isMock,
    int framesProcessed = 0,
    bool wasCancelled = false,
    List<String> notes = const <String>[],
  }) {
    return DeliveryAnalysis(
      trajectory: const <BallTrackPoint>[],
      trackingConfidence: 0,
      poseConfidence: 0,
      decisions: const <DeliveryDecision>[],
      modelVersion: modelVersion,
      isMock: isMock,
      samplingFps: 0,
      framesProcessed: framesProcessed,
      wasCancelled: wasCancelled,
      notes: notes,
    );
  }
}
