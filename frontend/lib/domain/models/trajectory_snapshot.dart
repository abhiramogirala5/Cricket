import 'package:equatable/equatable.dart';
import 'package:gully_umpire/domain/models/json_helpers.dart';

/// Compressed ball path of one delivery (API entity `TRAJECTORY_SNAPSHOT`).
final class TrajectorySnapshot extends Equatable {
  const TrajectorySnapshot({
    required this.id,
    required this.deliveryId,
    required this.samplingFps,
    required this.pointsCompressed,
    required this.modelVersion,
    required this.createdAt,
  });

  factory TrajectorySnapshot.fromJson(Map<String, Object?> json) => TrajectorySnapshot(
        id: asString(json['id']),
        deliveryId: asString(json['delivery_id']),
        samplingFps: asInt(json['sampling_fps']),
        pointsCompressed: asJsonListOrNull(json['points_compressed']) ?? const <Object?>[],
        modelVersion: asString(json['model_version']),
        createdAt: parseDateTime(json['created_at']),
      );

  /// The API accepts at most this many points.
  static const int maxPoints = 600;

  final String id;
  final String deliveryId;
  final int samplingFps;

  /// Each element is `[timestamp_ms, x, y, confidence]`.
  final List<Object?> pointsCompressed;
  final String modelVersion;
  final DateTime createdAt;

  bool get isMock => modelVersion.startsWith('mock');

  Map<String, Object?> toJson() => toSyncPayload();

  /// Exactly the keys of API_CONTRACT §5.3 `TRAJECTORY_SNAPSHOT`.
  Map<String, Object?> toSyncPayload() => <String, Object?>{
        'id': id,
        'delivery_id': deliveryId,
        'sampling_fps': samplingFps,
        'points_compressed': pointsCompressed,
        'model_version': modelVersion,
        'created_at': toIsoUtc(createdAt),
      };

  @override
  List<Object?> get props =>
      <Object?>[id, deliveryId, samplingFps, pointsCompressed, modelVersion, createdAt];
}
