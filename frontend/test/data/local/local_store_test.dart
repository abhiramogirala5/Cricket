import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/data/local/local_database.dart';
import 'package:gully_umpire/data/local/local_store.dart';
import 'package:gully_umpire/data/local/local_writer.dart';
import 'package:gully_umpire/domain/aggregates/match_bundle.dart';
import 'package:gully_umpire/domain/models/models.dart';
import 'package:gully_umpire/domain/sync/sync.dart';

import '../../support/data_test_support.dart';
import '../../support/model_fixtures.dart';

OutboxEvent eventNumber(
  int n, {
  String? matchId,
  SyncEntityType type = SyncEntityType.delivery,
  SyncAction action = SyncAction.upsert,
  Map<String, Object?>? payload,
}) =>
    OutboxEvent(
      eventId: 'event-$n',
      entityType: type,
      action: action,
      payload: payload ?? <String, Object?>{'n': n},
      clientCreatedAt: t0,
      matchId: matchId,
    );

void main() {
  late LocalStore store;

  setUp(() async {
    store = await openMemoryStore();
  });

  tearDown(() async {
    await store.close();
  });

  group('file names', () {
    test('one database file per user, with unsafe characters replaced', () {
      expect(LocalDatabase.fileNameFor('abc-123'), 'gully_umpire_abc-123.db');
      expect(LocalDatabase.fileNameFor('a/b c'), 'gully_umpire_a_b_c.db');
      expect(LocalDatabase.fileNameFor(''), 'gully_umpire_local.db');
    });
  });

  group('entities', () {
    test('every entity is stored and read back unchanged', () async {
      await store.transaction((LocalWriter w) async {
        await w.putTeam(sampleTeamA);
        await w.putTeam(sampleTeamB);
        await w.putPlayer(samplePlayer);
        await w.putMatch(sampleMatch);
        await w.putMatchPlayer(sampleMatchPlayer);
        await w.putRules(sampleRules);
        await w.putToss(sampleToss);
        await w.putInnings(sampleInnings);
        await w.putDelivery(sampleDelivery);
        await w.putDecision(sampleDecision);
        await w.putSceneScan(sampleScan);
        await w.putWicketDetection(sampleWicket);
        await w.putTrajectory(sampleTrajectory);
      });

      expect(await store.teams(), <Team>[sampleTeamB, sampleTeamA]);
      expect(await store.team('team-a'), sampleTeamA);
      expect(await store.player('player-1'), samplePlayer);
      expect(await store.match('match-1'), sampleMatch);
      expect(await store.matchPlayers('match-1'), <MatchPlayer>[sampleMatchPlayer]);
      expect(await store.rules('match-1'), sampleRules);
      expect(await store.toss('match-1'), sampleToss);
      expect(await store.inningsOf('match-1'), <Innings>[sampleInnings]);
      expect(await store.inningsById('innings-1'), sampleInnings);
      expect(await store.deliveries('innings-1'), <Delivery>[sampleDelivery]);
      expect(await store.delivery('delivery-1'), sampleDelivery);
      expect(await store.decisionsOfDelivery('delivery-1'), <DecisionRecord>[sampleDecision]);
      expect(await store.decisionsOfMatch('match-1'), <DecisionRecord>[sampleDecision]);
      expect(await store.sceneScans('match-1'), <SceneScan>[sampleScan]);
      expect(await store.wicketDetections('match-1'), <WicketDetection>[sampleWicket]);
      expect(await store.trajectoryOfDelivery('delivery-1'), sampleTrajectory);
    });

    test('missing rows read as null or empty', () async {
      expect(await store.team('nope'), isNull);
      expect(await store.match('nope'), isNull);
      expect(await store.toss('nope'), isNull);
      expect(await store.rules('nope'), isNull);
      expect(await store.deliveries('nope'), isEmpty);
      expect(await store.bundle('nope'), isNull);
    });

    test('writing the same id again replaces the row', () async {
      await store.transaction((LocalWriter w) async {
        await w.putTeam(sampleTeamA);
        await w.putTeam(sampleTeamA.copyWith(name: 'Red Dragons', updatedAt: t1));
      });
      final List<Team> teams = await store.teams();
      expect(teams, hasLength(1));
      expect(teams.single.name, 'Red Dragons');
    });

    test('the roster is ordered by name, ignoring case', () async {
      await store.transaction((LocalWriter w) async {
        await w.putPlayer(Player(id: 'p1', displayName: 'zed', createdAt: t0, updatedAt: t0));
        await w.putPlayer(Player(id: 'p2', displayName: 'Anil', createdAt: t0, updatedAt: t0));
        await w.putPlayer(Player(id: 'p3', displayName: 'bala', createdAt: t0, updatedAt: t0));
      });
      final List<Player> players = await store.players();
      expect(players.map((Player p) => p.displayName), <String>['Anil', 'bala', 'zed']);
    });

    test('matches come newest first', () async {
      CricketMatch matchAt(String id, DateTime created) => CricketMatch(
            id: id,
            teamAId: 'team-a',
            teamBId: 'team-b',
            createdAt: created,
            updatedAt: created,
          );
      await store.transaction((LocalWriter w) async {
        await w.putMatch(matchAt('old', DateTime.utc(2026, 1, 1)));
        await w.putMatch(matchAt('new', DateTime.utc(2026, 6, 1)));
        await w.putMatch(matchAt('mid', DateTime.utc(2026, 3, 1)));
      });
      final List<CricketMatch> matches = await store.matches();
      expect(matches.map((CricketMatch m) => m.id), <String>['new', 'mid', 'old']);
    });

    test('deliveries come in the order they were bowled', () async {
      Delivery ball(String id, int sequence) => Delivery(
            id: id,
            inningsId: 'innings-1',
            deliverySequence: sequence,
            overNumber: 0,
            bowlerId: 'b',
            strikerId: 's',
            createdAt: t0,
          );
      await store.transaction((LocalWriter w) async {
        await w.putDelivery(ball('c', 3));
        await w.putDelivery(ball('a', 1));
        await w.putDelivery(ball('b', 2));
      });
      final List<Delivery> balls = await store.deliveries('innings-1');
      expect(balls.map((Delivery d) => d.id), <String>['a', 'b', 'c']);
    });
  });

  group('bundle', () {
    test('assembles the match with its teams, squad, innings and balls', () async {
      await store.transaction((LocalWriter w) async {
        await w.putTeam(sampleTeamA);
        await w.putTeam(sampleTeamB);
        await w.putPlayer(samplePlayer);
        await w.putMatch(sampleMatch);
        await w.putMatchPlayer(sampleMatchPlayer);
        await w.putRules(sampleRules);
        await w.putToss(sampleToss);
        await w.putInnings(sampleInnings);
        await w.putDelivery(sampleDelivery);
        await w.putDecision(sampleDecision);
        await w.putSceneScan(sampleScan);
        await w.putWicketDetection(sampleWicket);
      });
      final MatchBundle? bundle = await store.bundle('match-1');
      expect(bundle, isNotNull);
      expect(bundle!.match, sampleMatch);
      expect(bundle.teamA, sampleTeamA);
      expect(bundle.teamB, sampleTeamB);
      expect(bundle.rules, sampleRules);
      expect(bundle.toss, sampleToss);
      expect(bundle.players.keys, <String>['player-1']);
      expect(bundle.deliveriesOf('innings-1'), <Delivery>[sampleDelivery]);
      expect(bundle.decisionsOf('delivery-1'), <DecisionRecord>[sampleDecision]);
      expect(bundle.activeWicket, sampleWicket);
      expect(bundle.latestScan, sampleScan);
      expect(bundle.currentInnings, sampleInnings);
    });

    test('is null when one of the teams is missing', () async {
      await store.transaction((LocalWriter w) async {
        await w.putTeam(sampleTeamA);
        await w.putMatch(sampleMatch);
      });
      expect(await store.bundle('match-1'), isNull);
    });
  });

  group('deleting a match', () {
    test('removes the match and all its parts but keeps the roster', () async {
      await store.transaction((LocalWriter w) async {
        await w.putTeam(sampleTeamA);
        await w.putTeam(sampleTeamB);
        await w.putPlayer(samplePlayer);
        await w.putMatch(sampleMatch);
        await w.putMatchPlayer(sampleMatchPlayer);
        await w.putRules(sampleRules);
        await w.putToss(sampleToss);
        await w.putInnings(sampleInnings);
        await w.putDelivery(sampleDelivery);
        await w.putDecision(sampleDecision);
        await w.putSceneScan(sampleScan);
        await w.putWicketDetection(sampleWicket);
        await w.putTrajectory(sampleTrajectory);
      });
      await store.transaction((LocalWriter w) async {
        await w.deleteMatchData('match-1');
      });
      expect(await store.match('match-1'), isNull);
      expect(await store.matchPlayers('match-1'), isEmpty);
      expect(await store.rules('match-1'), isNull);
      expect(await store.toss('match-1'), isNull);
      expect(await store.inningsOf('match-1'), isEmpty);
      expect(await store.deliveries('innings-1'), isEmpty);
      expect(await store.decisionsOfMatch('match-1'), isEmpty);
      expect(await store.sceneScans('match-1'), isEmpty);
      expect(await store.wicketDetections('match-1'), isEmpty);
      expect(await store.trajectoryOfDelivery('delivery-1'), isNull);
      expect(await store.teams(), hasLength(2));
      expect(await store.players(), hasLength(1));
    });

    test('leaves other matches alone', () async {
      final CricketMatch other = CricketMatch(
        id: 'match-2',
        teamAId: 'team-a',
        teamBId: 'team-b',
        createdAt: t0,
        updatedAt: t0,
      );
      await store.transaction((LocalWriter w) async {
        await w.putMatch(sampleMatch);
        await w.putMatch(other);
        await w.putInnings(sampleInnings);
      });
      await store.transaction((LocalWriter w) async {
        await w.deleteMatchData('match-1');
      });
      expect(await store.match('match-2'), other);
    });
  });

  group('transactions', () {
    test('a failure rolls everything back', () async {
      await expectLater(
        store.transaction((LocalWriter w) async {
          await w.putTeam(sampleTeamA);
          throw StateError('boom');
        }),
        throwsStateError,
      );
      expect(await store.teams(), isEmpty);
    });

    test('a committed transaction is announced on changes', () async {
      int announcements = 0;
      final subscription = store.changes.listen((_) => announcements += 1);
      await store.transaction((LocalWriter w) async {
        await w.putTeam(sampleTeamA);
      });
      await store.transaction((LocalWriter w) async {
        await w.putTeam(sampleTeamB);
      }, notify: false);
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();
      expect(announcements, 1);
    });

    test('a failed transaction is not announced', () async {
      int announcements = 0;
      final subscription = store.changes.listen((_) => announcements += 1);
      await expectLater(
        store.transaction((LocalWriter w) async {
          throw StateError('boom');
        }),
        throwsStateError,
      );
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();
      expect(announcements, 0);
    });
  });

  group('outbox', () {
    test('events are returned oldest first and counted', () async {
      await store.transaction((LocalWriter w) async {
        await w.enqueue(eventNumber(1));
        await w.enqueue(eventNumber(2));
        await w.enqueue(eventNumber(3));
      });
      final List<OutboxEvent> batch = await store.outboxBatch(100);
      expect(batch.map((OutboxEvent e) => e.eventId), <String>['event-1', 'event-2', 'event-3']);
      expect(batch.first.seq, isNotNull);
      expect(batch.first.payload, <String, Object?>{'n': 1});
      expect(batch.first.status, OutboxStatus.pending);
      expect(await store.pendingOutboxCount(), 3);
      expect(await store.failedOutboxCount(), 0);
    });

    test('the batch size limits how many events are returned', () async {
      await store.transaction((LocalWriter w) async {
        for (int i = 1; i <= 5; i++) {
          await w.enqueue(eventNumber(i));
        }
      });
      expect(await store.outboxBatch(2), hasLength(2));
    });

    test('the same event id cannot be queued twice', () async {
      await store.transaction((LocalWriter w) async {
        await w.enqueue(eventNumber(1));
      });
      await expectLater(
        store.transaction((LocalWriter w) async {
          await w.enqueue(eventNumber(1));
        }),
        throwsA(anything),
      );
      expect(await store.pendingOutboxCount(), 1);
    });

    test('accepted events are removed', () async {
      await store.transaction((LocalWriter w) async {
        await w.enqueue(eventNumber(1));
        await w.enqueue(eventNumber(2));
        await w.enqueue(eventNumber(3));
      });
      await store.transaction((LocalWriter w) async {
        await w.deleteOutboxEvents(<String>['event-1', 'event-3']);
        await w.deleteOutboxEvents(<String>[]);
      });
      final List<OutboxEvent> left = await store.allOutboxEvents();
      expect(left.map((OutboxEvent e) => e.eventId), <String>['event-2']);
    });

    test('a failed event keeps its error and is no longer pending', () async {
      await store.transaction((LocalWriter w) async {
        await w.enqueue(eventNumber(1));
        await w.markOutboxFailed('event-1', code: 'INVALID_DELIVERY', message: 'nope');
      });
      expect(await store.pendingOutboxCount(), 0);
      expect(await store.failedOutboxCount(), 1);
      final OutboxEvent failed = (await store.failedOutboxEvents()).single;
      expect(failed.status, OutboxStatus.failed);
      expect(failed.errorCode, 'INVALID_DELIVERY');
      expect(failed.errorMessage, 'nope');
      expect(failed.attempts, 1);
    });

    test('later events of a match wait behind a failed one; other matches do not', () async {
      await store.transaction((LocalWriter w) async {
        await w.enqueue(eventNumber(1, matchId: 'm1'));
        await w.enqueue(eventNumber(2, matchId: 'm1'));
        await w.enqueue(eventNumber(3, matchId: 'm2'));
        await w.enqueue(eventNumber(4, type: SyncEntityType.player));
        await w.markOutboxFailed('event-1', code: 'INVALID_DELIVERY');
      });
      final List<OutboxEvent> batch = await store.outboxBatch(100);
      expect(batch.map((OutboxEvent e) => e.eventId), <String>['event-3', 'event-4']);
    });

    test('an event with an earlier failure in ANOTHER match is not held back', () async {
      await store.transaction((LocalWriter w) async {
        await w.enqueue(eventNumber(1, matchId: 'm1'));
        await w.enqueue(eventNumber(2, matchId: 'm2'));
        await w.markOutboxFailed('event-2', code: 'INVALID_DELIVERY');
        await w.enqueue(eventNumber(3, matchId: 'm1'));
      });
      final List<OutboxEvent> batch = await store.outboxBatch(100);
      expect(batch.map((OutboxEvent e) => e.eventId), <String>['event-1', 'event-3']);
    });

    test('retrying puts a failed event back at its original place', () async {
      await store.transaction((LocalWriter w) async {
        await w.enqueue(eventNumber(1, matchId: 'm1'));
        await w.enqueue(eventNumber(2, matchId: 'm1'));
        await w.markOutboxFailed('event-1', code: 'INVALID_DELIVERY', message: 'x');
      });
      await store.transaction((LocalWriter w) async {
        await w.requeueOutboxEvent('event-1');
      });
      final List<OutboxEvent> batch = await store.outboxBatch(100);
      expect(batch.map((OutboxEvent e) => e.eventId), <String>['event-1', 'event-2']);
      expect(batch.first.attempts, 0);
      expect(batch.first.errorCode, isNull);
    });

    test('retry all re-queues every failed event', () async {
      await store.transaction((LocalWriter w) async {
        await w.enqueue(eventNumber(1));
        await w.enqueue(eventNumber(2));
        await w.markOutboxFailed('event-1', code: 'FORBIDDEN');
        await w.markOutboxFailed('event-2', code: 'INVALID_STATE');
      });
      late int changed;
      await store.transaction((LocalWriter w) async {
        changed = await w.requeueAllFailed();
      });
      expect(changed, 2);
      expect(await store.failedOutboxCount(), 0);
      expect(await store.pendingOutboxCount(), 2);
    });

    test('only "retry later" errors are re-queued automatically, and only a few times', () async {
      await store.transaction((LocalWriter w) async {
        await w.enqueue(eventNumber(1));
        await w.enqueue(eventNumber(2));
        await w.enqueue(eventNumber(3));
        await w.markOutboxFailed('event-1', code: SyncErrorCodes.parentNotFound);
        await w.markOutboxFailed('event-2', code: SyncErrorCodes.invalidDelivery);
        await w.markOutboxFailed('event-3', code: SyncErrorCodes.internalError);
        await w.markOutboxFailed('event-3', code: SyncErrorCodes.internalError);
        await w.markOutboxFailed('event-3', code: SyncErrorCodes.internalError);
      });
      late int changed;
      await store.transaction((LocalWriter w) async {
        changed = await w.requeueRetryableFailures(maxAttempts: 3);
      });
      expect(changed, 1);
      expect((await store.outboxBatch(10)).map((OutboxEvent e) => e.eventId), <String>['event-1']);
      expect(await store.failedOutboxCount(), 2);
    });

    test('a discarded event disappears', () async {
      await store.transaction((LocalWriter w) async {
        await w.enqueue(eventNumber(1));
        await w.discardOutboxEvent('event-1');
      });
      expect(await store.allOutboxEvents(), isEmpty);
    });

    test('dropping a match removes only its events', () async {
      await store.transaction((LocalWriter w) async {
        await w.enqueue(eventNumber(1, matchId: 'm1'));
        await w.enqueue(eventNumber(2, matchId: 'm2'));
        await w.enqueue(eventNumber(3));
        await w.dropOutboxForMatch('m1');
      });
      final List<OutboxEvent> left = await store.allOutboxEvents();
      expect(left.map((OutboxEvent e) => e.eventId), <String>['event-2', 'event-3']);
    });

    test('matches waiting for their deletion to be sent are listed', () async {
      await store.transaction((LocalWriter w) async {
        await w.enqueue(eventNumber(
          1,
          type: SyncEntityType.match,
          action: SyncAction.delete,
          payload: <String, Object?>{'id': 'm9'},
        ));
        await w.enqueue(eventNumber(2, type: SyncEntityType.match, payload: <String, Object?>{'id': 'm8'}));
      });
      expect(await store.matchesPendingDeletion(), <String>{'m9'});
    });

    test('the request json has exactly the contract keys', () async {
      final OutboxEvent event = eventNumber(1, matchId: 'm1');
      expect(event.toRequestJson(), <String, Object?>{
        'event_id': 'event-1',
        'entity_type': 'DELIVERY',
        'action': 'UPSERT',
        'payload': <String, Object?>{'n': 1},
        'client_created_at': '2026-10-08T07:33:00.000Z',
      });
    });
  });

  group('meta and clearing', () {
    test('meta values are stored and replaced', () async {
      expect(await store.meta('k'), isNull);
      await store.transaction((LocalWriter w) async {
        await w.setMeta('k', 'one');
        await w.setMeta('k', 'two');
      });
      expect(await store.meta('k'), 'two');
    });

    test('clearAll empties every table', () async {
      await store.transaction((LocalWriter w) async {
        await w.putTeam(sampleTeamA);
        await w.putPlayer(samplePlayer);
        await w.putMatch(sampleMatch);
        await w.enqueue(eventNumber(1));
        await w.setMeta('k', 'v');
      });
      await store.transaction((LocalWriter w) async {
        await w.clearAll();
      });
      expect(await store.teams(), isEmpty);
      expect(await store.players(), isEmpty);
      expect(await store.matches(), isEmpty);
      expect(await store.allOutboxEvents(), isEmpty);
      expect(await store.meta('k'), isNull);
    });
  });
}
