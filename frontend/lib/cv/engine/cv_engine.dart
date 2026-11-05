import 'package:gully_umpire/cv/adapters/mock/mock.dart';
import 'package:gully_umpire/cv/contracts/camera_frame_input.dart';
import 'package:gully_umpire/cv/device/device_policy.dart';
import 'package:gully_umpire/cv/pipelines/pipelines.dart';
import 'package:gully_umpire/cv/scene/wicket_scanner.dart';

/// Where the umpiring suggestions come from.
enum CvMode {
  /// No camera tracking: the app is used for scoring only and never makes an umpiring suggestion.
  scoreOnly,

  /// The live camera: the ball is tracked in the pictures of the phone's camera as they arrive.
  live,

  /// Simulated detectors (development only). Every result is labelled as a simulation.
  simulated,
}

/// The one door between the screens and computer vision.
///
/// The screens ask this interface what the phone can do (live camera, nothing, or a development
/// simulation) and never depend on how it is done.
abstract interface class CvEngine {
  CvMode get mode;

  /// Umpiring suggestions can be produced at all.
  bool get isAvailable;

  /// The results come from simulated detectors and must be labelled as such.
  bool get isSimulated;

  /// Looks for the wicket (the scene scan at the start of a match).
  ///
  /// When this phone is set to score only, or the engine has no models, the outcome has
  /// `skipped == true`.
  Future<SceneScanOutcome> scanScene({
    required DevicePolicy policy,
    CancellationFlag? cancel,
    void Function(WicketScanResult interim)? onProgress,
  });

  Future<void> dispose();
}

/// An engine without models. Scoring works; nothing is ever suggested.
final class ScoreOnlyCvEngine implements CvEngine {
  const ScoreOnlyCvEngine();

  @override
  CvMode get mode => CvMode.scoreOnly;

  @override
  bool get isAvailable => false;

  @override
  bool get isSimulated => false;

  @override
  Future<SceneScanOutcome> scanScene({
    required DevicePolicy policy,
    CancellationFlag? cancel,
    void Function(WicketScanResult interim)? onProgress,
  }) async {
    return const SceneScanOutcome(
      result: WicketScanResult(
        best: null,
        alternatives: <WicketScanCandidate>[],
        framesScanned: 0,
      ),
      framesScanned: 0,
      modelVersion: 'none',
      isMock: false,
      skipped: true,
    );
  }

  @override
  Future<void> dispose() async {}
}

/// The real thing: the phone's camera, the ball tracker and the batter measurement.
///
/// There is nothing to scan before a match: the umpire marks the stumps on the live camera picture
/// (see `StumpMarkingView`), so [scanScene] reports that no automatic scan was made. The camera
/// itself is owned by the screens that show it (`UmpireCameraController`), not by this class,
/// because it must be released the moment the umpire leaves the page.
final class LiveCvEngine implements CvEngine {
  const LiveCvEngine();

  @override
  CvMode get mode => CvMode.live;

  @override
  bool get isAvailable => true;

  @override
  bool get isSimulated => false;

  @override
  Future<SceneScanOutcome> scanScene({
    required DevicePolicy policy,
    CancellationFlag? cancel,
    void Function(WicketScanResult interim)? onProgress,
  }) async {
    return const SceneScanOutcome(
      result: WicketScanResult(
        best: null,
        alternatives: <WicketScanCandidate>[],
        framesScanned: 0,
      ),
      framesScanned: 0,
      modelVersion: 'live-manual',
      isMock: false,
      skipped: true,
    );
  }

  @override
  Future<void> dispose() async {}
}

/// Detectors that play back a scripted scene (see `MockScenario`). It exists so that the whole
/// app can be tried, and tested, without trained models. It looks at nothing.
final class SimulatedCvEngine implements CvEngine {
  SimulatedCvEngine({
    MockScenario scenario = const MockScenario(),
    this.framePacing = true,
  }) : _scenario = scenario;

  /// Play the scan frames back in real time so progress can be seen. Tests switch this off.
  final bool framePacing;

  MockScenario _scenario;
  int _deliveryCounter = 0;

  /// The scene that is currently simulated.
  MockScenario get scenario => _scenario;

  /// Changes the simulated scene (the wicket kind and how clearly it is seen).
  void configure({MockWicketKind? wicketKind, MockScanQuality? scanQuality}) {
    _scenario = _scenario.copyWith(wicketKind: wicketKind, scanQuality: scanQuality);
  }

  @override
  CvMode get mode => CvMode.simulated;

  @override
  bool get isAvailable => true;

  @override
  bool get isSimulated => true;

  /// Length of the simulated scan footage.
  static const int scanFootageMs = 3200;

  @override
  Future<SceneScanOutcome> scanScene({
    required DevicePolicy policy,
    CancellationFlag? cancel,
    void Function(WicketScanResult interim)? onProgress,
  }) {
    final SceneScanPipeline pipeline = SceneScanPipeline(
      detector: MockSceneObjectDetector(_scenario),
    );
    final int fps = policy.cameraFps > 0 ? policy.cameraFps : 30;
    return pipeline.scan(
      frames: _scanFrames(fps),
      policy: policy,
      cancel: cancel,
      onProgress: onProgress,
    );
  }

  Stream<CameraFrameInput> _scanFrames(int fps) async* {
    final List<CameraFrameInput> frames =
        MockCamera.frameList(fps: fps, startMs: 0, endMs: scanFootageMs);
    final Duration gap = Duration(milliseconds: (1000 / fps).round());
    for (final CameraFrameInput frame in frames) {
      if (framePacing) {
        await Future<void>.delayed(gap);
      }
      yield frame;
    }
  }

  /// Plays one simulated delivery of [kind] through the real analysis pipeline.
  ///
  /// The batter in the simulation is as tall as [DeliveryContext.batsmanHeightM], so the
  /// geometry the pipeline works out is consistent with the context it is given.
  Future<DeliveryAnalysis> simulateDelivery({
    required MockDeliveryKind kind,
    required DeliveryContext context,
    CancellationFlag? cancel,
  }) {
    _deliveryCounter += 1;
    final MockScenario scenario = _scenario.copyWith(
      deliveryKind: kind,
      seed: _scenario.seed + _deliveryCounter,
      batsmanHeightM: context.batsmanHeightM,
    );
    final DeliveryPipeline pipeline = DeliveryPipeline(
      ballDetector: MockBallDetector(scenario),
      poseEstimator: MockPoseEstimator(scenario),
      audioAnalyzer: MockAudioAnalyzer(scenario),
    );
    final int fps = context.policy.cameraFps > 0 ? context.policy.cameraFps : 30;
    return pipeline.analyse(
      frames: MockCamera.frames(
        fps: fps,
        startMs: scenario.releaseMs - 300,
        endMs: scenario.releaseMs + 1400,
      ),
      context: context,
      cancel: cancel,
    );
  }

  @override
  Future<void> dispose() async {}
}
