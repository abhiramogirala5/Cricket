import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/data/local/local_store.dart';
import 'package:gully_umpire/data/repositories/roster_repository.dart';
import 'package:gully_umpire/domain/models/models.dart';
import 'package:gully_umpire/domain/setup/match_setup.dart';
import 'package:gully_umpire/domain/sync/sync.dart';

import '../../support/data_test_support.dart';

void main() {
  late LocalStore store;
  late FakeClock clock;
  late SequenceIds ids;

  RosterRepository makeRepo({bool syncEnabled = true}) => RosterRepository(
        store: store,
        clock: clock,
        ids: ids,
        syncEnabled: syncEnabled,
      );

  setUp(() async {
    store = await openMemoryStore();
    clock = FakeClock();
    ids = SequenceIds();
  });

  tearDown(() async {
    await store.close();
  });

  group('createPlayer', () {
    test('saves the player and queues one PLAYER event with the contract payload', () async {
      final RosterRepository repo = makeRepo();

      final Player player = await repo.createPlayer(
        displayName: '  Asha Rao ',
        battingHand: BattingHand.left,
        declaredHeightCm: 168,
      );

      expect(player.id, 'id-0001');
      expect(player.displayName, 'Asha Rao');
      expect(player.battingHand, BattingHand.left);
      expect(player.createdAt, clock.now());
      expect(player.updatedAt, clock.now());
      expect((await repo.players()).single, player);

      final List<OutboxEvent> events = await store.allOutboxEvents();
      expect(events, hasLength(1));
      expect(events.single.eventId, 'id-0002');
      expect(events.single.entityType, SyncEntityType.player);
      expect(events.single.action, SyncAction.upsert);
      expect(events.single.payload, <String, Object?>{
        'id': 'id-0001',
        'display_name': 'Asha Rao',
        'batting_hand': 'LEFT',
        'declared_height_cm': 168,
      });
    });

    test('works without an account: nothing is queued when sync is off', () async {
      final RosterRepository repo = makeRepo(syncEnabled: false);

      await repo.createPlayer(displayName: 'Asha');

      expect(await repo.players(), hasLength(1));
      expect(await store.pendingOutboxCount(), 0);
    });

    test('rejects a name that is empty or too long and saves nothing', () async {
      final RosterRepository repo = makeRepo();

      await expectLater(repo.createPlayer(displayName: '   '), throwsA(isA<SetupException>()));
      await expectLater(
        repo.createPlayer(displayName: 'A' * (MatchSetupLimits.maxNameLength + 1)),
        throwsA(isA<SetupException>()),
      );

      expect(await repo.players(), isEmpty);
      expect(await store.pendingOutboxCount(), 0);
    });

    test('rejects an impossible height', () async {
      final RosterRepository repo = makeRepo();

      await expectLater(
        repo.createPlayer(displayName: 'Asha', declaredHeightCm: 20),
        throwsA(isA<SetupException>()),
      );
      await expectLater(
        repo.createPlayer(displayName: 'Asha', declaredHeightCm: 400),
        throwsA(isA<SetupException>()),
      );
      expect(await repo.players(), isEmpty);
    });
  });

  group('updatePlayer', () {
    test('changes only what was given, moves updatedAt and queues the new version', () async {
      final RosterRepository repo = makeRepo();
      final Player original = await repo.createPlayer(
        displayName: 'Asha',
        battingHand: BattingHand.right,
        declaredHeightCm: 165,
      );
      clock.advance(const Duration(minutes: 5));

      final Player updated = await repo.updatePlayer(original, displayName: 'Asha Rao');

      expect(updated.id, original.id);
      expect(updated.displayName, 'Asha Rao');
      expect(updated.battingHand, BattingHand.right);
      expect(updated.declaredHeightCm, 165);
      expect(updated.createdAt, original.createdAt);
      expect(updated.updatedAt, clock.now());
      expect((await repo.players()).single, updated);

      final List<OutboxEvent> events = await store.allOutboxEvents();
      expect(events, hasLength(2));
      expect(events.last.payload['display_name'], 'Asha Rao');
      expect(events.last.payload['declared_height_cm'], 165);
    });

    test('can change the batting hand', () async {
      final RosterRepository repo = makeRepo();
      final Player original = await repo.createPlayer(displayName: 'Asha');

      final Player updated = await repo.updatePlayer(original, battingHand: BattingHand.left);

      expect(updated.battingHand, BattingHand.left);
      expect((await store.player(original.id))!.battingHand, BattingHand.left);
    });

    test('can remove a saved height, and a new height replaces the old one', () async {
      final RosterRepository repo = makeRepo();
      final Player original = await repo.createPlayer(displayName: 'Asha', declaredHeightCm: 165);

      final Player taller = await repo.updatePlayer(original, declaredHeightCm: 172);
      expect(taller.declaredHeightCm, 172);

      final Player cleared = await repo.updatePlayer(taller, clearHeight: true);
      expect(cleared.declaredHeightCm, isNull);
      expect((await store.player(original.id))!.declaredHeightCm, isNull);

      final List<OutboxEvent> events = await store.allOutboxEvents();
      expect(events.last.payload['declared_height_cm'], isNull);
      expect(events.last.payload.containsKey('declared_height_cm'), isTrue);
    });

    test('rejects an invalid name and keeps the saved player unchanged', () async {
      final RosterRepository repo = makeRepo();
      final Player original = await repo.createPlayer(displayName: 'Asha');

      await expectLater(
        repo.updatePlayer(original, displayName: ' '),
        throwsA(isA<SetupException>()),
      );

      expect((await store.player(original.id))!.displayName, 'Asha');
      expect(await store.pendingOutboxCount(), 1, reason: 'only the original create is queued');
    });
  });

  test('teams are read from the store', () async {
    final RosterRepository repo = makeRepo();
    expect(await repo.teams(), isEmpty);
  });
}
