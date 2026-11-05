import 'package:equatable/equatable.dart';
import 'package:gully_umpire/domain/decisions/decision_status.dart';
import 'package:gully_umpire/domain/decisions/delivery_decision_type.dart';
import 'package:gully_umpire/domain/models/enums.dart';
import 'package:gully_umpire/domain/models/json_helpers.dart';

/// A stored umpiring decision for one delivery (API entity `DELIVERY_DECISION`).
final class DecisionRecord extends Equatable {
  const DecisionRecord({
    required this.id,
    required this.deliveryId,
    required this.decisionType,
    required this.decisionStatus,
    required this.decisionSource,
    required this.createdAt,
    this.automatedResult,
    this.finalResult,
    this.confidence,
    this.evidence,
  });

  factory DecisionRecord.fromJson(Map<String, Object?> json) => DecisionRecord(
        id: asString(json['id']),
        deliveryId: asString(json['delivery_id']),
        decisionType: DeliveryDecisionType.fromWire(json['decision_type']),
        automatedResult: asStringOrNull(json['automated_result']),
        finalResult: asStringOrNull(json['final_result']),
        confidence: asDoubleOrNull(json['confidence']),
        decisionStatus: DecisionStatus.fromWire(json['decision_status']),
        decisionSource: DecisionSource.fromWire(json['decision_source']),
        evidence: asJsonMapOrNull(json['evidence']),
        createdAt: parseDateTime(json['created_at']),
      );

  final String id;
  final String deliveryId;
  final DeliveryDecisionType decisionType;
  final String? automatedResult;
  final String? finalResult;
  final double? confidence;
  final DecisionStatus decisionStatus;
  final DecisionSource decisionSource;
  final Map<String, Object?>? evidence;
  final DateTime createdAt;

  /// The umpire's call if one was made, otherwise what the AI suggested.
  String? get effectiveResult => finalResult ?? automatedResult;

  Map<String, Object?> toJson() => toSyncPayload();

  /// Exactly the keys of API_CONTRACT §5.3 `DELIVERY_DECISION`.
  Map<String, Object?> toSyncPayload() => <String, Object?>{
        'id': id,
        'delivery_id': deliveryId,
        'decision_type': decisionType.wire,
        'automated_result': automatedResult,
        'final_result': finalResult,
        'confidence': confidence,
        'decision_status': decisionStatus.wire,
        'decision_source': decisionSource.wire,
        'evidence': evidence,
        'created_at': toIsoUtc(createdAt),
      };

  @override
  List<Object?> get props => <Object?>[
        id,
        deliveryId,
        decisionType,
        automatedResult,
        finalResult,
        confidence,
        decisionStatus,
        decisionSource,
        evidence,
        createdAt,
      ];
}
