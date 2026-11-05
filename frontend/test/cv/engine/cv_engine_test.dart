import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/cv/adapters/mock/mock.dart';
import 'package:gully_umpire/cv/device/device_policy.dart';
import 'package:gully_umpire/cv/engine/cv_engine.dart';
import 'package:gully_umpire/cv/geometry/polygon.dart';
import 'package:gully_umpire/cv/pipelines/pipelines.dart';
import 'package:gully_umpire/cv/rules/umpiring_rules.dart';
import 'package:gully_umpire/cv/scene/scan_readiness.dart';
import 'package:gully_umpire/domain/decisions/decisions.dart';

void main() {
  final DevicePolicy high = DevicePolicy.forProfile(DeviceProfile.high);
  final DevicePolicy scoreOnly = DevicePolicy.forProfile(DeviceProfile.scoreOnly);

  DeliveryContext contextOf(MockScenario scenario) {
    final Polygon? truth = MockWorld(scenario).truthWicketPolygon();
    return DeliveryContext(
      policy: high,
      rules: const UmpiringRuleConfig(),
      batsmanHeightM: scenario.batsmanHeightM,
      wicket: truth == null ? null : WicketTarget(polygon: truth, confidence: 0.95),
    );
  }

  group('ScoreOnlyCvEngine', () {
    test('never suggests anything and skips the scan', () async {
      const ScoreOnlyCvEngine engine = ScoreOnlyCvEngine();

      final SceneScanOutcome outcome = await engine.scanScene(policy: high);

      expect(engine.mode, CvMode.scoreOnly);
      expect(engine.isAvailable, isFalse);
      expect(engine.isSimulated, isFalse);
      expect(outcome.skipped, isTrue);
      expect(outcome.result.foundWicket, isFalse);
      expect(outcome.isMock, isFalse);
    });
  });

  group('LiveCvEngine', () {
    test('is the real engine: available, never a simulation', () {
      const LiveCvEngine engine = LiveCvEngine();

      expect(engine.mode, CvMode.live);
      expect(engine.isAvailable, isTrue);
      expect(engine.isSimulated, isFalse);
    });

    test('has no scene scan of its own: the stumps are marked by hand', () async {
      const LiveCvEngine engine = LiveCvEngine();

      final SceneScanOutcome outcome = await engine.scanScene(policy: high);

      expect(outcome.skipped, isTrue);
      expect(outcome.result.foundWicket, isFalse);
      expect(outcome.isMock, isFalse);
      expect(outcome.modelVersion, 'live-manual');
    });
  });

  group('SimulatedCvEngine', () {
    test('says plainly that it is a simulation', () {
      final SimulatedCvEngine engine = SimulatedCvEngine(framePacing: false);

      expect(engine.mode, CvMode.simulated);
      expect(engine.isAvailable, isTrue);
      expect(engine.isSimulated, isTrue);
    });

    test('a clear simulated scene is found and labelled as a mock', () async {
      final SimulatedCvEngine engine = SimulatedCvEngine(framePacing: false);

      final SceneScanOutcome outcome = await engine.scanScene(policy: high);

      expect(outcome.result.foundWicket, isTrue);
      expect(outcome.result.readiness, ScanReadiness.ready);
      expect(outcome.isMock, isTrue);
      expect(outcome.modelVersion, startsWith('mock-'));
      expect(outcome.skipped, isFalse);
    });

    test('an empty simulated scene asks to reposition', () async {
      final SimulatedCvEngine engine = SimulatedCvEngine(framePacing: false)
        ..configure(wicketKind: MockWicketKind.none);

      final SceneScanOutcome outcome = await engine.scanScene(policy: high);

      expect(outcome.result.foundWicket, isFalse);
      expect(outcome.result.readiness, ScanReadiness.reposition);
    });

    test('a phone set to score only skips the scan', () async {
      final SimulatedCvEngine engine = SimulatedCvEngine(framePacing: false);

      final SceneScanOutcome outcome = await engine.scanScene(policy: scoreOnly);

      expect(outcome.skipped, isTrue);
      expect(outcome.framesScanned, 0);
    });

    test('progress is reported while scanning', () async {
      final SimulatedCvEngine engine = SimulatedCvEngine(framePacing: false);
      int updates = 0;

      final SceneScanOutcome outcome =
          await engine.scanScene(policy: high, onProgress: (_) => updates++);

      expect(updates, outcome.framesScanned);
      expect(updates, greaterThan(0));
    });

    test('a cancelled scan stops and says so', () async {
      final SimulatedCvEngine engine = SimulatedCvEngine(framePacing: false);
      final CancellationFlag cancel = CancellationFlag()..cancel();

      final SceneScanOutcome outcome = await engine.scanScene(policy: high, cancel: cancel);

      expect(outcome.wasCancelled, isTrue);
    });

    test('a simulated wide is called wide and a straight ball is not', () async {
      final SimulatedCvEngine engine = SimulatedCvEngine(framePacing: false);
      const MockScenario base = MockScenario();

      final DeliveryAnalysis wide = await engine.simulateDelivery(
        kind: MockDeliveryKind.wide,
        context: contextOf(base),
      );
      final DeliveryAnalysis straight = await engine.simulateDelivery(
        kind: MockDeliveryKind.straightHit,
        context: contextOf(base),
      );

      DeliveryDecision wideCall(DeliveryAnalysis a) => a.decisions
          .firstWhere((DeliveryDecision d) => d.type == DeliveryDecisionType.wide);
      expect(wideCall(wide).automatedResult, 'WIDE');
      expect(wideCall(straight).automatedResult, 'NOT_WIDE');
      expect(wide.isMock, isTrue);
      expect(wide.modelVersion, startsWith('mock-'));
    });

    test('the simulated batter is as tall as the context says', () async {
      final SimulatedCvEngine engine = SimulatedCvEngine(framePacing: false);
      const MockScenario tall = MockScenario(batsmanHeightM: 1.95);

      final DeliveryAnalysis analysis = await engine.simulateDelivery(
        kind: MockDeliveryKind.straightHit,
        context: contextOf(tall),
      );

      final DeliveryDecision wide = analysis.decisions.firstWhere(
        (DeliveryDecision d) => d.type == DeliveryDecisionType.wide,
      );
      // The reach is the batter's height times the rule's reach multiplier (0.60 by default).
      expect(wide.evidence['reach_m'], closeTo(1.95 * 0.60, 1e-9));
    });

    test('each simulated delivery uses a different noise seed but stays reproducible', () async {
      final SimulatedCvEngine first = SimulatedCvEngine(framePacing: false);
      final SimulatedCvEngine second = SimulatedCvEngine(framePacing: false);
      const MockScenario base = MockScenario();

      final DeliveryAnalysis a1 = await first.simulateDelivery(
        kind: MockDeliveryKind.wide,
        context: contextOf(base),
      );
      final DeliveryAnalysis b1 = await second.simulateDelivery(
        kind: MockDeliveryKind.wide,
        context: contextOf(base),
      );

      expect(a1.trajectory, b1.trajectory);
    });
  });
}
