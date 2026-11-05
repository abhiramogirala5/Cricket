import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gully_umpire/core/di/session_providers.dart';
import 'package:gully_umpire/data/replays/replay_store.dart';
import 'package:gully_umpire/data/replays/replay_uploader.dart';
import 'package:gully_umpire/data/repositories/match_repository.dart';
import 'package:gully_umpire/data/repositories/roster_repository.dart';
import 'package:gully_umpire/data/session/active_session.dart';
import 'package:gully_umpire/data/sync/sync_engine.dart';
import 'package:gully_umpire/data/sync/sync_state.dart';
import 'package:gully_umpire/domain/aggregates/match_bundle.dart';
import 'package:gully_umpire/domain/aggregates/match_list_item.dart';
import 'package:gully_umpire/domain/models/models.dart';
import 'package:gully_umpire/domain/sync/sync.dart';

ActiveSession _require(ActiveSession? active) {
  if (active == null) {
    throw StateError('Nobody is signed in.');
  }
  return active;
}

/// Repositories of the open account. Only read these while signed in (event handlers).
final Provider<MatchRepository> matchRepositoryProvider =
    Provider<MatchRepository>((ref) => _require(ref.watch(activeSessionProvider)).matches);

final Provider<RosterRepository> rosterRepositoryProvider =
    Provider<RosterRepository>((ref) => _require(ref.watch(activeSessionProvider)).roster);

/// The replay files of the open account (`null` when nobody is signed in).
final Provider<ReplayStore?> replayStoreProvider =
    Provider<ReplayStore?>((ref) => ref.watch(activeSessionProvider)?.replays);

/// Sends replays to the server, or `null` in local-only mode.
final Provider<ReplayUploader?> replayUploaderProvider =
    Provider<ReplayUploader?>((ref) => ref.watch(activeSessionProvider)?.replayUploader);

/// The sync engine, or `null` when there is no account (local-only mode).
final Provider<SyncEngine?> syncEngineProvider =
    Provider<SyncEngine?>((ref) => ref.watch(activeSessionProvider)?.syncEngine);

/// Counts up every time the open account's data changes. Providers that read data watch this so
/// that they refresh themselves.
final dataChangesProvider = StreamProvider.autoDispose<int>((ref) {
  final ActiveSession? active = ref.watch(activeSessionProvider);
  final StreamController<int> controller = StreamController<int>();
  int tick = 0;
  controller.add(tick);
  if (active == null) {
    ref.onDispose(controller.close);
    return controller.stream;
  }
  final StreamSubscription<void> subscription = active.store.changes.listen((_) {
    tick += 1;
    if (!controller.isClosed) {
      controller.add(tick);
    }
  });
  ref.onDispose(() {
    subscription.cancel();
    controller.close();
  });
  return controller.stream;
});

/// The sync status for the status chip and the sync screen.
final syncStateProvider = StreamProvider.autoDispose<SyncState>((ref) {
  final SyncEngine? engine = ref.watch(syncEngineProvider);
  final StreamController<SyncState> controller = StreamController<SyncState>();
  if (engine == null) {
    controller.add(SyncState.initial);
    ref.onDispose(controller.close);
    return controller.stream;
  }
  final StreamSubscription<SyncState> subscription = engine.states.listen((SyncState state) {
    if (!controller.isClosed) {
      controller.add(state);
    }
  });
  controller.add(engine.state);
  ref.onDispose(() {
    subscription.cancel();
    controller.close();
  });
  return controller.stream;
});

/// All matches of the open account, newest first.
final matchListProvider = FutureProvider.autoDispose<List<MatchListItem>>((ref) async {
  ref.watch(dataChangesProvider);
  final ActiveSession? active = ref.watch(activeSessionProvider);
  if (active == null) {
    return const <MatchListItem>[];
  }
  return active.matches.matchList();
});

/// One match with everything about it (`null` when it does not exist, for example after it was
/// deleted).
final matchBundleProvider = FutureProvider.autoDispose.family<MatchBundle?, String>((ref, String matchId) async {
  ref.watch(dataChangesProvider);
  final ActiveSession? active = ref.watch(activeSessionProvider);
  if (active == null) {
    return null;
  }
  return active.matches.bundle(matchId);
});

/// The ball path of one delivery, loaded on demand.
final trajectoryProvider = FutureProvider.autoDispose.family<TrajectorySnapshot?, String>((ref, String deliveryId) async {
  final ActiveSession? active = ref.watch(activeSessionProvider);
  if (active == null) {
    return null;
  }
  return active.matches.trajectoryOf(deliveryId);
});

final teamsProvider = FutureProvider.autoDispose<List<Team>>((ref) async {
  ref.watch(dataChangesProvider);
  final ActiveSession? active = ref.watch(activeSessionProvider);
  if (active == null) {
    return const <Team>[];
  }
  return active.roster.teams();
});

final playersProvider = FutureProvider.autoDispose<List<Player>>((ref) async {
  ref.watch(dataChangesProvider);
  final ActiveSession? active = ref.watch(activeSessionProvider);
  if (active == null) {
    return const <Player>[];
  }
  return active.roster.players();
});

/// Events the server refused (sync screen).
final failedEventsProvider = FutureProvider.autoDispose<List<OutboxEvent>>((ref) async {
  ref.watch(dataChangesProvider);
  ref.watch(syncStateProvider);
  final ActiveSession? active = ref.watch(activeSessionProvider);
  if (active == null) {
    return const <OutboxEvent>[];
  }
  return active.store.failedOutboxEvents();
});
