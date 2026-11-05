import 'package:equatable/equatable.dart';
import 'package:gully_umpire/domain/models/enums.dart';
import 'package:gully_umpire/domain/models/json_helpers.dart';

/// A roster entry owned by the user. Players do not need an app account.
final class Player extends Equatable {
  const Player({
    required this.id,
    required this.displayName,
    required this.createdAt,
    required this.updatedAt,
    this.battingHand = BattingHand.unknown,
    this.declaredHeightCm,
  });

  factory Player.fromJson(Map<String, Object?> json) => Player(
        id: asString(json['id']),
        displayName: asString(json['display_name']),
        battingHand: BattingHand.fromWire(json['batting_hand']),
        declaredHeightCm: asIntOrNull(json['declared_height_cm']),
        createdAt: parseDateTime(json['created_at']),
        updatedAt: parseDateTime(json['updated_at']),
      );

  final String id;
  final String displayName;
  final BattingHand battingHand;
  final int? declaredHeightCm;
  final DateTime createdAt;
  final DateTime updatedAt;

  Player copyWith({
    String? displayName,
    BattingHand? battingHand,
    int? declaredHeightCm,
    DateTime? updatedAt,
  }) =>
      Player(
        id: id,
        displayName: displayName ?? this.displayName,
        battingHand: battingHand ?? this.battingHand,
        declaredHeightCm: declaredHeightCm ?? this.declaredHeightCm,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'display_name': displayName,
        'batting_hand': battingHand.wire,
        'declared_height_cm': declaredHeightCm,
        'created_at': toIsoUtc(createdAt),
        'updated_at': toIsoUtc(updatedAt),
      };

  /// Exactly the keys of API_CONTRACT §5.3 `PLAYER`.
  Map<String, Object?> toSyncPayload() => <String, Object?>{
        'id': id,
        'display_name': displayName,
        'batting_hand': battingHand.wire,
        'declared_height_cm': declaredHeightCm,
      };

  @override
  List<Object?> get props =>
      <Object?>[id, displayName, battingHand, declaredHeightCm, createdAt, updatedAt];
}
