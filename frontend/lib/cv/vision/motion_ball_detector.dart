import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:gully_umpire/cv/pipelines/ball_observation.dart';
import 'package:gully_umpire/cv/util/math_utils.dart';
import 'package:gully_umpire/cv/vision/background_model.dart';
import 'package:gully_umpire/cv/vision/blob_finder.dart';
import 'package:gully_umpire/cv/vision/luma_frame.dart';

/// Tuning of the [MotionBallDetector]. Sizes are in pixels of the analysed (shrunken) picture.
final class MotionDetectorConfig extends Equatable {
  const MotionDetectorConfig({
    this.minDiameterPx = 1.5,
    this.maxDiameterFraction = 0.12,
    this.maxElongation = 9.0,
    this.minFill = 0.45,
    this.maxCandidates = 6,
    this.minConfidence = 0.5,
  });

  /// A ball smaller than this (in the analysed picture) cannot be told from noise.
  final double minDiameterPx;

  /// A ball is never bigger than this share of the picture height.
  final double maxDiameterFraction;

  /// Longest allowed ratio between the long and the short axis (a fast ball is slightly smeared).
  final double maxElongation;

  /// Smallest share of its ellipse that a ball patch must fill.
  final double minFill;

  /// At most this many candidates are returned per frame (best first).
  final int maxCandidates;

  /// Candidates below this confidence are dropped.
  final double minConfidence;

  @override
  List<Object?> get props =>
      <Object?>[minDiameterPx, maxDiameterFraction, maxElongation, minFill, maxCandidates, minConfidence];
}

/// What the detector found in one frame.
final class MotionDetection {
  const MotionDetection({
    required this.state,
    required this.candidates,
    required this.threshold,
    required this.noise,
    required this.foregroundFraction,
    required this.blobCount,
  });

  /// [BackgroundState.ok] when [candidates] can be trusted.
  final BackgroundState state;

  /// Ball-like patches, best first. Positions are 0..1 across the picture, the diameter is a
  /// fraction of the picture height.
  final List<BallObservation> candidates;

  /// Brightness difference used as the movement threshold.
  final int threshold;

  /// Measured picture noise (brightness levels).
  final double noise;

  /// Share of the picture that moved.
  final double foregroundFraction;

  /// Number of moving patches measured.
  final int blobCount;
}

/// Finds ball-shaped moving things in a stream of pictures from a fixed camera.
///
/// No trained model is involved: the picture is compared with a learned background
/// ([BackgroundModel]), the moving pixels are grouped into patches ([BlobFinder]), and each patch
/// is scored by how ball-like it is: a small, compact, round patch that contrasts clearly with the
/// background. Deciding which patches are *the* ball is the tracker's job, because a single frame
/// cannot tell a ball from a swaying head.
final class MotionBallDetector {
  MotionBallDetector({
    this.config = const MotionDetectorConfig(),
    BackgroundModel? background,
    BlobFinder? finder,
  }) : _background = background ?? BackgroundModel(),
       _finder = finder ?? BlobFinder();

  final MotionDetectorConfig config;
  final BackgroundModel _background;
  final BlobFinder _finder;

  /// Forgets the learned scene.
  void reset() => _background.reset();

  /// Looks at the next picture.
  MotionDetection process(LumaFrame frame) {
    final BackgroundState state = _background.update(frame);
    if (state != BackgroundState.ok) {
      return MotionDetection(
        state: state,
        candidates: const <BallObservation>[],
        threshold: _background.threshold,
        noise: _background.noise,
        foregroundFraction: _background.foregroundFraction,
        blobCount: 0,
      );
    }
    final int threshold = _background.threshold;
    final List<Blob> blobs = _finder.find(
      diff: _background.diff,
      width: frame.width,
      height: frame.height,
      threshold: threshold,
    );
    final List<BallObservation> candidates = scoreBlobs(
      blobs,
      threshold: threshold,
      width: frame.width,
      height: frame.height,
      timestampMs: frame.timestampMs,
      config: config,
    );
    return MotionDetection(
      state: state,
      candidates: candidates,
      threshold: threshold,
      noise: _background.noise,
      foregroundFraction: _background.foregroundFraction,
      blobCount: blobs.length,
    );
  }
}

/// Scores every blob for how ball-like it is and returns the good ones, best first.
///
/// The confidence is `0.30 + 0.65 * q`, where `q` is a weighted geometric mean of four scores in
/// 0..1: size (not a speck, not huge), shape (compact), fill (a solid patch, not a ring or a
/// scatter) and contrast (clearly above the noise threshold).
List<BallObservation> scoreBlobs(
  List<Blob> blobs, {
  required int threshold,
  required int width,
  required int height,
  required int timestampMs,
  MotionDetectorConfig config = const MotionDetectorConfig(),
}) {
  final double maxDiameter = config.maxDiameterFraction * height;
  final List<BallObservation> scored = <BallObservation>[];
  for (final Blob blob in blobs) {
    final double elongation = blob.elongation;
    // Half-maximum area: unbiased for a blurred disc. A smeared (elongated) patch is measured
    // across its short side.
    final double equivalent = 2 * math.sqrt(blob.halfArea / math.pi);
    double diameter = elongation < 1.6 ? equivalent : blob.minor;
    if (diameter < 1.0) {
      diameter = 1.0;
    }
    if (diameter > maxDiameter || diameter < config.minDiameterPx * 0.7) {
      continue;
    }
    final double fill = blob.area / math.max(1e-6, math.pi / 4 * blob.major * blob.minor);
    final double sizeScore =
        scoreRising(diameter, low: config.minDiameterPx, high: config.minDiameterPx * 2) *
            scoreFalling(diameter, good: maxDiameter * 0.5, bad: maxDiameter);
    final double shapeScore = scoreFalling(elongation, good: 2.5, bad: config.maxElongation);
    final double fillScore =
        scoreRising(fill, low: config.minFill * 0.6, high: 0.8);
    final double contrastScore =
        scoreRising(blob.meanDiff / math.max(threshold, 1), low: 1.0, high: 2.5);
    final double quality = math.pow(sizeScore, 0.35).toDouble() *
        math.pow(shapeScore, 0.2).toDouble() *
        math.pow(fillScore, 0.2).toDouble() *
        math.pow(contrastScore, 0.25).toDouble();
    final double confidence = clamp01(0.30 + 0.65 * quality);
    if (confidence < config.minConfidence) {
      continue;
    }
    scored.add(
      BallObservation(
        timestampMs: timestampMs,
        x: blob.cx / width,
        y: blob.cy / height,
        confidence: confidence,
        diameter: diameter / height,
      ),
    );
  }
  scored.sort((BallObservation a, BallObservation b) => b.confidence.compareTo(a.confidence));
  if (scored.length > config.maxCandidates) {
    return scored.sublist(0, config.maxCandidates);
  }
  return scored;
}
