import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/data/local/local_store.dart';
import 'package:gully_umpire/data/repositories/match_repository.dart';
import 'package:gully_umpire/data/repositories/repository_inputs.dart';
import 'package:gully_umpire/domain/aggregates/match_bundle.dart';
import 'package:gully_umpire/domain/aggregates/match_list_item.dart';
import 'package:gully_umpire/domain/decisions/decisions.dart';
import 'package:gully_umpire/domain/models/models.dart';
import 'package:gully_umpire/domain/scoring/scoring.dart';
import 'package:gully_umpire/domain/setup/match_setup.dart';
import 'package:gully_umpire/domain/sync/sync.dart';

import '../../support/data_test_support.dart';

/// A match that has been created and whose first innings has started.
class Game {
  Game(this.bundle, this.innings)
      : batters = bundle.battingOrderIds(innings.battingTeamId),
        bowlers = bundle.battingOrderIds(innings.bowlingTeamId);

  final MatchBundle bundle;
  final Innings innings;
  final List<String> batters;
  final List<String> bowlers;

  String get matchId => bundle.match.id;
}

RosterEntryInput person(
  String name, {
  bool captain = false,
  bool keeper = false,
  BattingHand hand = BattingHand.unknown,
  int? height,
  String? existingId,
}) =>
    RosterEntryInput(
      displayName: name,
      isCaptain: captain,
      isWicketkeeper: keeper,
      battingHand: hand,
      declaredHeightCm: height,
      existingPlayerId: existingId,
    );

TeamInput squadOf(String name, List<String> players) =>
    TeamInput(name: name, players: players.map<RosterEntryInput>(person).toList());

NewMatchInput basicInput({
  int overs = 6,
  String teamA = 'Reds',
  String teamB = 'Blues',
  List<String> playersA = const <String>['Asha', 'Bala', 'Chitra'],
  List<String> playersB = const <String>['Dev', 'Esha', 'Farid'],
}) =>
    NewMatchInput(
      teamA: squadOf(teamA, playersA),
      teamB: squadOf(teamB, playersB),
      matchName: 'Sunday finals',
      locationName: 'Terrace',
      oversPerInnings: overs,
    );

SceneScan scanFor(String matchId, {String id = 'scan-1'}) => SceneScan(
      id: id,
      matchId: matchId,
      scanDurationMs: 1200,
      overallConfidence: 0.9,
      modelVersion: 'mock-scene-1.0',
      createdAt: DateTime.utc(2026, 10, 8, 7, 40),
    );

WicketDetection wicketFor(String matchId, String scanId, {String id = 'wicket-1'}) =>
    WicketDetection(
      id: id,
      matchId: matchId,
      sceneScanId: scanId,
      wicketFamily: WicketFamily.traditionalStumps,
      boundingBox: const <String, Object?>{'x': 0.477, 'y': 0.42, 'width': 0.046, 'height': 0.14},
      targetPolygon: const <Object?>[
        <String, Object?>{'x': 0.477, 'y': 0.42},
        <String, Object?>{'x': 0.523, 'y': 0.42},
        <String, Object?>{'x': 0.523, 'y': 0.56},
      ],
      objectConfidence: 0.9,
      temporalStability: 0.9,
      contextConfidence: 0.9,
      finalConfidence: 0.9,
      modelVersion: 'mock-scene-1.0',
      detectedAt: DateTime.utc(2026, 10, 8, 7, 40),
    );

void main() {
  late LocalStore store;
  late FakeClock clock;
  late SequenceIds ids;
  late MatchRepository repo;

  Future<List<OutboxEvent>> outbox() => store.allOutboxEvents();

  Future<List<String>> outboxTypes() async =>
      (await outbox()).map<String>((OutboxEvent e) => e.entityType.wire).toList();

  Future<Game> startGame({int overs = 6}) async {
    final MatchBundle bundle = await repo.createMatch(basicInput(overs: overs));
    final Innings innings =
        await repo.startInnings(matchId: bundle.match.id, battingTeamId: bundle.teamA.id);
    return Game(bundle, innings);
  }

  DeliveryDraft ball(
    Game g, {
    int runs = 0,
    int extras = 0,
    bool wide = false,
    bool noBall = false,
    bool bye = false,
    bool wicket = false,
    DismissalType? dismissal,
    String? dismissed,
  }) =>
      DeliveryDraft(
        bowlerId: g.bowlers.first,
        strikerId: g.batters[0],
        nonStrikerId: g.batters[1],
        runsBat: runs,
        runsExtras: extras,
        isWide: wide,
        isNoBall: noBall,
        isBye: bye,
        isWicket: wicket,
        dismissalType: dismissal,
        dismissedPlayerId: dismissed,
      );

  setUp(() async {
    store = await openMemoryStore();
    clock = FakeClock();
    ids = SequenceIds();
    repo = MatchRepository(store: store, clock: clock, ids: ids, syncEnabled: true);
  });

  tearDown(() async {
    await store.close();
  });

  group('createMatch', () {
    test('saves the teams, players, match, rules and squads', () async {
      final MatchBundle bundle = await repo.createMatch(basicInput());

      expect(bundle.teamA.name, 'Reds');
      expect(bundle.teamB.name, 'Blues');
      expect(bundle.match.status, MatchStatus.draft);
      expect(bundle.match.oversPerInnings, 6);
      expect(bundle.match.matchName, 'Sunday finals');
      expect(bundle.match.locationName, 'Terrace');
      expect(bundle.match.createdAt, clock.now());
      expect(bundle.rules, isNotNull);
      expect(bundle.rules!.matchId, bundle.match.id);
      expect(bundle.matchPlayers, hasLength(6));

      final List<String> reds =
          bundle.battingOrderIds(bundle.teamA.id).map<String>(bundle.playerName).toList();
      expect(reds, <String>['Asha', 'Bala', 'Chitra']);
      final List<MatchPlayer> redSquad = bundle.squad(bundle.teamA.id);
      expect(redSquad.map<int?>((MatchPlayer mp) => mp.battingOrder), <int?>[1, 2, 3]);

      expect(await store.teams(), hasLength(2));
      expect(await store.players(), hasLength(6));
    });

    test('queues the events parents first', () async {
      await repo.createMatch(basicInput());
      expect(await outboxTypes(), <String>[
        'TEAM',
        'TEAM',
        'PLAYER',
        'PLAYER',
        'PLAYER',
        'PLAYER',
        'PLAYER',
        'PLAYER',
        'MATCH',
        'MATCH_RULES',
        'MATCH_PLAYER',
        'MATCH_PLAYER',
        'MATCH_PLAYER',
        'MATCH_PLAYER',
        'MATCH_PLAYER',
        'MATCH_PLAYER',
      ]);
    });

    test('tags match events with the match so they can be held back or dropped together', () async {
      final MatchBundle bundle = await repo.createMatch(basicInput());
      for (final OutboxEvent event in await outbox()) {
        final bool belongsToMatch = event.entityType == SyncEntityType.match ||
            event.entityType == SyncEntityType.matchRules ||
            event.entityType == SyncEntityType.matchPlayer;
        expect(event.matchId, belongsToMatch ? bundle.match.id : isNull, reason: event.entityType.wire);
      }
    });

    test('the MATCH payload is exactly the contract payload', () async {
      final MatchBundle bundle = await repo.createMatch(basicInput());
      final OutboxEvent matchEvent =
          (await outbox()).firstWhere((OutboxEvent e) => e.entityType == SyncEntityType.match);
      expect(matchEvent.payload, bundle.match.toSyncPayload());
      expect(matchEvent.action, SyncAction.upsert);
      expect(matchEvent.payload.containsKey('created_at'), isFalse);
      expect(matchEvent.payload['status'], 'DRAFT');
    });

    test('every event has its own id and the creation time', () async {
      await repo.createMatch(basicInput());
      final List<OutboxEvent> events = await outbox();
      expect(events.map<String>((OutboxEvent e) => e.eventId).toSet(), hasLength(events.length));
      expect(events.every((OutboxEvent e) => e.clientCreatedAt == clock.now()), isTrue);
    });

    test('reuses a saved team with the same name (any case) and saved players', () async {
      final MatchBundle first = await repo.createMatch(basicInput());
      final String ashaId = first.players.values.firstWhere((Player p) => p.displayName == 'Asha').id;
      final int eventsBefore = (await outbox()).length;

      final MatchBundle second = await repo.createMatch(
        NewMatchInput(
          teamA: TeamInput(
            name: '  REDS ',
            players: <RosterEntryInput>[person('Asha', existingId: ashaId), person('Gita')],
          ),
          teamB: squadOf('Greens', <String>['Hari', 'Isha']),
        ),
      );

      expect(second.teamA.id, first.teamA.id);
      expect(second.teamB.name, 'Greens');
      expect(await store.teams(), hasLength(3));
      expect(await store.players(), hasLength(9));
      expect(second.matchPlayerIds, contains(ashaId));

      final List<OutboxEvent> added = (await outbox()).skip(eventsBefore).toList();
      final List<String> types = added.map<String>((OutboxEvent e) => e.entityType.wire).toList();
      expect(types.where((String t) => t == 'TEAM'), hasLength(1));
      expect(types.where((String t) => t == 'PLAYER'), hasLength(3));
      expect(types.where((String t) => t == 'MATCH_PLAYER'), hasLength(4));
    });

    test('changing the hand or height of a saved player updates and re-sends the player', () async {
      final MatchBundle first = await repo.createMatch(basicInput());
      final String ashaId = first.players.values.firstWhere((Player p) => p.displayName == 'Asha').id;
      final int eventsBefore = (await outbox()).length;

      final MatchBundle second = await repo.createMatch(
        NewMatchInput(
          teamA: TeamInput(
            name: 'Reds',
            players: <RosterEntryInput>[
              person('Asha', existingId: ashaId, hand: BattingHand.left, height: 165),
              person('Bala', existingId: first.players.values.firstWhere((Player p) => p.displayName == 'Bala').id),
            ],
          ),
          teamB: squadOf('Blues', <String>['Dev', 'Esha']),
        ),
      );

      final Player asha = (await store.player(ashaId))!;
      expect(asha.battingHand, BattingHand.left);
      expect(asha.declaredHeightCm, 165);
      final MatchPlayer ashaInMatch = second.matchPlayerById(ashaId)!;
      expect(ashaInMatch.battingHand, BattingHand.left);
      expect(ashaInMatch.declaredHeightCm, 165);

      final List<OutboxEvent> playerEvents = (await outbox())
          .skip(eventsBefore)
          .where((OutboxEvent e) => e.entityType == SyncEntityType.player)
          .toList();
      // Asha changed; Bala did not; Dev and Esha are new.
      expect(playerEvents, hasLength(3));
      expect(playerEvents.first.payload['id'], ashaId);
      expect(playerEvents.first.payload['batting_hand'], 'LEFT');
    });

    test('without an account nothing is queued', () async {
      repo = MatchRepository(store: store, clock: clock, ids: ids, syncEnabled: false);
      final MatchBundle bundle = await repo.createMatch(basicInput());
      expect(bundle.matchPlayers, hasLength(6));
      expect(await outbox(), isEmpty);
    });

    test('uses the rules that were chosen, for this match', () async {
      final MatchBundle bundle = await repo.createMatch(
        NewMatchInput(
          teamA: squadOf('Reds', <String>['Asha', 'Bala']),
          teamB: squadOf('Blues', <String>['Dev', 'Esha']),
          rules: const MatchRules(
            matchId: 'placeholder',
            wideEnabled: false,
            maxBouncersPerOver: 2,
            lateralReachMultiplier: 0.8,
          ),
        ),
      );
      expect(bundle.rules!.matchId, bundle.match.id);
      expect(bundle.rules!.wideEnabled, isFalse);
      expect(bundle.rules!.maxBouncersPerOver, 2);
      expect(bundle.rules!.lateralReachMultiplier, 0.8);
    });

    Future<void> expectRefused(NewMatchInput input, String messagePart) async {
      await expectLater(
        repo.createMatch(input),
        throwsA(isA<SetupException>().having((SetupException e) => e.message, 'message', contains(messagePart))),
      );
      expect(await store.teams(), isEmpty, reason: 'nothing may be saved');
      expect(await outbox(), isEmpty);
    }

    test('refuses teams with the same name', () async {
      await expectRefused(basicInput(teamA: 'Reds', teamB: ' reds'), 'different names');
    });

    test('refuses a team with fewer than two players', () async {
      await expectRefused(basicInput(playersA: <String>['Solo']), 'at least 2 players');
    });

    test('refuses overs outside 1-50', () async {
      await expectRefused(basicInput(overs: 0), 'Overs per innings');
      await expectRefused(basicInput(overs: 51), 'Overs per innings');
    });

    test('refuses a missing team name and a blank player name', () async {
      await expectRefused(basicInput(teamA: '  '), 'Enter a name');
      await expectRefused(basicInput(playersB: <String>['Dev', '   ']), 'needs a name');
    });

    test('refuses two captains and a bad height', () async {
      await expectRefused(
        NewMatchInput(
          teamA: TeamInput(
            name: 'Reds',
            players: <RosterEntryInput>[person('A', captain: true), person('B', captain: true)],
          ),
          teamB: squadOf('Blues', <String>['C', 'D']),
        ),
        'one captain',
      );
      await expectRefused(
        NewMatchInput(
          teamA: TeamInput(
            name: 'Reds',
            players: <RosterEntryInput>[person('A', height: 50), person('B')],
          ),
          teamB: squadOf('Blues', <String>['C', 'D']),
        ),
        'Height',
      );
    });

    test('refuses the same saved player twice', () async {
      await expectRefused(
        NewMatchInput(
          teamA: TeamInput(
            name: 'Reds',
            players: <RosterEntryInput>[person('A', existingId: 'p1'), person('B')],
          ),
          teamB: TeamInput(
            name: 'Blues',
            players: <RosterEntryInput>[person('A', existingId: 'p1'), person('D')],
          ),
        ),
        'more than once',
      );
    });

    test('a saved player that does not exist rolls the whole setup back', () async {
      await expectRefused(
        NewMatchInput(
          teamA: TeamInput(
            name: 'Reds',
            players: <RosterEntryInput>[person('Ghost', existingId: 'nobody'), person('B')],
          ),
          teamB: squadOf('Blues', <String>['C', 'D']),
        ),
        'not in your saved players',
      );
    });
  });

  group('status, scan and toss', () {
    test('setStatus changes the status and queues the match', () async {
      final MatchBundle bundle = await repo.createMatch(basicInput());
      final int before = (await outbox()).length;
      final CricketMatch updated = await repo.setStatus(bundle.match.id, MatchStatus.scanning);
      expect(updated.status, MatchStatus.scanning);
      expect((await store.match(bundle.match.id))!.status, MatchStatus.scanning);
      final List<OutboxEvent> added = (await outbox()).skip(before).toList();
      expect(added, hasLength(1));
      expect(added.single.payload['status'], 'SCANNING');
    });

    test('a finished match cannot change status', () async {
      final MatchBundle bundle = await repo.createMatch(basicInput());
      await repo.abandonMatch(bundle.match.id);
      await expectLater(
        repo.setStatus(bundle.match.id, MatchStatus.live),
        throwsA(isA<SetupException>()),
      );
    });

    test('saveScan stores the scan and wicket, queues them parents first, and marks the match ready',
        () async {
      final MatchBundle bundle = await repo.createMatch(basicInput());
      final int before = (await outbox()).length;
      final CricketMatch match = await repo.saveScan(
        matchId: bundle.match.id,
        scan: scanFor(bundle.match.id),
        wicket: wicketFor(bundle.match.id, 'scan-1'),
      );
      expect(match.status, MatchStatus.ready);
      final MatchBundle after = (await store.bundle(bundle.match.id))!;
      expect(after.latestScan!.id, 'scan-1');
      expect(after.activeWicket!.id, 'wicket-1');
      final List<String> types =
          (await outbox()).skip(before).map<String>((OutboxEvent e) => e.entityType.wire).toList();
      expect(types, <String>['SCENE_SCAN', 'WICKET_DETECTION', 'MATCH']);
    });

    test('a new scan retires the older wicket', () async {
      final MatchBundle bundle = await repo.createMatch(basicInput());
      await repo.saveScan(
        matchId: bundle.match.id,
        scan: scanFor(bundle.match.id),
        wicket: wicketFor(bundle.match.id, 'scan-1'),
      );
      final int before = (await outbox()).length;
      await repo.saveScan(
        matchId: bundle.match.id,
        scan: scanFor(bundle.match.id, id: 'scan-2'),
        wicket: wicketFor(bundle.match.id, 'scan-2', id: 'wicket-2'),
      );
      final MatchBundle after = (await store.bundle(bundle.match.id))!;
      expect(after.activeWicket!.id, 'wicket-2');
      expect(after.wicketDetections.firstWhere((WicketDetection w) => w.id == 'wicket-1').isActive, isFalse);
      final List<OutboxEvent> added = (await outbox()).skip(before).toList();
      final List<OutboxEvent> wicketEvents =
          added.where((OutboxEvent e) => e.entityType == SyncEntityType.wicketDetection).toList();
      expect(wicketEvents, hasLength(2));
      expect(wicketEvents.first.payload['id'], 'wicket-1');
      expect(wicketEvents.first.payload['is_active'], false);
      expect(wicketEvents.last.payload['id'], 'wicket-2');
      expect(wicketEvents.last.payload['is_active'], true);
    });

    test('a scan that found no wicket sends the match back to draft', () async {
      final MatchBundle bundle = await repo.createMatch(basicInput());
      await repo.setStatus(bundle.match.id, MatchStatus.scanning);
      final CricketMatch match =
          await repo.saveScan(matchId: bundle.match.id, scan: scanFor(bundle.match.id));
      expect(match.status, MatchStatus.draft);
      expect((await store.bundle(bundle.match.id))!.activeWicket, isNull);
    });

    test('marking the stumps again during play keeps the match live', () async {
      final Game game = await startGame();
      final CricketMatch match = await repo.saveScan(
        matchId: game.matchId,
        scan: scanFor(game.matchId),
        wicket: wicketFor(game.matchId, 'scan-1'),
      );
      expect(match.status, MatchStatus.live);
      expect((await store.match(game.matchId))!.status, MatchStatus.live);
      expect((await store.bundle(game.matchId))!.activeWicket!.id, 'wicket-1');
    });

    test('recordToss stores the toss and a second call keeps the same toss', () async {
      final MatchBundle bundle = await repo.createMatch(basicInput());
      final String callerId = bundle.battingOrderIds(bundle.teamA.id).first;
      final Toss first = await repo.recordToss(
        matchId: bundle.match.id,
        callChoice: TossSide.heads,
        result: TossSide.tails,
        winnerTeamId: bundle.teamB.id,
        winnerDecision: TossDecision.bowl,
        calledByPlayerId: callerId,
      );
      final Toss second = await repo.recordToss(
        matchId: bundle.match.id,
        callChoice: TossSide.tails,
        result: TossSide.tails,
        winnerTeamId: bundle.teamA.id,
        winnerDecision: TossDecision.bat,
      );
      expect(second.id, first.id);
      expect((await store.toss(bundle.match.id))!.winnerTeamId, bundle.teamA.id);
      final List<OutboxEvent> tossEvents =
          (await outbox()).where((OutboxEvent e) => e.entityType == SyncEntityType.toss).toList();
      expect(tossEvents, hasLength(2));
      expect(tossEvents.first.payload['id'], tossEvents.last.payload['id']);
      expect(tossEvents.first.payload['call_choice'], 'HEADS');
      expect(tossEvents.first.payload['winner_decision'], 'BOWL');
    });

    test('recordToss refuses a winner that is not in the match and a caller from outside', () async {
      final MatchBundle bundle = await repo.createMatch(basicInput());
      await expectLater(
        repo.recordToss(
          matchId: bundle.match.id,
          callChoice: TossSide.heads,
          result: TossSide.heads,
          winnerTeamId: 'someone-else',
          winnerDecision: TossDecision.bat,
        ),
        throwsA(isA<SetupException>()),
      );
      await expectLater(
        repo.recordToss(
          matchId: bundle.match.id,
          callChoice: TossSide.heads,
          result: TossSide.heads,
          winnerTeamId: bundle.teamA.id,
          winnerDecision: TossDecision.bat,
          calledByPlayerId: 'stranger',
        ),
        throwsA(isA<SetupException>()),
      );
      expect(await store.toss(bundle.match.id), isNull);
    });

    test('the toss cannot change once the innings has started', () async {
      final Game game = await startGame();
      await expectLater(
        repo.recordToss(
          matchId: game.matchId,
          callChoice: TossSide.heads,
          result: TossSide.heads,
          winnerTeamId: game.bundle.teamA.id,
          winnerDecision: TossDecision.bat,
        ),
        throwsA(isA<SetupException>()),
      );
    });
  });

  group('innings', () {
    test('starting the first innings makes the match live and queues innings then match', () async {
      final MatchBundle bundle = await repo.createMatch(basicInput());
      final int before = (await outbox()).length;
      clock.advance(const Duration(minutes: 5));
      final Innings innings =
          await repo.startInnings(matchId: bundle.match.id, battingTeamId: bundle.teamB.id);

      expect(innings.inningsNumber, 1);
      expect(innings.battingTeamId, bundle.teamB.id);
      expect(innings.bowlingTeamId, bundle.teamA.id);
      expect(innings.startedAt, clock.now());
      final CricketMatch match = (await store.match(bundle.match.id))!;
      expect(match.status, MatchStatus.live);
      expect(match.startedAt, clock.now());

      final List<OutboxEvent> added = (await outbox()).skip(before).toList();
      expect(added.map<String>((OutboxEvent e) => e.entityType.wire), <String>['INNINGS', 'MATCH']);
      expect(added.first.payload, innings.toSyncPayload());
      expect(added.first.payload.containsKey('total_runs'), isFalse);
    });

    test('refuses a batting team that is not in the match', () async {
      final MatchBundle bundle = await repo.createMatch(basicInput());
      await expectLater(
        repo.startInnings(matchId: bundle.match.id, battingTeamId: 'other'),
        throwsA(isA<SetupException>()),
      );
    });

    test('the second innings needs the first to be closed, and there are only two', () async {
      final Game game = await startGame();
      await expectLater(
        repo.startInnings(matchId: game.matchId, battingTeamId: game.bundle.teamB.id),
        throwsA(isA<SetupException>()),
      );
      await repo.closeInnings(game.innings.id);
      final Innings second =
          await repo.startInnings(matchId: game.matchId, battingTeamId: game.bundle.teamB.id);
      expect(second.inningsNumber, 2);
      await repo.closeInnings(second.id);
      await expectLater(
        repo.startInnings(matchId: game.matchId, battingTeamId: game.bundle.teamA.id),
        throwsA(isA<SetupException>()),
      );
    });

    test('closeInnings sets the end time, queues the innings once and is repeatable', () async {
      final Game game = await startGame();
      clock.advance(const Duration(minutes: 30));
      final Innings closed = await repo.closeInnings(game.innings.id);
      expect(closed.isClosed, isTrue);
      expect(closed.endedAt, clock.now());

      final int inningsEvents = (await outbox())
          .where((OutboxEvent e) => e.entityType == SyncEntityType.innings)
          .length;
      expect(inningsEvents, 2);
      clock.advance(const Duration(minutes: 1));
      final Innings again = await repo.closeInnings(game.innings.id);
      expect(again.endedAt, closed.endedAt);
      final int after = (await outbox())
          .where((OutboxEvent e) => e.entityType == SyncEntityType.innings)
          .length;
      expect(after, 2);
    });
  });

  group('recordDelivery', () {
    test('numbers the ball, saves it, updates the innings totals and queues it', () async {
      final Game game = await startGame();
      final int before = (await outbox()).length;
      final Delivery delivery =
          await repo.recordDelivery(inningsId: game.innings.id, draft: ball(game, runs: 4));

      expect(delivery.deliverySequence, 1);
      expect(delivery.overNumber, 0);
      expect(delivery.legalBallNumber, 1);
      expect(delivery.createdAt, clock.now());
      expect(await store.deliveries(game.innings.id), <Delivery>[delivery]);

      final Innings innings = (await store.inningsById(game.innings.id))!;
      expect(innings.totalRuns, 4);
      expect(innings.legalBalls, 1);
      expect(innings.wickets, 0);

      final List<OutboxEvent> added = (await outbox()).skip(before).toList();
      expect(added, hasLength(1));
      expect(added.single.entityType, SyncEntityType.delivery);
      expect(added.single.action, SyncAction.upsert);
      expect(added.single.matchId, game.matchId);
      expect(added.single.payload, delivery.toSyncPayload());
      for (final String derived in <String>['delivery_sequence', 'over_number', 'legal_ball_number']) {
        expect(added.single.payload.containsKey(derived), isFalse, reason: derived);
      }
    });

    test('a sequence of balls adds up like the scoring rules say', () async {
      final Game game = await startGame();
      await repo.recordDelivery(inningsId: game.innings.id, draft: ball(game));
      await repo.recordDelivery(inningsId: game.innings.id, draft: ball(game, runs: 4));
      final Delivery wide =
          await repo.recordDelivery(inningsId: game.innings.id, draft: ball(game, wide: true, extras: 1));
      final Delivery single =
          await repo.recordDelivery(inningsId: game.innings.id, draft: ball(game, runs: 1));
      await repo.recordDelivery(
        inningsId: game.innings.id,
        draft: ball(game, wicket: true, dismissal: DismissalType.bowled, dismissed: game.batters[0]),
      );

      expect(wide.deliverySequence, 3);
      expect(wide.legalBallNumber, isNull);
      expect(single.deliverySequence, 4);
      expect(single.legalBallNumber, 3);

      final Innings innings = (await store.inningsById(game.innings.id))!;
      expect(innings.totalRuns, 6);
      expect(innings.wickets, 1);
      expect(innings.legalBalls, 4);
    });

    test('saves decisions after the ball, in the contract shape', () async {
      final Game game = await startGame();
      final int before = (await outbox()).length;
      final Delivery delivery = await repo.recordDelivery(
        inningsId: game.innings.id,
        draft: ball(game, wide: true, extras: 1),
        decisions: const <DecisionInput>[
          DecisionInput(
            type: DeliveryDecisionType.wide,
            status: DecisionStatus.autoCall,
            source: DecisionSource.aiAssist,
            automatedResult: 'WIDE',
            finalResult: 'WIDE',
            confidence: 0.9,
            evidence: <String, Object?>{'distance_m': 1.4},
          ),
        ],
      );
      final List<DecisionRecord> stored = await store.decisionsOfDelivery(delivery.id);
      expect(stored, hasLength(1));
      expect(stored.single.decisionType, DeliveryDecisionType.wide);
      expect(stored.single.automatedResult, 'WIDE');
      expect(stored.single.confidence, 0.9);
      expect(stored.single.evidence, <String, Object?>{'distance_m': 1.4});

      final List<OutboxEvent> added = (await outbox()).skip(before).toList();
      expect(added.map<String>((OutboxEvent e) => e.entityType.wire), <String>['DELIVERY', 'DELIVERY_DECISION']);
      expect(added.last.payload['delivery_id'], delivery.id);
      expect(added.last.payload['decision_status'], 'AUTO_CALL');
      expect(added.last.payload['decision_source'], 'AI_ASSIST');
      expect(added.last.matchId, game.matchId);
    });

    test('keeps decision fields inside the limits the server enforces', () async {
      final Game game = await startGame();
      final Delivery delivery = await repo.recordDelivery(
        inningsId: game.innings.id,
        draft: ball(game),
        decisions: <DecisionInput>[
          DecisionInput(
            type: DeliveryDecisionType.edge,
            status: DecisionStatus.reviewRecommended,
            source: DecisionSource.aiAssist,
            automatedResult: 'X' * 60,
            confidence: 1.7,
            evidence: <String, Object?>{'blob': 'x' * 70000},
          ),
        ],
      );
      final DecisionRecord stored = (await store.decisionsOfDelivery(delivery.id)).single;
      expect(stored.automatedResult, hasLength(40));
      expect(stored.confidence, 1.0);
      expect(stored.evidence, isNull);
    });

    test('saves the ball path, and thins out a path with too many points', () async {
      final Game game = await startGame();
      final Delivery delivery = await repo.recordDelivery(
        inningsId: game.innings.id,
        draft: ball(game),
        trajectory: TrajectoryInput(
          samplingFps: 400,
          modelVersion: 'mock-ball-1.0',
          points: <List<double>>[
            for (int i = 0; i < 1000; i++) <double>[i * 10.0, 0.5, 0.5, 0.9],
          ],
        ),
      );
      final TrajectorySnapshot snapshot = (await store.trajectoryOfDelivery(delivery.id))!;
      expect(snapshot.pointsCompressed, hasLength(MatchRepository.maxTrajectoryPoints));
      expect(snapshot.pointsCompressed.first, <Object?>[0.0, 0.5, 0.5, 0.9]);
      expect(snapshot.pointsCompressed.last, <Object?>[9990.0, 0.5, 0.5, 0.9]);
      expect(snapshot.samplingFps, 240);
      expect(snapshot.modelVersion, 'mock-ball-1.0');
    });

    test('a path with no points is not saved', () async {
      final Game game = await startGame();
      final Delivery delivery = await repo.recordDelivery(
        inningsId: game.innings.id,
        draft: ball(game),
        trajectory: const TrajectoryInput(samplingFps: 30, points: <List<double>>[], modelVersion: 'm'),
      );
      expect(await store.trajectoryOfDelivery(delivery.id), isNull);
    });

    test('a ball the rules refuse is not saved and not queued', () async {
      final Game game = await startGame();
      final int before = (await outbox()).length;
      await expectLater(
        repo.recordDelivery(inningsId: game.innings.id, draft: ball(game, wide: true, extras: 1, runs: 2)),
        throwsA(isA<ScoringException>().having((ScoringException e) => e.code, 'code', 'INVALID_DELIVERY')),
      );
      expect(await store.deliveries(game.innings.id), isEmpty);
      expect((await outbox()).length, before);
      expect((await store.inningsById(game.innings.id))!.totalRuns, 0);
    });

    test('players from outside the match are refused', () async {
      final Game game = await startGame();
      await expectLater(
        repo.recordDelivery(
          inningsId: game.innings.id,
          draft: DeliveryDraft(
            bowlerId: game.bowlers.first,
            strikerId: 'stranger',
            nonStrikerId: game.batters[1],
          ),
        ),
        throwsA(isA<ScoringException>().having((ScoringException e) => e.code, 'code', 'INVALID_REFERENCE')),
      );
    });

    test('an unknown innings is refused', () async {
      final Game game = await startGame();
      await expectLater(
        repo.recordDelivery(inningsId: 'missing', draft: ball(game)),
        throwsA(isA<ScoringException>().having((ScoringException e) => e.code, 'code', 'ENTITY_NOT_FOUND')),
      );
    });

    test('a closed innings accepts no more balls', () async {
      final Game game = await startGame();
      await repo.closeInnings(game.innings.id);
      await expectLater(
        repo.recordDelivery(inningsId: game.innings.id, draft: ball(game)),
        throwsA(isA<ScoringException>().having((ScoringException e) => e.code, 'code', 'INNINGS_CLOSED')),
      );
    });

    test('the over limit is enforced', () async {
      final Game game = await startGame(overs: 1);
      for (int i = 0; i < 6; i++) {
        await repo.recordDelivery(inningsId: game.innings.id, draft: ball(game));
      }
      await expectLater(
        repo.recordDelivery(inningsId: game.innings.id, draft: ball(game)),
        throwsA(isA<ScoringException>().having((ScoringException e) => e.code, 'code', 'OVER_LIMIT_EXCEEDED')),
      );
      expect((await store.inningsById(game.innings.id))!.legalBalls, 6);
    });

    test('nothing can be scored after the match has ended', () async {
      final Game game = await startGame();
      await repo.abandonMatch(game.matchId);
      await expectLater(
        repo.recordDelivery(inningsId: game.innings.id, draft: ball(game)),
        throwsA(isA<SetupException>()),
      );
    });

    test('without an account the ball is saved but nothing is queued', () async {
      repo = MatchRepository(store: store, clock: clock, ids: ids, syncEnabled: false);
      final Game game = await startGame();
      await repo.recordDelivery(inningsId: game.innings.id, draft: ball(game, runs: 2));
      expect(await outbox(), isEmpty);
      expect((await store.inningsById(game.innings.id))!.totalRuns, 2);
    });
  });

  group('undoLastDelivery', () {
    test('voids the last ball, keeps it stored and queues a VOID event', () async {
      final Game game = await startGame();
      await repo.recordDelivery(inningsId: game.innings.id, draft: ball(game, runs: 1));
      final Delivery second =
          await repo.recordDelivery(inningsId: game.innings.id, draft: ball(game, runs: 6));
      final int before = (await outbox()).length;

      clock.advance(const Duration(seconds: 30));
      final Delivery voided = await repo.undoLastDelivery(game.innings.id, reason: 'Scorer mistake');

      expect(voided.id, second.id);
      expect(voided.isVoided, isTrue);
      expect(voided.voidedAt, clock.now());
      expect(voided.voidReason, 'Scorer mistake');
      expect(await store.deliveries(game.innings.id), hasLength(2));
      final Innings innings = (await store.inningsById(game.innings.id))!;
      expect(innings.totalRuns, 1);
      expect(innings.legalBalls, 1);

      final List<OutboxEvent> added = (await outbox()).skip(before).toList();
      expect(added, hasLength(1));
      expect(added.single.action, SyncAction.voidDelivery);
      expect(added.single.entityType, SyncEntityType.delivery);
      expect(added.single.payload, <String, Object?>{'id': second.id, 'void_reason': 'Scorer mistake'});
    });

    test('undo can be repeated until nothing is left', () async {
      final Game game = await startGame();
      final Delivery first = await repo.recordDelivery(inningsId: game.innings.id, draft: ball(game));
      final Delivery second = await repo.recordDelivery(inningsId: game.innings.id, draft: ball(game));
      expect((await repo.undoLastDelivery(game.innings.id)).id, second.id);
      expect((await repo.undoLastDelivery(game.innings.id)).id, first.id);
      await expectLater(
        repo.undoLastDelivery(game.innings.id),
        throwsA(isA<ScoringException>().having((ScoringException e) => e.code, 'code', 'NOTHING_TO_VOID')),
      );
    });

    test('sequence numbers are not reused after an undo, ball numbers are', () async {
      final Game game = await startGame();
      await repo.recordDelivery(inningsId: game.innings.id, draft: ball(game));
      await repo.recordDelivery(inningsId: game.innings.id, draft: ball(game));
      await repo.undoLastDelivery(game.innings.id);
      final Delivery next = await repo.recordDelivery(inningsId: game.innings.id, draft: ball(game));
      expect(next.deliverySequence, 3);
      expect(next.legalBallNumber, 2);
      expect(next.overNumber, 0);
    });

    test('a closed innings cannot be undone', () async {
      final Game game = await startGame();
      await repo.recordDelivery(inningsId: game.innings.id, draft: ball(game));
      await repo.closeInnings(game.innings.id);
      await expectLater(
        repo.undoLastDelivery(game.innings.id),
        throwsA(isA<ScoringException>().having((ScoringException e) => e.code, 'code', 'INNINGS_CLOSED')),
      );
    });
  });

  group('finishing a match', () {
    Future<void> scoreInnings(Game game, Innings innings, List<String> batters, List<String> bowlers, List<int> runs) async {
      for (final int r in runs) {
        await repo.recordDelivery(
          inningsId: innings.id,
          draft: DeliveryDraft(
            bowlerId: bowlers.first,
            strikerId: batters[0],
            nonStrikerId: batters[1],
            runsBat: r,
          ),
        );
      }
    }

    Future<Game> playBoth(List<int> firstRuns, List<int> secondRuns) async {
      final Game game = await startGame(overs: 2);
      await scoreInnings(game, game.innings, game.batters, game.bowlers, firstRuns);
      await repo.closeInnings(game.innings.id);
      final Innings second =
          await repo.startInnings(matchId: game.matchId, battingTeamId: game.bundle.teamB.id);
      await scoreInnings(game, second, game.bowlers, game.batters, secondRuns);
      return game;
    }

    test('the team with more runs wins by the run difference', () async {
      final Game game = await playBoth(<int>[4, 6], <int>[4]);
      final int before = (await outbox()).length;
      final MatchResult result = await repo.completeMatch(game.matchId);

      expect(result.winnerTeamId, game.bundle.teamA.id);
      expect(result.summary, 'Reds won by 6 runs');
      final CricketMatch match = (await store.match(game.matchId))!;
      expect(match.status, MatchStatus.completed);
      expect(match.winnerTeamId, game.bundle.teamA.id);
      expect(match.resultSummary, 'Reds won by 6 runs');
      expect(match.completedAt, clock.now());
      for (final Innings innings in await store.inningsOf(game.matchId)) {
        expect(innings.isClosed, isTrue);
      }

      final List<OutboxEvent> added = (await outbox()).skip(before).toList();
      expect(added.map<String>((OutboxEvent e) => e.entityType.wire), <String>['INNINGS', 'MATCH']);
      expect(added.last.payload['status'], 'COMPLETED');
      expect(added.last.payload['winner_team_id'], game.bundle.teamA.id);
    });

    test('the chasing team wins by the wickets it has left', () async {
      final Game game = await playBoth(<int>[4, 6], <int>[4, 6, 1]);
      final MatchResult result = await repo.completeMatch(game.matchId);
      expect(result.winnerTeamId, game.bundle.teamB.id);
      expect(result.summary, 'Blues won by 2 wickets');
    });

    test('equal totals are a tie with no winner', () async {
      final Game game = await playBoth(<int>[4, 6], <int>[6, 4]);
      final MatchResult result = await repo.completeMatch(game.matchId);
      expect(result.isTie, isTrue);
      final CricketMatch match = (await store.match(game.matchId))!;
      expect(match.winnerTeamId, isNull);
      expect(match.resultSummary, 'Match tied');
    });

    test('needs both innings', () async {
      final Game game = await startGame();
      await expectLater(repo.completeMatch(game.matchId), throwsA(isA<SetupException>()));
    });

    test('a finished match cannot be completed again', () async {
      final Game game = await playBoth(<int>[4], <int>[1]);
      await repo.completeMatch(game.matchId);
      await expectLater(repo.completeMatch(game.matchId), throwsA(isA<SetupException>()));
    });

    test('abandoning closes the open innings and records the reason', () async {
      final Game game = await startGame();
      await repo.recordDelivery(inningsId: game.innings.id, draft: ball(game, runs: 2));
      final CricketMatch match = await repo.abandonMatch(game.matchId, reason: 'rain');
      expect(match.status, MatchStatus.abandoned);
      expect(match.resultSummary, 'Match abandoned: rain');
      expect(match.isFinished, isTrue);
      expect((await store.inningsById(game.innings.id))!.isClosed, isTrue);
    });

    test('abandoning without a reason says so plainly', () async {
      final MatchBundle bundle = await repo.createMatch(basicInput());
      final CricketMatch match = await repo.abandonMatch(bundle.match.id);
      expect(match.resultSummary, 'Match abandoned');
    });
  });

  group('deleteMatch', () {
    test('removes the match and its unsent events, keeps the roster, and queues a DELETE', () async {
      final Game game = await startGame();
      await repo.recordDelivery(inningsId: game.innings.id, draft: ball(game, runs: 1));
      await repo.deleteMatch(game.matchId);

      expect(await store.match(game.matchId), isNull);
      expect(await store.deliveries(game.innings.id), isEmpty);
      expect(await store.matchPlayers(game.matchId), isEmpty);
      expect(await store.teams(), hasLength(2));
      expect(await store.players(), hasLength(6));

      final List<OutboxEvent> events = await outbox();
      expect(events.where((OutboxEvent e) => e.matchId == game.matchId), isEmpty);
      final List<String> types = events.map<String>((OutboxEvent e) => '${e.entityType.wire}/${e.action.wire}').toList();
      expect(types.where((String t) => t == 'TEAM/UPSERT'), hasLength(2));
      expect(types.where((String t) => t == 'PLAYER/UPSERT'), hasLength(6));
      expect(types.where((String t) => t == 'MATCH/DELETE'), hasLength(1));
      expect(types, hasLength(9));
      expect(events.last.payload, <String, Object?>{'id': game.matchId});
      expect(events.last.matchId, isNull);
    });

    test('deleting an unknown match does nothing', () async {
      await repo.deleteMatch('nope');
      expect(await outbox(), isEmpty);
    });
  });

  group('reading', () {
    test('matchList shows the newest match first with team names and scores', () async {
      final Game older = await startGame();
      await repo.recordDelivery(inningsId: older.innings.id, draft: ball(older, runs: 6));
      clock.advance(const Duration(hours: 2));
      final MatchBundle newer = await repo.createMatch(
        basicInput(teamA: 'Greens', teamB: 'Yellows', playersA: <String>['G1', 'G2'], playersB: <String>['Y1', 'Y2']),
      );

      final List<MatchListItem> items = await repo.matchList();
      expect(items.map<String>((MatchListItem i) => i.match.id), <String>[newer.match.id, older.matchId]);
      expect(items.first.teamAName, 'Greens');
      expect(items.first.teamBName, 'Yellows');
      expect(items.first.innings, isEmpty);
      expect(items.last.innings.single.totalRuns, 6);
      expect(items.last.title, 'Sunday finals');
      expect(items.first.title, 'Sunday finals');
      expect(items.last.isOpen, isTrue);
    });

    test('a match without a name is titled by its teams', () async {
      await repo.createMatch(
        NewMatchInput(
          teamA: squadOf('Reds', <String>['A', 'B']),
          teamB: squadOf('Blues', <String>['C', 'D']),
        ),
      );
      final List<MatchListItem> items = await repo.matchList();
      expect(items.single.title, 'Reds vs Blues');
    });

    test('bundle returns null for an unknown match', () async {
      expect(await repo.bundle('nope'), isNull);
    });
  });
}
