import 'package:equatable/equatable.dart';
import 'package:gully_umpire/domain/models/json_helpers.dart';

final class Team extends Equatable {
  const Team({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Team.fromJson(Map<String, Object?> json) => Team(
        id: asString(json['id']),
        name: asString(json['name']),
        createdAt: parseDateTime(json['created_at']),
        updatedAt: parseDateTime(json['updated_at']),
      );

  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;

  Team copyWith({String? name, DateTime? updatedAt}) => Team(
        id: id,
        name: name ?? this.name,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'created_at': toIsoUtc(createdAt),
        'updated_at': toIsoUtc(updatedAt),
      };

  /// Exactly the keys of API_CONTRACT §5.3 `TEAM`.
  Map<String, Object?> toSyncPayload() => <String, Object?>{'id': id, 'name': name};

  @override
  List<Object?> get props => <Object?>[id, name, createdAt, updatedAt];
}
