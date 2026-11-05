import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/cv/audio/acoustic_impulse_detector.dart';
import 'package:gully_umpire/cv/contracts/audio_impulse.dart';

void main() {
  group('AcousticImpulseDetector', () {
    late AcousticImpulseDetector detector;

    setUp(() {
      detector = AcousticImpulseDetector(
        config: const AcousticImpulseConfig(
          sampleRate: 44100,
          minPeakAmplitude: 0.05,
          minImpulseRiseDb: 8.0,
        ),
      );
    });

    tearDown(() async {
      await detector.dispose();
    });

    test('ignores steady ambient background noise without false spikes', () async {
      // 1 second of steady low-amplitude white noise
      final Int16List noise = Int16List(44100);
      final math.Random random = math.Random(42);
      for (int i = 0; i < noise.length; i++) {
        noise[i] = (random.nextDouble() * 400 - 200).round(); // ~0.006 amplitude
      }

      detector.processPcm16(samples: noise, timestampMs: 1000);
      final List<AudioImpulse> impulses = await detector.getRecentImpulses(900, 2100);

      expect(impulses, isEmpty);
    });

    test('detects a sharp high-frequency transient click (bat edge signature)', () async {
      // 500ms of ambient noise, followed by an impulse click at 2500Hz, then quiet
      final Int16List audio = Int16List(44100 ~/ 2); // 500ms
      final int clickStart = 44100 ~/ 4; // At 250ms

      // Generate click with ~2500Hz resonance lasting ~10ms (441 samples)
      for (int i = 0; i < 441; i++) {
        final double t = i / 44100.0;
        final double envelope = math.exp(-i / 100.0); // fast decay
        final double signal = math.sin(2 * math.pi * 2500.0 * t) * envelope;
        audio[clickStart + i] = (signal * 20000).round(); // high amplitude
      }

      detector.processPcm16(samples: audio, timestampMs: 1000);

      // Search around 1250ms (1000ms start + 250ms offset)
      final List<AudioImpulse> impulses = await detector.getRecentImpulses(1200, 1300);

      expect(impulses, isNotEmpty);
      final AudioImpulse snick = impulses.first;
      expect(snick.timestampMs, closeTo(1250, 20));
      expect(snick.peakAmplitude, greaterThan(0.20));
      expect(snick.spectralCentroid, inInclusiveRange(1200.0, 5000.0));
      expect(snick.impulseConfidence, greaterThan(0.50));
    });

    test('allows recording impulses directly and filters by time window', () async {
      const AudioImpulse imp1 = AudioImpulse(
        timestampMs: 1050,
        peakAmplitude: 0.6,
        spectralCentroid: 2800,
        impulseConfidence: 0.85,
      );
      const AudioImpulse imp2 = AudioImpulse(
        timestampMs: 1500,
        peakAmplitude: 0.7,
        spectralCentroid: 3000,
        impulseConfidence: 0.90,
      );

      detector.recordImpulse(imp1);
      detector.recordImpulse(imp2);

      final List<AudioImpulse> window = await detector.getRecentImpulses(1000, 1100);
      expect(window, hasLength(1));
      expect(window.single.timestampMs, 1050);

      final List<AudioImpulse> both = await detector.getRecentImpulses(1000, 1600);
      expect(both, hasLength(2));
    });
  });
}

