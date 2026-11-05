import 'package:equatable/equatable.dart';

/// What the sync engine reports to the UI.
final class SyncState extends Equatable {
  const SyncState({
    this.pending = 0,
    this.failed = 0,
    this.isSyncing = false,
    this.isOffline = false,
    this.needsSignIn = false,
    this.lastSyncedAt,
    this.lastError,
  });

  static const SyncState initial = SyncState();

  /// Changes waiting to be sent.
  final int pending;

  /// Changes the server refused; the user has to decide what to do with them.
  final int failed;
  final bool isSyncing;

  /// The phone reported no connection at the last attempt.
  final bool isOffline;

  /// The session ended; the user has to sign in again before anything can be sent.
  final bool needsSignIn;
  final DateTime? lastSyncedAt;

  /// A friendly sentence about the last problem, if any.
  final String? lastError;

  bool get hasPending => pending > 0;
  bool get hasFailed => failed > 0;

  /// Everything on this phone has reached the server.
  bool get isUpToDate => pending == 0 && failed == 0 && lastError == null && !needsSignIn;

  SyncState copyWith({
    int? pending,
    int? failed,
    bool? isSyncing,
    bool? isOffline,
    bool? needsSignIn,
    DateTime? lastSyncedAt,
    String? lastError,
    bool clearError = false,
  }) =>
      SyncState(
        pending: pending ?? this.pending,
        failed: failed ?? this.failed,
        isSyncing: isSyncing ?? this.isSyncing,
        isOffline: isOffline ?? this.isOffline,
        needsSignIn: needsSignIn ?? this.needsSignIn,
        lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
        lastError: clearError ? null : (lastError ?? this.lastError),
      );

  @override
  List<Object?> get props =>
      <Object?>[pending, failed, isSyncing, isOffline, needsSignIn, lastSyncedAt, lastError];
}
