import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/cv/device/device_policy.dart';
import 'package:gully_umpire/domain/decisions/decision_status.dart';
import 'package:gully_umpire/domain/decisions/delivery_decision.dart';
import 'package:gully_umpire/domain/decisions/delivery_decision_type.dart';

DeliveryDecision decision(DeliveryDecisionType type, DecisionStatus status, {double confidence = 0.9}) {
  return DeliveryDecision(
    type: type,
    automatedResult: 'RESULT',
    confidence: confidence,
    status: status,
    summary: 'Summary',
  );
}

DevicePolicy policy(DeviceProfile profile) => DevicePolicy.forProfile(profile);

void main() {
  group('DeviceProfile', () {
    test('wire values round-trip and unknown values fall back to score only', () {
      for (final DeviceProfile profile in DeviceProfile.values) {
        expect(DeviceProfile.fromWire(profile.wire), profile);
      }
      expect(DeviceProfile.fromWire('SUPER'), DeviceProfile.scoreOnly);
      expect(DeviceProfile.fromWire(null), DeviceProfile.scoreOnly);
    });

    test('classify uses processors and memory, preferring the lower profile', () {
      expect(DeviceProfile.classify(processorCount: 8), DeviceProfile.high);
      expect(DeviceProfile.classify(processorCount: 8, memoryMb: 8000), DeviceProfile.high);
      expect(DeviceProfile.classify(processorCount: 8, memoryMb: 4000), DeviceProfile.mid);
      expect(DeviceProfile.classify(processorCount: 6, memoryMb: 4000), DeviceProfile.mid);
      expect(DeviceProfile.classify(processorCount: 6, memoryMb: 3000), DeviceProfile.low);
      expect(DeviceProfile.classify(processorCount: 4, memoryMb: 2000), DeviceProfile.low);
      expect(DeviceProfile.classify(processorCount: 4), DeviceProfile.low);
      expect(DeviceProfile.classify(processorCount: 4, memoryMb: 1500), DeviceProfile.scoreOnly);
      expect(DeviceProfile.classify(processorCount: 2), DeviceProfile.scoreOnly);
    });
  });

  group('DevicePolicy table', () {
    test('frame rates follow the spec', () {
      expect(policy(DeviceProfile.high).cameraFps, 60);
      expect(policy(DeviceProfile.high).ballDetectorFps, 24);
      expect(policy(DeviceProfile.high).poseFps, 12);
      expect(policy(DeviceProfile.mid).cameraFps, 30);
      expect(policy(DeviceProfile.mid).ballDetectorFps, 12);
      expect(policy(DeviceProfile.mid).poseFps, 8);
      expect(policy(DeviceProfile.low).cameraFps, 30);
      expect(policy(DeviceProfile.low).ballDetectorFps, 8);
      expect(policy(DeviceProfile.low).poseFps, 4);
      expect(policy(DeviceProfile.scoreOnly).cameraFps, 0);
    });

    test('detector intervals are derived from the frame rates', () {
      expect(policy(DeviceProfile.high).ballIntervalMs, 42);
      expect(policy(DeviceProfile.high).poseIntervalMs, 83);
      expect(policy(DeviceProfile.mid).ballIntervalMs, 83);
      expect(policy(DeviceProfile.mid).poseIntervalMs, 125);
      expect(policy(DeviceProfile.low).ballIntervalMs, 125);
      expect(policy(DeviceProfile.low).poseIntervalMs, 250);
      expect(policy(DeviceProfile.scoreOnly).ballIntervalMs, 0);
      expect(policy(DeviceProfile.scoreOnly).poseIntervalMs, 0);
    });

    test('weaker devices need more track points before reviewing', () {
      expect(policy(DeviceProfile.high).minTrackPointsForReview, 6);
      expect(policy(DeviceProfile.mid).minTrackPointsForReview, 10);
      expect(policy(DeviceProfile.low).minTrackPointsForReview, 12);
    });

    test('only score-only devices cannot run umpiring', () {
      expect(policy(DeviceProfile.high).isUmpiringAvailable, isTrue);
      expect(policy(DeviceProfile.mid).isUmpiringAvailable, isTrue);
      expect(policy(DeviceProfile.low).isUmpiringAvailable, isTrue);
      expect(policy(DeviceProfile.scoreOnly).isUmpiringAvailable, isFalse);
    });

    test('each policy reports its own profile', () {
      for (final DeviceProfile profile in DeviceProfile.values) {
        expect(policy(profile).profile, profile);
      }
    });
  });

  group('DevicePolicy.apply', () {
    const List<DeliveryDecisionType> calls = <DeliveryDecisionType>[
      DeliveryDecisionType.wide,
      DeliveryDecisionType.noBallHeight,
    ];
    const List<DeliveryDecisionType> reviews = <DeliveryDecisionType>[
      DeliveryDecisionType.edge,
      DeliveryDecisionType.lbw,
      DeliveryDecisionType.wicketHit,
    ];

    test('a high device keeps everything unchanged', () {
      final DevicePolicy high = policy(DeviceProfile.high);
      for (final DeliveryDecisionType type in DeliveryDecisionType.values) {
        for (final DecisionStatus status in DecisionStatus.values) {
          final DeliveryDecision input = decision(type, status);
          expect(high.apply(input), input);
        }
      }
    });

    test('a mid device keeps only auto calls for wide and no-ball', () {
      final DevicePolicy mid = policy(DeviceProfile.mid);
      for (final DeliveryDecisionType type in calls) {
        final DeliveryDecision auto = decision(type, DecisionStatus.autoCall);
        expect(mid.apply(auto), auto);
        expect(mid.apply(decision(type, DecisionStatus.reviewRecommended, confidence: 0.75)), isNull);
        expect(mid.apply(decision(type, DecisionStatus.inconclusive, confidence: 0.3)), isNull);
      }
    });

    test('a mid device passes edge, LBW and wicket-hit reviews through', () {
      final DevicePolicy mid = policy(DeviceProfile.mid);
      for (final DeliveryDecisionType type in reviews) {
        final DeliveryDecision review = decision(type, DecisionStatus.reviewRecommended);
        expect(mid.apply(review), review);
      }
    });

    test('a low device never shows an auto call, only a review', () {
      final DevicePolicy low = policy(DeviceProfile.low);
      for (final DeliveryDecisionType type in calls) {
        final DeliveryDecision? weakened = low.apply(decision(type, DecisionStatus.autoCall));
        expect(weakened, isNotNull);
        expect(weakened!.status, DecisionStatus.reviewRecommended);
        expect(weakened.automatedResult, 'RESULT');
        expect(weakened.confidence, 0.9);

        final DeliveryDecision review = decision(type, DecisionStatus.reviewRecommended, confidence: 0.75);
        expect(low.apply(review), review);
      }
    });

    test('a low device drops edge, LBW and wicket-hit reviews', () {
      final DevicePolicy low = policy(DeviceProfile.low);
      for (final DeliveryDecisionType type in reviews) {
        expect(low.apply(decision(type, DecisionStatus.reviewRecommended)), isNull);
      }
    });

    test('a score-only device drops everything', () {
      final DevicePolicy none = policy(DeviceProfile.scoreOnly);
      for (final DeliveryDecisionType type in DeliveryDecisionType.values) {
        expect(none.apply(decision(type, DecisionStatus.autoCall)), isNull);
        expect(none.apply(decision(type, DecisionStatus.reviewRecommended)), isNull);
      }
    });

    test('a decision is never strengthened', () {
      for (final DeviceProfile profile in DeviceProfile.values) {
        for (final DeliveryDecisionType type in DeliveryDecisionType.values) {
          final DeliveryDecision input = decision(type, DecisionStatus.reviewRecommended, confidence: 0.75);
          final DeliveryDecision? output = policy(profile).apply(input);
          if (output != null) {
            expect(output.status, isNot(DecisionStatus.autoCall));
            expect(output.confidence, input.confidence);
          }
        }
      }
    });
  });

  group('DevicePolicy.live', () {
    test('every phone that can run the tracker gets the same checks', () {
      for (final DeviceProfile profile in <DeviceProfile>[
        DeviceProfile.high,
        DeviceProfile.mid,
        DeviceProfile.low,
      ]) {
        final DevicePolicy live = DevicePolicy.live(profile);

        expect(live.profile, profile);
        expect(live.isUmpiringAvailable, isTrue);
        expect(live.cameraFps, 30, reason: '$profile');
        expect(live.ballDetectorFps, 30);
        expect(live.ballIntervalMs, 33);
        expect(live.modelFrameWidth, 640);
        expect(live.minTrackPointsForReview, 6);
        expect(live.wideNoBall, WideNoBallMode.enabled);
        expect(live.reviewAssist, ReviewAssistMode.review);
        expect(live.replay, ReplayMode.enabled);
        // A speed is allowed, but only the interpreter can give one, and only with an entered distance.
        expect(live.speed, SpeedMode.ifCalibrated);
        expect(live.sceneScan, SceneScanMode.disabled);
        expect(live.opticalFlow, OpticalFlowMode.disabled);
      }
    });

    test('looks for the batter a little less often on weaker phones', () {
      expect(DevicePolicy.live(DeviceProfile.high).poseFps, 6);
      expect(DevicePolicy.live(DeviceProfile.mid).poseFps, 4);
      expect(DevicePolicy.live(DeviceProfile.low).poseFps, 4);
      expect(DevicePolicy.live(DeviceProfile.high).poseIntervalMs, 167);
      expect(DevicePolicy.live(DeviceProfile.low).poseIntervalMs, 250);
    });

    test('a phone with too few cores stays without the assistant', () {
      final DevicePolicy live = DevicePolicy.live(DeviceProfile.scoreOnly);

      expect(live, policy(DeviceProfile.scoreOnly));
      expect(live.isUmpiringAvailable, isFalse);
      expect(live.apply(decision(DeliveryDecisionType.wide, DecisionStatus.autoCall)), isNull);
    });

    test('lets every kind of suggestion through unchanged', () {
      final DevicePolicy live = DevicePolicy.live(DeviceProfile.low);

      for (final DeliveryDecisionType type in DeliveryDecisionType.values) {
        final DeliveryDecision auto = decision(type, DecisionStatus.autoCall);
        final DeliveryDecision review = decision(type, DecisionStatus.reviewRecommended, confidence: 0.7);

        expect(live.apply(auto), auto, reason: '$type');
        expect(live.apply(review), review, reason: '$type');
      }
    });

    test('differs from the policy of the model-based engine', () {
      expect(DevicePolicy.live(DeviceProfile.low), isNot(policy(DeviceProfile.low)));
      expect(DevicePolicy.live(DeviceProfile.high), isNot(policy(DeviceProfile.high)));
    });
  });
}
