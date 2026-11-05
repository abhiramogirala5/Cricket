import 'dart:async';
import 'dart:math' as math;

import 'package:gully_umpire/core/errors/app_exception.dart';
import 'package:gully_umpire/core/utils/app_log.dart';
import 'package:gully_umpire/core/utils/clock.dart';
import 'package:gully_umpire/data/local/local_store.dart';
import 'package:gully_umpire/data/remote/sync_api.dart';
import 'package:gully_umpire/data/sync/backoff.dart';
import 'package:gully_umpire/data/sync/connectivity_monitor.dart';
import 'package:gully_umpire/data/sync/sync_state.dart';
import 'package:gully_umpire/domain/models/json_helpers.dart';
import 'package:gully_umpire/domain/sync/sync.dart';

/// How one call to [SyncEngine.syncNow] ended.
enum SyncRunOutcome {
  /// Everything that could be sent was sent (or nothing was waiting).
  completed,

  /// Skipped: a recent failure is still being waited out.
  skippedBackoff,

  /// Skipped: the phone has no connection.
  skippedOffline,

  /// The server could not be reached; the events stay queued.
  failedNetwork,

  /// The server answered with an error (5xx, rate limit, disabled account ...); events stay queued.
  failedServer,

  /// The session ended; nothing can be sent until the user signs in again.
  needsSignIn,

  /// A bug or a damaged local database; reported in the state and logged.
  failedUnexpected,
}

final class SyncRunSummary {
  const SyncRunSummary({required this.outcome, this.accepted = 0, this.rejected = 0});

  final SyncRunOutcome outcome;

  /// Events the server applied or already had.
  final int accepted;

  /// Events the server refused (they are now `FAILED` in the outbox).
  final int rejected;
}

class _Step {
  const _Step({this.accepted = 0, this.rejected = 0, this.stop});

  final int accepted;
  final int rejected;

  /// Set when the run must end now.
  final SyncRunOutcome? stop;
}

/// Sends the outbox to the server in the background.
///
/// * Events are sent oldest first, at most [batchSize] per request, one request at a time.
/// * `APPLIED` and `DUPLICATE` events are removed; `REJECTED` ones become `FAILED` and wait for
///   the user (see the sync-issues screen).
/// * Network errors, `5xx` and `429` keep every event queued and are retried with exponential
///   backoff ([syncBackoff]).
/// * A `4xx` that rejects a whole batch is investigated by sending its events one by one, so one
///   bad event cannot block the others.
/// * Runs are triggered by changes to the local data, by the network coming back, by a timer and
///   by the user ("Sync now").
final class SyncEngine {
  SyncEngine({
    required LocalStore store,
    required SyncApi api,
    required AppClock clock,
    ConnectivityMonitor? connectivity,
    math.Random? random,
    this.batchSize = 100,
    this.pollInterval = const Duration(seconds: 60),
    this.maxAutoRetries = 3,
    this.changeDebounce = const Duration(milliseconds: 400),
  })  : _store = store,
        _api = api,
        _clock = clock,
        _connectivity = connectivity ?? const AlwaysOnlineMonitor(),
        _random = random;

  /// The API accepts 1-100 events per request.
  final int batchSize;
  final Duration pollInterval;

  /// How often an event that failed with a "retry later" error is retried automatically.
  final int maxAutoRetries;
  final Duration changeDebounce;

  final LocalStore _store;
  final SyncApi _api;
  final AppClock _clock;
  final ConnectivityMonitor _connectivity;
  final math.Random? _random;

  final StreamController<SyncState> _states = StreamController<SyncState>.broadcast();
  SyncState _state = SyncState.initial;

  Future<SyncRunSummary>? _running;
  StreamSubscription<void>? _changeSubscription;
  StreamSubscription<bool>? _connectivitySubscription;
  Timer? _timer;
  Timer? _debounce;
  DateTime? _nextAttemptAt;
  int _consecutiveFailures = 0;
  bool _started = false;
  bool _disposed = false;

  static const String lastSyncedMetaKey = 'last_synced_at';
  static const Duration _maxRetryAfter = Duration(minutes: 10);

  SyncState get state => _state;

  /// Emits on every change of [state].
  Stream<SyncState> get states => _states.stream;

  /// Starts the automatic triggers and does a first run.
  Future<void> start() async {
    if (_started || _disposed) {
      return;
    }
    _started = true;
    final DateTime? lastSynced = parseDateTimeOrNull(await _store.meta(lastSyncedMetaKey));
    if (lastSynced != null) {
      _publish(_state.copyWith(lastSyncedAt: lastSynced));
    }
    await refreshCounts();
    _changeSubscription = _store.changes.listen((_) => _scheduleRun());
    _connectivitySubscription = _connectivity.onlineChanges.listen((bool online) {
      if (online) {
        // The network just came back: do not wait for an old backoff to run out.
        _nextAttemptAt = null;
        _scheduleRun();
      }
    });
    _timer = Timer.periodic(pollInterval, (_) => unawaited(syncNow()));
    unawaited(syncNow());
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _debounce?.cancel();
    _timer?.cancel();
    await _changeSubscription?.cancel();
    await _connectivitySubscription?.cancel();
    final Future<SyncRunSummary>? running = _running;
    if (running != null) {
      try {
        await running;
      } on Object {
        // The run reports its own problems.
      }
    }
    await _states.close();
  }

  void _scheduleRun() {
    if (_disposed) {
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(changeDebounce, () => unawaited(syncNow()));
  }

  /// Sends what is waiting. Calls made while a run is in progress share that run.
  ///
  /// With [force] the backoff and the offline check are ignored (the user pressed "Sync now").
  Future<SyncRunSummary> syncNow({bool force = false}) {
    final Future<SyncRunSummary>? running = _running;
    if (running != null) {
      return running;
    }
    final Future<SyncRunSummary> started = _run(force: force).whenComplete(() {
      _running = null;
    });
    _running = started;
    return started;
  }

  Future<SyncRunSummary> _run({required bool force}) async {
    if (_disposed) {
      return const SyncRunSummary(outcome: SyncRunOutcome.completed);
    }
    if (!force) {
      if (_state.needsSignIn) {
        // Nothing can be sent until the user signs in again; the sign-in flow calls
        // `syncNow(force: true)`, which lifts this.
        return const SyncRunSummary(outcome: SyncRunOutcome.needsSignIn);
      }
      final DateTime? next = _nextAttemptAt;
      if (next != null && _clock.now().isBefore(next)) {
        return const SyncRunSummary(outcome: SyncRunOutcome.skippedBackoff);
      }
      if (!await _connectivity.isOnline()) {
        await _refreshAndPublish(isSyncing: false, isOffline: true);
        return const SyncRunSummary(outcome: SyncRunOutcome.skippedOffline);
      }
    }

    int accepted = 0;
    int rejected = 0;
    SyncRunOutcome outcome = SyncRunOutcome.completed;
    try {
      await _store.transaction((writer) async {
        await writer.requeueRetryableFailures(maxAttempts: maxAutoRetries);
      }, notify: false);
      List<OutboxEvent> batch = await _store.outboxBatch(batchSize);
      if (batch.isEmpty) {
        // Nothing to send: stay quiet (no "syncing" flicker every minute).
        await refreshCounts();
        return const SyncRunSummary(outcome: SyncRunOutcome.completed);
      }
      _publish(_state.copyWith(isSyncing: true, isOffline: false));
      while (!_disposed && batch.isNotEmpty) {
        final _Step step = await _sendBatch(batch);
        accepted += step.accepted;
        rejected += step.rejected;
        final SyncRunOutcome? stop = step.stop;
        if (stop != null) {
          outcome = stop;
          break;
        }
        if (step.accepted + step.rejected == 0) {
          break;
        }
        batch = await _store.outboxBatch(batchSize);
      }
    } on SessionExpiredException {
      outcome = SyncRunOutcome.needsSignIn;
    } on Object catch (error, stackTrace) {
      AppLog.error('Sync failed unexpectedly', error: error, stackTrace: stackTrace);
      outcome = SyncRunOutcome.failedUnexpected;
      _publish(_state.copyWith(lastError: 'Syncing hit a problem. It will be tried again.'));
      _recordFailure(null, null);
    }

    if (_disposed) {
      return SyncRunSummary(outcome: outcome, accepted: accepted, rejected: rejected);
    }

    final bool ok = outcome == SyncRunOutcome.completed;
    DateTime? syncedAt;
    if (ok) {
      _consecutiveFailures = 0;
      _nextAttemptAt = null;
      syncedAt = _clock.now();
      if (accepted > 0) {
        try {
          await _store.transaction((writer) async {
            await writer.setMeta(lastSyncedMetaKey, toIsoUtc(syncedAt) ?? '');
          }, notify: false);
        } on Object catch (error) {
          AppLog.warn('Could not store the last sync time: $error');
        }
      }
    }
    await _refreshAndPublish(
      isSyncing: false,
      needsSignIn: outcome == SyncRunOutcome.needsSignIn,
      clearError: ok,
      lastSyncedAt: syncedAt,
    );
    return SyncRunSummary(outcome: outcome, accepted: accepted, rejected: rejected);
  }

  Future<_Step> _sendBatch(List<OutboxEvent> batch) async {
    try {
      final SyncPushResponse response = await _api.push(batch);
      return await _applyResults(batch, response);
    } on SessionExpiredException {
      rethrow;
    } on NetworkException catch (error) {
      _recordFailure(error.userMessage, null);
      return const _Step(stop: SyncRunOutcome.failedNetwork);
    } on ApiException catch (error) {
      if (error.isServerError || error.isRateLimited) {
        _recordFailure(error.userMessage, error.retryAfter);
        return const _Step(stop: SyncRunOutcome.failedServer);
      }
      if (error.statusCode == 401 || error.statusCode == 403) {
        // The account itself is the problem (for example disabled); the events are fine.
        _recordFailure(error.userMessage, null);
        return const _Step(stop: SyncRunOutcome.failedServer);
      }
      if (batch.length > 1) {
        return _sendOneByOne(batch);
      }
      // A single event the server refuses as a whole (for example too large): park it.
      final OutboxEvent event = batch.first;
      await _store.transaction((writer) async {
        await writer.markOutboxFailed(event.eventId, code: error.code, message: error.message);
      }, notify: false);
      return const _Step(rejected: 1);
    }
  }

  Future<_Step> _sendOneByOne(List<OutboxEvent> batch) async {
    int accepted = 0;
    int rejected = 0;
    for (final OutboxEvent event in batch) {
      final _Step step = await _sendBatch(<OutboxEvent>[event]);
      accepted += step.accepted;
      rejected += step.rejected;
      if (step.stop != null) {
        return _Step(accepted: accepted, rejected: rejected, stop: step.stop);
      }
    }
    return _Step(accepted: accepted, rejected: rejected);
  }

  Future<_Step> _applyResults(List<OutboxEvent> batch, SyncPushResponse response) async {
    final Map<String, SyncEventResult> byId = <String, SyncEventResult>{
      for (final SyncEventResult result in response.results) result.eventId: result,
    };
    final List<String> acceptedIds = <String>[];
    final List<SyncEventResult> rejections = <SyncEventResult>[];
    bool incomplete = false;
    for (final OutboxEvent event in batch) {
      final SyncEventResult? result = byId[event.eventId];
      if (result == null) {
        incomplete = true;
      } else if (result.status.isAccepted) {
        acceptedIds.add(event.eventId);
      } else {
        rejections.add(result);
      }
    }
    await _store.transaction((writer) async {
      await writer.deleteOutboxEvents(acceptedIds);
      for (final SyncEventResult result in rejections) {
        await writer.markOutboxFailed(
          result.eventId,
          code: result.errorCode,
          message: result.errorMessage,
        );
      }
    }, notify: false);
    if (incomplete) {
      _recordFailure('The server\'s answer was incomplete. Trying again soon.', null);
      return _Step(
        accepted: acceptedIds.length,
        rejected: rejections.length,
        stop: SyncRunOutcome.failedServer,
      );
    }
    return _Step(accepted: acceptedIds.length, rejected: rejections.length);
  }

  void _recordFailure(String? message, Duration? retryAfter) {
    _consecutiveFailures += 1;
    Duration delay = syncBackoff(_consecutiveFailures, random: _random);
    if (retryAfter != null) {
      final Duration capped = retryAfter > _maxRetryAfter ? _maxRetryAfter : retryAfter;
      if (capped > delay) {
        delay = capped;
      }
    }
    _nextAttemptAt = _clock.now().add(delay);
    if (message != null) {
      _publish(_state.copyWith(lastError: message));
    }
  }

  /// Re-reads the counters from the database and publishes them.
  Future<void> refreshCounts() => _refreshAndPublish();

  Future<void> _refreshAndPublish({
    bool? isSyncing,
    bool? isOffline,
    bool? needsSignIn,
    bool clearError = false,
    DateTime? lastSyncedAt,
  }) async {
    if (_disposed) {
      return;
    }
    try {
      final int pending = await _store.pendingOutboxCount();
      final int failed = await _store.failedOutboxCount();
      _publish(
        _state.copyWith(
          pending: pending,
          failed: failed,
          isSyncing: isSyncing,
          isOffline: isOffline,
          needsSignIn: needsSignIn,
          clearError: clearError,
          lastSyncedAt: lastSyncedAt,
        ),
      );
    } on Object catch (error) {
      AppLog.warn('Could not read the outbox counters: $error');
      _publish(_state.copyWith(isSyncing: isSyncing ?? false));
    }
  }

  void _publish(SyncState next) {
    if (_disposed || next == _state) {
      return;
    }
    _state = next;
    if (!_states.isClosed) {
      _states.add(next);
    }
  }

  // ---- Decisions of the user on failed events ---------------------------------------------

  /// "Try again" on one failed event.
  Future<void> retryEvent(String eventId) async {
    await _store.transaction((writer) async {
      await writer.requeueOutboxEvent(eventId);
    }, notify: false);
    _nextAttemptAt = null;
    unawaited(syncNow(force: true));
  }

  /// "Try all again".
  Future<void> retryAllFailed() async {
    await _store.transaction((writer) async {
      await writer.requeueAllFailed();
    }, notify: false);
    _nextAttemptAt = null;
    unawaited(syncNow(force: true));
  }

  /// "Keep on this phone only": the change stays here but is never sent.
  Future<void> discardEvent(String eventId) async {
    await _store.transaction((writer) async {
      await writer.discardOutboxEvent(eventId);
    }, notify: false);
    await refreshCounts();
  }
}
