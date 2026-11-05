import 'package:gully_umpire/cv/adapters/mock/mock_scenario.dart';
import 'package:gully_umpire/cv/contracts/audio_analyzer.dart';
import 'package:gully_umpire/cv/contracts/audio_impulse.dart';
import 'package:gully_umpire/cv/contracts/cv_model_info.dart';

/// A stand-in for the real microphone analysis: a faint background sound in every delivery and a
/// sharp, high-pitched click at the moment of the contact in an edge delivery.
final class MockAudioAnalyzer implements AudioAnalyzer {
  MockAudioAnalyzer(this.scenario) : _world = MockWorld(scenario);

  final MockScenario scenario;
  final MockWorld _world;

  @override
  CvModelInfo get modelInfo => const CvModelInfo(name: 'Mock audio analyzer', version: 'mock-audio-1.0');

  List<AudioImpulse> get _impulses => <AudioImpulse>[
        AudioImpulse(
          timestampMs: scenario.releaseMs + 300,
          peakAmplitude: 0.2,
          spectralCentroid: 800,
          impulseConfidence: 0.2,
        ),
        if (scenario.deliveryKind == MockDeliveryKind.edge)
          AudioImpulse(
            timestampMs: _world.contactMs,
            peakAmplitude: 0.6,
            spectralCentroid: 3200,
            impulseConfidence: 0.9,
          ),
      ];

  @override
  Future<List<AudioImpulse>> getRecentImpulses(int fromMs, int toMs) async {
    return _impulses
        .where((AudioImpulse i) => i.timestampMs >= fromMs && i.timestampMs <= toMs)
        .toList();
  }

  @override
  Future<void> dispose() async {}
}
