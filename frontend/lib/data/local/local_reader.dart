import 'package:gully_umpire/data/replays/replay_record.dart';
import 'package:gully_umpire/domain/aggregates/match_bundle.dart';
import 'package:gully_umpire/domain/models/json_helpers.dart';
import 'package:gully_umpire/domain/models/models.dart';
import 'package:gully_umpire/domain/sync/sync.dart';
import 'package:sqflite/sqflite.dart';

/// Read access to the local database. Used directly for reads and, through [LocalWriter],
/// inside a transaction for writes.
class LocalReader {
  const LocalReader(this.executor);

  /// The database or the transaction the queries run on.
  final DatabaseExecutor executor;

  // ---- Rows to models --------------------------------------------------------------------

  static Map<String, Object?> _doc(Map<String, Object?> row) =>
      asJsonMapOrNull(row['doc']) ?? const <String, Object?>{};

  static List<T> _decode<T>(
    List<Map<String, Object?>> rows,
    T Function(Map<String, Object?> json) fromJson,
  ) =>
      rows.map<T>((Map<String, Object?> row) => fromJson(_doc(row))).toList(growable: false);

  static int _firstInt(List<Map<String, Object?>> rows) {
    if (rows.isEmpty || rows.first.isEmpty) {
      return 0;
    }
    return asInt(rows.first.values.first ?? 0);
  }

  // ---- Roster -----------------------------------------------------------------------------

  Future<List<Team>> teams() async => _decode<Team>(
        await executor.query('teams', orderBy: 'name COLLATE NOCASE ASC'),
        Team.fromJson,
      );

  Future<Team?> team(String id) async {
    final List<Map<String, Object?>> rows =
        await executor.query('teams', where: 'id = ?', whereArgs: <Object?>[id], limit: 1);
    return rows.isEmpty ? null : Team.fromJson(_doc(rows.first));
  }

  Future<List<Player>> players() async => _decode<Player>(
        await executor.query('players', orderBy: 'name COLLATE NOCASE ASC'),
        Player.fromJson,
      );

  Future<Player?> player(String id) async {
    final List<Map<String, Object?>> rows =
        await executor.query('players', where: 'id = ?', whereArgs: <Object?>[id], limit: 1);
    return rows.isEmpty ? null : Player.fromJson(_doc(rows.first));
  }

  Future<Set<String>> playerIds() async {
    final List<Map<String, Object?>> rows = await executor.query('players', columns: <String>['id']);
    return rows.map<String>((Map<String, Object?> row) => asString(row['id'])).toSet();
  }

  Future<Set<String>> teamIds() async {
    final List<Map<String, Object?>> rows = await executor.query('teams', columns: <String>['id']);
    return rows.map<String>((Map<String, Object?> row) => asString(row['id'])).toSet();
  }

  // ---- Matches ----------------------------------------------------------------------------

  /// Newest first.
  Future<List<CricketMatch>> matches() async => _decode<CricketMatch>(
        await executor.query('matches', orderBy: 'created_at_ms DESC, id ASC'),
        CricketMatch.fromJson,
      );

  Future<CricketMatch?> match(String id) async {
    final List<Map<String, Object?>> rows =
        await executor.query('matches', where: 'id = ?', whereArgs: <Object?>[id], limit: 1);
    return rows.isEmpty ? null : CricketMatch.fromJson(_doc(rows.first));
  }

  Future<Set<String>> matchIds() async {
    final List<Map<String, Object?>> rows = await executor.query('matches', columns: <String>['id']);
    return rows.map<String>((Map<String, Object?> row) => asString(row['id'])).toSet();
  }

  Future<List<MatchPlayer>> matchPlayers(String matchId) async => _decode<MatchPlayer>(
        await executor.query(
          'match_players',
          where: 'match_id = ?',
          whereArgs: <Object?>[matchId],
        ),
        MatchPlayer.fromJson,
      );

  Future<bool> matchPlayerExists(String matchId, String playerId) async {
    final List<Map<String, Object?>> rows = await executor.query(
      'match_players',
      columns: <String>['player_id'],
      where: 'match_id = ? AND player_id = ?',
      whereArgs: <Object?>[matchId, playerId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<MatchRules?> rules(String matchId) async {
    final List<Map<String, Object?>> rows = await executor
        .query('match_rules', where: 'match_id = ?', whereArgs: <Object?>[matchId], limit: 1);
    return rows.isEmpty ? null : MatchRules.fromJson(_doc(rows.first));
  }

  Future<Toss?> toss(String matchId) async {
    final List<Map<String, Object?>> rows = await executor
        .query('tosses', where: 'match_id = ?', whereArgs: <Object?>[matchId], limit: 1);
    return rows.isEmpty ? null : Toss.fromJson(_doc(rows.first));
  }

  /// Ordered by innings number.
  Future<List<Innings>> inningsOf(String matchId) async => _decode<Innings>(
        await executor.query(
          'innings',
          where: 'match_id = ?',
          whereArgs: <Object?>[matchId],
          orderBy: 'innings_number ASC',
        ),
        Innings.fromJson,
      );

  /// Every innings of every match (the match list shows the scores).
  Future<List<Innings>> allInnings() async => _decode<Innings>(
        await executor.query('innings', orderBy: 'match_id ASC, innings_number ASC'),
        Innings.fromJson,
      );

  Future<Innings?> inningsById(String inningsId) async {
    final List<Map<String, Object?>> rows = await executor
        .query('innings', where: 'id = ?', whereArgs: <Object?>[inningsId], limit: 1);
    return rows.isEmpty ? null : Innings.fromJson(_doc(rows.first));
  }

  /// All deliveries of an innings, voided ones included, in the order they were bowled.
  Future<List<Delivery>> deliveries(String inningsId) async => _decode<Delivery>(
        await executor.query(
          'deliveries',
          where: 'innings_id = ?',
          whereArgs: <Object?>[inningsId],
          orderBy: 'delivery_sequence ASC',
        ),
        Delivery.fromJson,
      );

  Future<Delivery?> delivery(String deliveryId) async {
    final List<Map<String, Object?>> rows = await executor
        .query('deliveries', where: 'id = ?', whereArgs: <Object?>[deliveryId], limit: 1);
    return rows.isEmpty ? null : Delivery.fromJson(_doc(rows.first));
  }

  Future<List<DecisionRecord>> decisionsOfDelivery(String deliveryId) async {
    final List<DecisionRecord> items = _decode<DecisionRecord>(
      await executor.query(
        'delivery_decisions',
        where: 'delivery_id = ?',
        whereArgs: <Object?>[deliveryId],
      ),
      DecisionRecord.fromJson,
    ).toList();
    items.sort((DecisionRecord a, DecisionRecord b) => a.createdAt.compareTo(b.createdAt));
    return items;
  }

  /// Every decision of every delivery of [matchId].
  Future<List<DecisionRecord>> decisionsOfMatch(String matchId) async {
    final List<Map<String, Object?>> rows = await executor.rawQuery(
      'SELECT dd.doc AS doc FROM delivery_decisions dd '
      'JOIN deliveries d ON d.id = dd.delivery_id '
      'JOIN innings i ON i.id = d.innings_id '
      'WHERE i.match_id = ?',
      <Object?>[matchId],
    );
    final List<DecisionRecord> items = _decode<DecisionRecord>(rows, DecisionRecord.fromJson).toList();
    items.sort((DecisionRecord a, DecisionRecord b) => a.createdAt.compareTo(b.createdAt));
    return items;
  }

  Future<List<SceneScan>> sceneScans(String matchId) async => _decode<SceneScan>(
        await executor.query('scene_scans', where: 'match_id = ?', whereArgs: <Object?>[matchId]),
        SceneScan.fromJson,
      );

  Future<List<WicketDetection>> wicketDetections(String matchId) async =>
      _decode<WicketDetection>(
        await executor
            .query('wicket_detections', where: 'match_id = ?', whereArgs: <Object?>[matchId]),
        WicketDetection.fromJson,
      );

  Future<TrajectorySnapshot?> trajectoryOfDelivery(String deliveryId) async {
    final List<Map<String, Object?>> rows = await executor.query(
      'trajectory_snapshots',
      where: 'delivery_id = ?',
      whereArgs: <Object?>[deliveryId],
      limit: 1,
    );
    return rows.isEmpty ? null : TrajectorySnapshot.fromJson(_doc(rows.first));
  }

  /// Everything about one match, or `null` when the match (or one of its teams) is not stored.
  Future<MatchBundle?> bundle(String matchId) async {
    final CricketMatch? match = await this.match(matchId);
    if (match == null) {
      return null;
    }
    final Team? teamA = await team(match.teamAId);
    final Team? teamB = await team(match.teamBId);
    if (teamA == null || teamB == null) {
      return null;
    }
    final List<MatchPlayer> matchPlayers = await this.matchPlayers(matchId);
    final Map<String, Player> players = <String, Player>{};
    for (final MatchPlayer mp in matchPlayers) {
      final Player? found = await player(mp.playerId);
      if (found != null) {
        players[found.id] = found;
      }
    }
    final List<Innings> innings = await inningsOf(matchId);
    final Map<String, List<Delivery>> deliveriesByInnings = <String, List<Delivery>>{};
    for (final Innings item in innings) {
      deliveriesByInnings[item.id] = await deliveries(item.id);
    }
    return MatchBundle(
      match: match,
      teamA: teamA,
      teamB: teamB,
      rules: await rules(matchId),
      matchPlayers: matchPlayers,
      players: players,
      toss: await toss(matchId),
      innings: innings,
      deliveriesByInnings: deliveriesByInnings,
      decisions: await decisionsOfMatch(matchId),
      sceneScans: await sceneScans(matchId),
      wicketDetections: await wicketDetections(matchId),
    );
  }

  // ---- Outbox -----------------------------------------------------------------------------

  /// The next events to send, oldest first.
  ///
  /// Events of a match that has an earlier `FAILED` event are held back: later changes depend on
  /// the earlier one, and sending them out of order would let the server's numbering drift.
  Future<List<OutboxEvent>> outboxBatch(int limit) async {
    final List<Map<String, Object?>> rows = await executor.rawQuery(
      "SELECT o.* FROM outbox o WHERE o.status = 'PENDING' AND NOT EXISTS ("
      "SELECT 1 FROM outbox f WHERE f.status = 'FAILED' AND f.match_id = o.match_id "
      'AND f.seq < o.seq) ORDER BY o.seq ASC LIMIT ?',
      <Object?>[limit],
    );
    return rows.map<OutboxEvent>(OutboxEvent.fromRow).toList(growable: false);
  }

  Future<int> pendingOutboxCount() async => _firstInt(
        await executor.rawQuery("SELECT COUNT(*) FROM outbox WHERE status = 'PENDING'"),
      );

  Future<int> failedOutboxCount() async => _firstInt(
        await executor.rawQuery("SELECT COUNT(*) FROM outbox WHERE status = 'FAILED'"),
      );

  Future<List<OutboxEvent>> failedOutboxEvents() async {
    final List<Map<String, Object?>> rows =
        await executor.query('outbox', where: "status = 'FAILED'", orderBy: 'seq ASC');
    return rows.map<OutboxEvent>(OutboxEvent.fromRow).toList(growable: false);
  }

  /// Every event still in the outbox (tests and diagnostics).
  Future<List<OutboxEvent>> allOutboxEvents() async {
    final List<Map<String, Object?>> rows = await executor.query('outbox', orderBy: 'seq ASC');
    return rows.map<OutboxEvent>(OutboxEvent.fromRow).toList(growable: false);
  }

  /// Matches whose deletion has not reached the server yet (they must not be restored).
  Future<Set<String>> matchesPendingDeletion() async {
    final List<Map<String, Object?>> rows = await executor.query(
      'outbox',
      columns: <String>['payload'],
      where: 'entity_type = ? AND action = ?',
      whereArgs: <Object?>[SyncEntityType.match.wire, SyncAction.delete.wire],
    );
    final Set<String> ids = <String>{};
    for (final Map<String, Object?> row in rows) {
      final Map<String, Object?>? payload = asJsonMapOrNull(row['payload']);
      final String? id = payload == null ? null : asStringOrNull(payload['id']);
      if (id != null) {
        ids.add(id);
      }
    }
    return ids;
  }

  // ---- Replay packs -----------------------------------------------------------------------

  Future<ReplayRecord?> replayRecord(String id) async {
    final List<Map<String, Object?>> rows =
        await executor.query('replay_packs', where: 'id = ?', whereArgs: <Object?>[id], limit: 1);
    return rows.isEmpty ? null : ReplayRecord.fromRow(rows.first);
  }

  Future<ReplayRecord?> replayRecordForDelivery(String deliveryId) async {
    final List<Map<String, Object?>> rows = await executor.query(
      'replay_packs',
      where: 'delivery_id = ?',
      whereArgs: <Object?>[deliveryId],
      orderBy: 'created_at_ms DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : ReplayRecord.fromRow(rows.first);
  }

  /// Replays of scored balls that still have to be uploaded, oldest first.
  Future<List<ReplayRecord>> replayRecordsToUpload({int limit = 5, int maxAttempts = 8}) async {
    final List<Map<String, Object?>> rows = await executor.query(
      'replay_packs',
      where: "delivery_id IS NOT NULL AND upload_state IN ('LOCAL', 'FAILED') AND attempts < ?",
      whereArgs: <Object?>[maxAttempts],
      orderBy: 'created_at_ms ASC',
      limit: limit,
    );
    return rows.map<ReplayRecord>(ReplayRecord.fromRow).toList(growable: false);
  }

  /// Every replay record, oldest first (for keeping the stored size in check).
  Future<List<ReplayRecord>> replayRecordsOldestFirst() async {
    final List<Map<String, Object?>> rows =
        await executor.query('replay_packs', orderBy: 'created_at_ms ASC');
    return rows.map<ReplayRecord>(ReplayRecord.fromRow).toList(growable: false);
  }

  // ---- Meta -------------------------------------------------------------------------------

  Future<String?> meta(String key) async {
    final List<Map<String, Object?>> rows =
        await executor.query('meta', where: 'key = ?', whereArgs: <Object?>[key], limit: 1);
    return rows.isEmpty ? null : asStringOrNull(rows.first['value']);
  }
}
