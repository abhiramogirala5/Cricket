import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/core/errors/app_exception.dart';
import 'package:gully_umpire/data/local/local_store.dart';
import 'package:gully_umpire/data/replays/replay_record.dart';
import 'package:gully_umpire/data/replays/replay_store.dart';
import 'package:gully_umpire/data/replays/replay_uploader.dart';
import 'package:path/path.dart' as p;

import '../../support/data_test_support.dart';
import '../sync/fake_sync_api.dart';
import 'replay_test_support.dart';

void main() {
  late LocalStore database;
  late Directory root;
  late FakeClock clock;
  late ReplayStore store;
  late FakeReplayApi api;
  late FakeConnectivity connectivity;
  late ReplayUploader uploader;

  ReplayUploader makeUploader({int batchSize = 3, Duration? kickDelay, Duration? pollInterval}) {
    return ReplayUploader(
      store: store,
      api: api,
      connectivity: connectivity,
      batchSize: batchSize,
      kickDelay: kickDelay ?? const Duration(milliseconds: 10),
      pollInterval: pollInterval ?? const Duration(hours: 1),
    );
  }

  /// Saves a replay of a scored ball (or of a ball that was not scored when [attach] is false).
  Future<void> add(String id, {bool attach = true, Uint8List? bytes}) async {
    clock.advance(const Duration(seconds: 1));
    await store.save(id: id, matchId: 'match-1', bytes: bytes ?? makeReplayBytes());
    if (attach) {
      await store.attachDelivery(id, 'delivery-$id');
    }
  }

  Future<ReplayRecord> recordOf(String id) async => (await store.record(id))!;

  setUp(() async {
    database = await openMemoryStore();
    root = makeTempReplayDirectory();
    clock = FakeClock();
    store = ReplayStore(
      store: database,
      resolveDirectory: () async => Directory(p.join(root.path, 'replays')),
      clock: clock,
    );
    api = FakeReplayApi();
    connectivity = FakeConnectivity();
    uploader = makeUploader();
  });

  tearDown(() async {
    await uploader.dispose();
    await database.close();
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  });

  group('a replay that is waiting', () {
    test('is announced, sent and completed in that order, then remembered as uploaded', () async {
      final Uint8List bytes = makeReplayBytes();
      await add('r1', bytes: bytes);

      final int uploaded = await uploader.uploadPending();

      expect(uploaded, 1);
      expect(api.calls, <String>['announce:r1', 'upload:r1', 'complete:r1']);
      expect(api.uploadedBytes['r1'], bytes);
      final ReplayRecord record = await recordOf('r1');
      expect(record.uploadState, ReplayUploadState.uploaded);
      expect(record.remoteId, 'r1');
    });

    test('tells the server what it needs to know about the file', () async {
      final Uint8List bytes = makeReplayBytes();
      await add('r1', bytes: bytes);

      await uploader.uploadPending();

      final Map<String, Object?> sent = api.announced.single;
      expect(sent['id'], 'r1');
      expect(sent['matchId'], 'match-1');
      expect(sent['deliveryId'], 'delivery-r1');
      expect(sent['sizeBytes'], bytes.length);
      expect(sent['width'], 4);
      expect(sent['height'], 4);
      expect(sent['frameCount'], 2);
      expect(sent['durationMs'], 33);
    });

    test('is not sent again once it is on the server', () async {
      await add('r1');
      await uploader.uploadPending();
      api.calls.clear();

      expect(await uploader.uploadPending(), 0);

      expect(api.calls, isEmpty);
    });

    test('the file is not sent when the server already holds it', () async {
      api.alreadyStored = true;
      await add('r1');

      expect(await uploader.uploadPending(), 1);

      expect(api.calls, <String>['announce:r1', 'complete:r1']);
      expect((await recordOf('r1')).isUploaded, isTrue);
    });

    test('is sent oldest first, and only as many as one run allows', () async {
      uploader = makeUploader(batchSize: 2);
      await add('r1');
      await add('r2');
      await add('r3');

      expect(await uploader.uploadPending(), 2);
      expect(api.calls.where((String c) => c.startsWith('announce')), <String>[
        'announce:r1',
        'announce:r2',
      ]);

      expect(await uploader.uploadPending(), 1);
      expect((await recordOf('r3')).isUploaded, isTrue);
    });
  });

  group('a replay that is not waiting', () {
    test('a ball that was never scored is not uploaded', () async {
      await add('r1', attach: false);

      expect(await uploader.uploadPending(), 0);

      expect(api.calls, isEmpty);
    });

    test('nothing is done while the phone is offline', () async {
      await add('r1');
      connectivity.goOffline();

      expect(await uploader.uploadPending(), 0);

      expect(api.calls, isEmpty);
      expect((await recordOf('r1')).uploadState, ReplayUploadState.local);

      connectivity.goOnline();
      expect(await uploader.uploadPending(), 1);
    });

    test('a record whose file is gone is forgotten without asking the server', () async {
      await add('r1');
      File(p.join(root.path, 'replays', 'r1.gur')).deleteSync();

      expect(await uploader.uploadPending(), 0);

      expect(api.calls, isEmpty);
      expect(await store.record('r1'), isNull);
    });

    test('a damaged file is marked, not sent, and does not block the next one', () async {
      await add('bad', bytes: Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]));
      await add('good');

      expect(await uploader.uploadPending(), 1);

      expect(api.calls, <String>['announce:good', 'upload:good', 'complete:good']);
      final ReplayRecord bad = await recordOf('bad');
      expect(bad.uploadState, ReplayUploadState.failed);
      expect(bad.attempts, 1);
      expect(bad.lastError, startsWith('Damaged file'));
    });
  });

  group('when something goes wrong', () {
    test('a lost connection stops the run, costs no attempt and is tried again', () async {
      api.announceError = const NetworkException('No connection.');
      await add('r1');
      await add('r2');

      expect(await uploader.uploadPending(), 0);

      expect(api.calls, <String>['announce:r1'], reason: 'the run stops at the first failure');
      final ReplayRecord r1 = await recordOf('r1');
      expect(r1.uploadState, ReplayUploadState.failed);
      expect(r1.attempts, 0);
      expect(r1.lastError, 'No connection.');
      expect((await recordOf('r2')).uploadState, ReplayUploadState.local);

      api.announceError = null;
      expect(await uploader.uploadPending(), 2);
      expect((await recordOf('r1')).isUploaded, isTrue);
      expect((await recordOf('r1')).lastError, isNull);
    });

    test('a failed file send is not counted as an attempt either', () async {
      api.uploadError = const NetworkException('The replay could not be sent.');
      await add('r1');

      await uploader.uploadPending();

      expect((await recordOf('r1')).attempts, 0);
      expect(api.calls, <String>['announce:r1', 'upload:r1']);
    });

    test('an expired sign-in stops the run without blaming the file', () async {
      api.announceError = const SessionExpiredException();
      await add('r1');
      await add('r2');

      expect(await uploader.uploadPending(), 0);

      expect(api.calls, hasLength(1));
      final ReplayRecord record = await recordOf('r1');
      expect(record.attempts, 0);
      expect(record.lastError, 'Sign in again to upload.');
    });

    test('a refused file counts as an attempt and the run goes on with the next', () async {
      api.announceError = const ApiException(
        code: 'UPLOAD_FAILED',
        message: 'The file is not acceptable.',
        statusCode: 400,
      );
      await add('r1');
      await add('r2');

      expect(await uploader.uploadPending(), 0);

      expect(api.calls, <String>['announce:r1', 'announce:r2']);
      expect((await recordOf('r1')).attempts, 1);
      expect((await recordOf('r2')).attempts, 1);
    });

    test('a server that has no storage stops the run and costs no attempt', () async {
      api.announceError = const ApiException(
        code: 'STORAGE_UNAVAILABLE',
        message: 'Storage is not set up.',
        statusCode: 503,
      );
      await add('r1');
      await add('r2');

      expect(await uploader.uploadPending(), 0);

      expect(api.calls, <String>['announce:r1']);
      expect((await recordOf('r1')).attempts, 0);
    });

    test('a rate limit stops the run and costs no attempt', () async {
      api.announceError = const ApiException(
        code: 'RATE_LIMITED',
        message: 'Slow down.',
        statusCode: 429,
      );
      await add('r1');
      await add('r2');

      await uploader.uploadPending();

      expect(api.calls, <String>['announce:r1']);
      expect((await recordOf('r1')).attempts, 0);
    });

    test('an unexpected error counts as an attempt and the run goes on', () async {
      api.completeError = StateError('surprise');
      await add('r1');
      await add('r2');

      expect(await uploader.uploadPending(), 0);

      expect(api.calls.where((String c) => c.startsWith('announce')), hasLength(2));
      final ReplayRecord record = await recordOf('r1');
      expect(record.attempts, 1);
      expect(record.lastError, 'Upload failed.');
    });

    test('a file that the server keeps refusing is given up on after eight attempts', () async {
      api.announceError = const ApiException(
        code: 'UPLOAD_FAILED',
        message: 'No.',
        statusCode: 400,
      );
      await add('r1');

      for (int i = 0; i < 10; i++) {
        await uploader.uploadPending();
      }

      expect(api.calls.where((String c) => c.startsWith('announce')), hasLength(8));
      expect(await store.hasFile('r1'), isTrue, reason: 'the replay stays on the phone');
    });
  });

  group('runs', () {
    test('calls made during a run share it', () async {
      await add('r1');

      final Future<int> first = uploader.uploadPending();
      final Future<int> second = uploader.uploadPending();

      expect(await first, 1);
      expect(await second, 1);
      expect(api.calls.where((String c) => c.startsWith('announce')), hasLength(1));
    });

    test('start puts an interrupted upload back in the queue and sends it', () async {
      await add('r1');
      await store.markUploading('r1');

      await uploader.start();
      await uploader.uploadPending();

      expect((await recordOf('r1')).isUploaded, isTrue);
    });

    test('start twice does nothing the second time', () async {
      await uploader.start();
      await uploader.start();
    });

    test('coming back online sends what was waiting', () async {
      await add('r1');
      connectivity.goOffline();
      await uploader.start();
      await uploader.uploadPending();
      expect((await recordOf('r1')).uploadState, ReplayUploadState.local);

      connectivity.goOnline();
      for (int i = 0; i < 100 && !(await recordOf('r1')).isUploaded; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      expect((await recordOf('r1')).isUploaded, isTrue);
    });

    test('kick sends a replay soon after it was scored', () async {
      await uploader.start();
      await add('r1');

      uploader.kick();
      for (int i = 0; i < 100 && !(await recordOf('r1')).isUploaded; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      expect((await recordOf('r1')).isUploaded, isTrue);
    });

    test('after dispose nothing more is sent', () async {
      await add('r1');
      await uploader.dispose();

      expect(await uploader.uploadPending(), 0);

      expect(api.calls, isEmpty);
      uploader.kick();
      await uploader.start();
    });
  });
}
