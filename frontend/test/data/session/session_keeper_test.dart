import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/data/session/session_keeper.dart';
import 'package:gully_umpire/data/session/session_models.dart';
import 'package:gully_umpire/data/session/session_storage.dart';
import 'package:gully_umpire/domain/models/user_profile.dart';

import '../../support/model_fixtures.dart';

final UserProfile user = UserProfile(
  id: 'user-1',
  email: 'asha@example.com',
  displayName: 'Asha Rao',
  createdAt: t0,
);

const AuthTokens tokens = AuthTokens(accessToken: 'access-1', refreshToken: 'refresh-1');

void main() {
  group('StoredSession', () {
    test('survives a JSON round trip', () {
      final StoredSession session = StoredSession(tokens: tokens, user: user);

      final StoredSession copy = StoredSession.fromJson(
        jsonDecode(jsonEncode(session.toJson())) as Map<String, Object?>,
      );

      expect(copy, session);
    });

    test('refuses a stored entry that has no user', () {
      expect(
        () => StoredSession.fromJson(const <String, Object?>{
          'access_token': 'a',
          'refresh_token': 'r',
        }),
        throwsFormatException,
      );
    });

    test('copyWith swaps only the part that is given', () {
      final StoredSession session = StoredSession(tokens: tokens, user: user);
      const AuthTokens fresh = AuthTokens(accessToken: 'access-2', refreshToken: 'refresh-2');

      expect(session.copyWith(tokens: fresh).user, user);
      expect(session.copyWith(tokens: fresh).tokens, fresh);
      expect(session.copyWith().tokens, tokens);
    });
  });

  group('SessionKeeper', () {
    late MemorySessionStorage storage;
    late SessionKeeper keeper;

    setUp(() {
      storage = MemorySessionStorage();
      keeper = SessionKeeper(storage);
    });

    tearDown(() async {
      await keeper.dispose();
    });

    test('starts signed out', () async {
      expect(keeper.current, isNull);
      expect(await keeper.load(), isNull);
    });

    test('load picks up a session saved by an earlier launch', () async {
      final StoredSession saved = StoredSession(tokens: tokens, user: user);
      final SessionKeeper restarted = SessionKeeper(MemorySessionStorage(saved));

      expect(await restarted.load(), saved);
      expect(restarted.current, saved);
      await restarted.dispose();
    });

    test('save keeps the session in memory and in storage', () async {
      final StoredSession session = StoredSession(tokens: tokens, user: user);

      await keeper.save(session);

      expect(keeper.current, session);
      expect(await storage.read(), session);
    });

    test('updateTokens replaces the tokens and keeps the user', () async {
      await keeper.save(StoredSession(tokens: tokens, user: user));
      const AuthTokens fresh = AuthTokens(accessToken: 'access-2', refreshToken: 'refresh-2');

      await keeper.updateTokens(fresh);

      expect(keeper.current!.tokens, fresh);
      expect(keeper.current!.user, user);
      expect((await storage.read())!.tokens, fresh);
    });

    test('updateUser replaces the user and keeps the tokens', () async {
      await keeper.save(StoredSession(tokens: tokens, user: user));
      final UserProfile renamed = UserProfile(
        id: user.id,
        email: user.email,
        displayName: 'Asha R',
        createdAt: user.createdAt,
      );

      await keeper.updateUser(renamed);

      expect(keeper.current!.user.displayName, 'Asha R');
      expect(keeper.current!.tokens, tokens);
    });

    test('updates are ignored when nobody is signed in', () async {
      await keeper.updateTokens(tokens);
      await keeper.updateUser(user);

      expect(keeper.current, isNull);
      expect(await storage.read(), isNull);
    });

    test('clear signs out without announcing an expiry', () async {
      await keeper.save(StoredSession(tokens: tokens, user: user));
      int expiries = 0;
      final sub = keeper.expired.listen((_) => expiries++);

      await keeper.clear();
      await Future<void>.delayed(Duration.zero);

      expect(keeper.current, isNull);
      expect(await storage.read(), isNull);
      expect(expiries, 0);
      await sub.cancel();
    });

    test('expire signs out and announces it exactly once', () async {
      await keeper.save(StoredSession(tokens: tokens, user: user));
      int expiries = 0;
      final sub = keeper.expired.listen((_) => expiries++);

      await keeper.expire();
      await keeper.expire();
      await Future<void>.delayed(Duration.zero);

      expect(keeper.current, isNull);
      expect(await storage.read(), isNull);
      expect(expiries, 1);
      await sub.cancel();
    });

    test('load does not read storage again once the session has been saved', () async {
      await keeper.save(StoredSession(tokens: tokens, user: user));
      await storage.clear();

      expect(await keeper.load(), isNotNull);
    });
  });
}
