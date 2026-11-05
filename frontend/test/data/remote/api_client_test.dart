import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/core/errors/app_exception.dart';
import 'package:gully_umpire/data/remote/api_client.dart';
import 'package:gully_umpire/data/session/session_keeper.dart';
import 'package:gully_umpire/data/session/session_models.dart';
import 'package:gully_umpire/data/session/session_storage.dart';
import 'package:gully_umpire/domain/models/user_profile.dart';

import '../../support/data_test_support.dart';
import 'scripted_adapter.dart';

final StoredSession signedIn = StoredSession(
  tokens: const AuthTokens(accessToken: 'access-1', refreshToken: 'refresh-1'),
  user: UserProfile(
    id: 'user-1',
    email: 'asha@example.com',
    displayName: 'Asha Rao',
    createdAt: DateTime.utc(2026, 10, 8),
  ),
);

void main() {
  late SessionKeeper keeper;
  late MemorySessionStorage storage;
  late ScriptedAdapter adapter;
  late ApiClient client;

  ApiClient buildClient() {
    final Dio dio = Dio()..httpClientAdapter = adapter;
    return ApiClient(
      baseUrl: 'http://test.local/api/v1',
      session: keeper,
      ids: SequenceIds(),
      timeout: const Duration(seconds: 5),
      dio: dio,
    );
  }

  setUp(() async {
    storage = MemorySessionStorage(signedIn);
    keeper = SessionKeeper(storage);
    await keeper.load();
    adapter = ScriptedAdapter((RequestOptions options) async => jsonReply(200, <String, Object?>{'ok': true}));
    client = buildClient();
  });

  tearDown(() async {
    client.close();
    await keeper.dispose();
  });

  group('requests', () {
    test('send the bearer token, a request id and the JSON body', () async {
      final Map<String, Object?> body = await client.sendForMap(
        'POST',
        '/sync/push',
        body: <String, Object?>{'events': <Object?>[]},
      );
      expect(body, <String, Object?>{'ok': true});
      final RequestOptions sent = adapter.requests.single;
      expect(sent.method, 'POST');
      expect(sent.uri.toString(), 'http://test.local/api/v1/sync/push');
      expect(sent.headers['Authorization'], 'Bearer access-1');
      expect(sent.headers['X-Request-ID'], 'id-0001');
      expect(sent.headers['Accept'], 'application/json');
      expect(adapter.sentJson(0), <String, Object?>{'events': <Object?>[]});
    });

    test('put query parameters in the URL', () async {
      await client.send('GET', '/players', query: <String, Object?>{'limit': 100, 'offset': 0});
      expect(adapter.requests.single.uri.query, 'limit=100&offset=0');
    });

    test('without auth no token is sent', () async {
      await client.send('POST', '/auth/login', auth: false, body: <String, Object?>{'a': 1});
      expect(adapter.requests.single.headers.containsKey('Authorization'), isFalse);
    });

    test('an authenticated call without a session fails before touching the network', () async {
      await keeper.clear();
      await expectLater(client.send('GET', '/users/me'), throwsA(isA<SessionExpiredException>()));
      expect(adapter.requests, isEmpty);
    });

    test('an empty 204 answer decodes to null', () async {
      adapter.onRequest = (RequestOptions options) async => emptyReply(204);
      expect(await client.send('POST', '/auth/logout', auth: false), isNull);
    });

    test('a 2xx answer that is not JSON is reported', () async {
      adapter.onRequest = (RequestOptions options) async => textReply(200, '<html>oops</html>');
      await expectLater(
        client.send('GET', '/players'),
        throwsA(isA<ApiException>().having((ApiException e) => e.code, 'code', 'INVALID_RESPONSE')),
      );
    });

    test('an object was expected but a list came back', () async {
      adapter.onRequest = (RequestOptions options) async => jsonReply(200, <Object?>[1, 2]);
      await expectLater(
        client.sendForMap('GET', '/players'),
        throwsA(isA<ApiException>().having((ApiException e) => e.code, 'code', 'INVALID_RESPONSE')),
      );
    });
  });

  group('errors', () {
    test('the error envelope becomes an ApiException', () async {
      adapter.onRequest = (RequestOptions options) async => jsonReply(
            422,
            errorEnvelope('VALIDATION_ERROR', 'bad email', details: <Object?>[
              <String, Object?>{'loc': <Object?>['body', 'email']},
            ]),
          );
      try {
        await client.send('POST', '/auth/register', auth: false, body: <String, Object?>{});
        fail('should have thrown');
      } on ApiException catch (error) {
        expect(error.code, 'VALIDATION_ERROR');
        expect(error.message, 'bad email');
        expect(error.statusCode, 422);
        expect(error.requestId, 'req-123');
        expect(error.details, hasLength(1));
        expect(error.isServerError, isFalse);
      }
    });

    test('a body that is not an envelope still gives a usable error', () async {
      adapter.onRequest = (RequestOptions options) async => textReply(502, 'Bad gateway');
      try {
        await client.send('GET', '/players');
        fail('should have thrown');
      } on ApiException catch (error) {
        expect(error.code, 'HTTP_502');
        expect(error.statusCode, 502);
        expect(error.isServerError, isTrue);
      }
    });

    test('Retry-After is read from a 429', () async {
      adapter.onRequest = (RequestOptions options) async => jsonReply(
            429,
            errorEnvelope('RATE_LIMITED', 'slow down'),
            headers: <String, List<String>>{
              'retry-after': <String>['30'],
            },
          );
      try {
        await client.send('POST', '/auth/login', auth: false, body: <String, Object?>{});
        fail('should have thrown');
      } on ApiException catch (error) {
        expect(error.isRateLimited, isTrue);
        expect(error.retryAfter, const Duration(seconds: 30));
      }
    });

    test('wrong credentials are an ApiException, not an ended session', () async {
      adapter.onRequest = (RequestOptions options) async =>
          jsonReply(401, errorEnvelope('INVALID_CREDENTIALS', 'wrong'));
      await expectLater(
        client.send('POST', '/auth/login', auth: false, body: <String, Object?>{}),
        throwsA(isA<ApiException>().having((ApiException e) => e.code, 'code', 'INVALID_CREDENTIALS')),
      );
      expect(keeper.current, isNotNull);
    });

    test('connection problems become NetworkException', () async {
      for (final DioExceptionType type in <DioExceptionType>[
        DioExceptionType.connectionError,
        DioExceptionType.connectionTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.badCertificate,
        DioExceptionType.unknown,
      ]) {
        adapter.onRequest = (RequestOptions options) async =>
            throw DioException(requestOptions: options, type: type);
        await expectLater(
          client.send('GET', '/players'),
          throwsA(isA<NetworkException>()),
          reason: '$type',
        );
      }
      expect(keeper.current, isNotNull);
    });
  });

  group('token refresh', () {
    test('refreshes once on TOKEN_EXPIRED, stores the new tokens and repeats the request', () async {
      adapter.onRequest = (RequestOptions options) async {
        if (options.uri.path.endsWith('/auth/refresh')) {
          return jsonReply(200, tokenPair('access-2', 'refresh-2'));
        }
        if (options.headers['Authorization'] == 'Bearer access-1') {
          return jsonReply(401, errorEnvelope('TOKEN_EXPIRED', 'expired'));
        }
        return jsonReply(200, <String, Object?>{'ok': true});
      };
      final Map<String, Object?> body = await client.sendForMap('GET', '/users/me');
      expect(body, <String, Object?>{'ok': true});
      expect(adapter.paths, <String>['/api/v1/users/me', '/api/v1/auth/refresh', '/api/v1/users/me']);
      expect(adapter.sentJson(1), <String, Object?>{'refresh_token': 'refresh-1'});
      expect(adapter.requests[1].headers.containsKey('Authorization'), isFalse);
      expect(adapter.requests[2].headers['Authorization'], 'Bearer access-2');
      expect(keeper.current!.tokens.refreshToken, 'refresh-2');
      expect((await storage.read())!.tokens.accessToken, 'access-2');
      expect(keeper.current!.user.id, 'user-1');
    });

    test('requests that expire at the same moment share ONE refresh', () async {
      final Completer<void> refreshGate = Completer<void>();
      int refreshCalls = 0;
      adapter.onRequest = (RequestOptions options) async {
        if (options.uri.path.endsWith('/auth/refresh')) {
          refreshCalls += 1;
          await refreshGate.future;
          return jsonReply(200, tokenPair('access-2', 'refresh-2'));
        }
        if (options.headers['Authorization'] == 'Bearer access-1') {
          return jsonReply(401, errorEnvelope('TOKEN_EXPIRED', 'expired'));
        }
        return jsonReply(200, <String, Object?>{'ok': true});
      };
      final Future<Object?> a = client.send('GET', '/players');
      final Future<Object?> b = client.send('GET', '/teams');
      final Future<Object?> c = client.send('GET', '/matches');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      refreshGate.complete();
      await Future.wait(<Future<Object?>>[a, b, c]);
      expect(refreshCalls, 1);
    });

    test('a refused refresh token ends the session', () async {
      int expiredEvents = 0;
      final StreamSubscription<void> subscription = keeper.expired.listen((_) => expiredEvents += 1);
      adapter.onRequest = (RequestOptions options) async {
        if (options.uri.path.endsWith('/auth/refresh')) {
          return jsonReply(401, errorEnvelope('INVALID_REFRESH_TOKEN', 'no'));
        }
        return jsonReply(401, errorEnvelope('TOKEN_EXPIRED', 'expired'));
      };
      await expectLater(client.send('GET', '/users/me'), throwsA(isA<SessionExpiredException>()));
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();
      expect(keeper.current, isNull);
      expect(await storage.read(), isNull);
      expect(expiredEvents, 1);
    });

    test('a refresh that cannot reach the server keeps the session', () async {
      adapter.onRequest = (RequestOptions options) async {
        if (options.uri.path.endsWith('/auth/refresh')) {
          throw DioException(requestOptions: options, type: DioExceptionType.connectionError);
        }
        return jsonReply(401, errorEnvelope('TOKEN_EXPIRED', 'expired'));
      };
      await expectLater(client.send('GET', '/users/me'), throwsA(isA<NetworkException>()));
      expect(keeper.current, isNotNull);
    });

    test('a refresh that hits a server error keeps the session', () async {
      adapter.onRequest = (RequestOptions options) async {
        if (options.uri.path.endsWith('/auth/refresh')) {
          return jsonReply(503, errorEnvelope('SERVICE_UNAVAILABLE', 'down'));
        }
        return jsonReply(401, errorEnvelope('TOKEN_EXPIRED', 'expired'));
      };
      await expectLater(
        client.send('GET', '/users/me'),
        throwsA(isA<ApiException>().having((ApiException e) => e.isServerError, 'server error', true)),
      );
      expect(keeper.current, isNotNull);
    });

    test('a token the server calls invalid ends the session without a refresh', () async {
      adapter.onRequest = (RequestOptions options) async =>
          jsonReply(401, errorEnvelope('INVALID_TOKEN', 'bad token'));
      await expectLater(client.send('GET', '/users/me'), throwsA(isA<SessionExpiredException>()));
      expect(adapter.paths, <String>['/api/v1/users/me']);
      expect(keeper.current, isNull);
    });

    test('a second 401 after a successful refresh ends the session', () async {
      adapter.onRequest = (RequestOptions options) async {
        if (options.uri.path.endsWith('/auth/refresh')) {
          return jsonReply(200, tokenPair('access-2', 'refresh-2'));
        }
        return jsonReply(401, errorEnvelope('TOKEN_EXPIRED', 'expired'));
      };
      await expectLater(client.send('GET', '/users/me'), throwsA(isA<SessionExpiredException>()));
      expect(keeper.current, isNull);
    });
  });
}
