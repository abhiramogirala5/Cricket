import 'dart:async';

import 'package:gully_umpire/data/remote/sync_api.dart';
import 'package:gully_umpire/data/sync/connectivity_monitor.dart';
import 'package:gully_umpire/domain/sync/sync.dart';

/// A [SyncApi] whose answers the test controls.
final class FakeSyncApi implements SyncApi {
  /// Every batch that was sent, in order.
  final List<List<String>> calls = <List<String>>[];

  /// Decides the answer for a batch. When `null` every event is `APPLIED`.
  Future<SyncPushResponse> Function(List<OutboxEvent> events)? handler;

  @override
  Future<SyncPushResponse> push(List<OutboxEvent> events) async {
    calls.add(events.map<String>((OutboxEvent e) => e.eventId).toList());
    final Future<SyncPushResponse> Function(List<OutboxEvent> events)? current = handler;
    if (current != null) {
      return current(events);
    }
    return SyncPushResponse(results: allApplied(events));
  }

  static List<SyncEventResult> allApplied(List<OutboxEvent> events) => events
      .map<SyncEventResult>(
        (OutboxEvent e) => SyncEventResult(eventId: e.eventId, status: SyncResultStatus.applied),
      )
      .toList();
}

/// A connectivity monitor the test can switch on and off.
final class FakeConnectivity implements ConnectivityMonitor {
  bool online = true;
  final StreamController<bool> _changes = StreamController<bool>.broadcast();

  @override
  Future<bool> isOnline() async => online;

  @override
  Stream<bool> get onlineChanges => _changes.stream;

  void goOnline() {
    online = true;
    _changes.add(true);
  }

  void goOffline() {
    online = false;
    _changes.add(false);
  }
}
