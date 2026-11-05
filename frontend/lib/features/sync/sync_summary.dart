import 'package:equatable/equatable.dart';
import 'package:gully_umpire/core/utils/formatters.dart';
import 'package:gully_umpire/data/sync/sync_state.dart';

/// How worried the person should be about the sync state.
enum SyncSeverity {
  /// Nothing to do (all sent, or there is no account to send to).
  calm,

  /// Busy or waiting; no action needed.
  working,

  /// The person can fix this (sign in again).
  attention,

  /// The server refused something; it needs a decision.
  problem,
}

/// A sentence or two about the sync state, ready for a tile or a banner.
final class SyncSummary extends Equatable {
  const SyncSummary({required this.severity, required this.title, required this.detail});

  final SyncSeverity severity;
  final String title;
  final String detail;

  @override
  List<Object?> get props => <Object?>[severity, title, detail];
}

/// Turns the sync engine's state into plain language. The order matters: the most important
/// thing to tell the person comes first.
SyncSummary describeSync(SyncState state, {required bool isLocalMode}) {
  if (isLocalMode) {
    return const SyncSummary(
      severity: SyncSeverity.calm,
      title: 'Saved on this phone',
      detail: 'No account is set up, so your matches are kept on this phone only.',
    );
  }
  if (state.needsSignIn) {
    return const SyncSummary(
      severity: SyncSeverity.attention,
      title: 'Sign in to keep syncing',
      detail: 'Your session ended. Your matches are safe on this phone.',
    );
  }
  if (state.hasFailed) {
    return SyncSummary(
      severity: SyncSeverity.problem,
      title: '${pluralize(state.failed, 'change')} not accepted',
      detail: 'The server refused ${state.failed == 1 ? 'it' : 'them'}. Open to decide what to do.',
    );
  }
  if (state.isSyncing) {
    return const SyncSummary(
      severity: SyncSeverity.working,
      title: 'Syncing…',
      detail: 'Sending your latest changes.',
    );
  }
  if (state.hasPending) {
    return SyncSummary(
      severity: SyncSeverity.working,
      title: '${pluralize(state.pending, 'change')} waiting to sync',
      detail: state.isOffline
          ? 'You are offline. They will be sent when the connection is back.'
          : 'They will be sent in a moment.',
    );
  }
  final String? error = state.lastError;
  if (error != null) {
    return SyncSummary(
      severity: SyncSeverity.attention,
      title: 'The last sync did not finish',
      detail: error,
    );
  }
  final DateTime? last = state.lastSyncedAt;
  return SyncSummary(
    severity: SyncSeverity.calm,
    title: 'Everything is saved to your account',
    detail: last == null ? 'Nothing is waiting to be sent.' : 'Last synced ${formatDateAndTime(last)}.',
  );
}
