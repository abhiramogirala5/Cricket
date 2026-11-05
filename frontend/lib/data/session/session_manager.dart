import 'dart:async';
import 'dart:io' show Directory;

import 'package:equatable/equatable.dart';
import 'package:gully_umpire/core/errors/app_exception.dart';
import 'package:gully_umpire/core/utils/app_log.dart';
import 'package:gully_umpire/core/utils/clock.dart';
import 'package:gully_umpire/core/utils/id_generator.dart';
import 'package:gully_umpire/data/local/local_store.dart';
import 'package:gully_umpire/data/remote/api_client.dart';
import 'package:gully_umpire/data/remote/auth_api.dart';
import 'package:gully_umpire/data/remote/remote_read_api.dart';
import 'package:gully_umpire/data/remote/replay_api.dart';
import 'package:gully_umpire/data/remote/sync_api.dart';
import 'package:gully_umpire/data/replays/replay_store.dart';
import 'package:gully_umpire/data/replays/replay_uploader.dart';
import 'package:gully_umpire/data/repositories/match_repository.dart';
import 'package:gully_umpire/data/repositories/roster_repository.dart';
import 'package:gully_umpire/data/session/active_session.dart';
import 'package:gully_umpire/data/session/session_keeper.dart';
import 'package:gully_umpire/data/session/session_models.dart';
import 'package:gully_umpire/data/sync/connectivity_monitor.dart';
import 'package:gully_umpire/data/sync/restore_service.dart';
import 'package:gully_umpire/data/sync/sync_engine.dart';
import 'package:gully_umpire/domain/models/user_profile.dart';

/// Opens the database of one account.
typedef StoreOpener = Future<LocalStore> Function(String userId);

/// Deletes the database file of one account.
typedef StoreRemover = Future<void> Function(String userId);

/// The folder in which the replay files of one account are kept.
typedef ReplayDirectoryResolver = Future<Directory> Function(String userId);

/// What the app currently shows: nobody, or a signed-in account (or the local-only user).
final class SessionView extends Equatable {
  const SessionView({this.active, this.user});

  static const SessionView signedOut = SessionView();

  /// `null` while nobody is signed in.
  final ActiveSession? active;

  /// The account's profile. `null` when signed out and in local-only mode.
  final UserProfile? user;

  bool get isSignedIn => active != null;

  @override
  List<Object?> get props => <Object?>[active, user];
}

/// Owns the sign-in state and everything that depends on it.
///
/// * Local-only mode (no backend configured): opens the single local database at start-up.
/// * With a backend: restores the stored session at start-up WITHOUT needing the network, so the
///   app opens straight into the user's matches even in a field with no signal.
/// * Sign-in and sign-up replace the active session; sign-out and account deletion close it.
final class SessionManager {
  SessionManager({
    required SessionKeeper keeper,
    required StoreOpener openStore,
    required StoreRemover removeStore,
    required AppClock clock,
    required IdGenerator ids,
    ApiClient? client,
    ConnectivityMonitor? connectivity,
    ReplayDirectoryResolver? replayDirectory,
    Duration networkGrace = const Duration(seconds: 8),
  })  : _keeper = keeper,
        _openStore = openStore,
        _removeStore = removeStore,
        _replayDirectory = replayDirectory,
        _clock = clock,
        _ids = ids,
        _client = client,
        _account = client == null ? null : AccountApi(client),
        _connectivity = connectivity,
        _networkGrace = networkGrace;

  final SessionKeeper _keeper;
  final StoreOpener _openStore;
  final StoreRemover _removeStore;
  final ReplayDirectoryResolver? _replayDirectory;
  final AppClock _clock;
  final IdGenerator _ids;
  final ApiClient? _client;
  final AccountApi? _account;
  final ConnectivityMonitor? _connectivity;
  final Duration _networkGrace;

  final StreamController<SessionView> _changes = StreamController<SessionView>.broadcast();
  SessionView _view = SessionView.signedOut;
  final Set<Future<void>> _background = <Future<void>>{};
  Future<void> _tail = Future<void>.value();
  bool _disposed = false;

  /// There is no backend: no accounts and no sync.
  bool get isLocalMode => _client == null;

  SessionView get view => _view;

  /// Emits whenever the active session or the profile changes.
  Stream<SessionView> get changes => _changes.stream;

  // ---- Start-up ---------------------------------------------------------------------------

  /// Opens whatever was open when the app was last used. Call once.
  Future<SessionView> start() => _exclusive<SessionView>(() async {
        if (isLocalMode) {
          final ActiveSession active = await _open(ActiveSession.localUserId);
          return _publish(SessionView(active: active));
        }
        final StoredSession? stored = await _keeper.load();
        if (stored == null) {
          return _publish(SessionView.signedOut);
        }
        final ActiveSession active = await _open(stored.user.id);
        _publish(SessionView(active: active, user: stored.user));
        _track(_afterOpen(active, refreshProfile: true));
        return _view;
      });

  // ---- Sign-in and sign-up ----------------------------------------------------------------

  Future<SessionView> register({
    required String email,
    required String password,
    required String displayName,
  }) =>
      _exclusive<SessionView>(() async {
        final AccountApi account = _requireAccount();
        final AuthResult result = await account.register(
          email: email.trim(),
          password: password,
          displayName: displayName.trim(),
        );
        return _begin(result);
      });

  Future<SessionView> login({required String email, required String password}) =>
      _exclusive<SessionView>(() async {
        final AccountApi account = _requireAccount();
        final AuthResult result = await account.login(email: email.trim(), password: password);
        return _begin(result);
      });

  Future<SessionView> _begin(AuthResult result) async {
    final ActiveSession? current = _view.active;
    await _keeper.save(StoredSession(tokens: result.tokens, user: result.user));
    if (current != null && current.userId == result.user.id) {
      // The session had ended and the same account signed in again. Its data is already open
      // and whatever was waiting to be sent can go now.
      _publish(SessionView(active: current, user: result.user));
      _track(_forceSync(current));
      return _view;
    }
    if (current != null) {
      await _close(current);
    }
    final ActiveSession opened;
    try {
      opened = await _open(result.user.id);
    } on Object {
      // Without a database there is nothing to work with; start again from the sign-in screen.
      await _keeper.clear();
      _publish(SessionView.signedOut);
      rethrow;
    }
    _publish(SessionView(active: opened, user: result.user));
    _track(_afterOpen(opened, refreshProfile: false));
    return _view;
  }

  // ---- Sign-out and deletion --------------------------------------------------------------

  /// Signs out. Anything not yet sent stays on the phone and is sent the next time this account
  /// signs in.
  Future<void> signOut() => _exclusive<void>(() async {
        final ActiveSession? active = _view.active;
        if (active == null || active.isLocal) {
          return;
        }
        // One last try to send what is waiting; a failure here must never block signing out.
        await _bestEffort(() => active.syncEngine!.syncNow(force: true));
        final StoredSession? stored = _keeper.current;
        final AccountApi? account = _account;
        if (stored != null && account != null) {
          await _bestEffort(() => account.logout(stored.tokens.refreshToken));
        }
        await _close(active);
        await _keeper.clear();
        _publish(SessionView.signedOut);
      });

  /// Deletes the account on the server, then the data on this phone.
  ///
  /// Throws [ApiException] (`PASSWORD_INCORRECT`) or [NetworkException] without changing anything
  /// when the server does not confirm the deletion.
  Future<void> deleteAccount({required String password}) => _exclusive<void>(() async {
        final AccountApi account = _requireAccount();
        final ActiveSession? active = _view.active;
        if (active == null || active.isLocal) {
          throw StateError('There is no account to delete.');
        }
        await account.deleteMe(password: password);
        await _close(active);
        await _keeper.clear();
        try {
          await _removeStore(active.userId);
        } on Object catch (error, stackTrace) {
          AppLog.error('Could not delete the local database', error: error, stackTrace: stackTrace);
        }
        _publish(SessionView.signedOut);
      });

  // ---- Profile ----------------------------------------------------------------------------

  Future<UserProfile> updateProfile({
    String? displayName,
    String? phone,
    bool clearPhone = false,
  }) async {
    final AccountApi account = _requireAccount();
    final UserProfile user = await account.updateMe(
      displayName: displayName?.trim(),
      phone: phone?.trim(),
      clearPhone: clearPhone,
    );
    await _keeper.updateUser(user);
    if (_view.active != null) {
      _publish(SessionView(active: _view.active, user: user));
    }
    return user;
  }

  /// Copies matches, teams and players from the server that this phone does not have yet.
  Future<RestoreReport> restoreNow() async {
    final ActiveSession? active = _view.active;
    final RestoreService? restore = active?.restoreService;
    if (restore == null) {
      return const RestoreReport();
    }
    return restore.restoreMissing();
  }

  // ---- Internals --------------------------------------------------------------------------

  AccountApi _requireAccount() {
    final AccountApi? account = _account;
    if (account == null) {
      throw StateError('No backend is configured.');
    }
    return account;
  }

  Future<ActiveSession> _open(String userId) async {
    final LocalStore store = await _openStore(userId);
    final ApiClient? client = _client;
    final bool syncs = client != null;
    final ReplayDirectoryResolver? resolveDirectory = _replayDirectory;
    final ReplayStore? replays = resolveDirectory == null
        ? null
        : ReplayStore(
            store: store,
            resolveDirectory: () => resolveDirectory(userId),
            clock: _clock,
          );
    return ActiveSession(
      userId: userId,
      isLocal: !syncs,
      store: store,
      roster: RosterRepository(store: store, clock: _clock, ids: _ids, syncEnabled: syncs),
      matches: MatchRepository(store: store, clock: _clock, ids: _ids, syncEnabled: syncs),
      syncEngine: client == null
          ? null
          : SyncEngine(
              store: store,
              api: HttpSyncApi(client),
              clock: _clock,
              connectivity: _connectivity,
            ),
      restoreService: client == null
          ? null
          : RestoreService(store: store, api: HttpRemoteReadApi(client), clock: _clock),
      replays: replays,
      replayUploader: client == null || replays == null
          ? null
          : ReplayUploader(
              store: replays,
              api: HttpReplayApi(client),
              connectivity: _connectivity ?? const AlwaysOnlineMonitor(),
            ),
    );
  }

  Future<void> _close(ActiveSession active) async {
    try {
      await active.dispose();
    } on Object catch (error, stackTrace) {
      AppLog.error('Closing the session failed', error: error, stackTrace: stackTrace);
    }
  }

  /// Background work after an account was opened. Nothing here may stop the user from working.
  Future<void> _afterOpen(ActiveSession active, {required bool refreshProfile}) async {
    try {
      await active.syncEngine?.start();
      await active.replayUploader?.start();
      final RestoreService? restore = active.restoreService;
      if (restore != null && await active.store.meta(RestoreService.restoredMetaKey) == null) {
        await restore.restoreMissing();
      }
      final AccountApi? account = _account;
      if (refreshProfile && account != null) {
        final UserProfile user = await account.me();
        if (identical(_view.active, active) && !_disposed) {
          await _keeper.updateUser(user);
          _publish(SessionView(active: active, user: user));
        }
      }
    } on SessionExpiredException {
      // The sync engine shows the "sign in again" notice; there is nothing else to do here.
    } on Object catch (error) {
      AppLog.warn('Background start-up work failed: $error');
    }
  }

  /// Remembers background work so that [whenBackgroundSettled] can wait for it.
  void _track(Future<void> work) {
    _background.add(work);
    unawaited(work.whenComplete(() => _background.remove(work)));
  }

  /// Completes when the start-up work that follows opening an account has finished (tests, and
  /// callers that must not race with it).
  Future<void> whenBackgroundSettled() async {
    while (_background.isNotEmpty) {
      await Future.wait<void>(_background.toList(growable: false));
    }
  }

  Future<void> _forceSync(ActiveSession active) async {
    await _bestEffort(() async {
      await active.syncEngine?.syncNow(force: true);
    });
  }

  Future<void> _bestEffort(Future<void> Function() action) async {
    try {
      await action().timeout(_networkGrace);
    } on Object catch (error) {
      AppLog.warn('Best-effort step failed: ${error.runtimeType}');
    }
  }

  SessionView _publish(SessionView next) {
    _view = next;
    if (!_disposed && !_changes.isClosed) {
      _changes.add(next);
    }
    return next;
  }

  /// Runs one account operation at a time, in the order requested.
  Future<T> _exclusive<T>(Future<T> Function() action) {
    final Completer<T> completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await action());
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<void> dispose() async {
    _disposed = true;
    final ActiveSession? active = _view.active;
    if (active != null) {
      await _close(active);
    }
    await _changes.close();
  }
}
