import 'package:equatable/equatable.dart';
import 'package:gully_umpire/domain/decisions/wicket_family.dart';
import 'package:gully_umpire/domain/models/json_helpers.dart';

/// The physical wicket found during the scan (API entity `WICKET_DETECTION`).
final class WicketDetection extends Equatable {
  const WicketDetection({
    required this.id,
    required this.matchId,
    required this.wicketFamily,
    required this.boundingBox,
    required this.targetPolygon,
    required this.objectConfidence,
    required this.temporalStability,
    required this.contextConfidence,
    required this.finalConfidence,
    required this.modelVersion,
    required this.detectedAt,
    this.sceneScanId,
    this.targetPlane,
    this.groundContactLine,
    this.isActive = true,
  });

  factory WicketDetection.fromJson(Map<String, Object?> json) => WicketDetection(
        id: asString(json['id']),
        matchId: asString(json['match_id']),
        sceneScanId: asStringOrNull(json['scene_scan_id']),
        wicketFamily: WicketFamily.fromWire(json['wicket_family']),
        boundingBox: asJsonMapOrNull(json['bounding_box']) ?? const <String, Object?>{},
        targetPolygon: asJsonListOrNull(json['target_polygon']) ?? const <Object?>[],
        targetPlane: asJsonMapOrNull(json['target_plane']),
        groundContactLine: asJsonMapOrNull(json['ground_contact_line']),
        objectConfidence: asDouble(json['object_confidence']),
        temporalStability: asDouble(json['temporal_stability']),
        contextConfidence: asDouble(json['context_confidence']),
        finalConfidence: asDouble(json['final_confidence']),
        isActive: asBool(json['is_active'], fallback: true),
        modelVersion: asString(json['model_version']),
        detectedAt: parseDateTime(json['detected_at']),
      );

  final String id;
  final String matchId;
  final String? sceneScanId;
  final WicketFamily wicketFamily;

  /// `{x, y, width, height}` normalised 0–1.
  final Map<String, Object?> boundingBox;

  /// List of `{x, y}` points (3–32).
  final List<Object?> targetPolygon;
  final Map<String, Object?>? targetPlane;
  final Map<String, Object?>? groundContactLine;
  final double objectConfidence;
  final double temporalStability;
  final double contextConfidence;
  final double finalConfidence;
  final bool isActive;
  final String modelVersion;
  final DateTime detectedAt;

  bool get isMock => modelVersion.startsWith('mock');

  /// The same detection marked as in use or retired (a new scan retires the older one).
  WicketDetection copyWith({bool? isActive}) => WicketDetection(
        id: id,
        matchId: matchId,
        sceneScanId: sceneScanId,
        wicketFamily: wicketFamily,
        boundingBox: boundingBox,
        targetPolygon: targetPolygon,
        targetPlane: targetPlane,
        groundContactLine: groundContactLine,
        objectConfidence: objectConfidence,
        temporalStability: temporalStability,
        contextConfidence: contextConfidence,
        finalConfidence: finalConfidence,
        isActive: isActive ?? this.isActive,
        modelVersion: modelVersion,
        detectedAt: detectedAt,
      );

  Map<String, Object?> toJson() => toSyncPayload();

  /// Exactly the keys of API_CONTRACT §5.3 `WICKET_DETECTION`.
  Map<String, Object?> toSyncPayload() => <String, Object?>{
        'id': id,
        'match_id': matchId,
        'scene_scan_id': sceneScanId,
        'wicket_family': wicketFamily.wire,
        'bounding_box': boundingBox,
        'target_polygon': targetPolygon,
        'target_plane': targetPlane,
        'ground_contact_line': groundContactLine,
        'object_confidence': objectConfidence,
        'temporal_stability': temporalStability,
        'context_confidence': contextConfidence,
        'final_confidence': finalConfidence,
        'is_active': isActive,
        'model_version': modelVersion,
        'detected_at': toIsoUtc(detectedAt),
      };

  @override
  List<Object?> get props => <Object?>[
        id,
        matchId,
        sceneScanId,
        wicketFamily,
        boundingBox,
        targetPolygon,
        targetPlane,
        groundContactLine,
        objectConfidence,
        temporalStability,
        contextConfidence,
        finalConfidence,
        isActive,
        modelVersion,
        detectedAt,
      ];
}
