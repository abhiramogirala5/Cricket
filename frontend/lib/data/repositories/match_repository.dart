import 'dart:convert';

import 'package:gully_umpire/core/utils/clock.dart';
import 'package:gully_umpire/core/utils/id_generator.dart';
import 'package:gully_umpire/data/local/local_store.dart';
import 'package:gully_umpire/data/local/local_writer.dart';
import 'package:gully_umpire/data/repositories/repository_inputs.dart';
import 'package:gully_umpire/domain/aggregates/match_bundle.dart';
import 'package:gully_umpire/domain/aggregates/match_list_item.dart';
import 'package:gully_umpire/domain/models/models.dart';
import 'package:gully_umpire/domain/scoring/scoring.dart';
import 'package:gully_umpire/domain/setup/match_setup.dart';
import 'package:gully_umpire/domain/sync/sync.dart';

/// Everything the app does to a match: set it up, scan, toss, score, undo, finish, delete.
///
/// Every method saves the change AND (when an account is in use) its outbox event in one
/// database transaction, so the phone and the sync queue can never disagree. All scoring rules
/// come from `ScoreEngine`, the same rules the server applies.
final class MatchRepository {
  MatchRepository({
    required LocalStore store,
    required AppClock clock,
    required IdGenerator ids,
    required bool syncEnabled,
  })  : _store = store,
        _clock = clock,
        _ids = ids,
        _syncEnabled = syncEnabled;

  /// Innings per match (limited-overs, two innings).
  static const int maxInnings = 2;

  /// The server accepts at most this many trajectory points (docs/API_CONTRACT.md §5.3).
  static const int maxTrajectoryPoints = TrajectorySnapshot.maxPoints;

  /// The server accepts evidence up to 64 KiB.
  static const int maxEvidenceBytes = 64 * 1024;

  final LocalStore _store;
  final AppClock _clock;
  final IdGenerator _ids;
  final bool _syncEnabled;

  /// A new id for something the caller builds itself (for example a scan result).
  String newId() => _ids.newId();

  // ---- Reading ----------------------------------------------------------------------------

  Future<MatchBundle?> bundle(String matchId) => _store.bundle(matchId);

  Future<List<MatchListItem>> matchList() async {
    final List<CricketMatch> matches = await _store.matches();
    final Map<String, String> teamNames = <String, String>{
      for (final Team team in await _store.teams()) team.id: team.name,
    };
    final Map<String, List<Innings>> inningsByMatch = <String, List<Innings>>{};
    for (final Innings innings in await _store.allInnings()) {
      inningsByMatch.putIfAbsent(innings.matchId, () => <Innings>[]).add(innings);
    }
    return matches
        .map<MatchListItem>(
          (CricketMatch match) => MatchListItem(
            match: match,
            teamAName: teamNames[match.teamAId] ?? 'Team',
            teamBName: teamNames[match.teamBId] ?? 'Team',
            innings: inningsByMatch[match.id] ?? const <Innings>[],
          ),
        )
        .toList(growable: false);
  }

  Future<TrajectorySnapshot?> trajectoryOf(String deliveryId) =>
      _store.trajectoryOfDelivery(deliveryId);

  // ---- Setup ------------------------------------------------------------------------------

  /// Creates the teams and players that are new, the match, its rules and its squads.
  Future<MatchBundle> createMatch(NewMatchInput input) async {
    final String? problem = validateNewMatch(input);
    if (problem != null) {
      throw SetupException(problem);
    }
    final DateTime now = _clock.now();
    return _store.transaction<MatchBundle>((LocalWriter writer) async {
      final List<Team> knownTeams = List<Team>.of(await writer.teams());

      Future<Team> resolveTeam(TeamInput team) async {
        final String wanted = team.trimmedName.toLowerCase();
        for (final Team known in knownTeams) {
          if (known.name.trim().toLowerCase() == wanted) {
            return known;
          }
        }
        final Team created = Team(
          id: _ids.newId(),
          name: team.trimmedName,
          createdAt: now,
          updatedAt: now,
        );
        await writer.putTeam(created);
        await _enqueue(writer, SyncEntityType.team, SyncAction.upsert, created.toSyncPayload(), now);
        knownTeams.add(created);
        return created;
      }

      final Team teamA = await resolveTeam(input.teamA);
      final Team teamB = await resolveTeam(input.teamB);

      Future<List<Player>> resolvePlayers(TeamInput team) async {
        final List<Player> resolved = <Player>[];
        for (final RosterEntryInput entry in team.players) {
          final String? existingId = entry.existingPlayerId;
          if (existingId != null) {
            final Player? saved = await writer.player(existingId);
            if (saved == null) {
              throw SetupException('${entry.trimmedName} is not in your saved players.');
            }
            final bool handChanged =
                entry.battingHand != BattingHand.unknown && entry.battingHand != saved.battingHand;
            final bool heightChanged =
                entry.declaredHeightCm != null && entry.declaredHeightCm != saved.declaredHeightCm;
            if (handChanged || heightChanged) {
              final Player updated = saved.copyWith(
                battingHand: entry.battingHand == BattingHand.unknown ? null : entry.battingHand,
                declaredHeightCm: entry.declaredHeightCm,
                updatedAt: now,
              );
              await writer.putPlayer(updated);
              await _enqueue(
                writer,
                SyncEntityType.player,
                SyncAction.upsert,
                updated.toSyncPayload(),
                now,
              );
              resolved.add(updated);
            } else {
              resolved.add(saved);
            }
          } else {
            final Player created = Player(
              id: _ids.newId(),
              displayName: entry.trimmedName,
              battingHand: entry.battingHand,
              declaredHeightCm: entry.declaredHeightCm,
              createdAt: now,
              updatedAt: now,
            );
            await writer.putPlayer(created);
            await _enqueue(
              writer,
              SyncEntityType.player,
              SyncAction.upsert,
              created.toSyncPayload(),
              now,
            );
            resolved.add(created);
          }
        }
        return resolved;
      }

      final List<Player> playersA = await resolvePlayers(input.teamA);
      final List<Player> playersB = await resolvePlayers(input.teamB);

      final String? name = _clean(input.matchName);
      final String? place = _clean(input.locationName);
      final CricketMatch match = CricketMatch(
        id: _ids.newId(),
        teamAId: teamA.id,
        teamBId: teamB.id,
        matchName: name,
        locationName: place,
        oversPerInnings: input.oversPerInnings,
        createdAt: now,
        updatedAt: now,
      );
      await writer.putMatch(match);
      await _enqueue(writer, SyncEntityType.match, SyncAction.upsert, match.toSyncPayload(), now,
          matchId: match.id);

      final MatchRules rules = (input.rules ?? MatchRules(matchId: match.id)).forMatch(match.id);
      await writer.putRules(rules);
      await _enqueue(
          writer, SyncEntityType.matchRules, SyncAction.upsert, rules.toSyncPayload(), now,
          matchId: match.id);

      Future<void> addSquad(Team team, TeamInput sheet, List<Player> players) async {
        for (int i = 0; i < players.length; i++) {
          final RosterEntryInput entry = sheet.players[i];
          final Player player = players[i];
          final MatchPlayer matchPlayer = MatchPlayer(
            matchId: match.id,
            playerId: player.id,
            teamId: team.id,
            battingHand: player.battingHand,
            declaredHeightCm: player.declaredHeightCm,
            battingOrder: i + 1,
            isCaptain: entry.isCaptain,
            isWicketkeeper: entry.isWicketkeeper,
          );
          await writer.putMatchPlayer(matchPlayer);
          await _enqueue(
            writer,
            SyncEntityType.matchPlayer,
            SyncAction.upsert,
            matchPlayer.toSyncPayload(),
            now,
            matchId: match.id,
          );
        }
      }

      await addSquad(teamA, input.teamA, playersA);
      await addSquad(teamB, input.teamB, playersB);

      final MatchBundle? bundle = await writer.bundle(match.id);
      if (bundle == null) {
        throw const SetupException('The match could not be saved.');
      }
      return bundle;
    });
  }

  /// Changes the match status (scanning, ready, live ...). A finished match cannot be changed.
  Future<CricketMatch> setStatus(String matchId, MatchStatus status) {
    return _store.transaction<CricketMatch>((LocalWriter writer) async {
      final CricketMatch match = await _requireOpenMatch(writer, matchId);
      final DateTime now = _clock.now();
      final CricketMatch updated = match.copyWith(status: status, updatedAt: now);
      await _saveMatch(writer, updated, now);
      return updated;
    });
  }

  // ---- Scan -------------------------------------------------------------------------------

  /// Stores the result of the area scan. The match is `READY` when a wicket was found,
  /// otherwise it goes back to `DRAFT` so the scan can be repeated or skipped. A match that is
  /// already `LIVE` (the stumps were marked again during play) stays `LIVE`.
  Future<CricketMatch> saveScan({
    required String matchId,
    required SceneScan scan,
    WicketDetection? wicket,
  }) {
    return _store.transaction<CricketMatch>((LocalWriter writer) async {
      final CricketMatch match = await _requireOpenMatch(writer, matchId);
      final DateTime now = _clock.now();

      await writer.putSceneScan(scan);
      await _enqueue(writer, SyncEntityType.sceneScan, SyncAction.upsert, scan.toSyncPayload(), now,
          matchId: matchId);

      if (wicket != null) {
        for (final WicketDetection older in await writer.wicketDetections(matchId)) {
          if (older.isActive && older.id != wicket.id) {
            final WicketDetection retired = older.copyWith(isActive: false);
            await writer.putWicketDetection(retired);
            await _enqueue(writer, SyncEntityType.wicketDetection, SyncAction.upsert,
                retired.toSyncPayload(), now,
                matchId: matchId);
          }
        }
        await writer.putWicketDetection(wicket);
        await _enqueue(
            writer, SyncEntityType.wicketDetection, SyncAction.upsert, wicket.toSyncPayload(), now,
            matchId: matchId);
      }

      // A match that is already being played stays live when the stumps are marked again.
      final MatchStatus status = match.status == MatchStatus.live
          ? MatchStatus.live
          : (wicket == null ? MatchStatus.draft : MatchStatus.ready);
      final CricketMatch updated = match.copyWith(status: status, updatedAt: now);
      await _saveMatch(writer, updated, now);
      return updated;
    });
  }

  // ---- Toss and innings -------------------------------------------------------------------

  Future<Toss> recordToss({
    required String matchId,
    required TossSide callChoice,
    required TossSide result,
    required String winnerTeamId,
    required TossDecision winnerDecision,
    String? calledByPlayerId,
  }) {
    return _store.transaction<Toss>((LocalWriter writer) async {
      final CricketMatch match = await _requireOpenMatch(writer, matchId);
      if (winnerTeamId != match.teamAId && winnerTeamId != match.teamBId) {
        throw const SetupException('The toss winner must be one of the two teams.');
      }
      if (calledByPlayerId != null &&
          !(await writer.matchPlayerExists(matchId, calledByPlayerId))) {
        throw const SetupException('The caller must be a player of this match.');
      }
      if ((await writer.inningsOf(matchId)).isNotEmpty) {
        throw const SetupException('The toss cannot change after the innings has started.');
      }
      final DateTime now = _clock.now();
      final Toss? existing = await writer.toss(matchId);
      final Toss toss = Toss(
        id: existing?.id ?? _ids.newId(),
        matchId: matchId,
        calledByPlayerId: calledByPlayerId,
        callChoice: callChoice,
        result: result,
        winnerTeamId: winnerTeamId,
        winnerDecision: winnerDecision,
        createdAt: existing?.createdAt ?? now,
      );
      await writer.putToss(toss);
      await _enqueue(writer, SyncEntityType.toss, SyncAction.upsert, toss.toSyncPayload(), now,
          matchId: matchId);
      return toss;
    });
  }

  /// Starts the next innings with [battingTeamId] batting. Starting the first innings makes the
  /// match `LIVE`.
  Future<Innings> startInnings({required String matchId, required String battingTeamId}) {
    return _store.transaction<Innings>((LocalWriter writer) async {
      final CricketMatch match = await _requireOpenMatch(writer, matchId);
      if (battingTeamId != match.teamAId && battingTeamId != match.teamBId) {
        throw const SetupException('The batting team must be one of the two teams.');
      }
      final List<Innings> existing = await writer.inningsOf(matchId);
      if (existing.length >= maxInnings) {
        throw const SetupException('Both innings have already been played.');
      }
      if (existing.isNotEmpty && !existing.last.isClosed) {
        throw const SetupException('Finish the current innings first.');
      }
      final DateTime now = _clock.now();
      final Innings innings = Innings(
        id: _ids.newId(),
        matchId: matchId,
        inningsNumber: existing.length + 1,
        battingTeamId: battingTeamId,
        bowlingTeamId: match.otherTeamId(battingTeamId),
        startedAt: now,
      );
      await writer.putInnings(innings);
      await _enqueue(writer, SyncEntityType.innings, SyncAction.upsert, innings.toSyncPayload(),
          now,
          matchId: matchId);
      if (match.status != MatchStatus.live) {
        final CricketMatch live = match.copyWith(
          status: MatchStatus.live,
          startedAt: match.startedAt ?? now,
          updatedAt: now,
        );
        await _saveMatch(writer, live, now);
      }
      return innings;
    });
  }

  /// Ends an innings (the scorer confirmed it, or the rules ended it).
  Future<Innings> closeInnings(String inningsId) {
    return _store.transaction<Innings>((LocalWriter writer) async {
      final Innings innings = await _requireInnings(writer, inningsId);
      if (innings.isClosed) {
        return innings;
      }
      await _requireOpenMatch(writer, innings.matchId);
      final DateTime now = _clock.now();
      final Innings closed = innings.copyWith(endedAt: now);
      await writer.putInnings(closed);
      await _enqueue(writer, SyncEntityType.innings, SyncAction.upsert, closed.toSyncPayload(), now,
          matchId: closed.matchId);
      return closed;
    });
  }

  // ---- Scoring ----------------------------------------------------------------------------

  /// Records one ball, with the decisions and the ball path that belong to it.
  ///
  /// Throws [ScoringException] when the rules refuse the ball (nothing is saved then).
  Future<Delivery> recordDelivery({
    required String inningsId,
    required DeliveryDraft draft,
    List<DecisionInput> decisions = const <DecisionInput>[],
    TrajectoryInput? trajectory,
  }) {
    return _store.transaction<Delivery>((LocalWriter writer) async {
      final Innings innings = await _requireInnings(writer, inningsId);
      final CricketMatch match = await _requireOpenMatch(writer, innings.matchId);
      final List<Delivery> existing = await writer.deliveries(inningsId);
      final Set<String> playerIds = (await writer.matchPlayers(match.id))
          .map<String>((MatchPlayer mp) => mp.playerId)
          .toSet();
      final DateTime now = _clock.now();

      final Delivery delivery = ScoreEngine.buildDelivery(
        innings: innings,
        oversPerInnings: match.oversPerInnings,
        existing: existing,
        draft: draft,
        id: _ids.newId(),
        now: now,
        matchPlayerIds: playerIds,
      );
      await writer.putDelivery(delivery);
      await _enqueue(
          writer, SyncEntityType.delivery, SyncAction.upsert, delivery.toSyncPayload(), now,
          matchId: match.id);

      for (final DecisionInput input in decisions) {
        final DecisionRecord record = DecisionRecord(
          id: _ids.newId(),
          deliveryId: delivery.id,
          decisionType: input.type,
          automatedResult: _limit(input.automatedResult, 40),
          finalResult: _limit(input.finalResult, 40),
          confidence: input.confidence?.clamp(0.0, 1.0).toDouble(),
          decisionStatus: input.status,
          decisionSource: input.source,
          evidence: _boundedEvidence(input.evidence),
          createdAt: now,
        );
        await writer.putDecision(record);
        await _enqueue(
            writer, SyncEntityType.deliveryDecision, SyncAction.upsert, record.toSyncPayload(), now,
            matchId: match.id);
      }

      if (trajectory != null && trajectory.points.isNotEmpty) {
        final TrajectorySnapshot snapshot = TrajectorySnapshot(
          id: _ids.newId(),
          deliveryId: delivery.id,
          samplingFps: trajectory.samplingFps.clamp(1, 240).toInt(),
          pointsCompressed: _downsample(trajectory.points),
          modelVersion: trajectory.modelVersion,
          createdAt: now,
        );
        await writer.putTrajectory(snapshot);
        await _enqueue(writer, SyncEntityType.trajectorySnapshot, SyncAction.upsert,
            snapshot.toSyncPayload(), now,
            matchId: match.id);
      }

      await _refreshInningsTotals(writer, innings, <Delivery>[...existing, delivery]);
      return delivery;
    });
  }

  /// Undoes the most recent ball (it stays stored, marked as voided).
  Future<Delivery> undoLastDelivery(String inningsId, {String? reason}) {
    return _store.transaction<Delivery>((LocalWriter writer) async {
      final Innings innings = await _requireInnings(writer, inningsId);
      await _requireOpenMatch(writer, innings.matchId);
      if (innings.isClosed) {
        throw const ScoringException(ScoringErrorCodes.inningsClosed, 'This innings has ended.');
      }
      final List<Delivery> existing = await writer.deliveries(inningsId);
      final DateTime now = _clock.now();
      final Delivery voided = ScoreEngine.voidLast(
        existing: existing,
        now: now,
        reason: _limit(reason, 100),
      );
      await writer.putDelivery(voided);
      await _enqueue(
          writer, SyncEntityType.delivery, SyncAction.voidDelivery, voided.toVoidPayload(), now,
          matchId: innings.matchId);
      final List<Delivery> after = <Delivery>[
        for (final Delivery d in existing) d.id == voided.id ? voided : d,
      ];
      await _refreshInningsTotals(writer, innings, after);
      return voided;
    });
  }

  // ---- Finishing --------------------------------------------------------------------------

  /// Ends the match with a result computed from both innings. Open innings are closed.
  Future<MatchResult> completeMatch(String matchId) {
    return _store.transaction<MatchResult>((LocalWriter writer) async {
      final CricketMatch match = await _requireOpenMatch(writer, matchId);
      final List<Innings> innings = await writer.inningsOf(matchId);
      if (innings.length < maxInnings) {
        throw const SetupException('Both innings must be played before the match can be completed.');
      }
      final DateTime now = _clock.now();

      final List<Innings> finalInnings = <Innings>[];
      for (final Innings item in innings) {
        if (item.isClosed) {
          finalInnings.add(item);
          continue;
        }
        final Innings closed = item.copyWith(endedAt: now);
        await writer.putInnings(closed);
        await _enqueue(
            writer, SyncEntityType.innings, SyncAction.upsert, closed.toSyncPayload(), now,
            matchId: matchId);
        finalInnings.add(closed);
      }

      final Innings first = finalInnings[0];
      final Innings second = finalInnings[1];
      final List<MatchPlayer> secondSquad = (await writer.matchPlayers(matchId))
          .where((MatchPlayer mp) => mp.teamId == second.battingTeamId)
          .toList();
      final Team? teamA = await writer.team(match.teamAId);
      final Team? teamB = await writer.team(match.teamBId);
      final MatchResult result = computeMatchResult(
        firstTeamId: first.battingTeamId,
        secondTeamId: second.battingTeamId,
        firstTotal: first.totalRuns,
        secondTotal: second.totalRuns,
        secondWickets: second.wickets,
        secondPlayerCount: secondSquad.length,
        teamNames: <String, String>{
          match.teamAId: teamA?.name ?? 'Team',
          match.teamBId: teamB?.name ?? 'Team',
        },
      );
      final CricketMatch completed = match.copyWith(
        status: MatchStatus.completed,
        completedAt: now,
        winnerTeamId: result.winnerTeamId,
        resultSummary: _limit(result.summary, 255),
        updatedAt: now,
      );
      await _saveMatch(writer, completed, now);
      return result;
    });
  }

  /// Ends the match without a result (rain, not enough players, ...).
  Future<CricketMatch> abandonMatch(String matchId, {String? reason}) {
    return _store.transaction<CricketMatch>((LocalWriter writer) async {
      final CricketMatch match = await _requireOpenMatch(writer, matchId);
      final DateTime now = _clock.now();
      final String? cleaned = _clean(reason);
      for (final Innings item in await writer.inningsOf(matchId)) {
        if (!item.isClosed) {
          final Innings closed = item.copyWith(endedAt: now);
          await writer.putInnings(closed);
          await _enqueue(
              writer, SyncEntityType.innings, SyncAction.upsert, closed.toSyncPayload(), now,
              matchId: matchId);
        }
      }
      final CricketMatch abandoned = match.copyWith(
        status: MatchStatus.abandoned,
        completedAt: now,
        resultSummary: _limit(cleaned == null ? 'Match abandoned' : 'Match abandoned: $cleaned', 255),
        updatedAt: now,
      );
      await _saveMatch(writer, abandoned, now);
      return abandoned;
    });
  }

  /// Deletes a match from this phone and, once online, from the server.
  Future<void> deleteMatch(String matchId) {
    return _store.transaction<void>((LocalWriter writer) async {
      final CricketMatch? match = await writer.match(matchId);
      if (match == null) {
        return;
      }
      final DateTime now = _clock.now();
      // Changes that never reached the server are pointless now.
      await writer.dropOutboxForMatch(matchId);
      await writer.deleteMatchData(matchId);
      await _enqueue(
        writer,
        SyncEntityType.match,
        SyncAction.delete,
        <String, Object?>{'id': matchId},
        now,
      );
    });
  }

  // ---- Helpers ----------------------------------------------------------------------------

  Future<void> _enqueue(
    LocalWriter writer,
    SyncEntityType type,
    SyncAction action,
    Map<String, Object?> payload,
    DateTime now, {
    String? matchId,
  }) async {
    if (!_syncEnabled) {
      return;
    }
    await writer.enqueue(
      OutboxEvent(
        eventId: _ids.newId(),
        entityType: type,
        action: action,
        payload: payload,
        clientCreatedAt: now,
        matchId: matchId,
      ),
    );
  }

  Future<void> _saveMatch(LocalWriter writer, CricketMatch match, DateTime now) async {
    await writer.putMatch(match);
    await _enqueue(writer, SyncEntityType.match, SyncAction.upsert, match.toSyncPayload(), now,
        matchId: match.id);
  }

  Future<CricketMatch> _requireOpenMatch(LocalWriter writer, String matchId) async {
    final CricketMatch? match = await writer.match(matchId);
    if (match == null) {
      throw const SetupException('This match could not be found.');
    }
    if (match.isFinished) {
      throw const SetupException('This match has ended.');
    }
    return match;
  }

  Future<Innings> _requireInnings(LocalWriter writer, String inningsId) async {
    final Innings? innings = await writer.inningsById(inningsId);
    if (innings == null) {
      throw const ScoringException(ScoringErrorCodes.entityNotFound, 'This innings could not be found.');
    }
    return innings;
  }

  /// Keeps the stored innings totals equal to what the deliveries add up to.
  Future<void> _refreshInningsTotals(
    LocalWriter writer,
    Innings innings,
    List<Delivery> deliveries,
  ) async {
    final InningsAggregate totals = ScoreEngine.aggregate(deliveries);
    await writer.putInnings(
      innings.copyWith(
        totalRuns: totals.totalRuns,
        wickets: totals.wickets,
        legalBalls: totals.legalBalls,
      ),
    );
  }

  static String? _clean(String? value) {
    final String? trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  static String? _limit(String? value, int maxLength) {
    if (value == null) {
      return null;
    }
    return value.length <= maxLength ? value : value.substring(0, maxLength);
  }

  static Map<String, Object?>? _boundedEvidence(Map<String, Object?>? evidence) {
    if (evidence == null) {
      return null;
    }
    // The server refuses more than 64 KiB; evidence is only an aid, so it is dropped if too big.
    return utf8.encode(jsonEncode(evidence)).length <= maxEvidenceBytes ? evidence : null;
  }

  static List<Object?> _downsample(List<List<double>> points) {
    List<List<double>> chosen = points;
    if (points.length > maxTrajectoryPoints) {
      final double step = (points.length - 1) / (maxTrajectoryPoints - 1);
      chosen = <List<double>>[
        for (int i = 0; i < maxTrajectoryPoints; i++) points[(i * step).round()],
      ];
    }
    return chosen
        .map<Object?>((List<double> point) => List<double>.from(point))
        .toList(growable: false);
  }
}
