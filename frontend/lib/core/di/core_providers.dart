import 'dart:io' show Directory;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gully_umpire/core/config/app_config.dart';
import 'package:gully_umpire/core/utils/clock.dart';
import 'package:gully_umpire/core/utils/id_generator.dart';
import 'package:gully_umpire/data/local/local_database.dart';
import 'package:gully_umpire/data/local/local_store.dart';
import 'package:gully_umpire/data/remote/api_client.dart';
import 'package:gully_umpire/data/session/session_keeper.dart';
import 'package:gully_umpire/data/session/session_manager.dart';
import 'package:gully_umpire/data/session/session_storage.dart';
import 'package:gully_umpire/data/sync/connectivity_monitor.dart';
import 'package:sqflite/sqflite.dart';

/// The configuration loaded from `.env`. `main()` overrides this with the real value.
final Provider<AppConfig> appConfigProvider = Provider<AppConfig>((ref) {
  throw UnimplementedError('appConfigProvider must be overridden with the loaded AppConfig.');
});

final Provider<AppClock> clockProvider = Provider<AppClock>((ref) => const SystemClock());

final Provider<IdGenerator> idGeneratorProvider =
    Provider<IdGenerator>((ref) => UuidGenerator());

final Provider<ConnectivityMonitor> connectivityMonitorProvider =
    Provider<ConnectivityMonitor>((ref) => PlusConnectivityMonitor());

final Provider<SessionStorage> sessionStorageProvider =
    Provider<SessionStorage>((ref) => SecureSessionStorage());

final Provider<SessionKeeper> sessionKeeperProvider = Provider<SessionKeeper>((ref) {
  final SessionKeeper keeper = SessionKeeper(ref.watch(sessionStorageProvider));
  ref.onDispose(keeper.dispose);
  return keeper;
});

/// The HTTP client, or `null` in local-only mode (no backend configured).
final Provider<ApiClient?> apiClientProvider = Provider<ApiClient?>((ref) {
  final AppConfig config = ref.watch(appConfigProvider);
  if (config.isLocalMode) {
    return null;
  }
  final ApiClient client = ApiClient(
    baseUrl: config.apiUrl,
    session: ref.watch(sessionKeeperProvider),
    ids: ref.watch(idGeneratorProvider),
    timeout: config.httpTimeout,
  );
  ref.onDispose(client.close);
  return client;
});

/// Opens the on-device database of an account.
final Provider<StoreOpener> storeOpenerProvider = Provider<StoreOpener>((ref) {
  return (String userId) async {
    final String path = await LocalDatabase.pathFor(databaseFactory, userId);
    final database = await LocalDatabase.open(factory: databaseFactory, path: path);
    return LocalStore(database);
  };
});

/// Deletes the on-device database of an account.
final Provider<StoreRemover> storeRemoverProvider = Provider<StoreRemover>((ref) {
  return (String userId) => LocalDatabase.deleteFor(databaseFactory, userId);
});

/// Where the replay files of an account are kept (next to its database).
final Provider<ReplayDirectoryResolver> replayDirectoryResolverProvider =
    Provider<ReplayDirectoryResolver>((ref) {
  return (String userId) async =>
      Directory(await LocalDatabase.replayDirectoryPathFor(databaseFactory, userId));
});
