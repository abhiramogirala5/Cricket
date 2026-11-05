import 'dart:math' as math;

import 'package:gully_umpire/cv/contracts/audio_analyzer.dart';
import 'package:gully_umpire/cv/contracts/ball_detector.dart';
import 'package:gully_umpire/cv/contracts/camera_frame_input.dart';
import 'package:gully_umpire/cv/contracts/cv_model_info.dart';
import 'package:gully_umpire/cv/contracts/detected_object.dart';
import 'package:gully_umpire/cv/contracts/pose.dart';
import 'package:gully_umpire/cv/contracts/pose_estimator.dart';
import 'package:gully_umpire/cv/device/device_policy.dart';
import 'package:gully_umpire/cv/geometry/bounding_box.dart';
import 'package:gully_umpire/cv/pipelines/ball_observation.dart';
import 'package:gully_umpire/cv/pipelines/delivery_context.dart';
import 'package:gully_umpire/cv/pipelines/delivery_interpreter.dart';
import 'package:gully_umpire/cv/pipelines/delivery_pipeline_config.dart';
import 'package:gully_umpire/cv/pipelines/frame_schedule.dart';
import 'package:gully_umpire/cv/pipelines/pose_sample.dart';
import 'package:gully_umpire/cv/tracking/ball_tracker.dart';

/// Watches the camera frames of one delivery and says what happened (spec §11).
///
/// For every frame the ball detector and pose estimator are run at the rate the device policy
/// allows. The ball detections are cleaned up (weak, wrongly sized and isolated detections are
/// dropped, a Kalman filter rejects jumps) and handed with the batter's pose to
/// [interpretDelivery]. Errors from the detectors are not caught here: the caller falls back to
/// manual scoring when one is thrown.
final class DeliveryPipeline {
  DeliveryPipeline({
    required this.ballDetector,
    required this.poseEstimator,
    this.audioAnalyzer,
    this.config = const DeliveryPipelineConfig(),
  });

  final BallDetector ballDetector;
  final PoseEstimator poseEstimator;

  /// Optional microphone analysis used by the edge check.
  final AudioAnalyzer? audioAnalyzer;

  final DeliveryPipelineConfig config;

  List<CvModelInfo> get _models => <CvModelInfo>[
        ballDetector.modelInfo,
        poseEstimator.modelInfo,
        if (audioAnalyzer != null) audioAnalyzer!.modelInfo,
      ];

  /// Version string of the models behind the results (starts with `mock-` for mock models).
  String get modelVersion => CvModelInfo.combinedVersion(_models);

  /// True when any model is a mock.
  bool get isMock => _models.any((CvModelInfo m) => m.isMock);

  /// Analyses one delivery from the frames in [frames], which should start a little before the
  /// release and end shortly after the ball has passed the batter.
  Future<DeliveryAnalysis> analyse({
    required Stream<CameraFrameInput> frames,
    required DeliveryContext context,
    CancellationFlag? cancel,
  }) async {
    final DevicePolicy policy = context.policy;
    if (!policy.isUmpiringAvailable) {
      return DeliveryAnalysis.none(
        modelVersion: modelVersion,
        isMock: isMock,
        notes: const <String>['This phone is set to score only.'],
      );
    }

    final FrameSchedule ballSchedule = FrameSchedule(policy.ballIntervalMs);
    final FrameSchedule poseSchedule = FrameSchedule(policy.poseIntervalMs);
    final _BallCapture capture = _BallCapture(
      BallTracker(config: BallTrackerConfig(maxGapMs: config.gapMsFor(policy.ballIntervalMs))),
    );
    final List<int> detectorRuns = <int>[];
    final List<PoseSample> poses = <PoseSample>[];
    double aspect = 16.0 / 9.0;
    int frameCount = 0;

    await for (final CameraFrameInput frame in frames) {
      if (cancel != null && cancel.isCancelled) {
        return DeliveryAnalysis.none(
          modelVersion: modelVersion,
          isMock: isMock,
          framesProcessed: frameCount,
          wasCancelled: true,
        );
      }
      frameCount += 1;
      aspect = frame.aspectRatio;
      final int timestampMs = frame.timestampMs;

      if (ballSchedule.take(timestampMs)) {
        detectorRuns.add(timestampMs);
        final List<DetectedObject> detections = await ballDetector.detect(frame);
        final BallObservation? observation =
            _chooseBall(detections, capture.tracker, timestampMs, aspect, capture.latest);
        if (observation != null) {
          capture.offer(observation, config.minSegmentPoints);
        }
      }
      if (poseSchedule.take(timestampMs)) {
        final PoseResult? pose = await poseEstimator.estimate(frame);
        if (pose != null) {
          final PoseSample? sample = poseSampleFrom(pose, timestampMs);
          if (sample != null) {
            poses.add(sample);
          }
        }
      }
    }
    capture.finish(config.minSegmentPoints);

    final AudioAnalyzer? audio = audioAnalyzer;
    return interpretDelivery(
      observations: capture.records,
      detectorRunTimes: detectorRuns,
      poses: poses,
      aspectRatio: aspect,
      context: context,
      modelVersion: modelVersion,
      isMock: isMock,
      framesProcessed: frameCount,
      impulseLookup: audio == null
          ? null
          : (int fromMs, int toMs) => audio.getRecentImpulses(fromMs, toMs),
      config: config,
    );
  }

  /// Picks the detection that is most likely the ball, or null when there is none worth using.
  ///
  /// A detection that agrees with where the current track says the ball should be wins; without
  /// one the most confident detection is taken (it may start a new track). A detection whose size
  /// differs hugely from the last accepted one is not the same ball.
  BallObservation? _chooseBall(
    List<DetectedObject> detections,
    BallTracker tracker,
    int timestampMs,
    double aspect,
    BallObservation? previous,
  ) {
    DetectedObject? chosen;
    double bestGate = double.infinity;
    DetectedObject? mostConfident;
    for (final DetectedObject detection in detections) {
      if (SceneLabels.normalize(detection.label) != SceneLabels.ball ||
          detection.confidence < config.minBallConfidence) {
        continue;
      }
      final BoundingBox box = detection.boundingBox;
      if (mostConfident == null || detection.confidence > mostConfident.confidence) {
        mostConfident = detection;
      }
      final double? gate = tracker.gateDistanceSquared(
        timestampMs,
        box.centerX,
        box.centerY,
        confidence: detection.confidence,
      );
      if (gate != null && gate <= tracker.config.gateChiSquare && gate < bestGate) {
        bestGate = gate;
        chosen = detection;
      }
    }
    chosen ??= mostConfident;
    if (chosen == null) {
      return null;
    }
    final BoundingBox box = chosen.boundingBox;
    final double diameter = (box.height + box.width * aspect) / 2;
    if (!(diameter > 0) || !box.centerX.isFinite || !box.centerY.isFinite) {
      return null;
    }
    if (previous != null && timestampMs - previous.timestampMs <= config.sizeCheckWindowMs) {
      final double ratio = diameter / previous.diameter;
      if (ratio > config.maxSizeRatio || ratio < 1 / config.maxSizeRatio) {
        return null;
      }
    }
    return BallObservation(
      timestampMs: timestampMs,
      x: box.centerX,
      y: box.centerY,
      confidence: chosen.confidence,
      diameter: diameter,
    );
  }
}

/// Collects the accepted ball observations of a delivery.
///
/// The tracker decides which detections belong together. A new motion segment starts when the
/// tracker starts or restarts a track; a segment that has fewer than a handful of points when the
/// next one begins (or at the end) was clutter and is removed.
final class _BallCapture {
  _BallCapture(this.tracker);

  final BallTracker tracker;
  final List<BallObservation> records = <BallObservation>[];

  BallObservation? _lastRejected;
  int _segmentStart = 0;

  BallObservation? get latest => records.isEmpty ? null : records.last;

  void offer(BallObservation observation, int minSegmentPoints) {
    final int rejectedBefore = tracker.rejectedCount;
    final BallTrackStatus status = tracker.update(
      timestampMs: observation.timestampMs,
      x: observation.x,
      y: observation.y,
      confidence: observation.confidence,
    );
    switch (status) {
      case BallTrackStatus.started:
        _beginSegment(minSegmentPoints);
        records.add(observation);
      case BallTrackStatus.resegmented:
        _beginSegment(minSegmentPoints);
        final BallObservation? pending = _lastRejected;
        if (pending != null) {
          records.add(pending);
        }
        records.add(observation);
      case BallTrackStatus.accepted:
        records.add(observation);
      case BallTrackStatus.rejected:
        if (tracker.rejectedCount > rejectedBefore) {
          _lastRejected = observation;
        }
    }
  }

  void finish(int minSegmentPoints) {
    _dropShortSegment(minSegmentPoints);
  }

  void _beginSegment(int minSegmentPoints) {
    _dropShortSegment(minSegmentPoints);
    _segmentStart = records.length;
  }

  void _dropShortSegment(int minSegmentPoints) {
    if (records.length - _segmentStart < minSegmentPoints) {
      records.removeRange(math.min(_segmentStart, records.length), records.length);
    }
  }
}
