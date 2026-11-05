import 'package:equatable/equatable.dart';
import 'package:gully_umpire/core/errors/app_exception.dart';
import 'package:gully_umpire/core/utils/app_log.dart';
import 'package:gully_umpire/core/utils/clock.dart';
import 'package:gully_umpire/data/local/local_store.dart';
import 'package:gully_umpire/data/local/local_writer.dart';
import 'package:gully_umpire/data/remote/remote_read_api.dart';
import 'package:gully_umpire/domain/models/models.dart';
import 'package:gully_umpire/domain/sync/match_snapshot.dart';

/// What a restore did.
final class RestoreReport extends Equatable {
  const RestoreReport({
    this.teamsAdded = 0,
    this.playersAdded = 0,
    this.matchesRestored = 0,
    this.matchesFailed = 0,
  });

  final int teamsAdded;
  final int playersAdded;
  final int matchesRestored;

  /// Matches that could not be fetched this time (they are tried again on the next restore).
  final int matchesFailed;

  bool get isEmpty => teamsAdded == 0 && playersAdded == 0 && matchesRestored == 0;

  @override
  List<Object?> get props => <Object?>[teamsAdded, playersAdded, matchesRestored, matchesFailed];
}

/// Copies what the server has but this phone does not (a new phone, or a reinstall).
///
/// It only ADDS: anything that already exists on the phone is left alone, because the phone may
/// hold changes that have not been sent yet. Matches that were deleted here but whose deletion
/// has not reached the server yet are not brought back.
final class RestoreService {
  RestoreService({
    required LocalStore store,
    required RemoteReadApi api,
    AppClock clock = const SystemClock(),
  })  : _store = store,
        _api = api,
        _clock = clock;

  static const String restoredMetaKey = 'restored_at';

  final LocalStore _store;
  final RemoteReadApi _api;
  final AppClock _clock;

  Future<RestoreReport> restoreMissing() async {
    final Set<String> deleting = await _store.matchesPendingDeletion();

    final List<Team> remoteTeams = await _api.teams();
    final List<Player> remotePlayers = await _api.players();
    final Set<String> knownTeams = await _store.teamIds();
    final Set<String> knownPlayers = await _store.playerIds();
    final List<Team> newTeams =
        remoteTeams.where((Team team) => !knownTeams.contains(team.id)).toList(growable: false);
    final List<Player> newPlayers = remotePlayers
        .where((Player player) => !knownPlayers.contains(player.id))
        .toList(growable: false);
    if (newTeams.isNotEmpty || newPlayers.isNotEmpty) {
      await _store.transaction((LocalWriter writer) async {
        for (final Team team in newTeams) {
          await writer.putTeam(team);
        }
        for (final Player player in newPlayers) {
          await writer.putPlayer(player);
        }
      });
    }

    final List<String> remoteMatchIds = await _api.matchIds();
    final Set<String> localMatchIds = await _store.matchIds();
    final List<String> missing = remoteMatchIds
        .where((String id) => !localMatchIds.contains(id) && !deleting.contains(id))
        .toList(growable: false);

    int restored = 0;
    int failed = 0;
    for (final String matchId in missing) {
      try {
        final MatchSnapshot snapshot = await _api.snapshot(matchId);
        await _store.transaction((LocalWriter writer) async {
          await writer.putBundleParts(
            match: snapshot.match,
            teams: snapshot.teams,
            players: snapshot.players,
            matchPlayers: snapshot.matchPlayers,
            innings: snapshot.innings,
            deliveries: snapshot.deliveries,
            decisions: snapshot.decisions,
            sceneScans: snapshot.sceneScans,
            wicketDetections: snapshot.wicketDetections,
            trajectories: snapshot.trajectories,
            rules: snapshot.rules,
            toss: snapshot.toss,
          );
        });
        restored += 1;
      } on SessionExpiredException {
        rethrow;
      } on NetworkException {
        rethrow;
      } on ApiException catch (error) {
        if (error.isServerError || error.isRateLimited) {
          rethrow;
        }
        AppLog.warn('Could not restore match $matchId: ${error.code}');
        failed += 1;
      } on FormatException catch (error) {
        AppLog.warn('Could not read the stored copy of match $matchId: ${error.message}');
        failed += 1;
      }
    }

    if (failed == 0) {
      await _store.transaction((LocalWriter writer) async {
        await writer.setMeta(restoredMetaKey, _clock.now().toIso8601String());
      }, notify: false);
    }
    return RestoreReport(
      teamsAdded: newTeams.length,
      playersAdded: newPlayers.length,
      matchesRestored: restored,
      matchesFailed: failed,
    );
  }
}
