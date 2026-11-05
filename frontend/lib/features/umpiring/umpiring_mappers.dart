import 'package:gully_umpire/core/config/app_config.dart';
import 'package:gully_umpire/cv/geometry/polygon.dart';
import 'package:gully_umpire/cv/pipelines/pipelines.dart';
import 'package:gully_umpire/cv/rules/umpiring_rules.dart';
import 'package:gully_umpire/cv/scene/wicket_scanner.dart';
import 'package:gully_umpire/data/repositories/repository_inputs.dart';
import 'package:gully_umpire/domain/decisions/decisions.dart';
import 'package:gully_umpire/domain/models/models.dart';

/// Glue between the computer-vision layer (which knows nothing about stored records) and the
/// records the app saves. Everything here is a pure function.

/// Height used for the batter when nobody entered one (metres).
const double defaultBatsmanHeightM = 1.70;

/// The rules the CV layer applies for a match.
///
/// A match's own rules decide which checks are wanted. The review aids (edge, LBW and wicket hit)
/// are experimental, so they also need their switch in `.env` to be on: they are off unless the
/// build turned them on.
UmpiringRuleConfig umpiringRulesFor(MatchRules? rules, AppConfig config) {
  final MatchRules effective = rules ?? const MatchRules(matchId: '');
  return UmpiringRuleConfig(
    wideEnabled: effective.wideEnabled,
    noBallEnabled: effective.noBallEnabled,
    wicketHitEnabled: config.enableLbwReview && effective.lbwReviewEnabled,
    edgeReviewEnabled: config.enableEdgeReview && effective.edgeReviewEnabled,
    lbwReviewEnabled: config.enableLbwReview && effective.lbwReviewEnabled,
    lateralReachMultiplier: effective.lateralReachMultiplier,
    height: HeightRuleConfig(
      fullTossAboveWaistIsNoBall: effective.fullTossAboveWaistIsNoBall,
      bouncedAboveShoulderIsNoBall: effective.bouncedAboveShoulderIsNoBall,
    ),
  );
}

/// The batter's height in metres: the match entry first, then the saved player, then a default.
double batsmanHeightMetres({MatchPlayer? matchPlayer, Player? player}) {
  final int? cm = matchPlayer?.declaredHeightCm ?? player?.declaredHeightCm;
  if (cm == null || cm <= 0) {
    return defaultBatsmanHeightM;
  }
  return cm / 100.0;
}

/// The wicket as the pipeline wants it, from the stored detection. `null` when there is none or
/// its outline is unusable.
WicketTarget? wicketTargetFrom(WicketDetection? detection) {
  if (detection == null || !detection.isActive) {
    return null;
  }
  try {
    final Polygon polygon = Polygon.fromJson(detection.targetPolygon);
    if (!polygon.isValid) {
      return null;
    }
    return WicketTarget(
      polygon: polygon,
      confidence: detection.finalConfidence,
      family: detection.wicketFamily,
    );
  } on Object {
    // A damaged outline is the same as no outline: the assistant says "not sure".
    return null;
  }
}

/// The two records that a scene scan produces.
final class ScanRecords {
  const ScanRecords({required this.scan, this.wicket});

  final SceneScan scan;

  /// `null` when no wicket was found.
  final WicketDetection? wicket;
}

/// Turns the outcome of a scan into the records to store.
ScanRecords scanRecordsFrom({
  required String matchId,
  required SceneScanOutcome outcome,
  required String scanId,
  required String wicketId,
  required DateTime now,
  required int scanDurationMs,
  int? captureFps,
  String? cameraDeviceModel,
}) {
  final WicketScanCandidate? best = outcome.result.best;
  final SceneScan scan = SceneScan(
    id: scanId,
    matchId: matchId,
    cameraDeviceModel: cameraDeviceModel,
    captureFps: captureFps,
    scanDurationMs: scanDurationMs < 0 ? 0 : scanDurationMs,
    batsmanPlane: outcome.result.batsmanBox == null
        ? null
        : <String, Object?>{'box': outcome.result.batsmanBox!.toJson()},
    overallConfidence: outcome.result.confidence,
    modelVersion: outcome.modelVersion,
    createdAt: now,
  );
  if (best == null) {
    return ScanRecords(scan: scan);
  }
  final WicketDetection wicket = WicketDetection(
    id: wicketId,
    matchId: matchId,
    sceneScanId: scanId,
    wicketFamily: best.family,
    boundingBox: best.box.toJson(),
    targetPolygon: best.polygon.toJson(),
    objectConfidence: best.objectConfidence,
    temporalStability: best.temporalStability,
    contextConfidence: (best.batsmanRelationshipScore + best.pitchAlignmentScore) / 2,
    finalConfidence: best.finalConfidence,
    modelVersion: outcome.modelVersion,
    detectedAt: now,
  );
  return ScanRecords(scan: scan, wicket: wicket);
}

/// What the scorer actually decided for a check, in the same words the CV layer uses for its own
/// result. `null` for the review aids, which do not map to one scoring button.
String? finalResultFor(DeliveryDecisionType type, DeliveryDraft draft) {
  switch (type) {
    case DeliveryDecisionType.wide:
      return draft.isWide ? 'WIDE' : 'NOT_WIDE';
    case DeliveryDecisionType.noBallHeight:
      return draft.isNoBall ? 'NO_BALL' : 'LEGAL';
    case DeliveryDecisionType.noBallFrontFoot:
    case DeliveryDecisionType.edge:
    case DeliveryDecisionType.lbw:
    case DeliveryDecisionType.wicketHit:
      return null;
  }
}

/// The decisions to store with a ball that was scored after the assistant looked at it.
///
/// * When the scorer's call agrees with the suggestion (or the assistant was not sure, or the
///   suggestion is only a review aid) the record keeps the suggestion's own status and is marked
///   as assistant output.
/// * When the scorer chose differently the record becomes a manual override, so that the review
///   screen and any later analysis see that a person overruled the assistant.
List<DecisionInput> decisionInputsFor(DeliveryAnalysis analysis, DeliveryDraft draft) {
  return <DecisionInput>[
    for (final DeliveryDecision decision in analysis.decisions)
      _inputFor(decision, finalResultFor(decision.type, draft)),
  ];
}

DecisionInput _inputFor(DeliveryDecision decision, String? finalResult) {
  final bool agrees =
      decision.isInconclusive || finalResult == null || finalResult == decision.automatedResult;
  return DecisionInput(
    type: decision.type,
    status: agrees ? decision.status : DecisionStatus.manualOverride,
    source: agrees ? DecisionSource.aiAssist : DecisionSource.manual,
    automatedResult: decision.automatedResult,
    finalResult: finalResult,
    confidence: decision.confidence,
    evidence: decision.evidence,
  );
}

/// The ball path to store, or `null` when nothing was tracked.
TrajectoryInput? trajectoryInputFor(DeliveryAnalysis analysis) {
  if (analysis.trajectory.isEmpty) {
    return null;
  }
  final int fps = analysis.samplingFps.isFinite ? analysis.samplingFps.round() : 1;
  return TrajectoryInput(
    samplingFps: fps < 1 ? 1 : (fps > 240 ? 240 : fps),
    points: <List<double>>[
      for (final point in analysis.trajectory)
        point.toCompressed().map<double>((num value) => value.toDouble()).toList(growable: false),
    ],
    modelVersion: analysis.modelVersion,
  );
}

/// Adds the measurements from [analysis] (and the wicket it was judged against) to [draft].
///
/// Speed is only stored when the pipeline produced one, and every number is kept inside the
/// ranges the API accepts.
DeliveryDraft draftWithAnalysis(
  DeliveryDraft draft, {
  DeliveryAnalysis? analysis,
  WicketDetection? wicket,
}) {
  if (analysis == null) {
    return draft;
  }
  double unit(double value) => value.isNaN ? 0.0 : (value < 0 ? 0.0 : (value > 1 ? 1.0 : value));
  final double? kmph = analysis.speed?.kmph;
  return draft.withMeasurements(
    wicketDetectionId: wicket?.id,
    speedKmph: kmph == null || !kmph.isFinite ? null : (kmph < 0 ? 0.0 : (kmph > 250 ? 250.0 : kmph)),
    speedConfidence: analysis.speed == null ? null : unit(analysis.speed!.confidence),
    ballTrackingConfidence: unit(analysis.trackingConfidence),
    poseTrackingConfidence: unit(analysis.poseConfidence),
    wicketTrackingConfidence: wicket == null ? null : unit(wicket.finalConfidence),
  );
}
