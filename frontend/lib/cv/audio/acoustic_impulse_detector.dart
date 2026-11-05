import 'dart:math' as math;
import 'dart:typed_data';

import 'package:gully_umpire/cv/contracts/audio_analyzer.dart';
import 'package:gully_umpire/cv/contracts/audio_impulse.dart';
import 'package:gully_umpire/cv/contracts/cv_model_info.dart';
import 'package:gully_umpire/cv/util/math_utils.dart';

/// Configuration for real-time acoustic edge / Snicko impulse detection.
final class AcousticImpulseConfig {
  const AcousticImpulseConfig({
    this.sampleRate = 44100,
    this.windowMs = 10,
    this.hopMs = 5,
    this.minImpulseRiseDb = 12.0,
    this.minPeakAmplitude = 0.08,
    this.edgeCentroidLowHz = 1500.0,
    this.edgeCentroidHighHz = 4200.0,
    this.historyDurationMs = 6000,
  });

  /// Audio sampling rate in Hz (standard mobile mono stream).
  final int sampleRate;

  /// Analysis window in milliseconds (10ms = 441 samples at 44.1kHz).
  final int windowMs;

  /// Hop size between consecutive windows.
  final int hopMs;

  /// Minimum instantaneous rise in energy (dB) over ambient noise floor to qualify as an impulse.
  final double minImpulseRiseDb;

  /// Minimum normalized peak amplitude (0..1) to reject gentle background whispers.
  final double minPeakAmplitude;

  /// Frequency band of bat-ball edge contact (willow resonant click).
  final double edgeCentroidLowHz;
  final double edgeCentroidHighHz;

  /// Rolling buffer retention window in milliseconds.
  final int historyDurationMs;

  int get windowSamples => (sampleRate * windowMs / 1000).round();
  int get hopSamples => (sampleRate * hopMs / 1000).round();
}

/// Real-time Digital Signal Processing (DSP) engine for detecting cricket bat-ball edge clicks.
///
/// Grounded in acoustic sports research (UltraEdge / Real-Time Snickometer DSP principles):
/// A leather cricket ball striking English willow produces a rapid transient spike lasting
/// 3-10 ms with energy concentrated in the 1.5 kHz - 4.2 kHz band. Conversely, pad/body strikes
/// produce low-frequency thuds (< 800 Hz), and crowd/wind noise produces diffuse energy.
final class AcousticImpulseDetector implements AudioAnalyzer {
  AcousticImpulseDetector({
    this.config = const AcousticImpulseConfig(),
  });

  final AcousticImpulseConfig config;
  final List<AudioImpulse> _history = <AudioImpulse>[];

  double _noiseFloorEnergy = 0.001;
  int _lastImpulseTimestampMs = -1000;
  bool _disposed = false;

  @override
  CvModelInfo get modelInfo => const CvModelInfo(
        name: 'Acoustic DSP Impulse Detector',
        version: 'dsp-ultraedge-1.0',
      );

  /// Ingests a chunk of raw 16-bit linear PCM audio samples (mono).
  ///
  /// [timestampMs] is the timestamp of the start of the chunk, aligned to the camera/delivery clock.
  void processPcm16({
    required Int16List samples,
    required int timestampMs,
  }) {
    if (_disposed || samples.isEmpty) {
      return;
    }

    final int win = config.windowSamples;
    final int hop = config.hopSamples;
    if (samples.length < win) {
      return;
    }

    // Convert Int16 to normalized float [-1.0, 1.0] and evaluate sliding energy
    for (int offset = 0; offset + win <= samples.length; offset += hop) {
      double sumSquares = 0.0;
      double peak = 0.0;
      int zeroCrossings = 0;
      double highFreqDiffSum = 0.0;

      double prev = samples[offset] / 32768.0;
      for (int i = 0; i < win; i++) {
        final double s = samples[offset + i] / 32768.0;
        final double sAbs = s.abs();
        if (sAbs > peak) {
          peak = sAbs;
        }
        sumSquares += s * s;

        // Count zero crossings for spectral centroid approximation
        if ((s >= 0 && prev < 0) || (s < 0 && prev >= 0)) {
          zeroCrossings++;
        }
        final double diff = s - prev;
        highFreqDiffSum += diff * diff;
        prev = s;
      }

      final double energy = sumSquares / win;
      final int frameTimeMs = timestampMs + ((offset * 1000) ~/ config.sampleRate);

      // Estimate spectral centroid from Zero Crossing Rate (ZCR) and first-order difference ratio
      // ZCR in speech/audio processing: f_centroid ~ ZCR * (sampleRate / 2) / (N_samples)
      final double zcr = zeroCrossings / win.toDouble();
      final double estimatedCentroid = zcr * (config.sampleRate / 2.0);

      // Evaluate transient energy rise in decibels relative to noise floor
      final double currentDb = 10.0 * math.log(math.max(1e-7, energy)) / math.ln10;
      final double noiseDb = 10.0 * math.log(math.max(1e-7, _noiseFloorEnergy)) / math.ln10;
      final double riseDb = currentDb - noiseDb;

      // Check impulse criteria: sharp energy spike above noise floor + sufficient amplitude
      final bool isSpike = riseDb >= config.minImpulseRiseDb && peak >= config.minPeakAmplitude;
      final bool isWillowBand = estimatedCentroid >= (config.edgeCentroidLowHz * 0.75) &&
          estimatedCentroid <= (config.edgeCentroidHighHz * 1.35);

      // Refractory period: edge impulses must be separated by at least 25ms
      if (isSpike && isWillowBand && (frameTimeMs - _lastImpulseTimestampMs) > 25) {
        _lastImpulseTimestampMs = frameTimeMs;

        // Confidence score based on spectral proximity to ideal willow resonance (~2500 Hz)
        // and loudness of transient rise
        final double centroidScore =
            1.0 - (estimatedCentroid - 2800.0).abs() / 2500.0;
        final double amplitudeScore = clamp01(peak / 0.5);
        final double riseScore = clamp01((riseDb - config.minImpulseRiseDb) / 20.0);

        final double confidence = clampDouble(
          centroidScore * 0.40 + amplitudeScore * 0.35 + riseScore * 0.25,
          0.10,
          0.98,
        );

        _history.add(
          AudioImpulse(
            timestampMs: frameTimeMs,
            peakAmplitude: clamp01(peak),
            spectralCentroid: estimatedCentroid.clamp(100.0, 10000.0),
            impulseConfidence: confidence,
          ),
        );
      } else {
        // Slow adaptation of background noise floor
        _noiseFloorEnergy = 0.95 * _noiseFloorEnergy + 0.05 * energy;
      }
    }

    _prune(timestampMs);
  }

  void _prune(int nowMs) {
    final int cutoff = nowMs - config.historyDurationMs;
    _history.removeWhere((AudioImpulse impulse) => impulse.timestampMs < cutoff);
  }

  @override
  Future<List<AudioImpulse>> getRecentImpulses(int fromMs, int toMs) async {
    return _history
        .where((AudioImpulse i) => i.timestampMs >= fromMs && i.timestampMs <= toMs)
        .toList();
  }

  /// Manually registers an impulse (useful for synthetic benchmarks or external microphone streams).
  void recordImpulse(AudioImpulse impulse) {
    if (!_disposed) {
      _history.add(impulse);
      _prune(impulse.timestampMs);
    }
  }

  /// Clears recent impulses.
  void clear() {
    _history.clear();
    _noiseFloorEnergy = 0.001;
    _lastImpulseTimestampMs = -1000;
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _history.clear();
  }
}

