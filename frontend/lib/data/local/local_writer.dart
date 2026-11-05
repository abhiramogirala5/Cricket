import 'dart:convert';

import 'package:gully_umpire/data/local/local_reader.dart';
import 'package:gully_umpire/data/replays/replay_record.dart';
import 'package:gully_umpire/domain/models/models.dart';
import 'package:gully_umpire/domain/sync/sync.dart';
import 'package:sqflite/sqflite.dart';

/// Write access to the local database. Only handed out inside `LocalStore.transaction`, so
/// that an entity and its outbox event are always saved together.
class LocalWriter extends LocalReader {
  const LocalWriter(super.executor);

  static String _encode(Map<String, Object?> doc) => jsonEncode(doc);

  Future<void> _replace(String table, Map<String, Object?> values) async {
    await executor.insert(table, values, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ---- Entities ---------------------------------------------------------------------------

  Future<void> putTeam(Team team) => _replace('teams', <String, Object?>{
        'id': team.id,
        'name': team.name,
        'doc': _encode(team.toJson()),
      });

  Future<void> putPlayer(Player player) => _replace('players', <String, Object?>{
        'id': player.id,
        'name': player.displayName,
        'doc': _encode(player.toJson()),
      });

  Future<void> putMatch(CricketMatch match) => _replace('matches', <String, Object?>{
        'id': match.id,
        'status': match.status.wire,
        'created_at_ms': match.createdAt.millisecondsSinceEpoch,
        'doc': _encode(match.toJson()),
      });

  Future<void> putMatchPlayer(MatchPlayer matchPlayer) => _replace('match_players', <String, Object?>{
        'match_id': matchPlayer.matchId,
        'player_id': matchPlayer.playerId,
        'doc': _encode(matchPlayer.toJson()),
      });

  Future<void> putRules(MatchRules rules) => _replace('match_rules', <String, Object?>{
        'match_id': rules.matchId,
        'doc': _encode(rules.toJson()),
      });

  Future<void> putToss(Toss toss) => _replace('tosses', <String, Object?>{
        'id': toss.id,
        'match_id': toss.matchId,
        'doc': _encode(toss.toJson()),
      });

  Future<void> putInnings(Innings innings) => _replace('innings', <String, Object?>{
        'id': innings.id,
        'match_id': innings.matchId,
        'innings_number': innings.inningsNumber,
        'doc': _encode(innings.toJson()),
      });

  Future<void> putDelivery(Delivery delivery) => _replace('deliveries', <String, Object?>{
        'id': delivery.id,
        'innings_id': delivery.inningsId,
        'delivery_sequence': delivery.deliverySequence,
        'is_voided': delivery.isVoided ? 1 : 0,
        'doc': _encode(delivery.toJson()),
      });

  Future<void> putDecision(DecisionRecord decision) =>
      _replace('delivery_decisions', <String, Object?>{
        'id': decision.id,
        'delivery_id': decision.deliveryId,
        'doc': _encode(decision.toJson()),
      });

  Future<void> putSceneScan(SceneScan scan) => _replace('scene_scans', <String, Object?>{
        'id': scan.id,
        'match_id': scan.matchId,
        'doc': _encode(scan.toJson()),
      });

  Future<void> putWicketDetection(WicketDetection detection) =>
      _replace('wicket_detections', <String, Object?>{
        'id': detection.id,
        'match_id': detection.matchId,
        'is_active': detection.isActive ? 1 : 0,
        'doc': _encode(detection.toJson()),
      });

  Future<void> putTrajectory(TrajectorySnapshot snapshot) =>
      _replace('trajectory_snapshots', <String, Object?>{
        'id': snapshot.id,
        'delivery_id': snapshot.deliveryId,
        'doc': _encode(snapshot.toJson()),
      });

  /// Removes a match and everything that belongs to it. Teams and players stay (the roster is
  /// shared between matches).
  Future<void> deleteMatchData(String matchId) async {
    final List<Object?> args = <Object?>[matchId];
    const String deliveriesOfMatch = 'SELECT d.id FROM deliveries d '
        'JOIN innings i ON i.id = d.innings_id WHERE i.match_id = ?';
    await executor.rawDelete(
      'DELETE FROM trajectory_snapshots WHERE delivery_id IN ($deliveriesOfMatch)',
      args,
    );
    await executor.rawDelete(
      'DELETE FROM delivery_decisions WHERE delivery_id IN ($deliveriesOfMatch)',
      args,
    );
    await executor.rawDelete(
      'DELETE FROM deliveries WHERE innings_id IN (SELECT id FROM innings WHERE match_id = ?)',
      args,
    );
    await executor.delete('innings', where: 'match_id = ?', whereArgs: args);
    await executor.delete('tosses', where: 'match_id = ?', whereArgs: args);
    await executor.delete('wicket_detections', where: 'match_id = ?', whereArgs: args);
    await executor.delete('scene_scans', where: 'match_id = ?', whereArgs: args);
    await executor.delete('match_rules', where: 'match_id = ?', whereArgs: args);
    await executor.delete('match_players', where: 'match_id = ?', whereArgs: args);
    await executor.delete('matches', where: 'id = ?', whereArgs: args);
  }

  /// Writes every part of a restored match (no outbox events: the server already has them).
  Future<void> putBundleParts({
    required CricketMatch match,
    required List<Team> teams,
    required List<Player> players,
    required List<MatchPlayer> matchPlayers,
    required List<Innings> innings,
    required List<Delivery> deliveries,
    required List<DecisionRecord> decisions,
    required List<SceneScan> sceneScans,
    required List<WicketDetection> wicketDetections,
    required List<TrajectorySnapshot> trajectories,
    MatchRules? rules,
    Toss? toss,
  }) async {
    final Set<String> knownTeams = await teamIds();
    for (final Team team in teams) {
      if (!knownTeams.contains(team.id)) {
        await putTeam(team);
      }
    }
    final Set<String> knownPlayers = await playerIds();
    for (final Player player in players) {
      if (!knownPlayers.contains(player.id)) {
        await putPlayer(player);
      }
    }
    await putMatch(match);
    if (rules != null) {
      await putRules(rules);
    }
    for (final MatchPlayer matchPlayer in matchPlayers) {
      await putMatchPlayer(matchPlayer);
    }
    if (toss != null) {
      await putToss(toss);
    }
    for (final Innings item in innings) {
      await putInnings(item);
    }
    for (final SceneScan scan in sceneScans) {
      await putSceneScan(scan);
    }
    for (final WicketDetection detection in wicketDetections) {
      await putWicketDetection(detection);
    }
    for (final Delivery delivery in deliveries) {
      await putDelivery(delivery);
    }
    for (final DecisionRecord decision in decisions) {
      await putDecision(decision);
    }
    for (final TrajectorySnapshot snapshot in trajectories) {
      await putTrajectory(snapshot);
    }
  }

  // ---- Outbox -----------------------------------------------------------------------------

  Future<void> enqueue(OutboxEvent event) async {
    await executor.insert('outbox', event.toRow(), conflictAlgorithm: ConflictAlgorithm.abort);
  }

  /// Removes events the server has accepted.
  Future<void> deleteOutboxEvents(List<String> eventIds) async {
    if (eventIds.isEmpty) {
      return;
    }
    final String marks = List<String>.filled(eventIds.length, '?').join(',');
    await executor.rawDelete('DELETE FROM outbox WHERE event_id IN ($marks)', eventIds);
  }

  /// Records that the server refused an event; it stays in the outbox until the user decides.
  Future<void> markOutboxFailed(String eventId, {String? code, String? message}) async {
    await executor.rawUpdate(
      "UPDATE outbox SET status = 'FAILED', attempts = attempts + 1, "
      'error_code = ?, error_message = ? WHERE event_id = ?',
      <Object?>[code, message, eventId],
    );
  }

  /// Puts a failed event back in the queue (the user chose "Try again").
  Future<void> requeueOutboxEvent(String eventId) async {
    await executor.rawUpdate(
      "UPDATE outbox SET status = 'PENDING', attempts = 0, error_code = NULL, "
      'error_message = NULL WHERE event_id = ?',
      <Object?>[eventId],
    );
  }

  Future<int> requeueAllFailed() => executor.rawUpdate(
        "UPDATE outbox SET status = 'PENDING', attempts = 0, error_code = NULL, "
        "error_message = NULL WHERE status = 'FAILED'",
      );

  /// Re-queues failed events whose error can resolve itself (`PARENT_NOT_FOUND`,
  /// `INTERNAL_ERROR`) while they have been tried fewer than [maxAttempts] times.
  Future<int> requeueRetryableFailures({required int maxAttempts}) => executor.rawUpdate(
        "UPDATE outbox SET status = 'PENDING' WHERE status = 'FAILED' AND attempts < ? "
        'AND error_code IN (?, ?)',
        <Object?>[maxAttempts, SyncErrorCodes.parentNotFound, SyncErrorCodes.internalError],
      );

  /// Throws an event away (the user chose "Keep on this phone only").
  Future<void> discardOutboxEvent(String eventId) async {
    await executor.delete('outbox', where: 'event_id = ?', whereArgs: <Object?>[eventId]);
  }

  /// Drops every event that belongs to [matchId] (used when the match is deleted).
  Future<void> dropOutboxForMatch(String matchId) async {
    await executor.delete('outbox', where: 'match_id = ?', whereArgs: <Object?>[matchId]);
  }

  // ---- Replay packs -----------------------------------------------------------------------

  Future<void> putReplayRecord(ReplayRecord record) => _replace('replay_packs', record.toRow());

  Future<void> deleteReplayRecord(String id) async {
    await executor.delete('replay_packs', where: 'id = ?', whereArgs: <Object?>[id]);
  }

  // ---- Meta -------------------------------------------------------------------------------

  Future<void> setMeta(String key, String value) =>
      _replace('meta', <String, Object?>{'key': key, 'value': value});

  /// Clears all stored data (account deletion); the schema stays.
  Future<void> clearAll() async {
    for (final String table in const <String>[
      'replay_packs',
      'trajectory_snapshots',
      'delivery_decisions',
      'deliveries',
      'innings',
      'tosses',
      'wicket_detections',
      'scene_scans',
      'match_rules',
      'match_players',
      'matches',
      'players',
      'teams',
      'outbox',
      'meta',
    ]) {
      await executor.delete(table);
    }
  }
}
