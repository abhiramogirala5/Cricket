import 'package:equatable/equatable.dart';

/// Identity of a detector / estimator implementation.
///
/// HONESTY RULE: every simulated adapter has a [version] that starts with
/// `mock-`. Anything derived from a mock adapter inherits that prefix through
/// [combinedVersion], and the UI shows a "Mock CV" badge for it.
final class CvModelInfo extends Equatable {
  const CvModelInfo({required this.name, required this.version});

  /// Prefix that marks simulated output.
  static const String mockPrefix = 'mock-';

  /// Database limit for `model_version`.
  static const int maxVersionLength = 100;

  /// Human readable name, e.g. `Mock scene detector`.
  final String name;

  /// Machine version, e.g. `mock-scene-1` or `ball-int8-2026.10`.
  final String version;

  /// True when this model only simulates output.
  bool get isMock => version.startsWith(mockPrefix);

  /// One `model_version` string for results produced by several models.
  ///
  /// The distinct versions are joined with `+`. If any model is a mock the
  /// result is guaranteed to start with `mock-`. The result is at most
  /// [maxVersionLength] characters (the API limit).
  static String combinedVersion(Iterable<CvModelInfo> models) {
    final List<String> versions = <String>[];
    bool anyMock = false;
    for (final CvModelInfo model in models) {
      if (model.isMock) {
        anyMock = true;
      }
      if (!versions.contains(model.version)) {
        versions.add(model.version);
      }
    }
    if (versions.isEmpty) {
      return 'unknown';
    }
    String joined = versions.join('+');
    if (anyMock && !joined.startsWith(mockPrefix)) {
      joined = '$mockPrefix$joined';
    }
    if (joined.length > maxVersionLength) {
      joined = joined.substring(0, maxVersionLength);
    }
    return joined;
  }

  @override
  List<Object?> get props => <Object?>[name, version];

  @override
  String toString() => 'CvModelInfo($name, $version)';
}
