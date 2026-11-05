import 'package:equatable/equatable.dart';
import 'package:gully_umpire/cv/pipelines/delivery_geometry.dart';

/// Tuning of the delivery pipeline. The numbers were chosen with the synthetic mock camera; real
/// footage will need them to be re-checked.
final class DeliveryPipelineConfig extends Equatable {
  const DeliveryPipelineConfig({
    this.minBallConfidence = 0.5,
    this.gapIntervalFactor = 2.2,
    this.minGapMs = 100,
    this.maxGapMs = 400,
    this.maxSizeRatio = 2.2,
    this.sizeCheckWindowMs = 400,
    this.minSegmentPoints = 3,
    this.minPoseSamples = 3,
    this.minTrajectoryConfidence = 0.5,
    this.batsmanMoveThresholdM = 0.25,
    this.ballDiameterM = 0.07,
    this.speedTrackingFactor = 0.8,
    this.heightUncertaintyM,
    this.geometry = const DeliveryGeometryConfig(),
  });

  /// The settings used with the real camera.
  ///
  /// [ballDiameterM] is the real size of the ball in use. The height of the ball at the batter is
  /// good to about 0.3 m with one camera, so a height that close to a rule limit is never called
  /// with confidence, and a ball that was first seen too far down the pitch is never called a
  /// full toss.
  factory DeliveryPipelineConfig.live({double ballDiameterM = 0.072}) {
    return DeliveryPipelineConfig(
      ballDiameterM: ballDiameterM,
      heightUncertaintyM: 0.30,
      geometry: const DeliveryGeometryConfig(minBounceViewRatio: 2.2),
    );
  }

  /// Detections below this confidence are not used at all.
  final double minBallConfidence;

  /// A silence of more than this many detector intervals (but between [minGapMs] and [maxGapMs])
  /// ends the current ball track, so a stray detection cannot be mistaken for the ball.
  final double gapIntervalFactor;
  final int minGapMs;
  final int maxGapMs;

  /// A detection whose apparent size differs from the previous one by more than this factor is not
  /// the same ball.
  final double maxSizeRatio;
  final int sizeCheckWindowMs;

  /// A stretch of the track shorter than this is treated as clutter and dropped.
  final int minSegmentPoints;

  /// Fewest usable pose samples needed to measure the batter.
  final int minPoseSamples;

  /// Below this ball-track quality no wide or no-ball suggestion is made, only "not sure".
  final double minTrajectoryConfidence;

  /// The batter counts as having moved towards the ball after moving this far sideways.
  final double batsmanMoveThresholdM;

  /// Real diameter of the ball in metres.
  final double ballDiameterM;

  /// Share of the track quality that is trusted for a speed estimate.
  final double speedTrackingFactor;

  /// How far (metres) the measured ball height at the batter can be off. A height closer than this
  /// to a rule limit is a coin toss, so the confidence of the call falls to half there. Null keeps
  /// the older default of one tenth of the batter's height.
  final double? heightUncertaintyM;

  final DeliveryGeometryConfig geometry;

  /// The ball detector is run at most once per this many milliseconds apart for the gap rule.
  int gapMsFor(int detectorIntervalMs) {
    final int gap = (detectorIntervalMs * gapIntervalFactor).round();
    if (gap < minGapMs) {
      return minGapMs;
    }
    if (gap > maxGapMs) {
      return maxGapMs;
    }
    return gap;
  }

  @override
  List<Object?> get props => <Object?>[
        minBallConfidence,
        gapIntervalFactor,
        minGapMs,
        maxGapMs,
        maxSizeRatio,
        sizeCheckWindowMs,
        minSegmentPoints,
        minPoseSamples,
        minTrajectoryConfidence,
        batsmanMoveThresholdM,
        ballDiameterM,
        speedTrackingFactor,
        heightUncertaintyM,
        geometry,
      ];
}
