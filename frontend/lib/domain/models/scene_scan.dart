import 'package:equatable/equatable.dart';
import 'package:gully_umpire/domain/models/json_helpers.dart';

/// Result of the pre-match scan of the playing area (API entity `SCENE_SCAN`).
final class SceneScan extends Equatable {
  const SceneScan({
    required this.id,
    required this.matchId,
    required this.scanDurationMs,
    required this.overallConfidence,
    required this.modelVersion,
    required this.createdAt,
    this.cameraDeviceModel,
    this.captureFps,
    this.groundPlane,
    this.pitchDirection,
    this.batsmanPlane,
  });

  factory SceneScan.fromJson(Map<String, Object?> json) => SceneScan(
        id: asString(json['id']),
        matchId: asString(json['match_id']),
        cameraDeviceModel: asStringOrNull(json['camera_device_model']),
        captureFps: asIntOrNull(json['capture_fps']),
        scanDurationMs: asInt(json['scan_duration_ms']),
        groundPlane: asJsonMapOrNull(json['ground_plane']),
        pitchDirection: asJsonMapOrNull(json['pitch_direction']),
        batsmanPlane: asJsonMapOrNull(json['batsman_plane']),
        overallConfidence: asDouble(json['overall_confidence']),
        modelVersion: asString(json['model_version']),
        createdAt: parseDateTime(json['created_at']),
      );

  final String id;
  final String matchId;
  final String? cameraDeviceModel;
  final int? captureFps;
  final int scanDurationMs;
  final Map<String, Object?>? groundPlane;
  final Map<String, Object?>? pitchDirection;
  final Map<String, Object?>? batsmanPlane;
  final double overallConfidence;
  final String modelVersion;
  final DateTime createdAt;

  /// Scans produced by the simulator are labelled so the UI can be honest about it.
  bool get isMock => modelVersion.startsWith('mock');

  Map<String, Object?> toJson() => toSyncPayload();

  /// Exactly the keys of API_CONTRACT §5.3 `SCENE_SCAN`.
  Map<String, Object?> toSyncPayload() => <String, Object?>{
        'id': id,
        'match_id': matchId,
        'camera_device_model': cameraDeviceModel,
        'capture_fps': captureFps,
        'scan_duration_ms': scanDurationMs,
        'ground_plane': groundPlane,
        'pitch_direction': pitchDirection,
        'batsman_plane': batsmanPlane,
        'overall_confidence': overallConfidence,
        'model_version': modelVersion,
        'created_at': toIsoUtc(createdAt),
      };

  @override
  List<Object?> get props => <Object?>[
        id,
        matchId,
        cameraDeviceModel,
        captureFps,
        scanDurationMs,
        groundPlane,
        pitchDirection,
        batsmanPlane,
        overallConfidence,
        modelVersion,
        createdAt,
      ];
}
