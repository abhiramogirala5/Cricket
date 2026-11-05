import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/core/errors/app_exception.dart';
import 'package:gully_umpire/data/local/local_database.dart';
import 'package:gully_umpire/data/local/local_store.dart';
import 'package:gully_umpire/data/remote/api_client.dart';
import 'package:gully_umpire/data/session/active_session.dart';
import 'package:gully_umpire/data/session/session_keeper.dart';
import 'package:gully_umpire/data/session/session_manager.dart';
import 'package:gully_umpire/data/session/session_models.dart';
import 'package:gully_umpire/data/session/session_storage.dart';
import 'package:gully_umpire/data/sync/restore_service.dart';
import 'package:gully_umpire/domain/models/models.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/data_test_support.dart';
import '../../support/model_fixtures.dart' show t0;
import '../remote/scripted_adapter.dart';

/// A fake backend: answers the endpoints the session manager talks to.
final class FakeBackend {
  FakeBackend() {
    adapter = ScriptedAdapter(handle);
  }

  late final ScriptedAdapter adapter;
  String userId = 'user-1';
  String password = 'correct-horse';
  bool offline = false;
  bool refuseTokens = false;
  List<Map<String, Object?>> teams = <Map<String, Object?>>[];

  int count(String method, String path) => adapter.requests
      .where((RequestOptions r) => r.method == method && r.uri.path == '/api/v1$path')
      .length;

  Future<ResponseBody> handle(RequestOptions options) async {
    if (offline) {
      throw DioException.connectionError(requestOptions: options, reason: 'offline');
    }
    final String path = options.uri.path.replaceFirst('/api/v1', '');
    final String key = '${options.method} $path';
    if (refuseTokens && !path.startsWith('/auth/login') && !path.startsWith('/auth/register')) {
      return jsonReply(401, errorEnvelope('INVALID_TOKEN', 'bad token'));
    }
    switch (key) {
      case 'POST /auth/login':
      case 'POST /auth/register':
        return jsonReply(key.endsWith('register') ? 201 : 200, <String, Object?>{
          'user': userJson(id: userId),
          'tokens': tokenPair('access-$userId', 'refresh-$userId'),
        });
      case 'POST /auth/logout':
        return emptyReply(204);
      case 'GET /users/me':
        return jsonReply(200, userJson(id: userId));
      case 'PATCH /users/me':
        return jsonReply(200, <String, Object?>{
          ...userJson(id: userId),
          'display_name': 'Asha Renamed',
        });
      case 'DELETE /users/me':
        final Object? sent = options.data;
        if (sent is String && sent.contains(password)) {
          return emptyReply(204);
        }
        return jsonReply(403, errorEnvelope('PASSWORD_INCORRECT', 'wrong password'));
      case 'POST /sync/push':
        final Map<String, Object?> body = adapter.sentJson(adapter.requests.length - 1);
        final List<Object?> events = body['events']! as List<Object?>;
        return jsonReply(200, <String, Object?>{
          'results': events
              .map<Map<String, Object?>>(
                (Object? e) => <String, Object?>{
                  'event_id': (e! as Map<Object?, Object?>)['event_id'],
                  'status': 'APPLIED',
                },
              )
              .toList(),
        });
      case 'GET /teams':
        return jsonReply(200, <String, Object?>{
          'items': teams,
          'total': teams.length,
          'limit': 100,
          'offset': 0,
        });
      case 'GET /players':
      case 'GET /matches':
        return jsonReply(200, <String, Object?>{
          'items': <Object?>[],
          'total': 0,
          'limit': 100,
          'offset': 0,
        });
    }
    return jsonReply(404, errorEnvelope('NOT_FOUND', 'no route for $key'));
  }
}

/// Waits (up to a few seconds) until [condition] holds. Background sync runs on its own timers.
Future<void> waitUntil(Future<bool> Function() condition) async {
  final DateTime deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!await condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('The condition did not become true in time.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  late Directory directory;
  late FakeBackend backend;
  late SessionKeeper keeper;
  late MemorySessionStorage storage;
  late ApiClient client;
  late SessionManager manager;
  late List<String> opened;

  Future<LocalStore> openFile(String userId) async {
    opened.add(userId);
    final database = await LocalDatabase.open(
      factory: databaseFactoryFfi,
      path: p.join(directory.path, LocalDatabase.fileNameFor(userId)),
    );
    return LocalStore(database);
  }

  Future<void> removeFile(String userId) =>
      databaseFactoryFfi.deleteDatabase(p.join(directory.path, LocalDatabase.fileNameFor(userId)));

  SessionManager makeManager({ApiClient? withClient, bool local = false}) => SessionManager(
        keeper: keeper,
        openStore: openFile,
        removeStore: removeFile,
        clock: FakeClock(),
        ids: SequenceIds(),
        client: local ? null : (withClient ?? client),
        networkGrace: const Duration(seconds: 2),
      );

  bool databaseExists(String userId) =>
      File(p.join(directory.path, LocalDatabase.fileNameFor(userId))).existsSync();

  setUpAll(sqfliteFfiInit);

  setUp(() {
    directory = Directory.systemTemp.createTempSync('gully_session_test_');
    opened = <String>[];
    backend = FakeBackend();
    storage = MemorySessionStorage();
    keeper = SessionKeeper(storage);
    client = ApiClient(
      baseUrl: 'http://test.local/api/v1',
      session: keeper,
      ids: SequenceIds(),
      dio: Dio()..httpClientAdapter = backend.adapter,
    );
    manager = makeManager();
  });

  tearDown(() async {
    await manager.dispose();
    client.close();
    await keeper.dispose();
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });

  group('start', () {
    test('with nobody signed in the app starts signed out and opens no database', () async {
      final SessionView view = await manager.start();

      expect(view.isSignedIn, isFalse);
      expect(opened, isEmpty);
    });

    test('a stored session opens straight away without asking the server first', () async {
      await keeper.save(StoredSession(
        tokens: const AuthTokens(accessToken: 'a', refreshToken: 'r'),
        user: UserProfile(
          id: 'user-1',
          email: 'asha@example.com',
          displayName: 'Stored name',
          createdAt: t0,
        ),
      ));
      backend.offline = true;

      final SessionView view = await manager.start();

      expect(view.isSignedIn, isTrue);
      expect(view.user!.displayName, 'Stored name');
      expect(view.active!.userId, 'user-1');
      expect(view.active!.isLocal, isFalse);
      expect(view.active!.syncs, isTrue);
      await manager.whenBackgroundSettled();
      expect(manager.view.active, isNotNull, reason: 'being offline never signs the user out');
    });

    test('the profile is refreshed from the server in the background', () async {
      await keeper.save(StoredSession(
        tokens: const AuthTokens(accessToken: 'a', refreshToken: 'r'),
        user: UserProfile(
          id: 'user-1',
          email: 'asha@example.com',
          displayName: 'Old name',
          createdAt: t0,
        ),
      ));

      await manager.start();
      await manager.whenBackgroundSettled();

      expect(backend.count('GET', '/users/me'), 1);
      expect(manager.view.user!.displayName, 'Asha Rao');
      expect(keeper.current!.user.displayName, 'Asha Rao');
    });

    test('local-only mode opens the single local database and never calls a server', () async {
      final SessionManager local = makeManager(local: true);

      final SessionView view = await local.start();

      expect(local.isLocalMode, isTrue);
      expect(view.isSignedIn, isTrue);
      expect(view.active!.isLocal, isTrue);
      expect(view.active!.userId, ActiveSession.localUserId);
      expect(view.active!.syncEngine, isNull);
      expect(view.user, isNull);
      expect(backend.adapter.requests, isEmpty);

      await view.active!.roster.createPlayer(displayName: 'Asha');
      expect(await view.active!.store.pendingOutboxCount(), 0, reason: 'nothing to sync');
      await local.dispose();
    });

    test('account operations are refused in local-only mode', () async {
      final SessionManager local = makeManager(local: true);
      await local.start();

      await expectLater(
        local.login(email: 'asha@example.com', password: 'whatever'),
        throwsA(isA<StateError>()),
      );
      await local.dispose();
    });
  });

  group('signing in', () {
    test('login stores the session and opens that account\'s database', () async {
      await manager.start();

      final SessionView view =
          await manager.login(email: ' asha@example.com ', password: 'correct-horse');

      expect(view.isSignedIn, isTrue);
      expect(view.user!.id, 'user-1');
      expect(opened, <String>['user-1']);
      expect(databaseExists('user-1'), isTrue);
      expect(keeper.current!.tokens.accessToken, 'access-user-1');
      expect(await storage.read(), isNotNull);
      expect(backend.adapter.sentJson(0)['email'], 'asha@example.com', reason: 'trimmed');
      await manager.whenBackgroundSettled();
    });

    test('a failed login changes nothing', () async {
      backend.refuseTokens = false;
      backend.adapter.onRequest = (RequestOptions options) async =>
          jsonReply(401, errorEnvelope('INVALID_CREDENTIALS', 'nope'));
      await manager.start();

      await expectLater(
        manager.login(email: 'asha@example.com', password: 'wrong'),
        throwsA(isA<ApiException>().having((ApiException e) => e.code, 'code', 'INVALID_CREDENTIALS')),
      );

      expect(manager.view.isSignedIn, isFalse);
      expect(keeper.current, isNull);
      expect(opened, isEmpty);
    });

    test('register signs the new account in', () async {
      backend.userId = 'user-2';
      await manager.start();

      final SessionView view = await manager.register(
        email: 'new@example.com',
        password: 'a-long-password',
        displayName: '  Asha  ',
      );

      expect(view.active!.userId, 'user-2');
      expect(backend.adapter.sentJson(0)['display_name'], 'Asha');
      await manager.whenBackgroundSettled();
    });

    test('a new phone gets its matches, teams and players from the server once', () async {
      backend.teams = <Map<String, Object?>>[
        <String, Object?>{
          'id': 'team-a',
          'name': 'Reds',
          'created_at': '2026-10-08T07:33:00Z',
          'updated_at': '2026-10-08T07:33:00Z',
        },
      ];
      await manager.start();

      final SessionView view = await manager.login(email: 'a@b.com', password: 'correct-horse');
      await manager.whenBackgroundSettled();

      expect((await view.active!.store.teams()).single.name, 'Reds');
      expect(await view.active!.store.meta(RestoreService.restoredMetaKey), isNotNull);
      expect(backend.count('GET', '/teams'), 1);
    });

    test('signing in as a different account closes the previous one', () async {
      await manager.start();
      final SessionView first = await manager.login(email: 'a@b.com', password: 'correct-horse');
      await manager.whenBackgroundSettled();
      backend.userId = 'user-2';

      final SessionView second = await manager.login(email: 'c@d.com', password: 'correct-horse');
      await manager.whenBackgroundSettled();

      expect(second.active!.userId, 'user-2');
      expect(first.active!.store.isClosed, isTrue);
      expect(opened, <String>['user-1', 'user-2']);
    });
  });

  group('signing out', () {
    test('sends what is waiting, revokes the token and keeps the data on the phone', () async {
      await manager.start();
      final SessionView view = await manager.login(email: 'a@b.com', password: 'correct-horse');
      await manager.whenBackgroundSettled();
      final Player saved = await view.active!.roster.createPlayer(displayName: 'Asha');
      backend.adapter.requests.clear();

      await manager.signOut();

      expect(backend.count('POST', '/sync/push'), 1, reason: 'one last attempt to send');
      expect(backend.count('POST', '/auth/logout'), 1);
      expect(manager.view.isSignedIn, isFalse);
      expect(keeper.current, isNull);
      expect(await storage.read(), isNull);
      expect(view.active!.store.isClosed, isTrue);
      expect(databaseExists('user-1'), isTrue, reason: 'signing out must not delete matches');

      // Signing in again brings the same data back.
      final SessionView again = await manager.login(email: 'a@b.com', password: 'correct-horse');
      await manager.whenBackgroundSettled();
      expect((await again.active!.roster.players()).single.id, saved.id);
    });

    test('works when the phone is offline and unsent changes stay queued', () async {
      await manager.start();
      final SessionView view = await manager.login(email: 'a@b.com', password: 'correct-horse');
      await manager.whenBackgroundSettled();
      backend.offline = true;
      await view.active!.roster.createPlayer(displayName: 'Asha');

      await manager.signOut();

      expect(manager.view.isSignedIn, isFalse);
      expect(keeper.current, isNull);

      backend.offline = false;
      final SessionView again = await manager.login(email: 'a@b.com', password: 'correct-horse');
      await manager.whenBackgroundSettled();
      // The unsent change survived and goes out after the second sign-in.
      await waitUntil(() async => await again.active!.store.pendingOutboxCount() == 0);
      expect(backend.count('POST', '/sync/push'), greaterThanOrEqualTo(1));
    });
  });

  group('deleting the account', () {
    test('removes the server account, the session and the local database', () async {
      await manager.start();
      await manager.login(email: 'a@b.com', password: 'correct-horse');
      await manager.whenBackgroundSettled();

      await manager.deleteAccount(password: 'correct-horse');

      expect(manager.view.isSignedIn, isFalse);
      expect(keeper.current, isNull);
      expect(databaseExists('user-1'), isFalse);
    });

    test('a wrong password deletes nothing', () async {
      await manager.start();
      final SessionView view = await manager.login(email: 'a@b.com', password: 'correct-horse');
      await manager.whenBackgroundSettled();

      await expectLater(
        manager.deleteAccount(password: 'wrong'),
        throwsA(isA<ApiException>().having((ApiException e) => e.code, 'code', 'PASSWORD_INCORRECT')),
      );

      expect(manager.view.isSignedIn, isTrue);
      expect(keeper.current, isNotNull);
      expect(view.active!.store.isClosed, isFalse);
      expect(databaseExists('user-1'), isTrue);
    });

    test('nothing is deleted when the server cannot be reached', () async {
      await manager.start();
      await manager.login(email: 'a@b.com', password: 'correct-horse');
      await manager.whenBackgroundSettled();
      backend.offline = true;

      await expectLater(
        manager.deleteAccount(password: 'correct-horse'),
        throwsA(isA<NetworkException>()),
      );

      expect(manager.view.isSignedIn, isTrue);
      expect(databaseExists('user-1'), isTrue);
    });
  });

  group('profile', () {
    test('updateProfile saves the server\'s answer everywhere', () async {
      await manager.start();
      await manager.login(email: 'a@b.com', password: 'correct-horse');
      await manager.whenBackgroundSettled();

      final UserProfile updated = await manager.updateProfile(displayName: 'Asha Renamed');

      expect(updated.displayName, 'Asha Renamed');
      expect(manager.view.user!.displayName, 'Asha Renamed');
      expect(keeper.current!.user.displayName, 'Asha Renamed');
    });
  });

  group('an ended session', () {
    test('the same account signing in again keeps its open data and resumes syncing', () async {
      await manager.start();
      final SessionView first = await manager.login(email: 'a@b.com', password: 'correct-horse');
      await manager.whenBackgroundSettled();

      // The server stops accepting the tokens.
      backend.refuseTokens = true;
      await first.active!.roster.createPlayer(displayName: 'Asha');
      await first.active!.syncEngine!.syncNow(force: true);
      expect(first.active!.syncEngine!.state.needsSignIn, isTrue);
      expect(keeper.current, isNull);
      expect(await first.active!.store.pendingOutboxCount(), 1);

      backend.refuseTokens = false;
      final SessionView second = await manager.login(email: 'a@b.com', password: 'correct-horse');
      await manager.whenBackgroundSettled();

      expect(identical(second.active, first.active), isTrue, reason: 'same database stays open');
      expect(first.active!.store.isClosed, isFalse);
      expect(first.active!.syncEngine!.state.needsSignIn, isFalse);
      expect(await first.active!.store.pendingOutboxCount(), 0);
    });
  });

  test('operations are carried out one at a time, in order', () async {
    await manager.start();
    final List<String> order = <String>[];

    final Future<void> a = manager.login(email: 'a@b.com', password: 'correct-horse').then((_) {
      order.add('login');
    });
    final Future<void> b = manager.signOut().then((_) {
      order.add('signOut');
    });
    await Future.wait<void>(<Future<void>>[a, b]);

    expect(order, <String>['login', 'signOut']);
    expect(manager.view.isSignedIn, isFalse);
  });
}
