import 'package:equatable/equatable.dart';
import 'package:gully_umpire/domain/models/json_helpers.dart';

/// The signed-in account (API `UserRead`).
final class UserProfile extends Equatable {
  const UserProfile({
    required this.id,
    required this.email,
    required this.displayName,
    required this.createdAt,
    this.phone,
    this.avatarUrl,
  });

  factory UserProfile.fromJson(Map<String, Object?> json) => UserProfile(
        id: asString(json['id']),
        email: asString(json['email']),
        displayName: asString(json['display_name']),
        phone: asStringOrNull(json['phone']),
        avatarUrl: asStringOrNull(json['avatar_url']),
        createdAt: parseDateTime(json['created_at']),
      );

  final String id;
  final String email;
  final String displayName;
  final String? phone;
  final String? avatarUrl;
  final DateTime createdAt;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'email': email,
        'display_name': displayName,
        'phone': phone,
        'avatar_url': avatarUrl,
        'created_at': toIsoUtc(createdAt),
      };

  /// First letters of the name, for avatar circles (`Asha Rao` -> `AR`).
  String get initials {
    final List<String> parts =
        displayName.trim().split(RegExp(r'\s+')).where((String p) => p.isNotEmpty).toList();
    if (parts.isEmpty) {
      return '?';
    }
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  @override
  List<Object?> get props => <Object?>[id, email, displayName, phone, avatarUrl, createdAt];
}
