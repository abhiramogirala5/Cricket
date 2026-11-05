import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/cv/adapters/mock/mock.dart';
import 'package:gully_umpire/cv/contracts/camera_frame_input.dart';
import 'package:gully_umpire/cv/device/device_policy.dart';
import 'package:gully_umpire/cv/geometry/polygon.dart';
import 'package:gully_umpire/cv/pipelines/delivery_context.dart';
import 'package:gully_umpire/cv/pipelines/delivery_pipeline.dart';
import 'package:gully_umpire/cv/pipelines/delivery_pipeline_config.dart';
import 'package:gully_umpire/cv/rules/umpiring_rules.dart';
import 'package:gully_umpire/cv/scene/scan_readiness.dart';
import 'package:gully_umpire/cv/tracking/ball_track_point.dart';
import 'package:gully_umpire/cv/tracking/speed_estimator.dart';
import 'package:gully_umpire/domain/decisions/decision_status.dart';
import 'package:gully_umpire/domain/decisions/delivery_decision.dart';
import 'package:gully_umpire/domain/decisions/delivery_decision_type.dart';

const UmpiringRuleConfig reviewRules = UmpiringRuleConfig(edgeReviewEnabled: true, lbwReviewEnabled: true);

DeliveryPipeline pipelineFor(MockScenario scenario, {bool withAudio = true}) {
  return DeliveryPipeline(
    ballDetector: MockBallDetector(scenario),
    poseEstimator: MockPoseEstimator(scenario),
    audioAnalyzer: withAudio ? MockAudioAnalyzer(scenario) : null,
  );
}

Stream<CameraFrameInput> cameraFor(MockScenario scenario, DevicePolicy policy) {
  return MockCamera.frames(
    fps: policy.cameraFps,
    startMs: scenario.releaseMs - 300,
    endMs: scenario.releaseMs + 1400,
  );
}

DeliveryContext contextFor(
  MockScenario scenario,
  DevicePolicy policy, {
  UmpiringRuleConfig rules = const UmpiringRuleConfig(),
  ScanReadiness readiness = ScanReadiness.ready,
  bool withWicket = true,
  double wicketConfidence = 0.95,
}) {
  final Polygon? truth = MockWorld(scenario).truthWicketPolygon();
  return DeliveryContext(
    policy: policy,
    rules: rules,
    batsmanHeightM: scenario.batsmanHeightM,
    wicket: withWicket && truth != null
        ? WicketTarget(polygon: truth, confidence: wicketConfidence)
        : null,
    readiness: readiness,
    // The mock camera's pitch is invented, so its flight length is assumed.
    assumedFlightDistanceM: 15,
  );
}

Future<DeliveryAnalysis> runDelivery(
  MockScenario scenario, {
  DeviceProfile profile = DeviceProfile.high,
  UmpiringRuleConfig rules = const UmpiringRuleConfig(),
  ScanReadiness readiness = ScanReadiness.ready,
  bool withWicket = true,
  bool withAudio = true,
  CancellationFlag? cancel,
}) {
  final DevicePolicy policy = DevicePolicy.forProfile(profile);
  return pipelineFor(scenario, withAudio: withAudio).analyse(
    frames: cameraFor(scenario, policy),
    context: contextFor(
      scenario,
      policy,
      rules: rules,
      readiness: readiness,
      withWicket: withWicket,
    ),
    cancel: cancel,
  );
}

MockScenario scenarioOf(MockDeliveryKind kind, {int seed = 1}) =>
    MockScenario(deliveryKind: kind, seed: seed);

DeliveryDecision? decisionOf(DeliveryAnalysis analysis, DeliveryDecisionType type) {
  for (final DeliveryDecision decision in analysis.decisions) {
    if (decision.type == type) {
      return decision;
    }
  }
  return null;
}

void main() {
  group('a straight hit on a high-end phone', () {
    late DeliveryAnalysis analysis;

    setUpAll(() async {
      analysis = await runDelivery(scenarioOf(MockDeliveryKind.straightHit));
    });

    test('is labelled as coming from mock models', () {
      expect(analysis.isMock, isTrue);
      expect(analysis.modelVersion, 'mock-ball-1.0+mock-pose-1.0+mock-audio-1.0');
    });

    test('processes every camera frame', () {
      // 1700 ms at 60 fps, both ends included.
      expect(analysis.framesProcessed, 103);
      expect(analysis.wasCancelled, isFalse);
    });

    test('tracks the ball well', () {
      expect(analysis.trackingConfidence, greaterThanOrEqualTo(0.75));
      expect(analysis.poseConfidence, greaterThan(0.8));
      expect(analysis.samplingFps, inInclusiveRange(15, 35));
      expect(analysis.trajectory.length, greaterThanOrEqualTo(12));
      for (int i = 1; i < analysis.trajectory.length; i++) {
        expect(
          analysis.trajectory[i].timestampMs,
          greaterThan(analysis.trajectory[i - 1].timestampMs),
        );
      }
      for (final BallTrackPoint point in analysis.trajectory) {
        expect(point.x, inInclusiveRange(0, 1));
        expect(point.y, inInclusiveRange(0, 1));
      }
    });

    test('finds the moment the ball reached the batter (900 ms after release)', () {
      expect(analysis.arrivalMs, isNotNull);
      expect(analysis.arrivalMs!, closeTo(2900, 60));
    });

    test('measures a ball that bounced, close to the batter and below head height', () {
      expect(analysis.bounced, isTrue);
      expect(analysis.ballLateralM!.abs(), lessThan(0.35));
      expect(analysis.ballHeightM!, inInclusiveRange(0.4, 1.0));
    });

    test('says not wide and legal height', () {
      final DeliveryDecision wide = decisionOf(analysis, DeliveryDecisionType.wide)!;
      expect(wide.automatedResult, 'NOT_WIDE');
      expect(wide.status, isNot(DecisionStatus.inconclusive));
      final DeliveryDecision height = decisionOf(analysis, DeliveryDecisionType.noBallHeight)!;
      expect(height.automatedResult, 'LEGAL');
      expect(height.status, isNot(DecisionStatus.inconclusive));
    });

    test('offers a wicket-hit review, never an automatic call', () {
      final DeliveryDecision hit = decisionOf(analysis, DeliveryDecisionType.wicketHit)!;
      expect(hit.automatedResult, 'LIKELY_HIT');
      expect(hit.status, DecisionStatus.reviewRecommended);
      expect(hit.confidence, lessThanOrEqualTo(0.8));
    });

    test('has an estimated speed that stays below the confidence cap', () {
      final SpeedEstimate speed = analysis.speed!;
      expect(speed.kmph, inInclusiveRange(15, 170));
      expect(speed.confidence, lessThanOrEqualTo(SpeedEstimator.maxConfidence));
    });

    test('edge and LBW stay off unless they are switched on', () {
      expect(decisionOf(analysis, DeliveryDecisionType.edge), isNull);
      expect(decisionOf(analysis, DeliveryDecisionType.lbw), isNull);
    });
  });

  group('different deliveries on a high-end phone', () {
    test('an off-stump miss is not a wide', () async {
      final DeliveryAnalysis analysis = await runDelivery(scenarioOf(MockDeliveryKind.offStumpMiss));
      expect(decisionOf(analysis, DeliveryDecisionType.wide)!.automatedResult, 'NOT_WIDE');
      expect(analysis.ballLateralM!.abs(), inInclusiveRange(0.3, 1.0));
      final DeliveryDecision? hit = decisionOf(analysis, DeliveryDecisionType.wicketHit);
      if (hit != null) {
        expect(hit.automatedResult, isNot('LIKELY_HIT'));
      }
    });

    test('a ball far outside the batter is a wide', () async {
      final DeliveryAnalysis analysis = await runDelivery(scenarioOf(MockDeliveryKind.wide));
      final DeliveryDecision wide = decisionOf(analysis, DeliveryDecisionType.wide)!;
      expect(wide.automatedResult, 'WIDE');
      expect(wide.status, isNot(DecisionStatus.inconclusive));
      expect(analysis.ballLateralM!, greaterThan(1.2));
      expect(decisionOf(analysis, DeliveryDecisionType.wicketHit)!.automatedResult, 'LIKELY_MISS');
    });

    test('a full toss at head height is a no-ball', () async {
      final DeliveryAnalysis analysis = await runDelivery(scenarioOf(MockDeliveryKind.highFullToss));
      final DeliveryDecision height = decisionOf(analysis, DeliveryDecisionType.noBallHeight)!;
      expect(height.automatedResult, 'NO_BALL');
      expect(analysis.bounced, isFalse);
      expect(analysis.ballHeightM!, greaterThan(1.0));
      expect(decisionOf(analysis, DeliveryDecisionType.wide)!.automatedResult, 'NOT_WIDE');
    });

    test('a high bouncer is legal under the default rules', () async {
      final DeliveryAnalysis analysis = await runDelivery(scenarioOf(MockDeliveryKind.bouncer));
      expect(analysis.bounced, isTrue);
      expect(analysis.ballHeightM!, greaterThan(1.1));
      expect(decisionOf(analysis, DeliveryDecisionType.noBallHeight)!.automatedResult, 'LEGAL');
    });

    test('the same bouncer is a no-ball when the shoulder rule is switched on', () async {
      final DeliveryAnalysis analysis = await runDelivery(
        scenarioOf(MockDeliveryKind.bouncer),
        rules: const UmpiringRuleConfig(
          height: HeightRuleConfig(bouncedAboveShoulderIsNoBall: true, shoulderHeightRatio: 0.70),
        ),
      );
      expect(decisionOf(analysis, DeliveryDecisionType.noBallHeight)!.automatedResult, 'NO_BALL');
    });

    test('a batter who steps towards a wide ball makes it not a wide', () async {
      final MockScenario scenario = MockScenario(
        deliveryKind: MockDeliveryKind.wide,
        batsmanShiftX: 0.14,
      );
      final DeliveryAnalysis analysis = await runDelivery(scenario);
      final DeliveryDecision wide = decisionOf(analysis, DeliveryDecisionType.wide)!;
      expect(wide.automatedResult, 'NOT_WIDE');
      expect(wide.summary.toLowerCase(), contains('moved'));
    });
  });

  group('review aids when switched on (experimental)', () {
    test('an edge with a synchronised click is a likely edge to review', () async {
      for (int seed = 1; seed <= 3; seed++) {
        final DeliveryAnalysis analysis = await runDelivery(
          scenarioOf(MockDeliveryKind.edge, seed: seed),
          rules: reviewRules,
        );
        final DeliveryDecision edge = decisionOf(analysis, DeliveryDecisionType.edge)!;
        expect(edge.automatedResult, 'EDGE_LIKELY', reason: 'seed $seed');
        expect(edge.status, DecisionStatus.reviewRecommended, reason: 'seed $seed');
        expect(edge.evidence['audio_available'], isTrue, reason: 'seed $seed');
        expect(edge.evidence['audio_score'] as num, greaterThan(0.5), reason: 'seed $seed');
      }
    });

    test('a pad hit without a click is only a review, not a likely edge', () async {
      for (int seed = 1; seed <= 3; seed++) {
        final DeliveryAnalysis analysis = await runDelivery(
          scenarioOf(MockDeliveryKind.lbwHitting, seed: seed),
          rules: reviewRules,
        );
        final DeliveryDecision edge = decisionOf(analysis, DeliveryDecisionType.edge)!;
        expect(edge.automatedResult, 'REVIEW_RECOMMENDED', reason: 'seed $seed');
        expect(edge.status, DecisionStatus.reviewRecommended, reason: 'seed $seed');
      }
    });

    test('LBW says hitting for a ball heading at the stumps', () async {
      for (int seed = 1; seed <= 3; seed++) {
        final DeliveryAnalysis analysis = await runDelivery(
          scenarioOf(MockDeliveryKind.lbwHitting, seed: seed),
          rules: reviewRules,
        );
        final DeliveryDecision lbw = decisionOf(analysis, DeliveryDecisionType.lbw)!;
        expect(lbw.automatedResult, 'LIKELY_HITTING', reason: 'seed $seed');
        expect(lbw.status, DecisionStatus.reviewRecommended, reason: 'seed $seed');
        expect(lbw.confidence, lessThanOrEqualTo(0.75), reason: 'seed $seed');
      }
    });

    test('LBW says missing for a ball heading well outside the stumps', () async {
      for (int seed = 1; seed <= 3; seed++) {
        final DeliveryAnalysis analysis = await runDelivery(
          scenarioOf(MockDeliveryKind.lbwMissing, seed: seed),
          rules: reviewRules,
        );
        expect(
          decisionOf(analysis, DeliveryDecisionType.lbw)!.automatedResult,
          'LIKELY_MISSING',
          reason: 'seed $seed',
        );
      }
    });

    test('deliveries without a contact have no edge or LBW result', () async {
      for (final MockDeliveryKind kind in <MockDeliveryKind>[
        MockDeliveryKind.straightHit,
        MockDeliveryKind.offStumpMiss,
        MockDeliveryKind.wide,
        MockDeliveryKind.highFullToss,
        MockDeliveryKind.bouncer,
      ]) {
        final DeliveryAnalysis analysis = await runDelivery(scenarioOf(kind), rules: reviewRules);
        expect(decisionOf(analysis, DeliveryDecisionType.edge), isNull, reason: kind.name);
        expect(decisionOf(analysis, DeliveryDecisionType.lbw), isNull, reason: kind.name);
      }
    });
  });

  group('rule switches and scene readiness', () {
    test('wide and no-ball checks can be switched off', () async {
      final DeliveryAnalysis noWide = await runDelivery(
        scenarioOf(MockDeliveryKind.straightHit),
        rules: const UmpiringRuleConfig(wideEnabled: false),
      );
      expect(decisionOf(noWide, DeliveryDecisionType.wide), isNull);
      expect(decisionOf(noWide, DeliveryDecisionType.noBallHeight), isNotNull);

      final DeliveryAnalysis noHeight = await runDelivery(
        scenarioOf(MockDeliveryKind.straightHit),
        rules: const UmpiringRuleConfig(noBallEnabled: false),
      );
      expect(decisionOf(noHeight, DeliveryDecisionType.noBallHeight), isNull);
      expect(decisionOf(noHeight, DeliveryDecisionType.wide), isNotNull);

      final DeliveryAnalysis noHit = await runDelivery(
        scenarioOf(MockDeliveryKind.straightHit),
        rules: const UmpiringRuleConfig(wicketHitEnabled: false),
      );
      expect(decisionOf(noHit, DeliveryDecisionType.wicketHit), isNull);
    });

    test('without a wicket the wide check is not sure and there is no wicket review', () async {
      final DeliveryAnalysis analysis = await runDelivery(
        scenarioOf(MockDeliveryKind.wide),
        withWicket: false,
      );
      final DeliveryDecision wide = decisionOf(analysis, DeliveryDecisionType.wide)!;
      expect(wide.status, DecisionStatus.inconclusive);
      expect(decisionOf(analysis, DeliveryDecisionType.wicketHit), isNull);
      // The height check does not depend on the wicket.
      expect(decisionOf(analysis, DeliveryDecisionType.noBallHeight)!.automatedResult, 'LEGAL');
    });

    test('a scene that asks for repositioning gives no assistance at all', () async {
      final DeliveryAnalysis analysis = await runDelivery(
        scenarioOf(MockDeliveryKind.wide),
        readiness: ScanReadiness.reposition,
      );
      expect(analysis.decisions, isEmpty);
      expect(analysis.notes, isNotEmpty);
    });

    test('limited readiness allows a wide check only', () async {
      final DeliveryAnalysis analysis = await runDelivery(
        scenarioOf(MockDeliveryKind.wide),
        readiness: ScanReadiness.limited,
      );
      expect(decisionOf(analysis, DeliveryDecisionType.wide), isNotNull);
      expect(decisionOf(analysis, DeliveryDecisionType.noBallHeight), isNull);
      expect(decisionOf(analysis, DeliveryDecisionType.wicketHit), isNull);
    });
  });

  group('device profiles', () {
    test('a mid-range phone only reports calls it is sure about', () async {
      final DeliveryAnalysis analysis = await runDelivery(
        scenarioOf(MockDeliveryKind.wide),
        profile: DeviceProfile.mid,
      );
      expect(analysis.decisions, isNotEmpty);
      for (final DeliveryDecision decision in analysis.decisions) {
        expect(decision.status, DecisionStatus.autoCall);
      }
      expect(decisionOf(analysis, DeliveryDecisionType.wide)!.automatedResult, 'WIDE');
      expect(analysis.samplingFps, inInclusiveRange(8, 16));
    });

    test('a mid-range phone does not have enough ball points for a wicket review', () async {
      final DeliveryAnalysis analysis = await runDelivery(scenarioOf(MockDeliveryKind.straightHit), profile: DeviceProfile.mid);
      expect(decisionOf(analysis, DeliveryDecisionType.wicketHit), isNull);
      expect(analysis.bounced, isTrue);
      expect(analysis.arrivalMs!, closeTo(2900, 80));
    });

    test('an entry-level phone never makes an automatic call', () async {
      final DeliveryAnalysis analysis = await runDelivery(
        scenarioOf(MockDeliveryKind.straightHit),
        profile: DeviceProfile.low,
        rules: reviewRules,
      );
      for (final DeliveryDecision decision in analysis.decisions) {
        expect(decision.status, isNot(DecisionStatus.autoCall));
      }
      final DeliveryDecision wide = decisionOf(analysis, DeliveryDecisionType.wide)!;
      expect(wide.automatedResult, 'NOT_WIDE');
      expect(wide.status, DecisionStatus.reviewRecommended);
      expect(decisionOf(analysis, DeliveryDecisionType.wicketHit), isNull);
      expect(decisionOf(analysis, DeliveryDecisionType.edge), isNull);
      expect(decisionOf(analysis, DeliveryDecisionType.lbw), isNull);
      expect(analysis.speed, isNull);
    });

    test('a score-only phone is not analysed at all', () async {
      final DeliveryAnalysis analysis = await runDelivery(
        scenarioOf(MockDeliveryKind.straightHit),
        profile: DeviceProfile.scoreOnly,
      );
      expect(analysis.decisions, isEmpty);
      expect(analysis.trajectory, isEmpty);
      expect(analysis.framesProcessed, 0);
      expect(analysis.notes, isNotEmpty);
      expect(analysis.isMock, isTrue);
    });
  });

  group('when the ball is not seen', () {
    test('a lost ball never produces a call, on any phone', () async {
      for (final DeviceProfile profile in <DeviceProfile>[
        DeviceProfile.high,
        DeviceProfile.mid,
        DeviceProfile.low,
      ]) {
        final DeliveryAnalysis analysis = await runDelivery(
          scenarioOf(MockDeliveryKind.lostBall),
          profile: profile,
        );
        for (final DeliveryDecision decision in analysis.decisions) {
          expect(decision.status, DecisionStatus.inconclusive, reason: profile.name);
        }
        expect(analysis.arrivalMs, isNull, reason: profile.name);
        expect(analysis.bounced, isNull, reason: profile.name);
      }
    });

    test('without a readable batter the checks are not sure', () async {
      final DeliveryAnalysis analysis = await runDelivery(
        MockScenario(poseQuality: MockPoseQuality.none),
      );
      expect(analysis.poseConfidence, 0);
      expect(analysis.decisions, isNotEmpty);
      for (final DeliveryDecision decision in analysis.decisions) {
        expect(decision.status, DecisionStatus.inconclusive);
      }
    });
  });

  group('cancellation', () {
    test('a flag raised before the start stops at the first frame', () async {
      final CancellationFlag flag = CancellationFlag()..cancel();
      final DeliveryAnalysis analysis = await runDelivery(const MockScenario(), cancel: flag);
      expect(analysis.wasCancelled, isTrue);
      expect(analysis.decisions, isEmpty);
      expect(analysis.framesProcessed, 0);
    });

    test('a flag raised part way stops the analysis', () async {
      const MockScenario scenario = MockScenario();
      final DevicePolicy policy = DevicePolicy.forProfile(DeviceProfile.high);
      final CancellationFlag flag = CancellationFlag();
      Stream<CameraFrameInput> cancelAfterTen() async* {
        int index = 0;
        await for (final CameraFrameInput frame in cameraFor(scenario, policy)) {
          if (index == 10) {
            flag.cancel();
          }
          index += 1;
          yield frame;
        }
      }

      final DeliveryAnalysis analysis = await pipelineFor(scenario).analyse(
        frames: cancelAfterTen(),
        context: contextFor(scenario, policy),
        cancel: flag,
      );
      expect(analysis.wasCancelled, isTrue);
      expect(analysis.framesProcessed, 10);
      expect(analysis.decisions, isEmpty);
    });

    test('the flag starts uncancelled and stays cancelled', () {
      final CancellationFlag flag = CancellationFlag();
      expect(flag.isCancelled, isFalse);
      flag.cancel();
      flag.cancel();
      expect(flag.isCancelled, isTrue);
    });
  });

  group('determinism', () {
    test('the same scenario gives the same result twice', () async {
      final DeliveryAnalysis a = await runDelivery(scenarioOf(MockDeliveryKind.wide, seed: 5));
      final DeliveryAnalysis b = await runDelivery(scenarioOf(MockDeliveryKind.wide, seed: 5));
      expect(a.trajectory, b.trajectory);
      expect(a.arrivalMs, b.arrivalMs);
      expect(a.decisions, b.decisions);
      expect(a.trackingConfidence, b.trackingConfidence);
    });
  });

  group('DeliveryAnalysis.none and DeliveryPipelineConfig', () {
    test('none carries only the model information', () {
      final DeliveryAnalysis none = DeliveryAnalysis.none(modelVersion: 'mock-x', isMock: true);
      expect(none.decisions, isEmpty);
      expect(none.trajectory, isEmpty);
      expect(none.trackingConfidence, 0);
      expect(none.speed, isNull);
      expect(none.wasCancelled, isFalse);
    });

    test('the track gap follows the detector interval within limits', () {
      const DeliveryPipelineConfig config = DeliveryPipelineConfig();
      expect(config.gapMsFor(42), 100);
      expect(config.gapMsFor(83), 183);
      expect(config.gapMsFor(125), 275);
      expect(config.gapMsFor(250), 400);
      expect(config.gapMsFor(0), 100);
    });

    test('the pipeline reports its model version without running', () {
      final DeliveryPipeline pipeline = pipelineFor(const MockScenario(), withAudio: false);
      expect(pipeline.modelVersion, 'mock-ball-1.0+mock-pose-1.0');
      expect(pipeline.isMock, isTrue);
    });
  });
}
