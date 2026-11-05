import 'package:gully_umpire/data/local/local_store.dart';
import 'package:gully_umpire/data/replays/replay_store.dart';
import 'package:gully_umpire/data/replays/replay_uploader.dart';
import 'package:gully_umpire/data/repositories/match_repository.dart';
import 'package:gully_umpire/data/repositories/roster_repository.dart';
import 'package:gully_umpire/data/sync/restore_service.dart';
import 'package:gully_umpire/data/sync/sync_engine.dart';

/// Everything that belongs to the account that is using the app right now: its database, the
/// repositories on top of it and (when there is an account) the background sync.
///
/// There is exactly one of these at a time. Signing out closes it; signing in as someone else
/// opens a different one, with a different database file, so accounts never see each other's data.
final class ActiveSession {
  ActiveSession({
    required this.userId,
    required this.isLocal,
    required this.store,
    required this.roster,
    required this.matches,
    this.syncEngine,
    this.restoreService,
    this.replays,
    this.replayUploader,
  });

  /// The server id of the account, or [localUserId] when the app runs without a backend.
  final String userId;

  /// The app runs without a backend: nothing is synced and there is no sign-in.
  final bool isLocal;
  final LocalStore store;
  final RosterRepository roster;
  final MatchRepository matches;
  final SyncEngine? syncEngine;
  final RestoreService? restoreService;

  /// The replay files of this account's deliveries (`null` where there is no place to keep files,
  /// as in some tests).
  final ReplayStore? replays;

  /// Sends the replays to the server; `null` in local-only mode.
  final ReplayUploader? replayUploader;

  /// Database owner used when there is no account.
  static const String localUserId = 'local';

  bool get syncs => syncEngine != null;

  Future<void> dispose() async {
    await replayUploader?.dispose();
    await syncEngine?.dispose();
    await store.close();
  }
}
