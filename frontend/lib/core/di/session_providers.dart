import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gully_umpire/core/di/core_providers.dart';
import 'package:gully_umpire/data/session/active_session.dart';
import 'package:gully_umpire/data/session/session_manager.dart';
import 'package:gully_umpire/data/sync/restore_service.dart';
import 'package:gully_umpire/domain/models/user_profile.dart';

final Provider<SessionManager> sessionManagerProvider = Provider<SessionManager>((ref) {
  final SessionManager manager = SessionManager(
    keeper: ref.watch(sessionKeeperProvider),
    openStore: ref.watch(storeOpenerProvider),
    removeStore: ref.watch(storeRemoverProvider),
    clock: ref.watch(clockProvider),
    ids: ref.watch(idGeneratorProvider),
    client: ref.watch(apiClientProvider),
    connectivity: ref.watch(connectivityMonitorProvider),
    replayDirectory: ref.watch(replayDirectoryResolverProvider),
  );
  ref.onDispose(manager.dispose);
  return manager;
});

/// Who is signed in, and the data that belongs to them. Loading while the app starts.
final AsyncNotifierProvider<SessionController, SessionView> sessionControllerProvider =
    AsyncNotifierProvider<SessionController, SessionView>(SessionController.new);

/// Starts the session at launch and forwards the sign-in actions of the screens.
class SessionController extends AsyncNotifier<SessionView> {
  late SessionManager _manager;

  @override
  Future<SessionView> build() async {
    _manager = ref.watch(sessionManagerProvider);
    final subscription = _manager.changes.listen((SessionView view) {
      state = AsyncData<SessionView>(view);
    });
    ref.onDispose(subscription.cancel);
    return _manager.start();
  }

  Future<void> login({required String email, required String password}) async {
    await _manager.login(email: email, password: password);
  }

  Future<void> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    await _manager.register(email: email, password: password, displayName: displayName);
  }

  Future<void> signOut() => _manager.signOut();

  Future<void> deleteAccount({required String password}) =>
      _manager.deleteAccount(password: password);

  Future<UserProfile> updateProfile({
    String? displayName,
    String? phone,
    bool clearPhone = false,
  }) =>
      _manager.updateProfile(displayName: displayName, phone: phone, clearPhone: clearPhone);

  Future<RestoreReport> restoreFromServer() => _manager.restoreNow();

  /// Tries the start-up again after it failed.
  void retryStart() => ref.invalidateSelf();
}

/// The open account, or `null` when nobody is signed in (or the app is still starting).
final Provider<ActiveSession?> activeSessionProvider = Provider<ActiveSession?>((ref) {
  return ref.watch(
    sessionControllerProvider.select((AsyncValue<SessionView> value) => value.valueOrNull?.active),
  );
});

/// The signed-in profile. `null` when signed out and in local-only mode.
final Provider<UserProfile?> currentUserProvider = Provider<UserProfile?>((ref) {
  return ref.watch(
    sessionControllerProvider.select((AsyncValue<SessionView> value) => value.valueOrNull?.user),
  );
});

/// True when no backend is configured (everything stays on this phone).
final Provider<bool> isLocalModeProvider = Provider<bool>((ref) {
  return ref.watch(appConfigProvider).isLocalMode;
});
