import 'package:equatable/equatable.dart';
import 'package:gully_umpire/domain/models/json_helpers.dart';
import 'package:gully_umpire/domain/models/user_profile.dart';

/// The access and refresh token of a signed-in user (API `TokenPair`).
final class AuthTokens extends Equatable {
  const AuthTokens({required this.accessToken, required this.refreshToken});

  factory AuthTokens.fromJson(Map<String, Object?> json) => AuthTokens(
        accessToken: asString(json['access_token']),
        refreshToken: asString(json['refresh_token']),
      );

  final String accessToken;
  final String refreshToken;

  Map<String, Object?> toJson() => <String, Object?>{
        'access_token': accessToken,
        'refresh_token': refreshToken,
      };

  @override
  List<Object?> get props => <Object?>[accessToken, refreshToken];
}

/// What is kept in secure storage between app launches.
final class StoredSession extends Equatable {
  const StoredSession({required this.tokens, required this.user});

  factory StoredSession.fromJson(Map<String, Object?> json) {
    final Map<String, Object?>? user = asJsonMapOrNull(json['user']);
    if (user == null) {
      throw const FormatException('Stored session has no user');
    }
    return StoredSession(
      tokens: AuthTokens.fromJson(json),
      user: UserProfile.fromJson(user),
    );
  }

  final AuthTokens tokens;
  final UserProfile user;

  StoredSession copyWith({AuthTokens? tokens, UserProfile? user}) =>
      StoredSession(tokens: tokens ?? this.tokens, user: user ?? this.user);

  Map<String, Object?> toJson() => <String, Object?>{
        ...tokens.toJson(),
        'user': user.toJson(),
      };

  @override
  List<Object?> get props => <Object?>[tokens, user];
}
