import 'package:gully_umpire/cv/pipelines/pose_sample.dart';

/// The most recent batter poses, oldest first, kept in time order and bounded in size.
///
/// A delivery is interpreted some time after it was bowled, so the poses taken just before it must
/// still be available: this keeps the last few seconds.
final class PoseBuffer {
  PoseBuffer({this.maxAgeMs = 10000, this.maxSamples = 200})
      : assert(maxAgeMs > 0 && maxSamples > 0, 'a pose buffer needs positive limits');

  /// Samples older than the newest one by more than this are dropped.
  final int maxAgeMs;

  /// Most samples kept.
  final int maxSamples;

  final List<PoseSample> _samples = <PoseSample>[];

  int get length => _samples.length;

  bool get isEmpty => _samples.isEmpty;

  /// The newest sample, or null.
  PoseSample? get latest => _samples.isEmpty ? null : _samples.last;

  /// Adds [sample]. A sample that is not newer than the newest one is ignored, so the buffer is
  /// always in time order.
  void add(PoseSample sample) {
    if (_samples.isNotEmpty && sample.timestampMs <= _samples.last.timestampMs) {
      return;
    }
    _samples.add(sample);
    while (_samples.length > maxSamples ||
        (_samples.isNotEmpty && sample.timestampMs - _samples.first.timestampMs > maxAgeMs)) {
      _samples.removeAt(0);
    }
  }

  /// The samples taken from [fromMs] to [toMs] (inclusive), oldest first.
  List<PoseSample> window(int fromMs, int toMs) {
    return <PoseSample>[
      for (final PoseSample s in _samples)
        if (s.timestampMs >= fromMs && s.timestampMs <= toMs) s,
    ];
  }

  void clear() => _samples.clear();
}
