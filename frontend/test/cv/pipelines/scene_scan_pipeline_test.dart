import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/cv/adapters/mock/mock.dart';
import 'package:gully_umpire/cv/contracts/camera_frame_input.dart';
import 'package:gully_umpire/cv/device/device_policy.dart';
import 'package:gully_umpire/cv/pipelines/delivery_context.dart';
import 'package:gully_umpire/cv/pipelines/scene_scan_pipeline.dart';
import 'package:gully_umpire/cv/scene/scan_readiness.dart';
import 'package:gully_umpire/cv/scene/wicket_scanner.dart';
import 'package:gully_umpire/domain/decisions/wicket_family.dart';

Stream<CameraFrameInput> camera({int fps = 30, int endMs = 5000}) =>
    MockCamera.frames(fps: fps, startMs: 0, endMs: endMs);

SceneScanPipeline pipelineFor(MockScenario scenario) =>
    SceneScanPipeline(detector: MockSceneObjectDetector(scenario));

void main() {
  group('SceneScanPipeline', () {
    test('a clear scene is found and the scan stops early at 12 frames', () async {
      for (int seed = 1; seed <= 3; seed++) {
        final SceneScanOutcome outcome = await pipelineFor(MockScenario(seed: seed)).scan(frames: camera());
        expect(outcome.result.foundWicket, isTrue, reason: 'seed $seed');
        expect(outcome.result.best!.family, WicketFamily.traditionalStumps, reason: 'seed $seed');
        expect(outcome.result.readiness, ScanReadiness.ready, reason: 'seed $seed');
        expect(outcome.framesScanned, 12, reason: 'seed $seed');
        expect(outcome.wasCancelled, isFalse);
        expect(outcome.skipped, isFalse);
      }
    });

    test('is labelled as a mock', () async {
      final SceneScanOutcome outcome = await pipelineFor(const MockScenario()).scan(frames: camera());
      expect(outcome.isMock, isTrue);
      expect(outcome.modelVersion, 'mock-scene-1.0');
    });

    test('finds the batter as the largest person', () async {
      final SceneScanOutcome outcome = await pipelineFor(const MockScenario()).scan(frames: camera());
      expect(outcome.result.batsmanBox, isNotNull);
      expect(outcome.result.batsmanBox!.centerX, closeTo(0.5, 0.02));
    });

    test('a noisy scene is scanned to the frame limit and found with moderate confidence', () async {
      for (int seed = 1; seed <= 3; seed++) {
        final SceneScanOutcome outcome = await pipelineFor(
          MockScenario(seed: seed, scanQuality: MockScanQuality.moderate),
        ).scan(frames: camera());
        expect(outcome.framesScanned, 30, reason: 'seed $seed');
        expect(outcome.result.readiness, ScanReadiness.moderate, reason: 'seed $seed');
      }
    });

    test('an empty scene finds nothing and asks to reposition', () async {
      final SceneScanOutcome outcome = await pipelineFor(
        const MockScenario(wicketKind: MockWicketKind.none),
      ).scan(frames: camera());
      expect(outcome.result.foundWicket, isFalse);
      expect(outcome.result.readiness, ScanReadiness.reposition);
      expect(outcome.framesScanned, 30);
    });

    test('reports progress once per scanned frame', () async {
      final List<WicketScanResult> interim = <WicketScanResult>[];
      final SceneScanOutcome outcome = await pipelineFor(const MockScenario()).scan(
        frames: camera(),
        onProgress: interim.add,
      );
      expect(interim, hasLength(outcome.framesScanned));
      expect(interim.last.framesScanned, outcome.framesScanned);
    });

    test('a camera that stops early gives a short scan', () async {
      final SceneScanOutcome outcome = await pipelineFor(const MockScenario()).scan(
        frames: camera(endMs: 450),
      );
      // Scanned at 0, 100, 200, 300 and 400 ms.
      expect(outcome.framesScanned, 5);
    });

    test('a sparse device scans less often', () async {
      final DevicePolicy low = DevicePolicy.forProfile(DeviceProfile.low);
      final SceneScanOutcome sparse = await pipelineFor(
        const MockScenario(wicketKind: MockWicketKind.none),
      ).scan(frames: camera(endMs: 3000), policy: low);
      // About one scan every 250 ms instead of every 100 ms.
      expect(sparse.framesScanned, inInclusiveRange(10, 14));
    });

    test('a score-only device skips the scan', () async {
      final SceneScanOutcome outcome = await pipelineFor(const MockScenario()).scan(
        frames: camera(),
        policy: DevicePolicy.forProfile(DeviceProfile.scoreOnly),
      );
      expect(outcome.skipped, isTrue);
      expect(outcome.framesScanned, 0);
      expect(outcome.result.foundWicket, isFalse);
    });

    test('a cancelled scan stops at once', () async {
      final CancellationFlag flag = CancellationFlag()..cancel();
      final SceneScanOutcome outcome = await pipelineFor(const MockScenario()).scan(
        frames: camera(),
        cancel: flag,
      );
      expect(outcome.wasCancelled, isTrue);
      expect(outcome.framesScanned, 0);
    });

    test('the scene config has the documented limits', () {
      const SceneScanConfig config = SceneScanConfig();
      expect(config.minFrames, 12);
      expect(config.maxFrames, 30);
      expect(config.earlyStopConfidence, 0.9);
      expect(config.scanIntervalMs, 100);
      expect(config.sparseScanIntervalMs, 250);
    });
  });
}
