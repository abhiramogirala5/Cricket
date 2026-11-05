import 'package:equatable/equatable.dart';
import 'package:gully_umpire/domain/models/enums.dart';
import 'package:gully_umpire/domain/models/json_helpers.dart';

/// One ball bowled (API entity `DELIVERY`).
///
/// `deliverySequence`, `overNumber` and `legalBallNumber` are derived by
/// `ScoreEngine` (and recomputed by the server). Voided deliveries are kept, never deleted.
final class Delivery extends Equatable {
  const Delivery({
    required this.id,
    required this.inningsId,
    required this.deliverySequence,
    required this.overNumber,
    required this.bowlerId,
    required this.strikerId,
    required this.createdAt,
    this.legalBallNumber,
    this.nonStrikerId,
    this.runsBat = 0,
    this.runsExtras = 0,
    this.isWide = false,
    this.isNoBall = false,
    this.isBye = false,
    this.isLegBye = false,
    this.isWicket = false,
    this.dismissalType,
    this.dismissedPlayerId,
    this.wicketDetectionId,
    this.speedKmph,
    this.speedConfidence,
    this.ballTrackingConfidence,
    this.poseTrackingConfidence,
    this.wicketTrackingConfidence,
    this.isVoided = false,
    this.voidedAt,
    this.voidReason,
  });

  factory Delivery.fromJson(Map<String, Object?> json) => Delivery(
        id: asString(json['id']),
        inningsId: asString(json['innings_id']),
        wicketDetectionId: asStringOrNull(json['wicket_detection_id']),
        deliverySequence: asInt(json['delivery_sequence']),
        overNumber: asInt(json['over_number']),
        legalBallNumber: asIntOrNull(json['legal_ball_number']),
        bowlerId: asString(json['bowler_id']),
        strikerId: asString(json['striker_id']),
        nonStrikerId: asStringOrNull(json['non_striker_id']),
        runsBat: asInt(json['runs_bat']),
        runsExtras: asInt(json['runs_extras']),
        isWide: asBool(json['is_wide']),
        isNoBall: asBool(json['is_no_ball']),
        isBye: asBool(json['is_bye']),
        isLegBye: asBool(json['is_leg_bye']),
        isWicket: asBool(json['is_wicket']),
        dismissalType: DismissalType.fromWireOrNull(json['dismissal_type']),
        dismissedPlayerId: asStringOrNull(json['dismissed_player_id']),
        speedKmph: asDoubleOrNull(json['speed_kmph']),
        speedConfidence: asDoubleOrNull(json['speed_confidence']),
        ballTrackingConfidence: asDoubleOrNull(json['ball_tracking_confidence']),
        poseTrackingConfidence: asDoubleOrNull(json['pose_tracking_confidence']),
        wicketTrackingConfidence: asDoubleOrNull(json['wicket_tracking_confidence']),
        isVoided: asBool(json['is_voided']),
        voidedAt: parseDateTimeOrNull(json['voided_at']),
        voidReason: asStringOrNull(json['void_reason']),
        createdAt: parseDateTime(json['created_at']),
      );

  final String id;
  final String inningsId;
  final String? wicketDetectionId;
  final int deliverySequence;
  final int overNumber;
  final int? legalBallNumber;
  final String bowlerId;
  final String strikerId;
  final String? nonStrikerId;
  final int runsBat;
  final int runsExtras;
  final bool isWide;
  final bool isNoBall;
  final bool isBye;
  final bool isLegBye;
  final bool isWicket;
  final DismissalType? dismissalType;
  final String? dismissedPlayerId;
  final double? speedKmph;
  final double? speedConfidence;
  final double? ballTrackingConfidence;
  final double? poseTrackingConfidence;
  final double? wicketTrackingConfidence;
  final bool isVoided;
  final DateTime? voidedAt;
  final String? voidReason;
  final DateTime createdAt;

  /// A legal ball counts towards the over; wides and no-balls do not.
  bool get isLegal => !isWide && !isNoBall;

  /// 1 for wides and no-balls, otherwise 0.
  int get penaltyRuns => (isWide || isNoBall) ? 1 : 0;

  int get totalRuns => runsBat + runsExtras;

  Delivery copyWith({bool? isVoided, DateTime? voidedAt, String? voidReason}) => Delivery(
        id: id,
        inningsId: inningsId,
        wicketDetectionId: wicketDetectionId,
        deliverySequence: deliverySequence,
        overNumber: overNumber,
        legalBallNumber: legalBallNumber,
        bowlerId: bowlerId,
        strikerId: strikerId,
        nonStrikerId: nonStrikerId,
        runsBat: runsBat,
        runsExtras: runsExtras,
        isWide: isWide,
        isNoBall: isNoBall,
        isBye: isBye,
        isLegBye: isLegBye,
        isWicket: isWicket,
        dismissalType: dismissalType,
        dismissedPlayerId: dismissedPlayerId,
        speedKmph: speedKmph,
        speedConfidence: speedConfidence,
        ballTrackingConfidence: ballTrackingConfidence,
        poseTrackingConfidence: poseTrackingConfidence,
        wicketTrackingConfidence: wicketTrackingConfidence,
        isVoided: isVoided ?? this.isVoided,
        voidedAt: voidedAt ?? this.voidedAt,
        voidReason: voidReason ?? this.voidReason,
        createdAt: createdAt,
      );

  /// Full row / API read shape (payload fields + derived + void fields).
  Map<String, Object?> toJson() => <String, Object?>{
        ...toSyncPayload(),
        'delivery_sequence': deliverySequence,
        'over_number': overNumber,
        'legal_ball_number': legalBallNumber,
        'is_voided': isVoided,
        'voided_at': toIsoUtc(voidedAt),
        'void_reason': voidReason,
      };

  /// Exactly the keys of API_CONTRACT §5.3 `DELIVERY` (UPSERT). The server derives the rest.
  Map<String, Object?> toSyncPayload() => <String, Object?>{
        'id': id,
        'innings_id': inningsId,
        'bowler_id': bowlerId,
        'striker_id': strikerId,
        'non_striker_id': nonStrikerId,
        'runs_bat': runsBat,
        'runs_extras': runsExtras,
        'is_wide': isWide,
        'is_no_ball': isNoBall,
        'is_bye': isBye,
        'is_leg_bye': isLegBye,
        'is_wicket': isWicket,
        'dismissal_type': dismissalType?.wire,
        'dismissed_player_id': dismissedPlayerId,
        'wicket_detection_id': wicketDetectionId,
        'speed_kmph': speedKmph,
        'speed_confidence': speedConfidence,
        'ball_tracking_confidence': ballTrackingConfidence,
        'pose_tracking_confidence': poseTrackingConfidence,
        'wicket_tracking_confidence': wicketTrackingConfidence,
        'created_at': toIsoUtc(createdAt),
      };

  /// Payload of a `VOID` event (API_CONTRACT §5.3 `DELIVERY`).
  Map<String, Object?> toVoidPayload() =>
      <String, Object?>{'id': id, 'void_reason': voidReason};

  @override
  List<Object?> get props => <Object?>[
        id,
        inningsId,
        wicketDetectionId,
        deliverySequence,
        overNumber,
        legalBallNumber,
        bowlerId,
        strikerId,
        nonStrikerId,
        runsBat,
        runsExtras,
        isWide,
        isNoBall,
        isBye,
        isLegBye,
        isWicket,
        dismissalType,
        dismissedPlayerId,
        speedKmph,
        speedConfidence,
        ballTrackingConfidence,
        poseTrackingConfidence,
        wicketTrackingConfidence,
        isVoided,
        voidedAt,
        voidReason,
        createdAt,
      ];
}
