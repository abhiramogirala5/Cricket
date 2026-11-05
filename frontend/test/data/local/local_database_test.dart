import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/data/local/local_database.dart';
import 'package:gully_umpire/data/local/local_store.dart';
import 'package:gully_umpire/data/local/local_writer.dart';
import 'package:gully_umpire/data/replays/replay_record.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/data_test_support.dart';
import '../../support/model_fixtures.dart';

const List<String> allTables = <String>[
  'teams',
  'players',
  'matches',
  'match_players',
  'match_rules',
  'tosses',
  'innings',
  'deliveries',
  'delivery_decisions',
  'scene_scans',
  'wicket_detections',
  'trajectory_snapshots',
  'outbox',
  'meta',
  'replay_packs',
];

Future<List<String>> tableNames(Database db) async {
  final List<Map<String, Object?>> rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
  );
  return rows.map<String>((Map<String, Object?> row) => row['name']! as String).toList();
}

Future<List<String>> indexNames(Database db) async {
  final List<Map<String, Object?>> rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'index' AND name LIKE 'ix_%' ORDER BY name",
  );
  return rows.map<String>((Map<String, Object?> row) => row['name']! as String).toList();
}

ReplayRecord record(
  String id, {
  String matchId = 'match-1',
  String? deliveryId,
  int createdAtMs = 1000,
  ReplayUploadState state = ReplayUploadState.local,
  int attempts = 0,
}) {
  return ReplayRecord(
    id: id,
    matchId: matchId,
    deliveryId: deliveryId,
    fileName: '$id.gur',
    sizeBytes: 100,
    createdAtMs: createdAtMs,
    uploadState: state,
    attempts: attempts,
  );
}

Directory makeTempDirectory() => Directory.systemTemp.createTempSync('gu_db_');

void main() {
  group('schema', () {
    test('a new database has every table and the replay indexes, at the current version', () async {
      sqfliteFfiInit();
      final Database db = await LocalDatabase.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      addTearDown(db.close);

      expect(await tableNames(db), <String>[...allTables]..sort());
      expect(await indexNames(db), containsAll(<String>['ix_replay_delivery', 'ix_replay_state']));
      expect(await db.getVersion(), LocalDatabase.schemaVersion);
      expect(LocalDatabase.schemaVersion, 2);
    });
  });

  group('upgrade from version 1', () {
    late Directory directory;
    late String path;

    setUp(() {
      sqfliteFfiInit();
      directory = makeTempDirectory();
      path = p.join(directory.path, 'old.db');
    });

    tearDown(() {
      directory.deleteSync(recursive: true);
    });

    /// A database as the first release left it: everything but the replay table, version 1.
    Future<void> writeOldDatabase({bool keepReplayTable = false}) async {
      final Database db = await LocalDatabase.open(factory: databaseFactoryFfi, path: path);
      final LocalStore store = LocalStore(db);
      await store.transaction((LocalWriter w) async {
        await w.putTeam(sampleTeamA);
        await w.setMeta('k', 'v');
        if (keepReplayTable) {
          await w.putReplayRecord(record('replay-1', deliveryId: 'delivery-1'));
        }
      });
      if (!keepReplayTable) {
        await db.execute('DROP TABLE replay_packs');
      }
      await db.setVersion(1);
      await store.close();
    }

    test('adds the replay table and keeps what was stored', () async {
      await writeOldDatabase();

      final Database db = await LocalDatabase.open(factory: databaseFactoryFfi, path: path);
      final LocalStore store = LocalStore(db);
      addTearDown(store.close);

      expect(await db.getVersion(), LocalDatabase.schemaVersion);
      expect(await tableNames(db), contains('replay_packs'));
      expect(await indexNames(db), containsAll(<String>['ix_replay_delivery', 'ix_replay_state']));
      expect((await store.teams()).map((team) => team.id), <String>['team-a']);
      expect(await store.meta('k'), 'v');
    });

    test('the new table is usable straight away', () async {
      await writeOldDatabase();
      final Database db = await LocalDatabase.open(factory: databaseFactoryFfi, path: path);
      final LocalStore store = LocalStore(db);
      addTearDown(store.close);

      await store.transaction((LocalWriter w) => w.putReplayRecord(record('replay-1', deliveryId: 'd-1')));

      expect((await store.replayRecord('replay-1'))!.deliveryId, 'd-1');
    });

    test('an upgrade that was cut short can simply run again', () async {
      await writeOldDatabase(keepReplayTable: true);

      final Database db = await LocalDatabase.open(factory: databaseFactoryFfi, path: path);
      final LocalStore store = LocalStore(db);
      addTearDown(store.close);

      expect(await db.getVersion(), LocalDatabase.schemaVersion);
      expect((await store.replayRecord('replay-1'))!.deliveryId, 'delivery-1');
    });

    test('opening a current database again changes nothing', () async {
      Database db = await LocalDatabase.open(factory: databaseFactoryFfi, path: path);
      LocalStore store = LocalStore(db);
      await store.transaction((LocalWriter w) => w.putReplayRecord(record('replay-1')));
      await store.close();

      db = await LocalDatabase.open(factory: databaseFactoryFfi, path: path);
      store = LocalStore(db);
      addTearDown(store.close);

      expect(await store.replayRecord('replay-1'), isNotNull);
      expect(await db.getVersion(), LocalDatabase.schemaVersion);
    });
  });

  group('replay records', () {
    late LocalStore store;

    setUp(() async {
      store = await openMemoryStore();
    });

    tearDown(() async {
      await store.close();
    });

    Future<void> save(Iterable<ReplayRecord> records) {
      return store.transaction((LocalWriter w) async {
        for (final ReplayRecord r in records) {
          await w.putReplayRecord(r);
        }
      });
    }

    test('a record is stored and read back unchanged', () async {
      final ReplayRecord original = ReplayRecord(
        id: 'replay-1',
        matchId: 'match-1',
        deliveryId: 'delivery-1',
        fileName: 'replay-1.gur',
        sizeBytes: 123456,
        createdAtMs: 5000,
        uploadState: ReplayUploadState.failed,
        remoteId: 'remote-1',
        attempts: 3,
        lastError: 'No signal',
      );

      await save(<ReplayRecord>[original]);

      expect(await store.replayRecord('replay-1'), original);
      expect(await store.replayRecord('nothing'), isNull);
    });

    test('saving a record again replaces it', () async {
      await save(<ReplayRecord>[record('replay-1')]);

      await save(<ReplayRecord>[
        record('replay-1').copyWith(uploadState: ReplayUploadState.uploaded, remoteId: 'remote-9'),
      ]);

      final ReplayRecord stored = (await store.replayRecord('replay-1'))!;
      expect(stored.uploadState, ReplayUploadState.uploaded);
      expect(stored.remoteId, 'remote-9');
      expect(await store.replayRecordsOldestFirst(), hasLength(1));
    });

    test('finds the replay of a delivery, the newest one when there are several', () async {
      await save(<ReplayRecord>[
        record('older', deliveryId: 'd-1', createdAtMs: 100),
        record('newer', deliveryId: 'd-1', createdAtMs: 200),
        record('other', deliveryId: 'd-2', createdAtMs: 300),
      ]);

      expect((await store.replayRecordForDelivery('d-1'))!.id, 'newer');
      expect((await store.replayRecordForDelivery('d-2'))!.id, 'other');
      expect(await store.replayRecordForDelivery('d-3'), isNull);
    });

    test('lists every record, oldest first', () async {
      await save(<ReplayRecord>[
        record('b', createdAtMs: 200),
        record('a', createdAtMs: 100),
        record('c', createdAtMs: 300),
      ]);

      expect((await store.replayRecordsOldestFirst()).map((ReplayRecord r) => r.id), <String>['a', 'b', 'c']);
    });

    test('offers for upload only the replays of saved balls that are not on the server yet', () async {
      await save(<ReplayRecord>[
        record('no-ball-yet', createdAtMs: 100),
        record('waiting', deliveryId: 'd-1', createdAtMs: 200),
        record('failed', deliveryId: 'd-2', createdAtMs: 300, state: ReplayUploadState.failed, attempts: 2),
        record('running', deliveryId: 'd-3', createdAtMs: 400, state: ReplayUploadState.uploading),
        record('done', deliveryId: 'd-4', createdAtMs: 500, state: ReplayUploadState.uploaded),
      ]);

      final List<ReplayRecord> due = await store.replayRecordsToUpload();

      expect(due.map((ReplayRecord r) => r.id), <String>['waiting', 'failed']);
    });

    test('gives up on a replay that failed too often, and honours the limit', () async {
      await save(<ReplayRecord>[
        record('tired', deliveryId: 'd-1', createdAtMs: 100, state: ReplayUploadState.failed, attempts: 8),
        record('one', deliveryId: 'd-2', createdAtMs: 200),
        record('two', deliveryId: 'd-3', createdAtMs: 300),
        record('three', deliveryId: 'd-4', createdAtMs: 400),
      ]);

      expect((await store.replayRecordsToUpload()).map((ReplayRecord r) => r.id), <String>['one', 'two', 'three']);
      expect((await store.replayRecordsToUpload(limit: 2)).map((ReplayRecord r) => r.id), <String>['one', 'two']);
      expect(
        (await store.replayRecordsToUpload(maxAttempts: 9)).map((ReplayRecord r) => r.id).first,
        'tired',
      );
    });

    test('a record can be deleted', () async {
      await save(<ReplayRecord>[record('a'), record('b')]);

      await store.transaction((LocalWriter w) => w.deleteReplayRecord('a'));

      expect(await store.replayRecord('a'), isNull);
      expect(await store.replayRecord('b'), isNotNull);
    });

    test('clearAll removes the records too', () async {
      await save(<ReplayRecord>[record('a', deliveryId: 'd-1')]);
      await store.transaction((LocalWriter w) async {
        await w.putTeam(sampleTeamA);
        await w.setMeta('k', 'v');
      });

      await store.transaction((LocalWriter w) => w.clearAll());

      expect(await store.replayRecordsOldestFirst(), isEmpty);
      expect(await store.replayRecordsToUpload(), isEmpty);
      expect(await store.teams(), isEmpty);
      expect(await store.meta('k'), isNull);
    });

    test('an unknown upload state in a stored row reads as "only on this phone"', () {
      final ReplayRecord read = ReplayRecord.fromRow(<String, Object?>{
        ...record('a').toRow(),
        'upload_state': 'SOMETHING_NEW',
      });

      expect(read.uploadState, ReplayUploadState.local);
    });
  });

  group('deleting an account', () {
    late Directory directory;

    setUp(() async {
      sqfliteFfiInit();
      directory = makeTempDirectory();
      await databaseFactoryFfi.setDatabasesPath(directory.path);
    });

    tearDown(() {
      directory.deleteSync(recursive: true);
    });

    test('removes the database file and the folder of replay files of that account only', () async {
      final String path = await LocalDatabase.pathFor(databaseFactoryFfi, 'user-1');
      final String otherPath = await LocalDatabase.pathFor(databaseFactoryFfi, 'user-2');
      await (await LocalDatabase.open(factory: databaseFactoryFfi, path: path)).close();
      final Database other = await LocalDatabase.open(factory: databaseFactoryFfi, path: otherPath);
      addTearDown(other.close);
      final Directory replays =
          Directory(await LocalDatabase.replayDirectoryPathFor(databaseFactoryFfi, 'user-1'))
            ..createSync(recursive: true);
      File(p.join(replays.path, 'replay-1.gur')).writeAsBytesSync(<int>[1, 2, 3]);
      final Directory otherReplays =
          Directory(await LocalDatabase.replayDirectoryPathFor(databaseFactoryFfi, 'user-2'))
            ..createSync(recursive: true);

      await LocalDatabase.deleteFor(databaseFactoryFfi, 'user-1');

      expect(File(path).existsSync(), isFalse);
      expect(replays.existsSync(), isFalse);
      expect(File(otherPath).existsSync(), isTrue);
      expect(otherReplays.existsSync(), isTrue);
    });

    test('is fine for an account that never had replays', () async {
      final String path = await LocalDatabase.pathFor(databaseFactoryFfi, 'user-3');
      await (await LocalDatabase.open(factory: databaseFactoryFfi, path: path)).close();

      await LocalDatabase.deleteFor(databaseFactoryFfi, 'user-3');

      expect(File(path).existsSync(), isFalse);
    });

    test('the replay folder sits next to the database file and is named after it', () async {
      final String folder = await LocalDatabase.replayDirectoryPathFor(databaseFactoryFfi, 'abc-123');

      expect(folder, p.join(directory.path, 'gully_umpire_abc-123_replays'));
    });
  });
}
