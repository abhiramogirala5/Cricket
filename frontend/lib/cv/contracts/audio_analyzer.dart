import 'package:gully_umpire/cv/contracts/audio_impulse.dart';
import 'package:gully_umpire/cv/contracts/cv_model_info.dart';

/// Detects short impact sounds (bat edge, pad, stumps) in the microphone stream.
abstract interface class AudioAnalyzer {
  /// Who produced the impulses. Mock adapters report a `mock-` version.
  CvModelInfo get modelInfo;

  /// Impulses with `fromMs <= timestampMs <= toMs`, oldest first.
  Future<List<AudioImpulse>> getRecentImpulses(int fromMs, int toMs);

  /// Releases native resources.
  Future<void> dispose();
}
