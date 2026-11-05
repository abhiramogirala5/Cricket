import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/core/errors/app_exception.dart';
import 'package:gully_umpire/data/remote/api_client.dart';
import 'package:gully_umpire/data/remote/replay_api.dart';
import 'package:gully_umpire/data/session/session_keeper.dart';
import 'package:gully_umpire/data/session/session_models.dart';
import 'package:gully_umpire/data/session/session_storage.dart';
import 'package:gully_umpire/domain/models/models.dart';

import '../../support/data_test_support.dart';
import '../../support/model_fixtures.dart';
import 'scripted_adapter.dart';

void main() {
  late SessionKeeper keeper;
  late ScriptedAdapter server;
  late ScriptedAdapter storage;
  late ApiClient client;
  late HttpReplayApi api;

  setUp(() async {
    keeper = SessionKeeper(
      MemorySessionStorage(
        StoredSession(
          tokens: const AuthTokens(accessToken: 'access-1', refreshToken: 'refresh-1'),
          user: UserProfile(
            id: 'user-1',
            email: 'asha@example.com',
            displayName: 'Asha Rao',
            createdAt: t0,
          ),
        ),
      ),
    );
    await keeper.load();
    server = ScriptedAdapter((RequestOptions options) async => jsonReply(200, <String, Object?>{}));
    storage = ScriptedAdapter((RequestOptions options) async => emptyReply(200));
    client = ApiClient(
      baseUrl: 'http://test.local/api/v1',
      session: keeper,
      ids: SequenceIds(),
      dio: Dio()..httpClientAdapter = server,
    );
    api = HttpReplayApi(client, fileDio: Dio()..httpClientAdapter = storage);
  });

  tearDown(() async {
    client.close();
    await keeper.dispose();
  });

  group('announce', () {
    test('sends what the server needs and reads the upload address', () async {
      server.onRequest = (RequestOptions options) async => jsonReply(201, <String, Object?>{
            'id': 'r1',
            'upload': <String, Object?>{
              'url': 'https://storage.example.com/signed?token=abc',
              'headers': <String, Object?>{'Content-Type': 'application/octet-stream'},
            },
          });

      final ReplayAnnouncement result = await api.announce(
        id: 'r1',
        matchId: 'match-1',
        deliveryId: 'delivery-1',
        sizeBytes: 1234,
        width: 360,
        height: 640,
        frameCount: 40,
        durationMs: 1300,
      );

      expect(server.paths.single, '/api/v1/replays');
      expect(server.requests.single.method, 'POST');
      expect(server.requests.single.headers['Authorization'], 'Bearer access-1');
      expect(server.sentJson(0), <String, Object?>{
        'id': 'r1',
        'match_id': 'match-1',
        'delivery_id': 'delivery-1',
        'size_bytes': 1234,
        'width': 360,
        'height': 640,
        'frame_count': 40,
        'duration_ms': 1300,
      });
      expect(result.alreadyStored, isFalse);
      expect(result.upload?.url, 'https://storage.example.com/signed?token=abc');
      expect(result.upload?.headers, <String, String>{'Content-Type': 'application/octet-stream'});
    });

    test('leaves out what is not known', () async {
      server.onRequest = (RequestOptions options) async => jsonReply(201, <String, Object?>{
            'upload': <String, Object?>{'url': 'https://s.example.com/x', 'headers': <String, Object?>{}},
          });

      await api.announce(id: 'r1', matchId: 'match-1', sizeBytes: 10);

      expect(server.sentJson(0), <String, Object?>{
        'id': 'r1',
        'match_id': 'match-1',
        'size_bytes': 10,
      });
    });

    test('an answer without an upload address means the server already has the file', () async {
      server.onRequest = (RequestOptions options) async =>
          jsonReply(200, <String, Object?>{'id': 'r1', 'upload': null});

      final ReplayAnnouncement result =
          await api.announce(id: 'r1', matchId: 'match-1', sizeBytes: 10);

      expect(result.alreadyStored, isTrue);
      expect(result.upload, isNull);
    });

    test('an unusable upload address is an error', () async {
      server.onRequest = (RequestOptions options) async => jsonReply(201, <String, Object?>{
            'upload': <String, Object?>{'url': '', 'headers': <String, Object?>{}},
          });

      await expectLater(
        api.announce(id: 'r1', matchId: 'match-1', sizeBytes: 10),
        throwsA(isA<ApiException>().having((ApiException e) => e.code, 'code', 'INVALID_RESPONSE')),
      );
    });

    test('an upload entry that is not an object is an error', () async {
      server.onRequest =
          (RequestOptions options) async => jsonReply(201, <String, Object?>{'upload': 'oops'});

      await expectLater(
        api.announce(id: 'r1', matchId: 'match-1', sizeBytes: 10),
        throwsA(isA<ApiException>()),
      );
    });

    test('a refusal from the server is reported with its code', () async {
      server.onRequest = (RequestOptions options) async => jsonReply(
            503,
            errorEnvelope('STORAGE_UNAVAILABLE', 'Replay storage is not set up.'),
          );

      await expectLater(
        api.announce(id: 'r1', matchId: 'match-1', sizeBytes: 10),
        throwsA(
          isA<ApiException>()
              .having((ApiException e) => e.code, 'code', 'STORAGE_UNAVAILABLE')
              .having((ApiException e) => e.statusCode, 'status', 503),
        ),
      );
    });
  });

  group('upload', () {
    test('puts the bytes at the signed address with the headers it gave and no account token',
        () async {
      final Uint8List bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);

      await api.upload(
        const ReplayUploadTarget(
          url: 'https://storage.example.com/signed?token=abc',
          headers: <String, String>{'Content-Type': 'application/octet-stream'},
        ),
        bytes,
      );

      final RequestOptions request = storage.requests.single;
      expect(request.method, 'PUT');
      expect(request.uri.toString(), 'https://storage.example.com/signed?token=abc');
      expect(storage.bodies.single, bytes, reason: 'the bytes arrive as they are, not as text');
      expect('${request.headers[Headers.contentLengthHeader]}', '${bytes.length}');
      expect(request.contentType, 'application/octet-stream');
      expect(request.headers.containsKey('Authorization'), isFalse);
      expect(server.requests, isEmpty, reason: 'the file never goes through the app server');
    });

    test('a refusal from the storage service is an error with its status', () async {
      storage.onRequest = (RequestOptions options) async => textReply(403, 'denied');

      await expectLater(
        api.upload(
          const ReplayUploadTarget(url: 'https://storage.example.com/x', headers: <String, String>{}),
          Uint8List(3),
        ),
        throwsA(
          isA<ApiException>()
              .having((ApiException e) => e.code, 'code', 'UPLOAD_FAILED')
              .having((ApiException e) => e.statusCode, 'status', 403),
        ),
      );
    });

    test('a lost connection is a network error', () async {
      storage.onRequest = (RequestOptions options) async => throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
          );

      await expectLater(
        api.upload(
          const ReplayUploadTarget(url: 'https://storage.example.com/x', headers: <String, String>{}),
          Uint8List(3),
        ),
        throwsA(isA<NetworkException>()),
      );
    });
  });

  group('complete', () {
    test('tells the server the file has been sent', () async {
      await api.complete('r1');

      expect(server.paths.single, '/api/v1/replays/r1/complete');
      expect(server.requests.single.method, 'POST');
    });

    test('an error from the server is reported', () async {
      server.onRequest = (RequestOptions options) async =>
          jsonReply(409, errorEnvelope('REPLAY_INCOMPLETE', 'The file did not arrive whole.'));

      await expectLater(
        api.complete('r1'),
        throwsA(isA<ApiException>().having((ApiException e) => e.code, 'code', 'REPLAY_INCOMPLETE')),
      );
    });
  });

  group('forDelivery', () {
    test('lists the stored replays of one delivery', () async {
      server.onRequest = (RequestOptions options) async => jsonReply(200, <String, Object?>{
            'items': <Object?>[
              <String, Object?>{'id': 'r2', 'size_bytes': 500, 'delivery_id': 'd1'},
              <String, Object?>{'id': 'r1', 'size_bytes': 400.0, 'delivery_id': 'd1'},
            ],
          });

      final List<RemoteReplay> replays = await api.forDelivery('d1');

      expect(server.requests.single.method, 'GET');
      expect(server.paths.single, '/api/v1/replays');
      expect(server.requests.single.queryParameters['delivery_id'], 'd1');
      expect(replays.map((RemoteReplay r) => r.id), <String>['r2', 'r1']);
      expect(replays.map((RemoteReplay r) => r.sizeBytes), <int>[500, 400]);
      expect(replays.first.deliveryId, 'd1');
    });

    test('entries that cannot be understood are skipped', () async {
      server.onRequest = (RequestOptions options) async => jsonReply(200, <String, Object?>{
            'items': <Object?>[
              'junk',
              <String, Object?>{'id': 5, 'size_bytes': 1},
              <String, Object?>{'id': 'ok', 'size_bytes': 1},
              <String, Object?>{'id': 'no-size'},
            ],
          });

      final List<RemoteReplay> replays = await api.forDelivery('d1');

      expect(replays.map((RemoteReplay r) => r.id), <String>['ok']);
    });

    test('no items means an empty list', () async {
      server.onRequest = (RequestOptions options) async => jsonReply(200, <String, Object?>{});

      expect(await api.forDelivery('d1'), isEmpty);
    });
  });

  group('download', () {
    test('asks for a download address, then fetches the file from it without a token', () async {
      server.onRequest = (RequestOptions options) async => jsonReply(200, <String, Object?>{
            'url': 'https://storage.example.com/get?token=xyz',
          });
      storage.onRequest = (RequestOptions options) async =>
          ResponseBody.fromBytes(<int>[9, 8, 7], 200);

      final Uint8List bytes = await api.download('r1');

      expect(server.paths.single, '/api/v1/replays/r1/download');
      expect(storage.requests.single.method, 'GET');
      expect(storage.requests.single.uri.toString(), 'https://storage.example.com/get?token=xyz');
      expect(storage.requests.single.headers.containsKey('Authorization'), isFalse);
      expect(bytes, <int>[9, 8, 7]);
    });

    test('a missing address is an error', () async {
      server.onRequest = (RequestOptions options) async => jsonReply(200, <String, Object?>{});

      await expectLater(
        api.download('r1'),
        throwsA(isA<ApiException>().having((ApiException e) => e.code, 'code', 'INVALID_RESPONSE')),
      );
      expect(storage.requests, isEmpty);
    });

    test('a refusal from the storage service is an error', () async {
      server.onRequest = (RequestOptions options) async =>
          jsonReply(200, <String, Object?>{'url': 'https://storage.example.com/get'});
      storage.onRequest = (RequestOptions options) async => ResponseBody.fromBytes(<int>[], 404);

      await expectLater(
        api.download('r1'),
        throwsA(isA<ApiException>().having((ApiException e) => e.code, 'code', 'DOWNLOAD_FAILED')),
      );
    });

    test('a lost connection is a network error', () async {
      server.onRequest = (RequestOptions options) async =>
          jsonReply(200, <String, Object?>{'url': 'https://storage.example.com/get'});
      storage.onRequest = (RequestOptions options) async => throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionTimeout,
          );

      await expectLater(api.download('r1'), throwsA(isA<NetworkException>()));
    });
  });

  group('ReplayUploadTarget', () {
    test('keeps only text headers', () {
      final ReplayUploadTarget target = ReplayUploadTarget.fromJson(<String, Object?>{
        'url': 'https://s.example.com/x',
        'headers': <Object?, Object?>{'A': 'b', 'C': 5, 7: 'x'},
      });

      expect(target.headers, <String, String>{'A': 'b'});
    });

    test('a missing headers entry means no headers', () {
      final ReplayUploadTarget target =
          ReplayUploadTarget.fromJson(<String, Object?>{'url': 'https://s.example.com/x'});

      expect(target.headers, isEmpty);
    });
  });
}
