import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/cv/geometry/point3d.dart';
import 'package:gully_umpire/cv/rules/umpiring_rules.dart';

WideResult classifyWideCase({
  double lateral = 0,
  double centre = 0,
  bool moved = false,
  double wicketConfidence = 0.9,
  double trajectoryConfidence = 0.9,
  double multiplier = 0.6,
}) {
  return UmpiringRules.classifyWide(
    ballAtBatsmanPlane: Point3D(lateral, 0.5, 0),
    batsmanCenter: Point3D(centre, 0, 0),
    batsmanHeightM: 1.7,
    lateralReachMultiplier: multiplier,
    batsmanMovedTowardBall: moved,
    wicketConfidence: wicketConfidence,
    trajectoryConfidence: trajectoryConfidence,
  );
}

HeightNoBallResult classifyHeightCase(
  double ballHeight, {
  bool bounced = false,
  HeightRuleConfig rules = const HeightRuleConfig(),
}) {
  return UmpiringRules.classifyHeightNoBall(
    ballHeightM: ballHeight,
    batsmanHeightM: 1.7,
    bounced: bounced,
    rules: rules,
  );
}

void main() {
  group('classifyWide (batter 1.70 m, reach 0.60 => 1.02 m)', () {
    test('a ball well outside the reach is a wide, on either side', () {
      expect(classifyWideCase(lateral: 1.5), WideResult.wide);
      expect(classifyWideCase(lateral: -1.5), WideResult.wide);
    });

    test('a ball within the reach is not a wide', () {
      expect(classifyWideCase(lateral: 0.5), WideResult.notWide);
      expect(classifyWideCase(lateral: -0.5), WideResult.notWide);
    });

    test('exactly on the limit is not a wide', () {
      expect(classifyWideCase(lateral: 1.02), WideResult.notWide);
      expect(classifyWideCase(lateral: 1.021), WideResult.wide);
    });

    test('the distance is measured from the batter, not from the middle of the picture', () {
      expect(classifyWideCase(lateral: 2.0, centre: 1.0), WideResult.notWide);
      expect(classifyWideCase(lateral: 2.1, centre: 1.0), WideResult.wide);
    });

    test('a batter who moved towards the ball cannot be given a wide', () {
      expect(classifyWideCase(lateral: 1.5, moved: true), WideResult.notWide);
    });

    test('a larger reach multiplier is more generous', () {
      expect(classifyWideCase(lateral: 1.1, multiplier: 0.7), WideResult.notWide);
      expect(classifyWideCase(lateral: 1.1, multiplier: 0.6), WideResult.wide);
    });

    test('a doubtful wicket or track is not sure', () {
      expect(classifyWideCase(lateral: 1.5, wicketConfidence: 0.69), WideResult.inconclusive);
      expect(classifyWideCase(lateral: 1.5, trajectoryConfidence: 0.69), WideResult.inconclusive);
      expect(classifyWideCase(lateral: 1.5, wicketConfidence: 0.70), WideResult.wide);
      expect(classifyWideCase(lateral: 1.5, moved: true, wicketConfidence: 0.5), WideResult.inconclusive);
    });

    test('wire values', () {
      expect(WideResult.wide.wire, 'WIDE');
      expect(WideResult.notWide.wire, 'NOT_WIDE');
      expect(WideResult.inconclusive.wire, 'INCONCLUSIVE');
    });
  });

  group('classifyHeightNoBall (batter 1.70 m: waist 0.935, shoulder 1.394)', () {
    test('a full toss above the waist is a no-ball', () {
      expect(classifyHeightCase(1.0), HeightNoBallResult.noBall);
      expect(classifyHeightCase(0.9), HeightNoBallResult.legal);
      expect(classifyHeightCase(0.935), HeightNoBallResult.legal);
    });

    test('a bounced ball is legal below head height unless the shoulder rule is on', () {
      expect(classifyHeightCase(1.5, bounced: true), HeightNoBallResult.legal);
      const HeightRuleConfig strict = HeightRuleConfig(bouncedAboveShoulderIsNoBall: true);
      expect(classifyHeightCase(1.5, bounced: true, rules: strict), HeightNoBallResult.noBall);
      expect(classifyHeightCase(1.3, bounced: true, rules: strict), HeightNoBallResult.legal);
    });

    test('above the head is a no-ball unless that rule is off', () {
      expect(classifyHeightCase(1.8, bounced: true), HeightNoBallResult.noBall);
      const HeightRuleConfig lenient = HeightRuleConfig(aboveHeadIsNoBall: false);
      expect(classifyHeightCase(1.8, bounced: true, rules: lenient), HeightNoBallResult.legal);
    });

    test('the full toss rule can be switched off', () {
      const HeightRuleConfig noWaistRule = HeightRuleConfig(fullTossAboveWaistIsNoBall: false);
      expect(classifyHeightCase(1.2, rules: noWaistRule), HeightNoBallResult.legal);
      expect(classifyHeightCase(1.8, rules: noWaistRule), HeightNoBallResult.noBall);
    });

    test('wire values', () {
      expect(HeightNoBallResult.noBall.wire, 'NO_BALL');
      expect(HeightNoBallResult.legal.wire, 'LEGAL');
    });
  });

  group('UmpiringRuleConfig', () {
    test('defaults: wides, no-balls and wicket hits on; edge and LBW off', () {
      const UmpiringRuleConfig config = UmpiringRuleConfig();
      expect(config.wideEnabled, isTrue);
      expect(config.noBallEnabled, isTrue);
      expect(config.wicketHitEnabled, isTrue);
      expect(config.edgeReviewEnabled, isFalse);
      expect(config.lbwReviewEnabled, isFalse);
      expect(config.lateralReachMultiplier, 0.60);
      expect(config.height.fullTossAboveWaistIsNoBall, isTrue);
      expect(config.height.bouncedAboveShoulderIsNoBall, isFalse);
    });

    test('is comparable by value', () {
      expect(const UmpiringRuleConfig(), const UmpiringRuleConfig());
      expect(const UmpiringRuleConfig(edgeReviewEnabled: true), isNot(const UmpiringRuleConfig()));
    });
  });
}
