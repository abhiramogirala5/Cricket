import 'dart:async';

import 'package:gully_umpire/data/session/session_models.dart';
import 'package:gully_umpire/data/session/session_storage.dart';
import 'package:gully_umpire/domain/models/user_profile.dart';

/// Holds the current session in memory (so requests do not wait for secure storage) and keeps
/// the stored copy in step.
final class SessionKeeper {
  SessionKeeper(this._storage);

  final SessionStorage _storage;
  final StreamController<void> _expired = StreamController<void>.broadcast();

  StoredSession? _current;
  bool _loaded = false;

  /// Emits when the server refused the refresh token and the user has to sign in again.
  Stream<void> get expired => _expired.stream;

  StoredSession? get current => _current;

  /// Reads the stored session once (call this at start-up).
  Future<StoredSession?> load() async {
    if (!_loaded) {
      _current = await _storage.read();
      _loaded = true;
    }
    return _current;
  }

  Future<void> save(StoredSession session) async {
    _current = session;
    _loaded = true;
    await _storage.write(session);
  }

  Future<void> updateTokens(AuthTokens tokens) async {
    final StoredSession? existing = _current;
    if (existing == null) {
      return;
    }
    await save(existing.copyWith(tokens: tokens));
  }

  Future<void> updateUser(UserProfile user) async {
    final StoredSession? existing = _current;
    if (existing == null) {
      return;
    }
    await save(existing.copyWith(user: user));
  }

  /// Forgets the session (sign-out).
  Future<void> clear() async {
    _current = null;
    _loaded = true;
    await _storage.clear();
  }

  /// Forgets the session because the server no longer accepts it.
  Future<void> expire() async {
    if (_current == null) {
      return;
    }
    await clear();
    if (!_expired.isClosed) {
      _expired.add(null);
    }
  }

  Future<void> dispose() => _expired.close();
}
