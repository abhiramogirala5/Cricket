import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:gully_umpire/core/errors/app_exception.dart';
import 'package:gully_umpire/core/utils/app_log.dart';
import 'package:gully_umpire/data/session/session_models.dart';
import 'package:gully_umpire/domain/models/json_helpers.dart';

/// Persistent home of the signed-in session.
abstract interface class SessionStorage {
  Future<StoredSession?> read();
  Future<void> write(StoredSession session);
  Future<void> clear();
}

/// Keeps the session in the platform's secure storage (Keychain / Android Keystore).
final class SecureSessionStorage implements SessionStorage {
  SecureSessionStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const String _key = 'gully_umpire.session.v1';

  final FlutterSecureStorage _storage;

  @override
  Future<StoredSession?> read() async {
    try {
      final String? raw = await _storage.read(key: _key);
      if (raw == null || raw.isEmpty) {
        return null;
      }
      final Map<String, Object?>? json = asJsonMapOrNull(raw);
      return json == null ? null : StoredSession.fromJson(json);
    } on FormatException catch (error) {
      // A damaged entry is useless; dropping it means "signed out", which is safe.
      AppLog.warn('Stored session could not be read (${error.message}); clearing it.');
      await clear();
      return null;
    } on Object catch (error, stackTrace) {
      AppLog.error('Secure storage read failed', error: error, stackTrace: stackTrace);
      throw const LocalDataException('Secure storage is not available.');
    }
  }

  @override
  Future<void> write(StoredSession session) async {
    try {
      await _storage.write(key: _key, value: jsonEncode(session.toJson()));
    } on Object catch (error, stackTrace) {
      AppLog.error('Secure storage write failed', error: error, stackTrace: stackTrace);
      throw const LocalDataException('Secure storage is not available.');
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
    } on Object catch (error, stackTrace) {
      AppLog.error('Secure storage delete failed', error: error, stackTrace: stackTrace);
    }
  }
}

/// Session storage that lives only in memory (tests).
final class MemorySessionStorage implements SessionStorage {
  MemorySessionStorage([this._session]);

  StoredSession? _session;

  @override
  Future<StoredSession?> read() async => _session;

  @override
  Future<void> write(StoredSession session) async {
    _session = session;
  }

  @override
  Future<void> clear() async {
    _session = null;
  }
}
