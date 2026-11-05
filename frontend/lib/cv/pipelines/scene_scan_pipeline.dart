import 'package:equatable/equatable.dart';
import 'package:gully_umpire/cv/contracts/camera_frame_input.dart';
import 'package:gully_umpire/cv/contracts/cv_model_info.dart';
import 'package:gully_umpire/cv/contracts/detected_object.dart';
import 'package:gully_umpire/cv/contracts/scene_object_detector.dart';
import 'package:gully_umpire/cv/device/device_policy.dart';
import 'package:gully_umpire/cv/geometry/bounding_box.dart';
import 'package:gully_umpire/cv/pipelines/delivery_context.dart';
import 'package:gully_umpire/cv/pipelines/frame_schedule.dart';
import 'package:gully_umpire/cv/scene/wicket_scanner.dart';

/// Tuning of the scene scan (spec §7: a scan of one to three seconds).
final class SceneScanConfig extends Equatable {
  const SceneScanConfig({
    this.minFrames = 12,
    this.maxFrames = 30,
    this.earlyStopConfidence = 0.9,
    this.scanIntervalMs = 100,
    this.sparseScanIntervalMs = 250,
    this.minPersonHeight = 0.10,
  });

  /// The scan never stops before this many frames have been looked at.
  final int minFrames;

  /// The scan always stops after this many frames.
  final int maxFrames;

  /// After [minFrames], the scan stops as soon as the best wicket is at least this confident.
  final double earlyStopConfidence;

  /// Time between two scanned frames (10 per second by default).
  final int scanIntervalMs;

  /// Time between two scanned frames on a phone that scans sparsely.
  final int sparseScanIntervalMs;

  /// A person smaller than this fraction of the picture height is not the batter.
  final double minPersonHeight;

  @override
  List<Object?> get props => <Object?>[
        minFrames,
        maxFrames,
        earlyStopConfidence,
        scanIntervalMs,
        sparseScanIntervalMs,
        minPersonHeight,
      ];
}

/// What a scene scan found.
final class SceneScanOutcome {
  const SceneScanOutcome({
    required this.result,
    required this.framesScanned,
    required this.modelVersion,
    required this.isMock,
    this.wasCancelled = false,
    this.skipped = false,
  });

  /// Best wicket, alternatives and the batter box.
  final WicketScanResult result;

  final int framesScanned;

  /// Version string of the detector (starts with `mock-` for a mock).
  final String modelVersion;

  final bool isMock;

  final bool wasCancelled;

  /// No scan was made because this phone is set to score only.
  final bool skipped;
}

/// Scans the scene at the start of a match to find the wicket without any manual marking.
final class SceneScanPipeline {
  SceneScanPipeline({
    required this.detector,
    this.config = const SceneScanConfig(),
    this.scannerConfig = const WicketScannerConfig(),
  });

  final SceneObjectDetector detector;
  final SceneScanConfig config;
  final WicketScannerConfig scannerConfig;

  /// Looks at [frames] until the wicket is clear, [SceneScanConfig.maxFrames] frames have been
  /// seen, [cancel] is raised or the stream ends. [onProgress] is called after each scanned frame
  /// with the current best result (for the live overlay).
  Future<SceneScanOutcome> scan({
    required Stream<CameraFrameInput> frames,
    DevicePolicy? policy,
    CancellationFlag? cancel,
    void Function(WicketScanResult interim)? onProgress,
  }) async {
    final CvModelInfo info = detector.modelInfo;
    final WicketScanner scanner = WicketScanner(config: scannerConfig);
    if (policy != null && policy.sceneScan == SceneScanMode.disabled) {
      return SceneScanOutcome(
        result: scanner.result(),
        framesScanned: 0,
        modelVersion: info.version,
        isMock: info.isMock,
        skipped: true,
      );
    }
    final int interval = policy != null && policy.sceneScan == SceneScanMode.sparse
        ? config.sparseScanIntervalMs
        : config.scanIntervalMs;
    final FrameSchedule schedule = FrameSchedule(interval);
    bool cancelled = false;

    await for (final CameraFrameInput frame in frames) {
      if (cancel != null && cancel.isCancelled) {
        cancelled = true;
        break;
      }
      if (!schedule.take(frame.timestampMs)) {
        continue;
      }
      final List<DetectedObject> detections = await detector.detect(frame);
      scanner.addFrame(detections, batsmanBox: _batsmanBox(detections));
      final WicketScanResult interim = scanner.result();
      if (onProgress != null) {
        onProgress(interim);
      }
      if (scanner.framesScanned >= config.maxFrames) {
        break;
      }
      if (scanner.framesScanned >= config.minFrames &&
          interim.confidence >= config.earlyStopConfidence) {
        break;
      }
    }
    return SceneScanOutcome(
      result: scanner.result(),
      framesScanned: scanner.framesScanned,
      modelVersion: info.version,
      isMock: info.isMock,
      wasCancelled: cancelled,
    );
  }

  /// The most likely batter: the largest person that is tall enough to be one.
  BoundingBox? _batsmanBox(List<DetectedObject> detections) {
    BoundingBox? best;
    for (final DetectedObject detection in detections) {
      if (!SceneLabels.isPerson(detection.label) || detection.confidence < 0.4) {
        continue;
      }
      final BoundingBox box = detection.boundingBox.clampedToUnit();
      if (box.isEmpty || box.height < config.minPersonHeight) {
        continue;
      }
      if (best == null || box.area > best.area) {
        best = box;
      }
    }
    return best;
  }
}
