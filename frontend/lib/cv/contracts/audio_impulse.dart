import 'package:equatable/equatable.dart';

/// A short, sharp sound detected by an [AudioAnalyzer] (spec §8 `AudioImpulse`).
final class AudioImpulse extends Equatable {
  const AudioImpulse({
    required this.timestampMs,
    required this.peakAmplitude,
    required this.spectralCentroid,
    required this.impulseConfidence,
  });

  /// Time of the impulse on the same clock as the camera frames.
  final int timestampMs;

  /// Peak amplitude 0..1.
  final double peakAmplitude;

  /// Spectral centroid in Hz. A bat edge is bright (high centroid); a pad or
  /// background thump is duller.
  final double spectralCentroid;

  /// Probability 0..1 that this is a real impact and not background noise.
  final double impulseConfidence;

  @override
  List<Object?> get props => <Object?>[timestampMs, peakAmplitude, spectralCentroid, impulseConfidence];
}
