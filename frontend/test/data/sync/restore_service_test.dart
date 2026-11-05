import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/core/errors/app_exception.dart';
import 'package:gully_umpire/data/local/local_store.dart';
import 'package:gully_umpire/data/local/local_writer.dart';
import 'package:gully_umpire/data/remote/remote_read_api.dart';
import 'package:gully_umpire/data/sync/restore_service.dart';
import 'package:gully_umpire/domain/models/models.dart';
import 'package:gully_umpire/domain/sync/match_snapshot.dart';
import 'package:gully_umpire/domain/sync/sync.dart';

import '../../support/data_test_support.dart';
import '../../support/model_fixtures.dart';

/// A [RemoteReadApi] that serves fixed data and can be told to fail for chosen matches.
final class FakeRemoteReadApi implements RemoteReadApi {
  List<Team> remoteTeams = <Team>[];
  List<Player> remotePlayers = <Player>[];
  final Map<String, MatchSnapshot> snapshots = <String, MatchSnapshot>{};
  final Map<String, Object> snapshotErrors = <String, Object>{};
  Object? listError;
  final List<String> snapshotCalls = <String>[];

  @override
  Future<List<Team>> teams() async {
    final Object? error = listError;
    if (error != null) {
      throw error;
    }
    return remoteTeams;
  }

  @override
  Future<List<Player>> players() async => remotePlayers;

  @override
  Future<List<String>> matchIds() async => snapshots.keys.toList();

  @override
  Future<MatchSnapshot> snapshot(String matchId) async {
    snapshotCalls.add(matchId);
    final Object? error = snapshotErrors[matchId];
    if (error != null) {
      throw error;
    }
    return snapshots[matchId]!;
  }
}

MatchSnapshot snapshotOf(
  String matchId, {
  List<Team>? teams,
  List<Player>? players,
  bool withInnings = true,
}) {
  final CricketMatch match = CricketMatch(
    id: matchId,
    teamAId: 'team-a',
    teamBId: 'team-b',
    status: MatchStatus.live,
    oversPerInnings: 6,
    createdAt: t0,
    updatedAt: t1,
  );
  return MatchSnapshot(
    match: match,
    rules: MatchRules(matchId: matchId),
    teams: teams ?? <Team>[sampleTeamA, sampleTeamB],
    players: players ?? <Player>[samplePlayer],
    matchPlayers: <MatchPlayer>[
      MatchPlayer(
        matchId: matchId,
        playerId: samplePlayer.id,
        teamId: 'team-a',
        battingOrder: 1,
      ),
    ],
    innings: withInnings
        ? <Innings>[
            Innings(
              id: 'innings-of-$matchId',
              matchId: matchId,
              inningsNumber: 1,
              battingTeamId: 'team-a',
              bowlingTeamId: 'team-b',
              startedAt: t0,
            ),
          ]
        : const <Innings>[],
    deliveries: const <Delivery>[],
    decisions: const <DecisionRecord>[],
    sceneScans: const <SceneScan>[],
    wicketDetections: const <WicketDetection>[],
    trajectories: const <TrajectorySnapshot>[],
  );
}

void main() {
  late LocalStore store;
  late FakeRemoteReadApi api;
  late FakeClock clock;
  late RestoreService service;

  setUp(() async {
    store = await openMemoryStore();
    api = FakeRemoteReadApi();
    clock = FakeClock();
    service = RestoreService(store: store, api: api, clock: clock);
  });

  tearDown(() async {
    await store.close();
  });

  test('an empty server restores nothing and still records that it ran', () async {
    final RestoreReport report = await service.restoreMissing();

    expect(report.isEmpty, isTrue);
    expect(report.matchesFailed, 0);
    expect(await store.meta(RestoreService.restoredMetaKey), clock.now().toIso8601String());
  });

  test('copies teams, players and matches that this phone does not have', () async {
    api.remoteTeams = <Team>[sampleTeamA, sampleTeamB];
    api.remotePlayers = <Player>[samplePlayer];
    api.snapshots['match-1'] = snapshotOf('match-1');
    api.snapshots['match-2'] = snapshotOf('match-2');

    final RestoreReport report = await service.restoreMissing();

    expect(report.teamsAdded, 2);
    expect(report.playersAdded, 1);
    expect(report.matchesRestored, 2);
    expect(report.matchesFailed, 0);
    expect(await store.matchIds(), <String>{'match-1', 'match-2'});
    expect(await store.teamIds(), <String>{'team-a', 'team-b'});
    expect(await store.playerIds(), <String>{'player-1'});
    expect((await store.inningsOf('match-1')).single.id, 'innings-of-match-1');
    expect(await store.rules('match-2'), isNotNull);
    expect((await store.matchPlayers('match-1')).single.playerId, 'player-1');
  });

  test('restoring never queues anything to send back to the server', () async {
    api.remoteTeams = <Team>[sampleTeamA, sampleTeamB];
    api.remotePlayers = <Player>[samplePlayer];
    api.snapshots['match-1'] = snapshotOf('match-1');

    await service.restoreMissing();

    expect(await store.pendingOutboxCount(), 0);
  });

  test('leaves anything that is already on the phone alone', () async {
    final Team renamed = sampleTeamA.copyWith(name: 'Renamed locally', updatedAt: t1);
    final Player editedPlayer = samplePlayer.copyWith(displayName: 'Asha (edited here)');
    final CricketMatch localMatch = CricketMatch(
      id: 'match-1',
      teamAId: 'team-a',
      teamBId: 'team-b',
      matchName: 'My local copy',
      status: MatchStatus.live,
      oversPerInnings: 3,
      createdAt: t0,
      updatedAt: t1,
    );
    await store.transaction((LocalWriter w) async {
      await w.putTeam(renamed);
      await w.putPlayer(editedPlayer);
      await w.putMatch(localMatch);
    }, notify: false);

    api.remoteTeams = <Team>[sampleTeamA, sampleTeamB];
    api.remotePlayers = <Player>[samplePlayer];
    api.snapshots['match-1'] = snapshotOf('match-1');

    final RestoreReport report = await service.restoreMissing();

    expect(report.teamsAdded, 1, reason: 'only team-b was missing');
    expect(report.playersAdded, 0);
    expect(report.matchesRestored, 0);
    expect(api.snapshotCalls, isEmpty, reason: 'a match that exists locally is not downloaded');
    expect((await store.team('team-a'))!.name, 'Renamed locally');
    expect((await store.player('player-1'))!.displayName, 'Asha (edited here)');
    expect((await store.match('match-1'))!.matchName, 'My local copy');
  });

  test('does not bring back a match that was deleted here but not yet on the server', () async {
    await store.transaction((LocalWriter w) async {
      await w.enqueue(
        OutboxEvent(
          eventId: 'delete-1',
          entityType: SyncEntityType.match,
          action: SyncAction.delete,
          payload: const <String, Object?>{'id': 'match-1'},
          clientCreatedAt: t0,
        ),
      );
    }, notify: false);
    api.snapshots['match-1'] = snapshotOf('match-1');
    api.snapshots['match-2'] = snapshotOf('match-2');

    final RestoreReport report = await service.restoreMissing();

    expect(report.matchesRestored, 1);
    expect(await store.matchIds(), <String>{'match-2'});
    expect(api.snapshotCalls, <String>['match-2']);
  });

  test('a match the server refuses to describe is counted and retried next time', () async {
    api.snapshots['match-1'] = snapshotOf('match-1');
    api.snapshots['match-2'] = snapshotOf('match-2');
    api.snapshotErrors['match-1'] = const ApiException(
      code: 'MATCH_NOT_FOUND',
      message: 'gone',
      statusCode: 404,
    );

    final RestoreReport report = await service.restoreMissing();

    expect(report.matchesRestored, 1);
    expect(report.matchesFailed, 1);
    expect(await store.matchIds(), <String>{'match-2'});
    expect(
      await store.meta(RestoreService.restoredMetaKey),
      isNull,
      reason: 'the restore is not complete, so it must not be marked as done',
    );

    api.snapshotErrors.clear();
    final RestoreReport second = await service.restoreMissing();
    expect(second.matchesRestored, 1);
    expect(second.matchesFailed, 0);
    expect(await store.matchIds(), <String>{'match-1', 'match-2'});
    expect(await store.meta(RestoreService.restoredMetaKey), isNotNull);
  });

  test('an unreadable snapshot is skipped without stopping the others', () async {
    api.snapshots['match-1'] = snapshotOf('match-1');
    api.snapshots['match-2'] = snapshotOf('match-2');
    api.snapshotErrors['match-1'] = const FormatException('bad date');

    final RestoreReport report = await service.restoreMissing();

    expect(report.matchesRestored, 1);
    expect(report.matchesFailed, 1);
    expect(await store.matchIds(), <String>{'match-2'});
  });

  test('connection and server problems stop the restore so it can be retried later', () async {
    api.snapshots['match-1'] = snapshotOf('match-1');

    api.snapshotErrors['match-1'] = const NetworkException();
    await expectLater(service.restoreMissing(), throwsA(isA<NetworkException>()));

    api.snapshotErrors['match-1'] = const ApiException(
      code: 'HTTP_503',
      message: 'down',
      statusCode: 503,
    );
    await expectLater(service.restoreMissing(), throwsA(isA<ApiException>()));

    api.snapshotErrors['match-1'] = const ApiException(
      code: 'RATE_LIMITED',
      message: 'slow down',
      statusCode: 429,
    );
    await expectLater(service.restoreMissing(), throwsA(isA<ApiException>()));

    api.snapshotErrors['match-1'] = const SessionExpiredException();
    await expectLater(service.restoreMissing(), throwsA(isA<SessionExpiredException>()));

    expect(await store.matchIds(), isEmpty);
  });

  test('a failure while listing stops before anything is written', () async {
    api.listError = const NetworkException();
    api.snapshots['match-1'] = snapshotOf('match-1');

    await expectLater(service.restoreMissing(), throwsA(isA<NetworkException>()));

    expect(await store.matchIds(), isEmpty);
    expect(await store.meta(RestoreService.restoredMetaKey), isNull);
  });

  test('teams and players that a restored match needs are added if they are missing', () async {
    final Player extra = Player(
      id: 'player-extra',
      displayName: 'Chitra',
      createdAt: t0,
      updatedAt: t0,
    );
    api.snapshots['match-1'] = snapshotOf(
      'match-1',
      players: <Player>[samplePlayer, extra],
    );

    final RestoreReport report = await service.restoreMissing();

    expect(report.matchesRestored, 1);
    expect(await store.playerIds(), <String>{'player-1', 'player-extra'});
    expect(await store.teamIds(), <String>{'team-a', 'team-b'});
  });

  test('restoring twice in a row changes nothing the second time', () async {
    api.remoteTeams = <Team>[sampleTeamA, sampleTeamB];
    api.remotePlayers = <Player>[samplePlayer];
    api.snapshots['match-1'] = snapshotOf('match-1');

    await service.restoreMissing();
    final RestoreReport again = await service.restoreMissing();

    expect(again.isEmpty, isTrue);
    expect(api.snapshotCalls, <String>['match-1']);
  });
}
