import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/data/sync/sync_state.dart';
import 'package:gully_umpire/features/sync/sync_summary.dart';

void main() {
  group('describeSync', () {
    test('local mode is calm whatever the engine says', () {
      final SyncSummary summary = describeSync(
        const SyncState(pending: 4, failed: 1, needsSignIn: true),
        isLocalMode: true,
      );
      expect(summary.severity, SyncSeverity.calm);
      expect(summary.title, 'Saved on this phone');
    });

    test('an ended session asks for a sign-in before anything else', () {
      final SyncSummary summary = describeSync(
        const SyncState(pending: 2, failed: 1, isSyncing: true, needsSignIn: true),
        isLocalMode: false,
      );
      expect(summary.severity, SyncSeverity.attention);
      expect(summary.title, 'Sign in to keep syncing');
      expect(summary.detail, contains('safe on this phone'));
    });

    test('one refused change is a problem, in the singular', () {
      final SyncSummary summary = describeSync(
        const SyncState(failed: 1, pending: 3, isSyncing: true),
        isLocalMode: false,
      );
      expect(summary.severity, SyncSeverity.problem);
      expect(summary.title, '1 change not accepted');
      expect(summary.detail, 'The server refused it. Open to decide what to do.');
    });

    test('several refused changes are a problem, in the plural', () {
      final SyncSummary summary = describeSync(const SyncState(failed: 3), isLocalMode: false);
      expect(summary.severity, SyncSeverity.problem);
      expect(summary.title, '3 changes not accepted');
      expect(summary.detail, 'The server refused them. Open to decide what to do.');
    });

    test('a running sync is reported before the waiting count', () {
      final SyncSummary summary = describeSync(
        const SyncState(pending: 5, isSyncing: true),
        isLocalMode: false,
      );
      expect(summary.severity, SyncSeverity.working);
      expect(summary.title, 'Syncing…');
    });

    test('waiting changes online will be sent in a moment', () {
      final SyncSummary summary = describeSync(const SyncState(pending: 3), isLocalMode: false);
      expect(summary.severity, SyncSeverity.working);
      expect(summary.title, '3 changes waiting to sync');
      expect(summary.detail, 'They will be sent in a moment.');
    });

    test('waiting changes offline say that the phone is offline', () {
      final SyncSummary summary = describeSync(
        const SyncState(pending: 1, isOffline: true),
        isLocalMode: false,
      );
      expect(summary.title, '1 change waiting to sync');
      expect(summary.detail, 'You are offline. They will be sent when the connection is back.');
    });

    test('an unfinished last sync shows its own message', () {
      final SyncSummary summary = describeSync(
        const SyncState(lastError: 'The server did not answer.'),
        isLocalMode: false,
      );
      expect(summary.severity, SyncSeverity.attention);
      expect(summary.title, 'The last sync did not finish');
      expect(summary.detail, 'The server did not answer.');
    });

    test('nothing waiting and nothing synced yet is calm', () {
      final SyncSummary summary = describeSync(SyncState.initial, isLocalMode: false);
      expect(summary.severity, SyncSeverity.calm);
      expect(summary.title, 'Everything is saved to your account');
      expect(summary.detail, 'Nothing is waiting to be sent.');
    });

    test('says when the last sync was', () {
      final SyncSummary summary = describeSync(
        SyncState(lastSyncedAt: DateTime(2026, 10, 8, 19, 5)),
        isLocalMode: false,
      );
      expect(summary.severity, SyncSeverity.calm);
      expect(summary.detail, 'Last synced 8 Oct 2026, 7:05 PM.');
    });
  });
}
