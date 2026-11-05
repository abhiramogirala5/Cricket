import 'package:gully_umpire/core/utils/clock.dart';
import 'package:gully_umpire/core/utils/id_generator.dart';
import 'package:gully_umpire/data/local/local_store.dart';
import 'package:gully_umpire/data/local/local_writer.dart';
import 'package:gully_umpire/domain/models/models.dart';
import 'package:gully_umpire/domain/setup/match_setup.dart';
import 'package:gully_umpire/domain/sync/sync.dart';

/// The user's saved players and teams (the roster shared by all matches).
final class RosterRepository {
  RosterRepository({
    required LocalStore store,
    required AppClock clock,
    required IdGenerator ids,
    required bool syncEnabled,
  })  : _store = store,
        _clock = clock,
        _ids = ids,
        _syncEnabled = syncEnabled;

  final LocalStore _store;
  final AppClock _clock;
  final IdGenerator _ids;
  final bool _syncEnabled;

  Future<List<Player>> players() => _store.players();

  Future<List<Team>> teams() => _store.teams();

  Future<Player> createPlayer({
    required String displayName,
    BattingHand battingHand = BattingHand.unknown,
    int? declaredHeightCm,
  }) async {
    final String? problem = validatePlayerFields(name: displayName, heightCm: declaredHeightCm);
    if (problem != null) {
      throw SetupException(problem);
    }
    final DateTime now = _clock.now();
    final Player player = Player(
      id: _ids.newId(),
      displayName: displayName.trim(),
      battingHand: battingHand,
      declaredHeightCm: declaredHeightCm,
      createdAt: now,
      updatedAt: now,
    );
    await _store.transaction((LocalWriter writer) async {
      await writer.putPlayer(player);
      await _enqueue(writer, SyncEntityType.player, player.toSyncPayload(), now);
    });
    return player;
  }

  /// Changes a saved player. A `null` argument keeps the saved value; to remove a saved height
  /// pass [clearHeight] (it wins over [declaredHeightCm]).
  Future<Player> updatePlayer(
    Player player, {
    String? displayName,
    BattingHand? battingHand,
    int? declaredHeightCm,
    bool clearHeight = false,
  }) async {
    final String name = displayName ?? player.displayName;
    final int? height = clearHeight ? null : (declaredHeightCm ?? player.declaredHeightCm);
    final String? problem = validatePlayerFields(name: name, heightCm: height);
    if (problem != null) {
      throw SetupException(problem);
    }
    final DateTime now = _clock.now();
    final Player updated = Player(
      id: player.id,
      displayName: name.trim(),
      battingHand: battingHand ?? player.battingHand,
      declaredHeightCm: height,
      createdAt: player.createdAt,
      updatedAt: now,
    );
    await _store.transaction((LocalWriter writer) async {
      await writer.putPlayer(updated);
      await _enqueue(writer, SyncEntityType.player, updated.toSyncPayload(), now);
    });
    return updated;
  }

  Future<void> _enqueue(
    LocalWriter writer,
    SyncEntityType type,
    Map<String, Object?> payload,
    DateTime now,
  ) async {
    if (!_syncEnabled) {
      return;
    }
    await writer.enqueue(
      OutboxEvent(
        eventId: _ids.newId(),
        entityType: type,
        action: SyncAction.upsert,
        payload: payload,
        clientCreatedAt: now,
      ),
    );
  }
}
