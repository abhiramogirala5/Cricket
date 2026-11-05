import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/cv/device/device_policy.dart';
import 'package:gully_umpire/cv/live/ball_kind.dart';
import 'package:gully_umpire/cv/live/live_analysis.dart';
import 'package:gully_umpire/cv/live/live_tracker.dart';
import 'package:gully_umpire/cv/live/replay_codec.dart';
import 'package:gully_umpire/cv/live/replay_meta.dart';
import 'package:gully_umpire/cv/live/vision_protocol.dart';
import 'package:gully_umpire/cv/pipelines/ball_observation.dart';
import 'package:gully_umpire/cv/pipelines/delivery_context.dart';
import 'package:gully_umpire/cv/pipelines/pose_sample.dart';
import 'package:gully_umpire/cv/rules/umpiring_rules.dart';
import 'package:gully_umpire/cv/vision/luma_frame.dart';
import 'package:gully_umpire/domain/decisions/delivery_decision.dart';

import '../../support/flight_fixtures.dart';

LiveInputs inputs({
  bool withWicket = true,
  UmpiringRuleConfig rules = const UmpiringRuleConfig(),
  double? cameraToBatterM,
}) {
  return LiveInputs(
    policy: DevicePolicy.live(DeviceProfile.high),
    rules: rules,
    batsmanHeightM: batterHeightM,
    ballKind: BallKind.cricketBall,
    wicket: withWicket ? wicketOutline() : null,
    wicketConfidence: 0.9,
    cameraToBatterM: cameraToBatterM,
  );
}

DecodedCapture captureOf(List<BallObservation> observations, {Uint8List? replay}) {
  return DecodedCapture(
    capture: LiveDeliveryCapture(
      observations: observations,
      frameTimesMs: timesOf(observations),
      aspectRatio: 0.5625,
      framesProcessed: 50,
      frameWidth: 180,
      frameHeight: 320,
      trackQuality: 0.9,
      startMs: observations.first.timestampMs,
      endMs: observations.last.timestampMs,
    ),
    replay: replay,
  );
}

Uint8List tinyPack() {
  return ReplayCodec.encode(<LumaFrame>[
    for (int i = 0; i < 3; i++)
      LumaFrame(width: 16, height: 9, timestampMs: 400 + i * 33, pixels: Uint8List(16 * 9)),
  ]);
}

void main() {
  group('LiveInputs', () {
    test('builds the context the interpreter needs from a marked wicket', () {
      final LiveInputs live = inputs();

      final DeliveryContext context = live.toContext();

      expect(context.policy, live.policy);
      expect(context.rules, live.rules);
      expect(context.batsmanHeightM, batterHeightM);
      expect(context.wicket!.polygon, wicketOutline());
      expect(context.wicket!.confidence, 0.9);
      expect(context.readiness.asksToReposition, isFalse);
    });

    test('without a wicket the scene is not ready for assistance', () {
      final DeliveryContext context = inputs(withWicket: false).toContext();

      expect(context.wicket, isNull);
      expect(context.readiness.asksToReposition, isTrue);
    });

    test('carries the distance to the batter into the context, and none when none was entered', () {
      expect(inputs(cameraToBatterM: 12.192).toContext().cameraToBatterM, 12.192);
      expect(inputs().toContext().cameraToBatterM, isNull);
      // Nothing is assumed in its place.
      expect(inputs().toContext().assumedFlightDistanceM, isNull);
    });

    test('a copy keeps the distance, replaces it, or drops it', () {
      final LiveInputs live = inputs(cameraToBatterM: 12.192);

      expect(live.copyWith(batsmanHeightM: 1.9).cameraToBatterM, 12.192);
      expect(live.copyWith(cameraToBatterM: 15).cameraToBatterM, 15);
      expect(live.copyWith(withoutDistance: true).cameraToBatterM, isNull);
      expect(live.copyWith(withoutDistance: true), isNot(live));
    });

    test('a copy changes only what it is told to', () {
      final LiveInputs live = inputs();

      final LiveInputs taller = live.copyWith(batsmanHeightM: 1.9, ballKind: BallKind.tennisBall);

      expect(taller.batsmanHeightM, 1.9);
      expect(taller.ballKind, BallKind.tennisBall);
      expect(taller.policy, live.policy);
      expect(taller.rules, live.rules);
      expect(taller.wicket, live.wicket);
      expect(live.batsmanHeightM, batterHeightM);
      expect(taller, isNot(live));
      expect(live.copyWith(), live);
    });
  });

  group('analyseLiveDelivery', () {
    test('interprets a delivery, labels it as live and keeps the numbers for the replay', () async {
      final List<BallObservation> observations = flight();

      final LiveDeliveryResult result = await analyseLiveDelivery(
        decoded: captureOf(observations),
        poses: standingBatter(),
        inputs: inputs(),
        nowMs: 123456,
      );

      expect(result.receivedAtMs, 123456);
      expect(result.analysis.isMock, isFalse);
      expect(result.analysis.modelVersion, liveModelVersion);
      expect(result.analysis.framesProcessed, 50);
      expect(result.analysis.bounced, isTrue);
      expect(result.analysis.arrivalMs, closeTo(flightArrivalMs, 2));
      final ReplayMeta meta = result.meta;
      expect(meta.ballKind, 'CRICKET_BALL');
      expect(meta.aspectRatio, 0.5625);
      expect(meta.batterHeightM, batterHeightM);
      expect(meta.track, hasLength(observations.length));
      expect(meta.track.first.timestampMs, observations.first.timestampMs);
      expect(meta.track.first.diameter, observations.first.diameter);
      expect(meta.track.last.y, observations.last.y);
      expect(meta.wicket, wicketOutline());
      expect(meta.plane, result.analysis.plane);
      expect(meta.arrivalMs, result.analysis.arrivalMs);
      expect(meta.bounceMs, result.analysis.bounceMs);
      expect(meta.bounced, isTrue);
      expect(meta.ballHeightM, result.analysis.ballHeightM);
      expect(meta.ballLateralM, result.analysis.ballLateralM);
      expect(meta.heightUncertaintyM, 0.30);
      expect(meta.waistRatio, 0.55);
      expect(meta.shoulderRatio, 0.82);
      expect(meta.poses, result.analysis.poses);
      expect(meta.trackQuality, result.analysis.trackingConfidence);
    });

    test('the replay shows exactly the verdicts the app gave', () async {
      final LiveDeliveryResult result = await analyseLiveDelivery(
        decoded: captureOf(flight()),
        poses: standingBatter(),
        inputs: inputs(),
        nowMs: 0,
      );

      expect(result.analysis.decisions, isNotEmpty);
      expect(result.meta.verdicts, hasLength(result.analysis.decisions.length));
      for (int i = 0; i < result.analysis.decisions.length; i++) {
        final DeliveryDecision decision = result.analysis.decisions[i];
        final ReplayVerdict verdict = result.meta.verdicts[i];
        expect(verdict.typeWire, decision.type.wire);
        expect(verdict.result, decision.automatedResult);
        expect(verdict.statusWire, decision.status.wire);
        expect(verdict.confidence, decision.confidence);
        expect(verdict.summary, decision.summary);
      }
    });

    test('puts the meaning of the delivery into the replay file itself', () async {
      final LiveDeliveryResult result = await analyseLiveDelivery(
        decoded: captureOf(flight(), replay: tinyPack()),
        poses: standingBatter(),
        inputs: inputs(),
        nowMs: 0,
      );

      expect(result.replay, isNotNull);
      final ReplayReader reader = ReplayReader.parse(result.replay!);
      expect(reader.frameCount, 3);
      expect(ReplayMeta.fromJson(reader.meta!), result.meta);
    });

    test('has no replay file when the worker kept no pictures', () async {
      final LiveDeliveryResult result = await analyseLiveDelivery(
        decoded: captureOf(flight()),
        poses: standingBatter(),
        inputs: inputs(),
        nowMs: 0,
      );

      expect(result.replay, isNull);
      expect(result.meta.track, isNotEmpty);
    });

    test('is not sure about a ball that was hardly tracked', () async {
      final List<BallObservation> two = flight().take(2).toList();

      final LiveDeliveryResult result = await analyseLiveDelivery(
        decoded: captureOf(two),
        poses: standingBatter(),
        inputs: inputs(),
        nowMs: 0,
      );

      expect(result.analysis.arrivalMs, isNull);
      expect(result.analysis.decisions, isNotEmpty);
      for (final DeliveryDecision decision in result.analysis.decisions) {
        expect(decision.automatedResult, 'INCONCLUSIVE');
      }
      expect(result.analysis.notes, contains('The ball was not tracked clearly enough.'));
      expect(result.meta.verdicts.every((ReplayVerdict v) => v.result == 'INCONCLUSIVE'), isTrue);
    });

    test('is not sure when the batter was not seen', () async {
      final LiveDeliveryResult result = await analyseLiveDelivery(
        decoded: captureOf(flight()),
        poses: const <PoseSample>[],
        inputs: inputs(),
        nowMs: 0,
      );

      expect(result.analysis.notes, contains('The batter was not visible enough to measure.'));
      expect(result.analysis.decisions, isNotEmpty);
      expect(result.analysis.decisions.every((DeliveryDecision d) => d.isInconclusive), isTrue);
    });

    test('gives no assistance until the wicket has been marked', () async {
      final LiveDeliveryResult result = await analyseLiveDelivery(
        decoded: captureOf(flight(), replay: tinyPack()),
        poses: standingBatter(),
        inputs: inputs(withWicket: false),
        nowMs: 0,
      );

      expect(result.analysis.decisions, isEmpty);
      expect(result.analysis.notes, contains('Umpire assistance is not available for this delivery.'));
      expect(result.meta.verdicts, isEmpty);
      expect(result.meta.wicket, isNull);
      // The ball path and the replay are still there to look at.
      expect(result.meta.track, hasLength(flight().length));
      expect(result.replay, isNotNull);
    });

    test('a phone that cannot keep up gets no assistance either', () async {
      final LiveDeliveryResult result = await analyseLiveDelivery(
        decoded: captureOf(flight()),
        poses: standingBatter(),
        inputs: inputs().copyWith(policy: DevicePolicy.live(DeviceProfile.scoreOnly)),
        nowMs: 0,
      );

      expect(result.analysis.decisions, isEmpty);
    });

    test('the match rules decide which checks are made', () async {
      final LiveDeliveryResult result = await analyseLiveDelivery(
        decoded: captureOf(flight()),
        poses: standingBatter(),
        inputs: inputs(rules: const UmpiringRuleConfig(wideEnabled: false, wicketHitEnabled: false)),
        nowMs: 0,
      );

      final Set<String> types = result.meta.verdicts.map((ReplayVerdict v) => v.typeWire).toSet();
      expect(types, <String>{'NO_BALL_HEIGHT'});
    });

    test('the version label says the result came from the live camera, not from a mock', () {
      expect(liveModelVersion, startsWith('live-'));
      expect(liveModelVersion, isNot(startsWith('mock')));
    });
  });
}
