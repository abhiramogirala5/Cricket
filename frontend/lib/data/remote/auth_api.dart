import 'package:equatable/equatable.dart';
import 'package:gully_umpire/data/remote/api_client.dart';
import 'package:gully_umpire/data/session/session_models.dart';
import 'package:gully_umpire/domain/models/json_helpers.dart';
import 'package:gully_umpire/domain/models/user_profile.dart';

/// The `AuthResponse` of register and login.
final class AuthResult extends Equatable {
  const AuthResult({required this.user, required this.tokens});

  factory AuthResult.fromJson(Map<String, Object?> json) {
    final Map<String, Object?>? user = asJsonMapOrNull(json['user']);
    final Map<String, Object?>? tokens = asJsonMapOrNull(json['tokens']);
    if (user == null || tokens == null) {
      throw const FormatException('Auth response is missing the user or the tokens');
    }
    return AuthResult(user: UserProfile.fromJson(user), tokens: AuthTokens.fromJson(tokens));
  }

  final UserProfile user;
  final AuthTokens tokens;

  @override
  List<Object?> get props => <Object?>[user, tokens];
}

/// `/auth/*` and `/users/me` (docs/API_CONTRACT.md §3).
final class AccountApi {
  const AccountApi(this._client);

  final ApiClient _client;

  Future<AuthResult> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final Map<String, Object?> json = await _client.sendForMap(
      'POST',
      '/auth/register',
      auth: false,
      body: <String, Object?>{
        'email': email,
        'password': password,
        'display_name': displayName,
      },
    );
    return AuthResult.fromJson(json);
  }

  Future<AuthResult> login({required String email, required String password}) async {
    final Map<String, Object?> json = await _client.sendForMap(
      'POST',
      '/auth/login',
      auth: false,
      body: <String, Object?>{'email': email, 'password': password},
    );
    return AuthResult.fromJson(json);
  }

  /// Revokes the refresh token on the server (the call is idempotent).
  Future<void> logout(String refreshToken) async {
    await _client.send(
      'POST',
      '/auth/logout',
      auth: false,
      body: <String, Object?>{'refresh_token': refreshToken},
    );
  }

  Future<UserProfile> me() async =>
      UserProfile.fromJson(await _client.sendForMap('GET', '/users/me'));

  Future<UserProfile> updateMe({String? displayName, String? phone, bool clearPhone = false}) async {
    final Map<String, Object?> body = <String, Object?>{};
    if (displayName != null) {
      body['display_name'] = displayName;
    }
    if (clearPhone) {
      body['phone'] = null;
    } else if (phone != null) {
      body['phone'] = phone;
    }
    return UserProfile.fromJson(await _client.sendForMap('PATCH', '/users/me', body: body));
  }

  /// Deletes the account and all its data on the server.
  Future<void> deleteMe({required String password}) async {
    await _client.send('DELETE', '/users/me', body: <String, Object?>{'password': password});
  }
}
