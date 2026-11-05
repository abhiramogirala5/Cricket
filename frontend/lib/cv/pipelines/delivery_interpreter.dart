import 'dart:math' as math;

import 'package:gully_umpire/cv/contracts/audio_impulse.dart';
import 'package:gully_umpire/cv/device/device_policy.dart';
import 'package:gully_umpire/cv/geometry/plane.dart';
import 'package:gully_umpire/cv/geometry/point2d.dart';
import 'package:gully_umpire/cv/geometry/point3d.dart';
import 'package:gully_umpire/cv/pipelines/ball_observation.dart';
import 'package:gully_umpire/cv/pipelines/delivery_context.dart';
import 'package:gully_umpire/cv/pipelines/delivery_geometry.dart';
import 'package:gully_umpire/cv/pipelines/delivery_pipeline_config.dart';
import 'package:gully_umpire/cv/pipelines/delivery_speed.dart';
import 'package:gully_umpire/cv/pipelines/pose_sample.dart';
import 'package:gully_umpire/cv/rules/decision_factory.dart';
import 'package:gully_umpire/cv/rules/edge_review.dart';
import 'package:gully_umpire/cv/rules/lbw_review.dart';
import 'package:gully_umpire/cv/rules/umpiring_rules.dart';
import 'package:gully_umpire/cv/rules/wicket_hit_review.dart';
import 'package:gully_umpire/cv/tracking/ball_track_point.dart';
import 'package:gully_umpire/cv/tracking/speed_estimator.dart';
import 'package:gully_umpire/cv/util/math_utils.dart';
import 'package:gully_umpire/domain/decisions/delivery_decision.dart';
import 'package:gully_umpire/domain/decisions/delivery_decision_type.dart';

const String _reasonTrack = 'The ball was not tracked clearly enough.';
const String _reasonBatter = 'The batter was not visible enough to measure.';
const String _reasonArrival = 'The moment the ball reached the batter could not be found.';
const String _reasonPosition = 'The ball position at the batter could not be worked out.';
const String _reasonBounce =
    'There were not enough ball points before the batter to tell whether it bounced.';
const String _reasonLateStart =
    'The ball was first seen too far down the pitch to tell whether it bounced.';
const String _reasonNoContact = 'No sudden change in the ball\'s path was seen near the batter, so '
    'the edge and LBW checks were not made. That is not a verdict.';
const String _reasonFewPoints =
    'Too few ball points were followed for the edge, LBW and stumps checks. Look at the replay '
    'yourself.';
const String _reasonNoDistance = 'No ball speed: enter how far the phone is from the batter when '
    'you mark the stumps.';
const String _reasonSpeedUnsure = 'The ball speed could not be measured well enough for this ball, '
    'so none is shown.';
const String _reasonStumps = 'The stumps cannot be trusted right now, so the LBW and stumps '
    'checks were not made. Mark them again if the phone was moved.';

/// Turns what the cameras saw (ball detections, detector run times, batter poses) into a
/// [DeliveryAnalysis]. Pure apart from the optional [impulseLookup] for the edge-sound check.
///
/// Nothing here is certain: a single camera cannot see depth, so every result carries a
/// confidence, no result is ever stronger than the weakest measurement behind it, and when the
/// data is not good enough the answer is "not sure" rather than a guess.
Future<DeliveryAnalysis> interpretDelivery({
  required List<BallObservation> observations,
  required List<int> detectorRunTimes,
  required List<PoseSample> poses,
  required double aspectRatio,
  required DeliveryContext context,
  required String modelVersion,
  required bool isMock,
  required int framesProcessed,
  Future<List<AudioImpulse>> Function(int fromMs, int toMs)? impulseLookup,
  DeliveryPipelineConfig config = const DeliveryPipelineConfig(),
}) async {
  final DevicePolicy policy = context.policy;
  final UmpiringRuleConfig rules = context.rules;
  final List<String> notes = <String>[];
  final List<BallTrackPoint> trajectory =
      observations.map<BallTrackPoint>((BallObservation o) => o.toTrackPoint()).toList();
  final double trackingConfidence = _trackingConfidence(observations, detectorRunTimes);
  final double poseConfidence = poses.isEmpty
      ? 0
      : meanOf(poses.map<double>((PoseSample p) => p.confidence).toList());
  final double samplingFps = _samplingFps(observations);

  DeliveryAnalysis finish(
    List<DeliveryDecision> decisions, {
    SpeedEstimate? speed,
    double? arrivalMs,
    bool? bounced,
    double? ballHeightM,
    double? ballLateralM,
    int? bounceMs,
    int? contactMs,
    ReferencePlane? plane,
  }) {
    final List<DeliveryDecision> allowed = <DeliveryDecision>[];
    for (final DeliveryDecision decision in decisions) {
      final DeliveryDecision? kept = policy.apply(decision);
      if (kept != null) {
        allowed.add(kept);
      }
    }
    return DeliveryAnalysis(
      trajectory: trajectory,
      trackingConfidence: trackingConfidence,
      poseConfidence: poseConfidence,
      speed: speed,
      decisions: allowed,
      modelVersion: modelVersion,
      isMock: isMock,
      samplingFps: samplingFps,
      framesProcessed: framesProcessed,
      arrivalMs: arrivalMs?.round(),
      bounced: bounced,
      ballHeightM: ballHeightM,
      ballLateralM: ballLateralM,
      notes: List<String>.unmodifiable(notes),
      observations: List<BallObservation>.unmodifiable(observations),
      bounceMs: bounceMs,
      contactMs: contactMs,
      plane: plane,
      poses: List<PoseSample>.unmodifiable(poses),
    );
  }

  if (!policy.isUmpiringAvailable || context.readiness.asksToReposition) {
    notes.add('Umpire assistance is not available for this delivery.');
    return finish(const <DeliveryDecision>[]);
  }

  final bool wantWide = rules.wideEnabled && context.readiness.allowsWideAssist;
  final bool wantHeight = rules.noBallEnabled && context.readiness.allowsNoBallAssist;

  List<DeliveryDecision> unsure(String reason) {
    notes.add(reason);
    return <DeliveryDecision>[
      if (wantWide) DecisionFactory.inconclusive(DeliveryDecisionType.wide, reason),
      if (wantHeight) DecisionFactory.inconclusive(DeliveryDecisionType.noBallHeight, reason),
    ];
  }

  if (observations.length < config.minSegmentPoints ||
      trackingConfidence < config.minTrajectoryConfidence) {
    return finish(unsure(_reasonTrack));
  }
  if (poses.length < config.minPoseSamples) {
    return finish(unsure(_reasonBatter));
  }

  // The batter gives the scale: a person of known height standing on the plane the ball
  // arrives at.
  // MCC Law 41.7 requires upright stance at the crease; prioritize pre-flight/stance poses
  // before ball release so shot-making crouch/jump movements do not distort the reference plane.
  final int releaseTime = observations.isNotEmpty ? observations.first.timestampMs : 0;
  final List<PoseSample> stancePoses =
      poses.where((PoseSample p) => p.timestampMs <= releaseTime).toList();
  final List<PoseSample> referencePoses =
      stancePoses.length >= config.minPoseSamples ? stancePoses : poses;
  final double groundY = medianOf(referencePoses.map<double>((PoseSample p) => p.groundY).toList());
  final double topY = medianOf(referencePoses.map<double>((PoseSample p) => p.topY).toList());
  if (!(groundY - topY > 0.05) || !(context.batsmanHeightM > 0)) {
    return finish(unsure(_reasonBatter));
  }
  final List<PoseSample> firstSamples = referencePoses.take(3).toList();
  final double startCenterX =
      medianOf(firstSamples.map<double>((PoseSample p) => p.centerX).toList());
  final ReferencePlane plane = ReferencePlane.fromSubject(
    centerX: startCenterX,
    groundY: groundY,
    topY: topY,
    subjectHeightM: context.batsmanHeightM,
    aspectRatio: aspectRatio,
  );

  final double planeDiameter = config.ballDiameterM / plane.metersPerUnitY;
  final double? arrivalMs = estimateArrivalMs(
    observations,
    planeDiameter: planeDiameter,
    config: config.geometry,
  );
  if (arrivalMs == null) {
    return finish(unsure(_reasonArrival));
  }
  final Point2D? arrivalPoint = ballPositionAt(observations, arrivalMs, config: config.geometry);
  if (arrivalPoint == null) {
    return finish(unsure(_reasonArrival));
  }
  final double lateralM = plane.lateralMeters(arrivalPoint.x);
  final double heightM = plane.heightMeters(arrivalPoint.y);
  if (!lateralM.isFinite || !heightM.isFinite) {
    return finish(unsure(_reasonPosition));
  }

  final List<BallObservation> beforeArrival = observations
      .where((BallObservation o) => o.timestampMs <= arrivalMs)
      .toList();
  BounceInfo? bounce =
      detectBounce(beforeArrival, arrivalY: arrivalPoint.y, config: config.geometry);
  String bounceReason = _reasonBounce;
  if (bounce != null &&
      !bounce.bounced &&
      config.geometry.minBounceViewRatio > 0 &&
      beforeArrival.isNotEmpty &&
      beforeArrival.first.diameter < config.geometry.minBounceViewRatio * planeDiameter) {
    // The track began after the place where a bounce would have been: "no bounce" is a guess.
    bounce = null;
    bounceReason = _reasonLateStart;
  }

  final List<DeliveryDecision> decisions = <DeliveryDecision>[];
  final double wicketConfidence = context.wicket?.confidence ?? 0;

  if (wantWide) {
    final List<PoseSample> upToArrival =
        poses.where((PoseSample p) => p.timestampMs <= arrivalMs).toList();
    final List<PoseSample> lastSamples = upToArrival.length > 3
        ? upToArrival.sublist(upToArrival.length - 3)
        : upToArrival;
    final double endCenterX = lastSamples.isEmpty
        ? startCenterX
        : medianOf(lastSamples.map<double>((PoseSample p) => p.centerX).toList());
    final double shiftM = (endCenterX - startCenterX) * plane.metersPerUnitX;
    final bool movedTowardBall = shiftM.abs() >= config.batsmanMoveThresholdM &&
        (shiftM > 0) == (lateralM > 0) &&
        lateralM.abs() > 0.05;
    decisions.add(
      DecisionFactory.wide(
        assessWide(
          ballAtBatsmanPlane: Point3D(lateralM, heightM, 0),
          batsmanCenter: const Point3D(0, 0, 0),
          batsmanHeightM: context.batsmanHeightM,
          lateralReachMultiplier: rules.lateralReachMultiplier,
          batsmanMovedTowardBall: movedTowardBall,
          wicketConfidence: wicketConfidence,
          trajectoryConfidence: trackingConfidence,
        ),
      ),
    );
  }

  if (wantHeight) {
    if (bounce == null) {
      notes.add(bounceReason);
      decisions.add(DecisionFactory.inconclusive(DeliveryDecisionType.noBallHeight, bounceReason));
    } else {
      decisions.add(
        DecisionFactory.heightNoBall(
          assessHeightNoBall(
            ballHeightM: heightM,
            batsmanHeightM: context.batsmanHeightM,
            bounced: bounce.bounced,
            rules: rules.height,
            measurementConfidence: math.min(poseConfidence, trackingConfidence),
            uncertaintyM: config.heightUncertaintyM,
          ),
        ),
      );
    }
  }

  // Review aids: only with enough ball points, and (for the wicket) only when it was found well.
  int? pathChangeMs;
  final bool enoughPoints = beforeArrival.length >= policy.minTrackPointsForReview;
  final bool wicketUsable =
      context.wicket != null && context.readiness.allowsWicketDependentReview;
  if (enoughPoints) {
    final WicketTarget? wicket = context.wicket;
    if ((rules.wicketHitEnabled || rules.lbwReviewEnabled) && !(wicketUsable && wicket != null)) {
      notes.add(_reasonStumps);
    }
    if (rules.wicketHitEnabled && wicketUsable && wicket != null) {
      decisions.add(
        DecisionFactory.wicketHit(
          assessWicketHit(
            track: trajectory,
            fromTimestampMs: arrivalMs.round(),
            wicketTarget: wicket.polygon,
            wicketConfidence: wicket.confidence,
            trackingConfidence: trackingConfidence,
          ),
        ),
      );
    }
    if (rules.edgeReviewEnabled || rules.lbwReviewEnabled) {
      final ContactInfo? contact = detectContact(
        observations,
        arrivalMs: arrivalMs,
        afterBounceMs: bounce?.timestampMs,
        config: config.geometry,
      );
      if (contact != null) {
        pathChangeMs = contact.timestampMs;
        final List<BallObservation> afterBounce = observations
            .where((BallObservation o) => bounce?.timestampMs == null || o.timestampMs >= bounce!.timestampMs!)
            .toList();
        final List<BallTrackPoint> before = afterBounce
            .where((BallObservation o) => o.timestampMs < contact.timestampMs)
            .map<BallTrackPoint>((BallObservation o) => o.toTrackPoint())
            .toList();
        final List<BallTrackPoint> after = observations
            .where((BallObservation o) => o.timestampMs >= contact.timestampMs)
            .map<BallTrackPoint>((BallObservation o) => o.toTrackPoint())
            .toList();
        if (rules.edgeReviewEnabled) {
          List<AudioImpulse>? impulses;
          if (impulseLookup != null) {
            impulses = await impulseLookup(contact.timestampMs - 40, contact.timestampMs + 40);
          }
          decisions.add(
            DecisionFactory.edge(
              assessEdge(
                before: before,
                after: after,
                contactTimestampMs: contact.timestampMs,
                trackingConfidence: trackingConfidence,
                impulses: impulses,
              ),
            ),
          );
        }
        if (rules.lbwReviewEnabled && wicketUsable && wicket != null) {
          final List<BallTrackPoint> preImpact = afterBounce
              .where((BallObservation o) => o.timestampMs <= contact.timestampMs)
              .map<BallTrackPoint>((BallObservation o) => o.toTrackPoint())
              .toList();
          decisions.add(
            DecisionFactory.lbw(
              assessLbw(
                preImpact: preImpact,
                wicketTarget: wicket.polygon,
                wicketConfidence: wicket.confidence,
                trackingConfidence: trackingConfidence,
              ),
            ),
          );
        }
      } else {
        notes.add(_reasonNoContact);
      }
    }
  } else if (rules.wicketHitEnabled || rules.edgeReviewEnabled || rules.lbwReviewEnabled) {
    notes.add(_reasonFewPoints);
  }

  final SpeedEstimate? speed = _speed(
    policy: policy,
    context: context,
    observations: observations,
    arrivalMs: arrivalMs,
    bounce: bounce,
    planeDiameter: planeDiameter,
    aspectRatio: aspectRatio,
    trackingConfidence: trackingConfidence,
    config: config,
  );
  if (speed == null) {
    final String? why = _whyNoSpeed(policy, context);
    if (why != null) {
      notes.add(why);
    }
  }

  return finish(
    decisions,
    speed: speed,
    arrivalMs: arrivalMs,
    bounced: bounce?.bounced,
    ballHeightM: heightM,
    ballLateralM: lateralM,
    bounceMs: bounce?.timestampMs,
    contactMs: pathChangeMs,
    plane: plane,
  );
}

/// Quality (0..1) of the ball track: how sure the detector was, how many of the detector runs found
/// the ball, and how many points there are.
double _trackingConfidence(List<BallObservation> observations, List<int> detectorRunTimes) {
  if (observations.isEmpty) {
    return 0;
  }
  final int first = observations.first.timestampMs;
  final int last = observations.last.timestampMs;
  int runs = 0;
  for (final int time in detectorRunTimes) {
    if (time >= first && time <= last) {
      runs += 1;
    }
  }
  final double hitRate = math.min(1.0, observations.length / math.max(1, runs));
  final double meanConfidence =
      meanOf(observations.map<double>((BallObservation o) => o.confidence).toList());
  final double enough = scoreRising(observations.length.toDouble(), low: 3, high: 8);
  return clamp01(meanConfidence * math.sqrt(hitRate) * enough);
}

/// Effective detections per second, from the median time between observations.
double _samplingFps(List<BallObservation> observations) {
  if (observations.length < 2) {
    return 0;
  }
  final List<double> gaps = <double>[
    for (int i = 1; i < observations.length; i++)
      (observations[i].timestampMs - observations[i - 1].timestampMs).toDouble(),
  ];
  final double median = medianOf(gaps);
  if (!(median > 0)) {
    return 0;
  }
  return clampDouble(1000.0 / median, 1, 240);
}

/// The speed of the ball, when this phone and this delivery allow one.
///
/// With a phone-to-batter distance the speed is measured from how fast the ball shrinks (see
/// [estimateDepthSpeed]). Without one, only the simulator's assumed flight distance can give a
/// speed; the live camera has neither and shows none.
SpeedEstimate? _speed({
  required DevicePolicy policy,
  required DeliveryContext context,
  required List<BallObservation> observations,
  required double arrivalMs,
  required BounceInfo? bounce,
  required double planeDiameter,
  required double aspectRatio,
  required double trackingConfidence,
  required DeliveryPipelineConfig config,
}) {
  switch (policy.speed) {
    case SpeedMode.disabled:
    case SpeedMode.relativeOnly:
      return null;
    case SpeedMode.ifCalibrated:
      if (trackingConfidence < 0.7) {
        return null;
      }
    case SpeedMode.enabled:
      break;
  }
  final double? distanceM = context.cameraToBatterM;
  if (distanceM != null) {
    final SpeedEstimate? depthSpeed = estimateDepthSpeed(
      observations: observations,
      arrivalMs: arrivalMs,
      bounce: bounce,
      planeDiameter: planeDiameter,
      cameraToBatterM: distanceM,
      ballDiameterM: config.ballDiameterM,
      aspectRatio: aspectRatio,
      trackingConfidence: trackingConfidence,
    );
    final SpeedEstimate? tofSpeed = estimateTimeOfFlightSpeed(
      observations: observations,
      arrivalMs: arrivalMs,
      bounce: bounce,
      planeDiameter: planeDiameter,
      cameraToBatterM: distanceM,
      ballDiameterM: config.ballDiameterM,
      aspectRatio: aspectRatio,
      trackingConfidence: trackingConfidence,
    );
    if (depthSpeed != null && tofSpeed != null) {
      return depthSpeed.confidence >= tofSpeed.confidence ? depthSpeed : tofSpeed;
    }
    return depthSpeed ?? tofSpeed;
  }
  final double? flightM = context.assumedFlightDistanceM;
  if (flightM == null) {
    return null;
  }
  final List<double> gaps = <double>[
    for (int i = 1; i < observations.length; i++)
      (observations[i].timestampMs - observations[i - 1].timestampMs).toDouble(),
  ];
  if (gaps.isEmpty) {
    return null;
  }
  return SpeedEstimator.estimate(
    releaseMs: observations.first.timestampMs,
    arrivalMs: arrivalMs.round(),
    flightDistanceM: flightM,
    trackingConfidence: trackingConfidence * config.speedTrackingFactor,
    frameIntervalMs: medianOf(gaps),
  );
}

/// Why no speed is shown, for the notes: null when none is expected (the phone does not measure
/// speeds, or the speed comes from the simulator's assumed flight).
String? _whyNoSpeed(DevicePolicy policy, DeliveryContext context) {
  if (policy.speed != SpeedMode.ifCalibrated && policy.speed != SpeedMode.enabled) {
    return null;
  }
  if (context.cameraToBatterM != null) {
    return _reasonSpeedUnsure;
  }
  return context.assumedFlightDistanceM == null ? _reasonNoDistance : null;
}
