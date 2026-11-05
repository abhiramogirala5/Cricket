import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/cv/device/device_policy.dart';
import 'package:gully_umpire/cv/pipelines/ball_observation.dart';
import 'package:gully_umpire/cv/pipelines/delivery_context.dart';
import 'package:gully_umpire/cv/pipelines/delivery_geometry.dart';
import 'package:gully_umpire/cv/pipelines/delivery_interpreter.dart';
import 'package:gully_umpire/cv/pipelines/delivery_pipeline_config.dart';
import 'package:gully_umpire/cv/rules/decision_factory.dart';
import 'package:gully_umpire/cv/rules/umpiring_rules.dart';
import 'package:gully_umpire/cv/scene/scan_readiness.dart';
import 'package:gully_umpire/cv/util/length_units.dart';
import 'package:gully_umpire/domain/decisions/decision_status.dart';
import 'package:gully_umpire/domain/decisions/delivery_decision.dart';
import 'package:gully_umpire/domain/decisions/delivery_decision_type.dart';

import '../../support/flight_fixtures.dart';

// The flights come from test/support/flight_fixtures.dart. Their numbers were worked out by hand:
// the batter is 1.7 m tall and 0.6 of the picture high, so one picture height is 2.83 m at the
// batter; a ball 7.2 cm wide looks 0.0254 of the picture height wide there.

DeliveryContext contextWithWicket() {
  return DeliveryContext(
    policy: DevicePolicy.live(DeviceProfile.high),
    rules: const UmpiringRuleConfig(),
    batsmanHeightM: batterHeightM,
    wicket: WicketTarget(polygon: wicketOutline(), confidence: 0.9),
  );
}

Future<DeliveryAnalysis> interpret(
  List<BallObservation> observations, {
  DeliveryPipelineConfig? config,
}) {
  return interpretDelivery(
    observations: observations,
    detectorRunTimes: timesOf(observations),
    poses: standingBatter(),
    aspectRatio: 0.5625,
    context: contextWithWicket(),
    modelVersion: 'test-1',
    isMock: false,
    framesProcessed: 50,
    config: config ?? DeliveryPipelineConfig.live(ballDiameterM: ballDiameterM),
  );
}

DeliveryDecision decisionOf(DeliveryAnalysis analysis, DeliveryDecisionType type) {
  return analysis.decisions.singleWhere((DeliveryDecision d) => d.type == type);
}

void main() {
  group('DeliveryPipelineConfig.live', () {
    test('trusts the height of the ball to about 0.3 m and looks at the start of the track', () {
      final DeliveryPipelineConfig live = DeliveryPipelineConfig.live();

      expect(live.heightUncertaintyM, 0.30);
      expect(live.geometry.minBounceViewRatio, 2.2);
      expect(live.ballDiameterM, 0.072);
    });

    test('takes the real size of the ball', () {
      expect(DeliveryPipelineConfig.live(ballDiameterM: 0.067).ballDiameterM, 0.067);
    });

    test('the older settings neither limit the height nor look at the start of the track', () {
      const DeliveryPipelineConfig older = DeliveryPipelineConfig();

      expect(older.heightUncertaintyM, isNull);
      expect(older.geometry.minBounceViewRatio, 0);
    });
  });

  group('assessHeightNoBall with a stated uncertainty', () {
    HeightNoBallAssessment assess({double? uncertaintyM, double height = 1.0, bool bounced = false}) {
      return assessHeightNoBall(
        ballHeightM: height,
        batsmanHeightM: 1.7,
        bounced: bounced,
        rules: const HeightRuleConfig(),
        measurementConfidence: 1.0,
        uncertaintyM: uncertaintyM,
      );
    }

    test('a height close to a limit is a coin toss, sooner when the height is less certain', () {
      // A full toss at 1.0 m is 0.065 m above the waist (0.935 m).
      final HeightNoBallAssessment older = assess();
      final HeightNoBallAssessment live = assess(uncertaintyM: 0.30);

      expect(older.result, HeightNoBallResult.noBall);
      expect(live.result, HeightNoBallResult.noBall);
      // Older scale: a tenth of the batter's height (0.17 m): 0.5 + 0.5 * 0.065 / 0.17.
      expect(older.confidence, closeTo(0.6912, 0.001));
      // Stated scale 0.30 m: 0.5 + 0.5 * 0.065 / 0.30.
      expect(live.confidence, closeTo(0.6083, 0.001));
    });

    test('a height far from every limit keeps the full confidence', () {
      final HeightNoBallAssessment live = assess(uncertaintyM: 0.30, height: 0.3);

      expect(live.result, HeightNoBallResult.legal);
      expect(live.confidence, closeTo(1.0, 1e-9));
    });

    test('an uncertainty of zero or less falls back to the older scale', () {
      expect(assess(uncertaintyM: 0).confidence, closeTo(assess().confidence, 1e-12));
      expect(assess(uncertaintyM: -1).confidence, closeTo(assess().confidence, 1e-12));
    });
  });

  group('interpretDelivery with the live settings', () {
    test('a ball that bounced and rose to about 0.9 m is a legal height, called with confidence', () async {
      final DeliveryAnalysis analysis = await interpret(flight());

      expect(analysis.arrivalMs, closeTo(flightArrivalMs, 2));
      expect(analysis.bounced, isTrue);
      expect(analysis.bounceMs, 697);
      expect(analysis.ballHeightM, closeTo(0.906, 0.01));
      expect(analysis.ballLateralM, closeTo(0, 1e-6));
      expect(analysis.plane, isNotNull);
      expect(analysis.isMock, isFalse);
      expect(analysis.modelVersion, 'test-1');
      final DeliveryDecision height = decisionOf(analysis, DeliveryDecisionType.noBallHeight);
      expect(height.automatedResult, 'LEGAL');
      expect(height.confidence, closeTo(0.9, 1e-6));
      expect(height.status, DecisionStatus.autoCall);
      final DeliveryDecision wide = decisionOf(analysis, DeliveryDecisionType.wide);
      expect(wide.automatedResult, 'NOT_WIDE');
      expect(wide.status, DecisionStatus.autoCall);
    });

    test('a full toss seen from the start is a no-ball, but close to the waist so not a sure one', () async {
      final DeliveryAnalysis analysis = await interpret(flight(startMs: 200, bounce: false));

      expect(analysis.bounced, isFalse);
      expect(analysis.ballHeightM, closeTo(0.9917, 0.01));
      final DeliveryDecision height = decisionOf(analysis, DeliveryDecisionType.noBallHeight);
      expect(height.automatedResult, 'NO_BALL');
      // 0.9 * (0.5 + 0.5 * 0.0567 / 0.30)
      expect(height.confidence, closeTo(0.535, 0.02));
      expect(height.status, DecisionStatus.inconclusive);
    });

    test('with the older settings the same flight is called with more confidence', () async {
      final DeliveryAnalysis live = await interpret(flight(startMs: 200, bounce: false));
      final DeliveryAnalysis older = await interpret(
        flight(startMs: 200, bounce: false),
        config: const DeliveryPipelineConfig(ballDiameterM: ballDiameterM),
      );

      final double liveConfidence = decisionOf(live, DeliveryDecisionType.noBallHeight).confidence;
      final double olderConfidence = decisionOf(older, DeliveryDecisionType.noBallHeight).confidence;

      // 0.9 * (0.5 + 0.5 * 0.0567 / 0.17)
      expect(olderConfidence, closeTo(0.6, 0.02));
      expect(liveConfidence, lessThan(olderConfidence));
    });

    test('a ball first seen too far down the pitch cannot be called a full toss', () async {
      // The track begins at 400 ms, when the ball looks only twice as big as at the batter: a
      // bounce could have happened before that.
      final DeliveryAnalysis analysis = await interpret(flight(bounce: false));

      expect(analysis.bounced, isNull);
      expect(analysis.bounceMs, isNull);
      final DeliveryDecision height = decisionOf(analysis, DeliveryDecisionType.noBallHeight);
      expect(height.automatedResult, 'INCONCLUSIVE');
      expect(height.status, DecisionStatus.inconclusive);
      expect(height.evidence['reason'], contains('first seen too far down the pitch'));
      expect(analysis.notes, contains(height.evidence['reason']));
      // The wide check does not depend on a bounce.
      expect(decisionOf(analysis, DeliveryDecisionType.wide).automatedResult, 'NOT_WIDE');
    });

    test('the older settings would have called that same flight a full toss', () async {
      final DeliveryAnalysis analysis = await interpret(
        flight(bounce: false),
        config: const DeliveryPipelineConfig(ballDiameterM: ballDiameterM),
      );

      expect(analysis.bounced, isFalse);
      expect(decisionOf(analysis, DeliveryDecisionType.noBallHeight).automatedResult, 'NO_BALL');
    });

    test('the check of the start of the track can be tuned', () async {
      const DeliveryPipelineConfig strict = DeliveryPipelineConfig(
        ballDiameterM: ballDiameterM,
        geometry: DeliveryGeometryConfig(minBounceViewRatio: 3.0),
      );
      const DeliveryPipelineConfig lenient = DeliveryPipelineConfig(
        ballDiameterM: ballDiameterM,
        geometry: DeliveryGeometryConfig(minBounceViewRatio: 1.5),
      );

      // Seen from 200 ms the ball first looks 2.9 times as big as at the batter.
      final List<BallObservation> early = flight(startMs: 200, bounce: false);
      final DeliveryAnalysis withStrict = await interpret(early, config: strict);
      final DeliveryAnalysis withLenient = await interpret(early, config: lenient);

      expect(decisionOf(withStrict, DeliveryDecisionType.noBallHeight).automatedResult, 'INCONCLUSIVE');
      expect(decisionOf(withLenient, DeliveryDecisionType.noBallHeight).automatedResult, 'NO_BALL');
    });

    test('a bounce that was seen is never doubted because the track started late', () async {
      final DeliveryAnalysis analysis = await interpret(flight());

      expect(analysis.bounced, isTrue);
      expect(decisionOf(analysis, DeliveryDecisionType.noBallHeight).automatedResult, 'LEGAL');
    });
  });

  group('interpretDelivery says why a review check was not made', () {
    Future<DeliveryAnalysis> interpretWithReviews(
      List<BallObservation> observations, {
      bool reviews = true,
      bool stumpsTrusted = true,
    }) {
      final double wicketConfidence = stumpsTrusted ? 0.9 : 0.6;
      return interpretDelivery(
        observations: observations,
        detectorRunTimes: timesOf(observations),
        poses: standingBatter(),
        aspectRatio: 0.5625,
        context: DeliveryContext(
          policy: DevicePolicy.live(DeviceProfile.high),
          rules: UmpiringRuleConfig(edgeReviewEnabled: reviews, lbwReviewEnabled: reviews),
          batsmanHeightM: batterHeightM,
          wicket: WicketTarget(polygon: wicketOutline(), confidence: wicketConfidence),
          readiness: ScanReadiness.fromConfidence(wicketConfidence),
        ),
        modelVersion: 'test-1',
        isMock: false,
        framesProcessed: 50,
        config: DeliveryPipelineConfig.live(ballDiameterM: ballDiameterM),
      );
    }

    bool hasNote(DeliveryAnalysis analysis, String part) {
      return analysis.notes.any((String note) => note.contains(part));
    }

    test('a path with no sudden change near the batter gets no edge or LBW, and the notes say so', () async {
      // The flight is a smooth path after the bounce, so there is nothing that looks like a contact.
      final DeliveryAnalysis analysis = await interpretWithReviews(flight());

      final Iterable<DeliveryDecisionType> types =
          analysis.decisions.map((DeliveryDecision d) => d.type);
      expect(types, isNot(contains(DeliveryDecisionType.edge)));
      expect(types, isNot(contains(DeliveryDecisionType.lbw)));
      expect(hasNote(analysis, 'No sudden change in the ball'), isTrue);
      expect(hasNote(analysis, 'not a verdict'), isTrue);
    });

    test('says nothing about edge or LBW when those checks are switched off', () async {
      final DeliveryAnalysis analysis = await interpretWithReviews(flight(), reviews: false);

      expect(hasNote(analysis, 'No sudden change in the ball'), isFalse);
    });

    test('says when the stumps cannot be trusted for the LBW and stumps checks', () async {
      final DeliveryAnalysis analysis = await interpretWithReviews(flight(), stumpsTrusted: false);

      expect(hasNote(analysis, 'stumps cannot be trusted'), isTrue);
    });

    test('has no such note when the stumps are trusted', () async {
      final DeliveryAnalysis analysis = await interpretWithReviews(flight());

      expect(hasNote(analysis, 'stumps cannot be trusted'), isFalse);
    });
  });

  group('interpretDelivery measures the ball speed from the entered distance', () {
    Future<DeliveryAnalysis> interpretAt(List<BallObservation> observations, {double? distanceM}) {
      return interpretDelivery(
        observations: observations,
        detectorRunTimes: timesOf(observations),
        poses: standingBatter(),
        aspectRatio: 0.5625,
        context: DeliveryContext(
          policy: DevicePolicy.live(DeviceProfile.high),
          rules: const UmpiringRuleConfig(),
          batsmanHeightM: batterHeightM,
          wicket: WicketTarget(polygon: wicketOutline(), confidence: 0.9),
          cameraToBatterM: distanceM,
        ),
        modelVersion: 'test-1',
        isMock: false,
        framesProcessed: 50,
        config: DeliveryPipelineConfig.live(ballDiameterM: ballDiameterM),
      );
    }

    bool hasNote(DeliveryAnalysis analysis, String part) {
      return analysis.notes.any((String note) => note.contains(part));
    }

    test('works the speed out of the size of the ball and the 40 feet that were entered', () async {
      // In the fixture 1 / diameter grows by 32 per second before the bounce, so the ball moves
      // 32 * planeDiameter * distance = 9.91 m/s away from the camera, and falls in the picture at
      // 1.90 m/s: sqrt(9.91^2 + 1.90^2) = 10.09 m/s = 36.3 km/h.
      final DeliveryAnalysis analysis = await interpretAt(flight(), distanceM: feetToMetres(40));

      expect(analysis.speed, isNotNull);
      expect(analysis.speed!.kmph, closeTo(36.34, 0.1));
      // The points lie exactly on a line, so what is left is what the entered distance and the
      // batter's height can be out by: 5.7% of the speed.
      expect(analysis.speed!.uncertaintyKmph! / analysis.speed!.kmph, closeTo(0.0566, 0.002));
      expect(analysis.speed!.confidence, lessThanOrEqualTo(0.75));
      expect(hasNote(analysis, 'No ball speed'), isFalse);
    });

    test('a longer distance means a faster ball (the batter looks the same size, so he is further)', () async {
      final DeliveryAnalysis near = await interpretAt(flight(), distanceM: feetToMetres(40));
      final DeliveryAnalysis far = await interpretAt(flight(), distanceM: feetToMetres(60));

      expect(far.speed!.kmph, greaterThan(near.speed!.kmph));
    });

    test('shows no speed, and says why, when no distance was entered', () async {
      final DeliveryAnalysis analysis = await interpretAt(flight());

      expect(analysis.speed, isNull);
      expect(hasNote(analysis, 'No ball speed: enter how far the phone is from the batter'), isTrue);
    });

    test('shows no speed, and says why, when the entered distance cannot be right', () async {
      final DeliveryAnalysis analysis = await interpretAt(flight(), distanceM: 0.5);

      expect(analysis.speed, isNull);
      expect(hasNote(analysis, 'could not be measured well enough'), isTrue);
    });

    test('shows no speed when it is not known whether the ball bounced', () async {
      // First seen too far down the pitch: "no bounce" cannot be said, so neither can a speed.
      final DeliveryAnalysis analysis =
          await interpretAt(flight(bounce: false), distanceM: feetToMetres(40));

      expect(analysis.bounced, isNull);
      expect(analysis.speed, isNull);
    });

    test('a phone that does not measure speeds shows none and says nothing about it', () async {
      final DeliveryAnalysis analysis = await interpretDelivery(
        observations: flight(),
        detectorRunTimes: timesOf(flight()),
        poses: standingBatter(),
        aspectRatio: 0.5625,
        context: DeliveryContext(
          policy: DevicePolicy.forProfile(DeviceProfile.low),
          rules: const UmpiringRuleConfig(),
          batsmanHeightM: batterHeightM,
          wicket: WicketTarget(polygon: wicketOutline(), confidence: 0.9),
          cameraToBatterM: feetToMetres(40),
        ),
        modelVersion: 'test-1',
        isMock: false,
        framesProcessed: 50,
        config: DeliveryPipelineConfig.live(ballDiameterM: ballDiameterM),
      );

      expect(analysis.speed, isNull);
      expect(hasNote(analysis, 'ball speed'), isFalse);
    });
  });

  group('interpretDelivery keeps the time of a sudden change of path', () {
    // The smooth flight, but knocked sideways after 994 ms (a picture or two before the ball
    // reaches the batter at 1000 ms).
    List<BallObservation> knockedSideways() {
      return <BallObservation>[
        for (final BallObservation o in flight())
          BallObservation(
            timestampMs: o.timestampMs,
            x: o.timestampMs > 994 ? 0.5 + 1.2 * (o.timestampMs - 994) / 1000 : o.x,
            y: o.y,
            confidence: o.confidence,
            diameter: o.diameter,
          ),
      ];
    }

    Future<DeliveryAnalysis> interpretWith(List<BallObservation> observations, {bool reviews = true}) {
      return interpretDelivery(
        observations: observations,
        detectorRunTimes: timesOf(observations),
        poses: standingBatter(),
        aspectRatio: 0.5625,
        context: DeliveryContext(
          policy: DevicePolicy.live(DeviceProfile.high),
          rules: UmpiringRuleConfig(edgeReviewEnabled: reviews, lbwReviewEnabled: reviews),
          batsmanHeightM: batterHeightM,
          wicket: WicketTarget(polygon: wicketOutline(), confidence: 0.9),
        ),
        modelVersion: 'test-1',
        isMock: false,
        framesProcessed: 50,
        config: DeliveryPipelineConfig.live(ballDiameterM: ballDiameterM),
      );
    }

    test('gives the moment the path changed', () async {
      final DeliveryAnalysis analysis = await interpretWith(knockedSideways());

      expect(analysis.contactMs, 994);
    });

    test('gives none for a smooth path', () async {
      final DeliveryAnalysis analysis = await interpretWith(flight());

      expect(analysis.contactMs, isNull);
    });

    test('is not looked for when the edge and LBW aids are off', () async {
      final DeliveryAnalysis analysis = await interpretWith(knockedSideways(), reviews: false);

      expect(analysis.contactMs, isNull);
    });
  });
}
