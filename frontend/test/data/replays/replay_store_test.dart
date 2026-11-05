import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/data/local/local_store.dart';
import 'package:gully_umpire/data/replays/replay_record.dart';
import 'package:gully_umpire/data/replays/replay_store.dart';
import 'package:path/path.dart' as p;

import '../../support/data_test_support.dart';
import 'replay_test_support.dart';

void main() {
  late LocalStore database;
  late Directory root;
  late Directory folder;
  late FakeClock clock;
  late ReplayStore store;

  ReplayStore makeStore({int maxPacks = 80, int maxBytes = 200 * 1024 * 1024}) {
    return ReplayStore(
      store: database,
      resolveDirectory: () async => folder,
      clock: clock,
      maxPacks: maxPacks,
      maxBytes: maxBytes,
    );
  }

  Uint8List bytesOf(int length) => Uint8List.fromList(List<int>.filled(length, 7));

  /// Saves a replay one second after the previous one, so that the order is clear.
  Future<ReplayRecord> add(String id, {Uint8List? bytes, String? deliveryId}) async {
    clock.advance(const Duration(seconds: 1));
    return store.save(
      id: id,
      matchId: 'match-1',
      bytes: bytes ?? makeReplayBytes(),
      deliveryId: deliveryId,
    );
  }

  setUp(() async {
    database = await openMemoryStore();
    root = makeTempReplayDirectory();
    folder = Directory(p.join(root.path, 'nested', 'replays'));
    clock = FakeClock();
    store = makeStore();
  });

  tearDown(() async {
    await database.close();
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  });

  group('save and read', () {
    test('writes the file, creates the folder and keeps a record', () async {
      final Uint8List bytes = makeReplayBytes();

      final ReplayRecord record = await store.save(id: 'r1', matchId: 'match-1', bytes: bytes);

      expect(record.id, 'r1');
      expect(record.matchId, 'match-1');
      expect(record.fileName, 'r1.gur');
      expect(record.sizeBytes, bytes.length);
      expect(record.deliveryId, isNull);
      expect(record.uploadState, ReplayUploadState.local);
      expect(record.createdAtMs, clock.now().millisecondsSinceEpoch);
      expect(File(p.join(folder.path, 'r1.gur')).existsSync(), isTrue);
      expect(await store.record('r1'), record);
      expect(await store.hasFile('r1'), isTrue);
      expect(await store.read('r1'), bytes);
    });

    test('leaves no temporary file behind', () async {
      await store.save(id: 'r1', matchId: 'match-1', bytes: makeReplayBytes());

      final List<String> names = folder
          .listSync()
          .map<String>((FileSystemEntity e) => p.basename(e.path))
          .toList(growable: false);
      expect(names, <String>['r1.gur']);
    });

    test('can be saved already attached to a delivery', () async {
      final ReplayRecord record = await add('r1', deliveryId: 'd1');

      expect(record.deliveryId, 'd1');
      expect((await store.forDelivery('d1'))?.id, 'r1');
    });

    test('an unknown replay has no record, no file and no bytes', () async {
      expect(await store.record('nope'), isNull);
      expect(await store.hasFile('nope'), isFalse);
      expect(await store.read('nope'), isNull);
      expect(await store.forDelivery('nope'), isNull);
    });

    test('a record whose file was removed reads as missing', () async {
      await add('r1');
      File(p.join(folder.path, 'r1.gur')).deleteSync();

      expect(await store.record('r1'), isNotNull);
      expect(await store.hasFile('r1'), isFalse);
      expect(await store.read('r1'), isNull);
    });
  });

  group('attaching to a delivery', () {
    test('the replay is found by its delivery afterwards', () async {
      await add('r1');
      expect(await store.forDelivery('d1'), isNull);

      await store.attachDelivery('r1', 'd1');

      expect((await store.forDelivery('d1'))?.id, 'r1');
      expect((await store.record('r1'))?.deliveryId, 'd1');
    });

    test('attaching an unknown replay changes nothing', () async {
      await store.attachDelivery('ghost', 'd1');

      expect(await store.forDelivery('d1'), isNull);
    });
  });

  group('upload bookkeeping', () {
    test('only replays of scored balls wait for upload, oldest first', () async {
      await add('r1', deliveryId: 'd1');
      await add('r2'); // never scored
      await add('r3', deliveryId: 'd3');

      final List<ReplayRecord> waiting = await store.pendingUploads();

      expect(waiting.map((ReplayRecord r) => r.id), <String>['r1', 'r3']);
    });

    test('the limit is respected', () async {
      await add('r1', deliveryId: 'd1');
      await add('r2', deliveryId: 'd2');
      await add('r3', deliveryId: 'd3');

      expect(await store.pendingUploads(limit: 2), hasLength(2));
    });

    test('starting an upload does not use up an attempt', () async {
      await add('r1', deliveryId: 'd1');

      await store.markUploading('r1');

      final ReplayRecord record = (await store.record('r1'))!;
      expect(record.uploadState, ReplayUploadState.uploading);
      expect(record.attempts, 0);
      expect(await store.pendingUploads(), isEmpty, reason: 'an upload that runs is not waiting');
    });

    test('a refused upload counts as an attempt and is tried again later', () async {
      await add('r1', deliveryId: 'd1');

      await store.markFailed('r1', 'Too big');

      final ReplayRecord record = (await store.record('r1'))!;
      expect(record.uploadState, ReplayUploadState.failed);
      expect(record.attempts, 1);
      expect(record.lastError, 'Too big');
      expect((await store.pendingUploads()).map((ReplayRecord r) => r.id), <String>['r1']);
    });

    test('a lost connection does not count as an attempt', () async {
      await add('r1', deliveryId: 'd1');

      await store.markFailed('r1', 'Offline', countAttempt: false);

      expect((await store.record('r1'))?.attempts, 0);
    });

    test('after eight refusals the replay stays on the phone', () async {
      await add('r1', deliveryId: 'd1');

      for (int i = 0; i < 8; i++) {
        await store.markFailed('r1', 'Refused');
      }

      expect(await store.pendingUploads(), isEmpty);
      expect(await store.hasFile('r1'), isTrue);
    });

    test('an uploaded replay remembers its copy and clears the error', () async {
      await add('r1', deliveryId: 'd1');
      await store.markFailed('r1', 'Refused');

      await store.markUploaded('r1', 'remote-1');

      final ReplayRecord record = (await store.record('r1'))!;
      expect(record.uploadState, ReplayUploadState.uploaded);
      expect(record.isUploaded, isTrue);
      expect(record.remoteId, 'remote-1');
      expect(record.lastError, isNull);
      expect(await store.pendingUploads(), isEmpty);
    });

    test('an upload that was interrupted by a crash goes back in the queue', () async {
      await add('r1', deliveryId: 'd1');
      await add('r2', deliveryId: 'd2');
      await store.markUploading('r1');
      await store.markUploaded('r2', 'remote-2');

      await store.recoverInterrupted();

      expect((await store.record('r1'))?.uploadState, ReplayUploadState.failed);
      expect((await store.record('r2'))?.uploadState, ReplayUploadState.uploaded);
      expect((await store.pendingUploads()).map((ReplayRecord r) => r.id), <String>['r1']);
    });

    test('updating an unknown replay does nothing', () async {
      await store.markUploading('ghost');
      await store.markFailed('ghost', 'x');
      await store.markUploaded('ghost', 'y');

      expect(await store.record('ghost'), isNull);
    });
  });

  group('delete', () {
    test('removes the file and the record', () async {
      await add('r1', deliveryId: 'd1');

      await store.delete('r1');

      expect(await store.record('r1'), isNull);
      expect(await store.forDelivery('d1'), isNull);
      expect(File(p.join(folder.path, 'r1.gur')).existsSync(), isFalse);
    });

    test('deleting an unknown replay is harmless', () async {
      await store.delete('ghost');
    });
  });

  group('prune', () {
    test('a replay of a ball that was never scored goes after six hours', () async {
      await add('old');
      clock.advance(const Duration(hours: 7));

      await add('new');

      expect(await store.record('old'), isNull);
      expect(await store.record('new'), isNotNull);
      expect(File(p.join(folder.path, 'old.gur')).existsSync(), isFalse);
    });

    test('a replay of a scored ball is kept however old it is', () async {
      await add('old', deliveryId: 'd1');
      clock.advance(const Duration(hours: 30));

      await add('new');

      expect(await store.record('old'), isNotNull);
    });

    test('a replay younger than six hours is kept', () async {
      await add('r1');
      clock.advance(const Duration(hours: 5));

      await add('r2');

      expect(await store.record('r1'), isNotNull);
    });

    test('over the count limit the oldest goes first', () async {
      store = makeStore(maxPacks: 2);
      await add('r1');
      await add('r2');

      await add('r3');

      expect(await store.record('r1'), isNull);
      expect(await store.record('r2'), isNotNull);
      expect(await store.record('r3'), isNotNull);
    });

    test('a copy that is safe on the server goes before an older one that is not', () async {
      store = makeStore(maxPacks: 2);
      await add('r1', deliveryId: 'd1');
      await add('r2', deliveryId: 'd2');
      await store.markUploaded('r2', 'remote-2');

      await add('r3', deliveryId: 'd3');

      // Three are over the limit of two: r2 is on the server, so it goes, not the older r1.
      expect(await store.record('r2'), isNull);
      expect(await store.record('r1'), isNotNull);
      expect(await store.record('r3'), isNotNull);
    });

    test('over the size limit the oldest goes first', () async {
      store = makeStore(maxBytes: 10);
      await add('r1', bytes: bytesOf(6));

      await add('r2', bytes: bytesOf(6));

      expect(await store.record('r1'), isNull);
      expect(await store.record('r2'), isNotNull);
    });

    test('nothing is removed while within the limits', () async {
      store = makeStore(maxPacks: 3, maxBytes: 100);
      await add('r1', bytes: bytesOf(10));
      await add('r2', bytes: bytesOf(10));
      await add('r3', bytes: bytesOf(10));

      expect(await store.record('r1'), isNotNull);
      expect(await store.record('r2'), isNotNull);
      expect(await store.record('r3'), isNotNull);
    });
  });

  group('ReplayRecord', () {
    test('survives a trip through a database row', () {
      const ReplayRecord record = ReplayRecord(
        id: 'r1',
        matchId: 'm1',
        deliveryId: 'd1',
        fileName: 'r1.gur',
        sizeBytes: 123,
        createdAtMs: 456,
        uploadState: ReplayUploadState.failed,
        remoteId: 'x',
        attempts: 3,
        lastError: 'oops',
      );

      expect(ReplayRecord.fromRow(record.toRow()), record);
    });

    test('an unknown stored state means local', () {
      expect(ReplayUploadState.fromWire('NONSENSE'), ReplayUploadState.local);
      expect(ReplayUploadState.fromWire(null), ReplayUploadState.local);
      for (final ReplayUploadState state in ReplayUploadState.values) {
        expect(ReplayUploadState.fromWire(state.wire), state);
      }
    });

    test('copyWith can clear the error', () {
      const ReplayRecord record = ReplayRecord(
        id: 'r1',
        matchId: 'm1',
        fileName: 'r1.gur',
        sizeBytes: 1,
        createdAtMs: 1,
        lastError: 'oops',
      );

      expect(record.copyWith(clearError: true).lastError, isNull);
      expect(record.copyWith(attempts: 2).lastError, 'oops');
    });
  });
}
