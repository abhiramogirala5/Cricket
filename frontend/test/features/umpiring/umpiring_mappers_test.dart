import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/core/config/app_config.dart';
import 'package:gully_umpire/cv/device/device_policy.dart';
import 'package:gully_umpire/cv/engine/cv_engine.dart';
import 'package:gully_umpire/cv/adapters/mock/mock.dart';
import 'package:gully_umpire/cv/pipelines/pipelines.dart';
import 'package:gully_umpire/cv/rules/umpiring_rules.dart';
import 'package:gully_umpire/cv/tracking/ball_track_point.dart';
import 'package:gully_umpire/cv/tracking/speed_estimator.dart';
import 'package:gully_umpire/data/repositories/repository_inputs.dart';
import 'package:gully_umpire/domain/decisions/decisions.dart';
import 'package:gully_umpire/domain/models/models.dart';
import 'package:gully_umpire/features/umpiring/umpiring_mappers.dart';

import '../../support/model_fixtures.dart';

DeliveryDecision decision(
  DeliveryDecisionType type,
  String result,
  double confidence,
  DecisionStatus status,
) =>
    DeliveryDecision(
      type: type,
      automatedResult: result,
      confidence: confidence,
      status: status,
      summary: 'summary',
    );

DeliveryAnalysis analysisOf({
  List<DeliveryDecision> decisions = const <DeliveryDecision>[],
  List<BallTrackPoint> trajectory = const <BallTrackPoint>[],
  SpeedEstimate? speed,
  double samplingFps = 24.4,
  double trackingConfidence = 0.9,
  double poseConfidence = 0.8,
}) =>
    DeliveryAnalysis(
      trajectory: trajectory,
      trackingConfidence: trackingConfidence,
      poseConfidence: poseConfidence,
      decisions: decisions,
      modelVersion: 'mock-ball-1.0+mock-pose-1.0',
      isMock: true,
      samplingFps: samplingFps,
      framesProcessed: 40,
      speed: speed,
    );

const DeliveryDraft plainBall = DeliveryDraft(bowlerId: 'bowler', strikerId: 'striker');

void main() {
  group('umpiringRulesFor', () {
    const AppConfig reviewsOff = AppConfig(environment: AppEnvironment.development, apiBaseUrl: '');
    const AppConfig reviewsOn = AppConfig(
      environment: AppEnvironment.development,
      apiBaseUrl: '',
      enableEdgeReview: true,
      enableLbwReview: true,
    );

    test('review aids stay off unless the build switches them on', () {
      final UmpiringRuleConfig rules =
          umpiringRulesFor(const MatchRules(matchId: 'm'), reviewsOff);

      expect(rules.wideEnabled, isTrue);
      expect(rules.noBallEnabled, isTrue);
      expect(rules.edgeReviewEnabled, isFalse);
      expect(rules.lbwReviewEnabled, isFalse);
      expect(rules.wicketHitEnabled, isFalse);
    });

    test('with the switches on, the match rules decide', () {
      final UmpiringRuleConfig on = umpiringRulesFor(const MatchRules(matchId: 'm'), reviewsOn);
      expect(on.edgeReviewEnabled, isTrue);
      expect(on.lbwReviewEnabled, isTrue);
      expect(on.wicketHitEnabled, isTrue);

      final UmpiringRuleConfig off = umpiringRulesFor(
        const MatchRules(matchId: 'm', edgeReviewEnabled: false, lbwReviewEnabled: false),
        reviewsOn,
      );
      expect(off.edgeReviewEnabled, isFalse);
      expect(off.lbwReviewEnabled, isFalse);
      expect(off.wicketHitEnabled, isFalse);
    });

    test('the match can turn the wide and no-ball checks off and tune the reach', () {
      final UmpiringRuleConfig rules = umpiringRulesFor(
        const MatchRules(
          matchId: 'm',
          wideEnabled: false,
          noBallEnabled: false,
          lateralReachMultiplier: 0.8,
          fullTossAboveWaistIsNoBall: false,
          bouncedAboveShoulderIsNoBall: true,
        ),
        reviewsOff,
      );

      expect(rules.wideEnabled, isFalse);
      expect(rules.noBallEnabled, isFalse);
      expect(rules.lateralReachMultiplier, 0.8);
      expect(rules.height.fullTossAboveWaistIsNoBall, isFalse);
      expect(rules.height.bouncedAboveShoulderIsNoBall, isTrue);
    });

    test('a match without stored rules uses the defaults', () {
      final UmpiringRuleConfig rules = umpiringRulesFor(null, reviewsOff);

      expect(rules.wideEnabled, isTrue);
      expect(rules.noBallEnabled, isTrue);
    });
  });

  group('batsmanHeightMetres', () {
    final Player saved = samplePlayer.copyWith(declaredHeightCm: 180);

    test('the match entry wins over the saved player', () {
      expect(batsmanHeightMetres(matchPlayer: sampleMatchPlayer, player: saved), closeTo(1.70, 1e-9));
    });

    test('the saved player is used when the match entry has no height', () {
      const MatchPlayer noHeight = MatchPlayer(matchId: 'm', playerId: 'p', teamId: 't');
      expect(batsmanHeightMetres(matchPlayer: noHeight, player: saved), closeTo(1.80, 1e-9));
    });

    test('without any height the default is used', () {
      expect(batsmanHeightMetres(), defaultBatsmanHeightM);
      final Player none = Player(id: 'p', displayName: 'A', createdAt: t0, updatedAt: t0);
      expect(batsmanHeightMetres(player: none), defaultBatsmanHeightM);
    });
  });

  group('scan records', () {
    final DevicePolicy high = DevicePolicy.forProfile(DeviceProfile.high);

    test('a found wicket becomes a scan and an active wicket detection', () async {
      final SceneScanOutcome outcome =
          await SimulatedCvEngine(framePacing: false).scanScene(policy: high);

      final ScanRecords records = scanRecordsFrom(
        matchId: 'match-1',
        outcome: outcome,
        scanId: 'scan-9',
        wicketId: 'wicket-9',
        now: t1,
        scanDurationMs: 1234,
        captureFps: 60,
        cameraDeviceModel: 'Pixel',
      );

      expect(records.scan.id, 'scan-9');
      expect(records.scan.matchId, 'match-1');
      expect(records.scan.scanDurationMs, 1234);
      expect(records.scan.captureFps, 60);
      expect(records.scan.cameraDeviceModel, 'Pixel');
      expect(records.scan.overallConfidence, outcome.result.confidence);
      expect(records.scan.isMock, isTrue);
      expect(records.scan.createdAt, t1);

      final WicketDetection wicket = records.wicket!;
      expect(wicket.id, 'wicket-9');
      expect(wicket.sceneScanId, 'scan-9');
      expect(wicket.matchId, 'match-1');
      expect(wicket.wicketFamily, outcome.result.best!.family);
      expect(wicket.finalConfidence, outcome.result.best!.finalConfidence);
      expect(wicket.isActive, isTrue);
      expect(wicket.modelVersion, outcome.modelVersion);
      expect(wicket.targetPolygon, isNotEmpty);
    });

    test('a scan that found nothing stores only the scan', () async {
      final SceneScanOutcome outcome = await (SimulatedCvEngine(framePacing: false)
            ..configure(wicketKind: MockWicketKind.none))
          .scanScene(policy: high);

      final ScanRecords records = scanRecordsFrom(
        matchId: 'match-1',
        outcome: outcome,
        scanId: 'scan-9',
        wicketId: 'wicket-9',
        now: t1,
        scanDurationMs: -5,
      );

      expect(records.wicket, isNull);
      expect(records.scan.overallConfidence, 0);
      expect(records.scan.scanDurationMs, 0, reason: 'never negative');
    });

    test('a stored wicket turns back into a target for the pipeline', () async {
      final SceneScanOutcome outcome =
          await SimulatedCvEngine(framePacing: false).scanScene(policy: high);
      final WicketDetection wicket = scanRecordsFrom(
        matchId: 'match-1',
        outcome: outcome,
        scanId: 'scan-9',
        wicketId: 'wicket-9',
        now: t1,
        scanDurationMs: 1000,
      ).wicket!;

      final WicketTarget target = wicketTargetFrom(wicket)!;

      expect(target.confidence, wicket.finalConfidence);
      expect(target.family, wicket.wicketFamily);
      expect(target.polygon.isValid, isTrue);
    });

    test('no target is made from a missing, retired or damaged wicket', () {
      expect(wicketTargetFrom(null), isNull);
      expect(wicketTargetFrom(sampleWicket.copyWith(isActive: false)), isNull);
      final WicketDetection damaged = WicketDetection(
        id: 'w',
        matchId: 'm',
        wicketFamily: sampleWicket.wicketFamily,
        boundingBox: const <String, Object?>{},
        targetPolygon: const <Object?>['not a point', 3],
        objectConfidence: 0.9,
        temporalStability: 0.9,
        contextConfidence: 0.9,
        finalConfidence: 0.9,
        modelVersion: 'mock-scene-1.0',
        detectedAt: t0,
      );
      expect(wicketTargetFrom(damaged), isNull);
      final WicketDetection flat = WicketDetection(
        id: 'w',
        matchId: 'm',
        wicketFamily: sampleWicket.wicketFamily,
        boundingBox: const <String, Object?>{},
        targetPolygon: const <Object?>[
          <String, Object?>{'x': 0.1, 'y': 0.1},
          <String, Object?>{'x': 0.2, 'y': 0.1},
        ],
        objectConfidence: 0.9,
        temporalStability: 0.9,
        contextConfidence: 0.9,
        finalConfidence: 0.9,
        modelVersion: 'mock-scene-1.0',
        detectedAt: t0,
      );
      expect(wicketTargetFrom(flat), isNull);
    });
  });

  group('decisionInputsFor', () {
    final DeliveryAnalysis analysis = analysisOf(
      decisions: <DeliveryDecision>[
        decision(DeliveryDecisionType.wide, 'WIDE', 0.9, DecisionStatus.autoCall),
        decision(DeliveryDecisionType.noBallHeight, 'LEGAL', 0.8, DecisionStatus.reviewRecommended),
        decision(DeliveryDecisionType.wicketHit, 'OUT', 0.75, DecisionStatus.reviewRecommended),
        decision(DeliveryDecisionType.edge, 'INCONCLUSIVE', 0, DecisionStatus.inconclusive),
      ],
    );

    test('agreement keeps the suggestion as assistant output', () {
      final List<DecisionInput> inputs = decisionInputsFor(
        analysis,
        const DeliveryDraft(
          bowlerId: 'bowler',
          strikerId: 'striker',
          isWide: true,
          runsExtras: 1,
        ),
      );

      final DecisionInput wide = inputs[0];
      expect(wide.type, DeliveryDecisionType.wide);
      expect(wide.automatedResult, 'WIDE');
      expect(wide.finalResult, 'WIDE');
      expect(wide.status, DecisionStatus.autoCall);
      expect(wide.source, DecisionSource.aiAssist);
    });

    test('the scorer overruling a suggestion is recorded as a manual override', () {
      final List<DecisionInput> inputs = decisionInputsFor(analysis, plainBall);

      final DecisionInput wide = inputs[0];
      expect(wide.automatedResult, 'WIDE');
      expect(wide.finalResult, 'NOT_WIDE');
      expect(wide.status, DecisionStatus.manualOverride);
      expect(wide.source, DecisionSource.manual);
      expect(wide.confidence, 0.9);
    });

    test('a legal height call that the scorer accepted keeps its status', () {
      final DecisionInput height = decisionInputsFor(analysis, plainBall)[1];

      expect(height.automatedResult, 'LEGAL');
      expect(height.finalResult, 'LEGAL');
      expect(height.status, DecisionStatus.reviewRecommended);
      expect(height.source, DecisionSource.aiAssist);
    });

    test('a no-ball entered against a legal suggestion is an override', () {
      final DecisionInput height = decisionInputsFor(
        analysis,
        const DeliveryDraft(
          bowlerId: 'bowler',
          strikerId: 'striker',
          isNoBall: true,
          runsExtras: 1,
        ),
      )[1];

      expect(height.finalResult, 'NO_BALL');
      expect(height.status, DecisionStatus.manualOverride);
      expect(height.source, DecisionSource.manual);
    });

    test('review aids have no final result and keep their own status', () {
      final DecisionInput hit = decisionInputsFor(analysis, plainBall)[2];

      expect(hit.type, DeliveryDecisionType.wicketHit);
      expect(hit.finalResult, isNull);
      expect(hit.status, DecisionStatus.reviewRecommended);
      expect(hit.source, DecisionSource.aiAssist);
    });

    test('a result that was not sure stays "not sure"', () {
      final DecisionInput edge = decisionInputsFor(analysis, plainBall)[3];

      expect(edge.status, DecisionStatus.inconclusive);
      expect(edge.source, DecisionSource.aiAssist);
    });

    test('no analysis means no decisions', () {
      expect(decisionInputsFor(analysisOf(), plainBall), isEmpty);
    });
  });

  group('trajectoryInputFor', () {
    test('turns the tracked points into the stored compressed form', () {
      final TrajectoryInput? input = trajectoryInputFor(
        analysisOf(
          trajectory: const <BallTrackPoint>[
            BallTrackPoint(timestampMs: 2000, x: 0.5, y: 0.2, confidence: 0.9),
            BallTrackPoint(timestampMs: 2042, x: 0.51, y: 0.3, confidence: 0.8),
          ],
        ),
      );

      expect(input!.samplingFps, 24);
      expect(input.modelVersion, 'mock-ball-1.0+mock-pose-1.0');
      expect(input.points, <List<double>>[
        <double>[2000, 0.5, 0.2, 0.9],
        <double>[2042, 0.51, 0.3, 0.8],
      ]);
    });

    test('nothing tracked means nothing stored', () {
      expect(trajectoryInputFor(analysisOf()), isNull);
    });

    test('the sampling rate is kept between 1 and 240', () {
      const List<BallTrackPoint> one = <BallTrackPoint>[
        BallTrackPoint(timestampMs: 1, x: 0.5, y: 0.5, confidence: 0.9),
      ];
      expect(trajectoryInputFor(analysisOf(trajectory: one, samplingFps: 0))!.samplingFps, 1);
      expect(trajectoryInputFor(analysisOf(trajectory: one, samplingFps: 1000))!.samplingFps, 240);
      expect(trajectoryInputFor(analysisOf(trajectory: one, samplingFps: double.nan))!.samplingFps, 1);
    });
  });

  group('draftWithAnalysis', () {
    test('without an analysis the draft is unchanged', () {
      expect(identical(draftWithAnalysis(plainBall), plainBall), isTrue);
    });

    test('adds the measurements and keeps every number in its allowed range', () {
      final DeliveryDraft draft = draftWithAnalysis(
        plainBall,
        analysis: analysisOf(
          speed: const SpeedEstimate(kmph: 300, confidence: 1.4),
          trackingConfidence: 0.9,
          poseConfidence: 0.8,
        ),
        wicket: sampleWicket,
      );

      expect(draft.speedKmph, 250);
      expect(draft.speedConfidence, 1.0);
      expect(draft.ballTrackingConfidence, 0.9);
      expect(draft.poseTrackingConfidence, 0.8);
      expect(draft.wicketTrackingConfidence, sampleWicket.finalConfidence);
      expect(draft.wicketDetectionId, sampleWicket.id);
      expect(draft.bowlerId, 'bowler');
      expect(draft.strikerId, 'striker');
    });

    test('without a speed or a wicket those fields stay empty', () {
      final DeliveryDraft draft = draftWithAnalysis(plainBall, analysis: analysisOf());

      expect(draft.speedKmph, isNull);
      expect(draft.speedConfidence, isNull);
      expect(draft.wicketDetectionId, isNull);
      expect(draft.wicketTrackingConfidence, isNull);
      expect(draft.ballTrackingConfidence, 0.9);
    });

    test('the scorer\'s own entries are never changed', () {
      const DeliveryDraft scored = DeliveryDraft(
        bowlerId: 'bowler',
        strikerId: 'striker',
        nonStrikerId: 'other',
        runsBat: 4,
        isWicket: true,
        dismissalType: DismissalType.bowled,
        dismissedPlayerId: 'striker',
      );

      final DeliveryDraft draft = draftWithAnalysis(scored, analysis: analysisOf());

      expect(draft.runsBat, 4);
      expect(draft.isWicket, isTrue);
      expect(draft.dismissalType, DismissalType.bowled);
      expect(draft.dismissedPlayerId, 'striker');
      expect(draft.nonStrikerId, 'other');
    });
  });
}
