import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/core/errors/app_exception.dart';
import 'package:gully_umpire/data/local/local_store.dart';
import 'package:gully_umpire/data/local/local_writer.dart';
import 'package:gully_umpire/data/sync/sync_engine.dart';
import 'package:gully_umpire/data/sync/sync_state.dart';
import 'package:gully_umpire/domain/sync/sync.dart';

import '../../support/data_test_support.dart';
import 'fake_sync_api.dart';

SyncPushResponse answer(
  List<OutboxEvent> events,
  Map<String, SyncEventResult> special,
) =>
    SyncPushResponse(
      results: events
          .map<SyncEventResult>(
            (OutboxEvent e) =>
                special[e.eventId] ??
                SyncEventResult(eventId: e.eventId, status: SyncResultStatus.applied),
          )
          .toList(),
    );

SyncEventResult refusal(String eventId, String code, [String message = 'refused']) =>
    SyncEventResult(
      eventId: eventId,
      status: SyncResultStatus.rejected,
      errorCode: code,
      errorMessage: message,
    );

void main() {
  late LocalStore store;
  late FakeSyncApi api;
  late FakeClock clock;
  late FakeConnectivity connectivity;
  late SyncEngine engine;

  Future<void> queue(int count, {String? matchId, int from = 1}) async {
    await store.transaction((LocalWriter w) async {
      for (int i = from; i < from + count; i++) {
        await w.enqueue(
          OutboxEvent(
            eventId: 'e$i',
            entityType: SyncEntityType.delivery,
            action: SyncAction.upsert,
            payload: <String, Object?>{'i': i},
            clientCreatedAt: DateTime.utc(2026, 10, 8),
            matchId: matchId,
          ),
        );
      }
    }, notify: false);
  }

  SyncEngine makeEngine({int batchSize = 100}) => SyncEngine(
        store: store,
        api: api,
        clock: clock,
        connectivity: connectivity,
        random: Random(1),
        batchSize: batchSize,
        changeDebounce: const Duration(milliseconds: 10),
        pollInterval: const Duration(hours: 1),
      );

  setUp(() async {
    store = await openMemoryStore();
    api = FakeSyncApi();
    clock = FakeClock();
    connectivity = FakeConnectivity();
    engine = makeEngine();
  });

  tearDown(() async {
    await engine.dispose();
    await store.close();
  });

  group('a normal run', () {
    test('with nothing queued it does not call the server', () async {
      final SyncRunSummary summary = await engine.syncNow();
      expect(summary.outcome, SyncRunOutcome.completed);
      expect(summary.accepted, 0);
      expect(api.calls, isEmpty);
      expect(engine.state.isSyncing, isFalse);
    });

    test('sends events oldest first and removes the accepted ones', () async {
      await queue(3, matchId: 'm1');
      final SyncRunSummary summary = await engine.syncNow();
      expect(api.calls, <List<String>>[
        <String>['e1', 'e2', 'e3'],
      ]);
      expect(summary.outcome, SyncRunOutcome.completed);
      expect(summary.accepted, 3);
      expect(summary.rejected, 0);
      expect(await store.allOutboxEvents(), isEmpty);
      expect(engine.state.pending, 0);
      expect(engine.state.failed, 0);
      expect(engine.state.lastSyncedAt, clock.now());
      expect(engine.state.isUpToDate, isTrue);
    });

    test('a DUPLICATE answer also removes the event', () async {
      await queue(1);
      api.handler = (List<OutboxEvent> events) async => answer(events, <String, SyncEventResult>{
            'e1': const SyncEventResult(eventId: 'e1', status: SyncResultStatus.duplicate),
          });
      final SyncRunSummary summary = await engine.syncNow();
      expect(summary.accepted, 1);
      expect(await store.allOutboxEvents(), isEmpty);
    });

    test('sends at most batchSize events per request', () async {
      await engine.dispose();
      engine = makeEngine(batchSize: 2);
      await queue(5);
      final SyncRunSummary summary = await engine.syncNow();
      expect(api.calls, <List<String>>[
        <String>['e1', 'e2'],
        <String>['e3', 'e4'],
        <String>['e5'],
      ]);
      expect(summary.accepted, 5);
    });

    test('calls made during a run share that run', () async {
      await queue(1);
      final Completer<void> release = Completer<void>();
      api.handler = (List<OutboxEvent> events) async {
        await release.future;
        return SyncPushResponse(results: FakeSyncApi.allApplied(events));
      };
      final Future<SyncRunSummary> first = engine.syncNow();
      final Future<SyncRunSummary> second = engine.syncNow();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      release.complete();
      final List<SyncRunSummary> results = await Future.wait(<Future<SyncRunSummary>>[first, second]);
      expect(api.calls, hasLength(1));
      expect(results[0].accepted, 1);
      expect(identical(results[0], results[1]), isTrue);
    });

    test('the state stream reports syncing and then the result', () async {
      await queue(1);
      final List<SyncState> seen = <SyncState>[];
      final StreamSubscription<SyncState> subscription = engine.states.listen(seen.add);
      await engine.syncNow();
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();
      expect(seen.any((SyncState s) => s.isSyncing), isTrue);
      expect(seen.last.isSyncing, isFalse);
      expect(seen.last.pending, 0);
    });
  });

  group('rejected events', () {
    test('become FAILED with the server\'s code and hold back later events of the same match',
        () async {
      await queue(3, matchId: 'm1');
      await queue(1, matchId: 'm2', from: 4);
      api.handler = (List<OutboxEvent> events) async => answer(events, <String, SyncEventResult>{
            'e1': refusal('e1', SyncErrorCodes.invalidDelivery, 'wide with bat runs'),
          });
      final SyncRunSummary summary = await engine.syncNow();
      expect(summary.rejected, 1);
      expect(summary.accepted, 3);

      final List<OutboxEvent> left = await store.allOutboxEvents();
      expect(left.map((OutboxEvent e) => e.eventId), <String>['e1']);
      expect(left.single.status, OutboxStatus.failed);
      expect(left.single.errorCode, SyncErrorCodes.invalidDelivery);
      expect(left.single.errorMessage, 'wide with bat runs');
      expect(engine.state.failed, 1);
      expect(engine.state.pending, 0);
    });

    test('events queued behind a failed one are not sent in the next run', () async {
      await queue(2, matchId: 'm1');
      api.handler = (List<OutboxEvent> events) async => answer(events, <String, SyncEventResult>{
            'e1': refusal('e1', SyncErrorCodes.invalidState),
          });
      await engine.syncNow();
      // e2 was sent in the same batch (the server applied it); queue two new events.
      await queue(2, matchId: 'm1', from: 3);
      api.calls.clear();
      final SyncRunSummary summary = await engine.syncNow();
      expect(api.calls, isEmpty);
      expect(summary.accepted, 0);
      expect(engine.state.pending, 2);
      expect(engine.state.failed, 1);
    });

    test('"retry later" errors are tried again automatically on the next run', () async {
      await queue(1);
      int round = 0;
      api.handler = (List<OutboxEvent> events) async {
        round += 1;
        if (round == 1) {
          return answer(events, <String, SyncEventResult>{
            'e1': refusal('e1', SyncErrorCodes.internalError),
          });
        }
        return SyncPushResponse(results: FakeSyncApi.allApplied(events));
      };
      final SyncRunSummary first = await engine.syncNow();
      expect(first.rejected, 1);
      expect(engine.state.failed, 1);

      final SyncRunSummary second = await engine.syncNow();
      expect(second.accepted, 1);
      expect(await store.allOutboxEvents(), isEmpty);
    });

    test('permanent errors are not retried automatically', () async {
      await queue(1);
      api.handler = (List<OutboxEvent> events) async => answer(events, <String, SyncEventResult>{
            'e1': refusal('e1', SyncErrorCodes.forbidden),
          });
      await engine.syncNow();
      api.calls.clear();
      await engine.syncNow();
      expect(api.calls, isEmpty);
      expect(engine.state.failed, 1);
    });

    test('"try again" re-queues the event and sends it', () async {
      await queue(1);
      bool refuse = true;
      api.handler = (List<OutboxEvent> events) async {
        if (refuse) {
          return answer(events, <String, SyncEventResult>{
            'e1': refusal('e1', SyncErrorCodes.invalidState),
          });
        }
        return SyncPushResponse(results: FakeSyncApi.allApplied(events));
      };
      await engine.syncNow();
      expect(engine.state.failed, 1);

      refuse = false;
      await engine.retryEvent('e1');
      await engine.syncNow();
      expect(await store.allOutboxEvents(), isEmpty);
      expect(engine.state.failed, 0);
    });

    test('"try all again" re-queues every failed event', () async {
      await queue(2);
      bool refuse = true;
      api.handler = (List<OutboxEvent> events) async {
        if (refuse) {
          return answer(events, <String, SyncEventResult>{
            'e1': refusal('e1', SyncErrorCodes.invalidState),
            'e2': refusal('e2', SyncErrorCodes.invalidReference),
          });
        }
        return SyncPushResponse(results: FakeSyncApi.allApplied(events));
      };
      await engine.syncNow();
      expect(engine.state.failed, 2);

      refuse = false;
      await engine.retryAllFailed();
      await engine.syncNow();
      expect(await store.allOutboxEvents(), isEmpty);
    });

    test('"keep on this phone only" drops the event', () async {
      await queue(1);
      api.handler = (List<OutboxEvent> events) async => answer(events, <String, SyncEventResult>{
            'e1': refusal('e1', SyncErrorCodes.invalidState),
          });
      await engine.syncNow();
      await engine.discardEvent('e1');
      expect(await store.allOutboxEvents(), isEmpty);
      expect(engine.state.failed, 0);
    });
  });

  group('when the server cannot be reached', () {
    test('a network error keeps every event and starts a backoff', () async {
      await queue(2);
      api.handler = (List<OutboxEvent> events) async => throw const NetworkException();
      final SyncRunSummary summary = await engine.syncNow();
      expect(summary.outcome, SyncRunOutcome.failedNetwork);
      expect(await store.pendingOutboxCount(), 2);
      expect(engine.state.lastError, isNotNull);
      expect(engine.state.isSyncing, isFalse);

      api.calls.clear();
      final SyncRunSummary skipped = await engine.syncNow();
      expect(skipped.outcome, SyncRunOutcome.skippedBackoff);
      expect(api.calls, isEmpty);
    });

    test('"sync now" ignores the backoff', () async {
      await queue(1);
      api.handler = (List<OutboxEvent> events) async => throw const NetworkException();
      await engine.syncNow();
      api.handler = null;
      final SyncRunSummary summary = await engine.syncNow(force: true);
      expect(summary.outcome, SyncRunOutcome.completed);
      expect(summary.accepted, 1);
      expect(engine.state.lastError, isNull);
    });

    test('the run is attempted again once the backoff has passed', () async {
      await queue(1);
      api.handler = (List<OutboxEvent> events) async => throw const NetworkException();
      await engine.syncNow();
      api.handler = null;
      clock.advance(const Duration(seconds: 3));
      final SyncRunSummary summary = await engine.syncNow();
      expect(summary.outcome, SyncRunOutcome.completed);
      expect(summary.accepted, 1);
    });

    test('the backoff grows with every failure in a row', () async {
      await queue(1);
      api.handler = (List<OutboxEvent> events) async => throw const NetworkException();
      for (int i = 0; i < 4; i++) {
        await engine.syncNow(force: true);
      }
      // Four failures: the wait is about 8 s (6.4-9.6 s), so 5 s later it is still too early.
      clock.advance(const Duration(seconds: 5));
      expect((await engine.syncNow()).outcome, SyncRunOutcome.skippedBackoff);
      clock.advance(const Duration(seconds: 6));
      expect((await engine.syncNow()).outcome, SyncRunOutcome.failedNetwork);
    });

    test('a server error (5xx) keeps the events and backs off', () async {
      await queue(1);
      api.handler = (List<OutboxEvent> events) async =>
          throw const ApiException(code: 'INTERNAL_ERROR', message: 'oops', statusCode: 500);
      final SyncRunSummary summary = await engine.syncNow();
      expect(summary.outcome, SyncRunOutcome.failedServer);
      expect(await store.pendingOutboxCount(), 1);
      expect(await store.failedOutboxCount(), 0);
    });

    test('Retry-After on a 429 is respected when it is longer than the backoff', () async {
      await queue(1);
      api.handler = (List<OutboxEvent> events) async => throw const ApiException(
            code: 'RATE_LIMITED',
            message: 'slow down',
            statusCode: 429,
            retryAfter: Duration(seconds: 120),
          );
      await engine.syncNow();
      clock.advance(const Duration(seconds: 60));
      expect((await engine.syncNow()).outcome, SyncRunOutcome.skippedBackoff);
      api.handler = null;
      clock.advance(const Duration(seconds: 61));
      expect((await engine.syncNow()).outcome, SyncRunOutcome.completed);
    });

    test('an offline phone skips the run, "sync now" tries anyway', () async {
      await queue(1);
      connectivity.online = false;
      final SyncRunSummary skipped = await engine.syncNow();
      expect(skipped.outcome, SyncRunOutcome.skippedOffline);
      expect(engine.state.isOffline, isTrue);
      expect(api.calls, isEmpty);

      final SyncRunSummary forced = await engine.syncNow(force: true);
      expect(forced.outcome, SyncRunOutcome.completed);
      expect(forced.accepted, 1);
    });

    test('an incomplete answer keeps the unanswered events', () async {
      await queue(2);
      api.handler = (List<OutboxEvent> events) async => SyncPushResponse(
            results: <SyncEventResult>[
              SyncEventResult(eventId: events.first.eventId, status: SyncResultStatus.applied),
            ],
          );
      final SyncRunSummary summary = await engine.syncNow();
      expect(summary.outcome, SyncRunOutcome.failedServer);
      expect(summary.accepted, 1);
      final List<OutboxEvent> left = await store.allOutboxEvents();
      expect(left.map((OutboxEvent e) => e.eventId), <String>['e2']);
      expect(left.single.status, OutboxStatus.pending);
    });
  });

  group('a request the server refuses as a whole', () {
    test('is split up so that one bad event cannot block the others', () async {
      await queue(3);
      api.handler = (List<OutboxEvent> events) async {
        if (events.length > 1 || events.single.eventId == 'e2') {
          throw const ApiException(
            code: 'VALIDATION_ERROR',
            message: 'bad payload',
            statusCode: 422,
          );
        }
        return SyncPushResponse(results: FakeSyncApi.allApplied(events));
      };
      final SyncRunSummary summary = await engine.syncNow();
      expect(api.calls, <List<String>>[
        <String>['e1', 'e2', 'e3'],
        <String>['e1'],
        <String>['e2'],
        <String>['e3'],
      ]);
      expect(summary.accepted, 2);
      expect(summary.rejected, 1);
      final List<OutboxEvent> left = await store.allOutboxEvents();
      expect(left.map((OutboxEvent e) => e.eventId), <String>['e2']);
      expect(left.single.status, OutboxStatus.failed);
      expect(left.single.errorCode, 'VALIDATION_ERROR');
    });

    test('a disabled account stops the run without touching the events', () async {
      await queue(2);
      api.handler = (List<OutboxEvent> events) async => throw const ApiException(
            code: 'ACCOUNT_DISABLED',
            message: 'disabled',
            statusCode: 403,
          );
      final SyncRunSummary summary = await engine.syncNow();
      expect(summary.outcome, SyncRunOutcome.failedServer);
      expect(await store.pendingOutboxCount(), 2);
      expect(await store.failedOutboxCount(), 0);
    });
  });

  group('the session', () {
    test('an ended session stops syncing and asks for a new sign-in', () async {
      await queue(2);
      api.handler = (List<OutboxEvent> events) async => throw const SessionExpiredException();
      final SyncRunSummary summary = await engine.syncNow();
      expect(summary.outcome, SyncRunOutcome.needsSignIn);
      expect(engine.state.needsSignIn, isTrue);
      expect(await store.pendingOutboxCount(), 2);
    });

    test('automatic runs stay quiet until the user signs in, then a forced run resumes', () async {
      await queue(2);
      api.handler = (List<OutboxEvent> events) async => throw const SessionExpiredException();
      await engine.syncNow();
      expect(api.calls, hasLength(1));

      api.handler = null;
      final SyncRunSummary quiet = await engine.syncNow();
      expect(quiet.outcome, SyncRunOutcome.needsSignIn);
      expect(api.calls, hasLength(1), reason: 'no request while the session is ended');

      final SyncRunSummary resumed = await engine.syncNow(force: true);
      expect(resumed.outcome, SyncRunOutcome.completed);
      expect(resumed.accepted, 2);
      expect(engine.state.needsSignIn, isFalse);
      expect(await store.pendingOutboxCount(), 0);
    });
  });

  group('automatic triggers', () {
    test('a change to the local data starts a run by itself', () async {
      await engine.start();
      await store.transaction((LocalWriter w) async {
        await w.enqueue(
          OutboxEvent(
            eventId: 'auto-1',
            entityType: SyncEntityType.team,
            action: SyncAction.upsert,
            payload: const <String, Object?>{'id': 't'},
            clientCreatedAt: DateTime.utc(2026, 10, 8),
          ),
        );
      });
      final DateTime deadline = DateTime.now().add(const Duration(seconds: 3));
      while (api.calls.isEmpty && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(api.calls, <List<String>>[
        <String>['auto-1'],
      ]);
    });

    test('coming back online ends a backoff and sends right away', () async {
      // The server is unreachable from the very start, so the first automatic run cannot win.
      api.handler = (List<OutboxEvent> events) async => throw const NetworkException();
      await engine.start();
      await queue(1);
      await engine.syncNow(force: true);
      expect(await store.pendingOutboxCount(), 1);

      api.handler = null;
      connectivity.goOnline();
      final DateTime deadline = DateTime.now().add(const Duration(seconds: 3));
      while (await store.pendingOutboxCount() > 0 && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(await store.pendingOutboxCount(), 0);
    });
  });
}
