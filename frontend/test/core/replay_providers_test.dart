import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/core/di/data_providers.dart';
import 'package:gully_umpire/core/di/replay_providers.dart';
import 'package:gully_umpire/cv/live/replay_codec.dart';
import 'package:gully_umpire/data/local/local_store.dart';
import 'package:gully_umpire/data/remote/replay_api.dart';
import 'package:gully_umpire/data/replays/replay_record.dart';
import 'package:gully_umpire/data/replays/replay_store.dart';
import 'package:path/path.dart' as p;

import '../data/replays/replay_test_support.dart';
import '../support/data_test_support.dart';

void main() {
  late LocalStore database;
  late Directory root;
  late ReplayStore store;
  late FakeReplayApi api;
  late FakeClock clock;

  ProviderContainer containerWith({ReplayStore? replays, ReplayApi? remote}) {
    final ProviderContainer container = ProviderContainer(
      overrides: [
        replayStoreProvider.overrideWithValue(replays),
        replayApiProvider.overrideWithValue(remote),
        dataChangesProvider.overrideWith((ref) => Stream<int>.value(0)),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<ReplayLookup> lookup(ProviderContainer container, String deliveryId) async {
    final ProviderSubscription<AsyncValue<ReplayLookup>> keepAlive =
        container.listen(replayLookupProvider(deliveryId), (previous, next) {});
    try {
      return await container.read(replayLookupProvider(deliveryId).future);
    } finally {
      keepAlive.close();
    }
  }

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
  });

  tearDown(() async {
    await database.close();
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  });

  group('replayLookupProvider', () {
    test('a replay on this phone is found without asking the server', () async {
      await store.save(id: 'r1', matchId: 'm1', bytes: makeReplayBytes(), deliveryId: 'd1');
      final ProviderContainer container = containerWith(replays: store, remote: api);

      final ReplayLookup found = await lookup(container, 'd1');

      expect(found.availability, ReplayAvailability.onThisPhone);
      expect(found.replayId, 'r1');
      expect(api.calls, isEmpty);
    });

    test('a replay that only the server has is offered for download', () async {
      api.byDelivery['d1'] = const <RemoteReplay>[RemoteReplay(id: 'remote-1', sizeBytes: 10)];
      final ProviderContainer container = containerWith(replays: store, remote: api);

      final ReplayLookup found = await lookup(container, 'd1');

      expect(found.availability, ReplayAvailability.online);
      expect(found.replayId, 'remote-1');
    });

    test('a record whose file is gone falls back to the server', () async {
      await store.save(id: 'r1', matchId: 'm1', bytes: makeReplayBytes(), deliveryId: 'd1');
      File(p.join(root.path, 'replays', 'r1.gur')).deleteSync();
      api.byDelivery['d1'] = const <RemoteReplay>[RemoteReplay(id: 'remote-1', sizeBytes: 10)];
      final ProviderContainer container = containerWith(replays: store, remote: api);

      final ReplayLookup found = await lookup(container, 'd1');

      expect(found.availability, ReplayAvailability.online);
    });

    test('a ball without a replay has none', () async {
      final ProviderContainer container = containerWith(replays: store, remote: api);

      final ReplayLookup found = await lookup(container, 'd1');

      expect(found.availability, ReplayAvailability.none);
      expect(found.replayId, isNull);
    });

    test('a server that cannot be reached simply means no replay', () async {
      api.listError = StateError('offline');
      final ProviderContainer container = containerWith(replays: store, remote: api);

      final ReplayLookup found = await lookup(container, 'd1');

      expect(found.availability, ReplayAvailability.none);
    });

    test('without a server (local-only mode) only the phone is searched', () async {
      final ProviderContainer container = containerWith(replays: store);

      expect((await lookup(container, 'd1')).availability, ReplayAvailability.none);

      await store.save(id: 'r1', matchId: 'm1', bytes: makeReplayBytes(), deliveryId: 'd2');
      expect((await lookup(container, 'd2')).availability, ReplayAvailability.onThisPhone);
    });

    test('without an open account there is nothing to find', () async {
      final ProviderContainer container = containerWith(remote: api);

      expect((await lookup(container, 'd1')).availability, ReplayAvailability.none);
      expect(api.calls, isEmpty);
    });
  });

  group('downloadReplay', () {
    test('keeps the downloaded file on the phone for that ball and marks it as on the server',
        () async {
      final Uint8List bytes = makeReplayBytes();
      api.downloads['remote-1'] = bytes;

      final String id = await downloadReplay(
        store: store,
        api: api,
        remoteId: 'remote-1',
        matchId: 'm1',
        deliveryId: 'd1',
      );

      expect(id, 'remote-1');
      expect(await store.read('remote-1'), bytes);
      final ReplayRecord record = (await store.forDelivery('d1'))!;
      expect(record.id, 'remote-1');
      expect(record.matchId, 'm1');
      expect(record.isUploaded, isTrue);
      expect(record.remoteId, 'remote-1');
    });

    test('a file that cannot be played is refused and not kept', () async {
      api.downloads['remote-1'] = Uint8List.fromList(List<int>.filled(40, 3));

      await expectLater(
        downloadReplay(
          store: store,
          api: api,
          remoteId: 'remote-1',
          matchId: 'm1',
          deliveryId: 'd1',
        ),
        throwsA(isA<ReplayFormatException>()),
      );

      expect(await store.record('remote-1'), isNull);
    });

    test('a failed download is passed on and nothing is kept', () async {
      api.downloadError = StateError('gone');

      await expectLater(
        downloadReplay(
          store: store,
          api: api,
          remoteId: 'remote-1',
          matchId: 'm1',
          deliveryId: 'd1',
        ),
        throwsStateError,
      );

      expect(await store.record('remote-1'), isNull);
    });
  });
}
