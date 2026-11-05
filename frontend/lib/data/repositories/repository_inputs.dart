import 'package:gully_umpire/domain/decisions/decisions.dart';
import 'package:gully_umpire/domain/models/enums.dart';

/// A decision to store with a delivery: what the app suggested and what the umpire finally said.
final class DecisionInput {
  const DecisionInput({
    required this.type,
    required this.status,
    required this.source,
    this.automatedResult,
    this.finalResult,
    this.confidence,
    this.evidence,
  });

  final DeliveryDecisionType type;
  final DecisionStatus status;
  final DecisionSource source;
  final String? automatedResult;
  final String? finalResult;
  final double? confidence;
  final Map<String, Object?>? evidence;
}

/// The ball path to store with a delivery.
final class TrajectoryInput {
  const TrajectoryInput({
    required this.samplingFps,
    required this.points,
    required this.modelVersion,
  });

  final int samplingFps;

  /// Each point is `[timestamp_ms, x, y, confidence]`.
  final List<List<double>> points;
  final String modelVersion;
}
