import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/cv/geometry/point3d.dart';
import 'package:gully_umpire/cv/rules/decision_factory.dart';
import 'package:gully_umpire/cv/rules/edge_review.dart';
import 'package:gully_umpire/cv/rules/lbw_review.dart';
import 'package:gully_umpire/cv/rules/umpiring_rules.dart';
import 'package:gully_umpire/cv/rules/wicket_hit_review.dart';
import 'package:gully_umpire/domain/decisions/decisions.dart';

WideAssessment wideAssessment({
  double lateral = 1.89,
  bool moved = false,
  double wicketConfidence = 0.9,
  double trajectoryConfidence = 0.9,
}) {
  return assessWide(
    ballAtBatsmanPlane: Point3D(lateral, 0.5, 0),
    batsmanCenter: const Point3D(0, 0, 0),
    batsmanHeightM: 1.7,
    lateralReachMultiplier: 0.6,
    batsmanMovedTowardBall: moved,
    wicketConfidence: wicketConfidence,
    trajectoryConfidence: trajectoryConfidence,
  );
}

HeightNoBallAssessment heightAssessment(
  double height, {
  bool bounced = false,
  double measurement = 0.9,
}) {
  return assessHeightNoBall(
    ballHeightM: height,
    batsmanHeightM: 1.7,
    bounced: bounced,
    rules: const HeightRuleConfig(),
    measurementConfidence: measurement,
  );
}

void main() {
  group('assessWide', () {
    test('a clear wide is confident', () {
      final WideAssessment a = wideAssessment();
      expect(a.result, WideResult.wide);
      expect(a.reachM, closeTo(1.02, 1e-12));
      expect(a.distanceM, closeTo(1.89, 1e-12));
      expect(a.confidence, closeTo(0.9, 1e-12));
    });

    test('a ball near the limit is hard to call', () {
      // margin = (1.1 - 1.02) / (1.02 * 0.5), confidence = 0.9 * (0.5 + 0.5 * margin)
      final WideAssessment a = wideAssessment(lateral: 1.1);
      expect(a.result, WideResult.wide);
      expect(a.confidence, closeTo(0.9 * (0.5 + 0.5 * (0.08 / 0.51)), 1e-9));
    });

    test('the confidence is never above the weaker measurement', () {
      final WideAssessment a = wideAssessment(wicketConfidence: 0.8);
      expect(a.confidence, lessThanOrEqualTo(0.8));
    });

    test('a doubtful wicket gives a low confidence "not sure"', () {
      final WideAssessment a = wideAssessment(wicketConfidence: 0.5);
      expect(a.result, WideResult.inconclusive);
      expect(a.confidence, closeTo(0.25, 1e-12));
    });

    test('a batter who moved towards the ball is a not-wide with 90% of the base confidence', () {
      final WideAssessment a = wideAssessment(moved: true);
      expect(a.result, WideResult.notWide);
      expect(a.confidence, closeTo(0.81, 1e-12));
    });
  });

  group('assessHeightNoBall', () {
    test('a high full toss is a confident no-ball', () {
      final HeightNoBallAssessment a = heightAssessment(1.35);
      expect(a.result, HeightNoBallResult.noBall);
      expect(a.waistM, closeTo(0.935, 1e-12));
      expect(a.confidence, closeTo(0.9, 1e-12));
    });

    test('a ball near the waist limit is less certain', () {
      final HeightNoBallAssessment a = heightAssessment(0.95);
      // nearest limit 0.935 is 0.015 away; margin = 0.015 / 0.17.
      expect(a.confidence, closeTo(0.9 * (0.5 + 0.5 * (0.015 / 0.17)), 1e-9));
    });

    test('the measurement confidence is the upper bound', () {
      expect(heightAssessment(1.35, measurement: 0.6).confidence, closeTo(0.6, 1e-12));
    });
  });

  group('DecisionFactory', () {
    test('a confident wide is an auto call with evidence', () {
      final DeliveryDecision decision = DecisionFactory.wide(wideAssessment());
      expect(decision.type, DeliveryDecisionType.wide);
      expect(decision.automatedResult, 'WIDE');
      expect(decision.status, DecisionStatus.autoCall);
      expect(decision.summary, startsWith('Wide:'));
      expect(decision.evidence['distance_m'], closeTo(1.89, 1e-12));
      expect(decision.evidence['reach_m'], closeTo(1.02, 1e-12));
    });

    test('a wide near the limit is only "not sure"', () {
      final DeliveryDecision decision = DecisionFactory.wide(wideAssessment(lateral: 1.1));
      expect(decision.automatedResult, 'WIDE');
      expect(decision.status, DecisionStatus.inconclusive);
    });

    test('an inconclusive wide says so', () {
      final DeliveryDecision decision =
          DecisionFactory.wide(wideAssessment(wicketConfidence: 0.5));
      expect(decision.automatedResult, 'INCONCLUSIVE');
      expect(decision.status, DecisionStatus.inconclusive);
      expect(decision.summary, startsWith('Wide: not sure'));
    });

    test('a batter moving towards the ball is explained', () {
      final DeliveryDecision decision = DecisionFactory.wide(wideAssessment(moved: true));
      expect(decision.automatedResult, 'NOT_WIDE');
      expect(decision.status, DecisionStatus.reviewRecommended);
      expect(decision.summary, contains('moved towards the ball'));
    });

    test('a height no-ball is an auto call when sure', () {
      final DeliveryDecision decision = DecisionFactory.heightNoBall(heightAssessment(1.35));
      expect(decision.type, DeliveryDecisionType.noBallHeight);
      expect(decision.automatedResult, 'NO_BALL');
      expect(decision.status, DecisionStatus.autoCall);
      expect(decision.summary, contains('full toss'));
      expect(decision.evidence['bounced'], isFalse);
    });

    test('the summary of a bounced legal ball mentions the bounce', () {
      final DeliveryDecision decision =
          DecisionFactory.heightNoBall(heightAssessment(1.0, bounced: true));
      expect(decision.automatedResult, 'LEGAL');
      expect(decision.summary, contains('after a bounce'));
    });

    test('inconclusive helper', () {
      final DeliveryDecision decision =
          DecisionFactory.inconclusive(DeliveryDecisionType.noBallHeight, 'Ball lost.');
      expect(decision.automatedResult, 'INCONCLUSIVE');
      expect(decision.confidence, 0);
      expect(decision.status, DecisionStatus.inconclusive);
      expect(decision.evidence['reason'], 'Ball lost.');
      expect(decision.summary, contains('Ball lost.'));
    });

    test('edge, LBW and wicket-hit results are never auto calls', () {
      final DeliveryDecision edge = DecisionFactory.edge(
        const EdgeAssessment(
          result: EdgeResult.edgeLikely,
          confidence: 0.95,
          visualScore: 1,
          audioScore: 0.8,
          audioAvailable: true,
          suspectedContactTimestampMs: 1000,
        ),
      );
      expect(edge.type, DeliveryDecisionType.edge);
      expect(edge.status, DecisionStatus.reviewRecommended);

      final DeliveryDecision lbw = DecisionFactory.lbw(
        const LbwAssessment(result: LbwResult.likelyHitting, confidence: 0.75),
      );
      expect(lbw.type, DeliveryDecisionType.lbw);
      expect(lbw.status, DecisionStatus.reviewRecommended);

      final DeliveryDecision hit = DecisionFactory.wicketHit(
        const WicketHitAssessment(result: WicketHitResult.likelyHit, confidence: 0.8),
      );
      expect(hit.type, DeliveryDecisionType.wicketHit);
      expect(hit.status, DecisionStatus.reviewRecommended);
    });

    test('weak review results are "not sure"', () {
      final DeliveryDecision lbw = DecisionFactory.lbw(
        const LbwAssessment(result: LbwResult.likelyMissing, confidence: 0.4),
      );
      expect(lbw.status, DecisionStatus.inconclusive);
      final DeliveryDecision mixed = DecisionFactory.lbw(
        const LbwAssessment(result: LbwResult.reviewRecommended, confidence: 0.4),
      );
      expect(mixed.status, DecisionStatus.reviewRecommended);
      final DeliveryDecision none = DecisionFactory.edge(
        const EdgeAssessment.inconclusive('Too few points.'),
      );
      expect(none.status, DecisionStatus.inconclusive);
      expect(none.summary, contains('Too few points.'));
    });
  });
}
