import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Tells the sync engine when the phone is probably online.
///
/// "Online" only means a network is connected; whether the server can be reached is found out by
/// trying, so a wrong answer here costs at most one failed attempt.
abstract interface class ConnectivityMonitor {
  Future<bool> isOnline();

  /// Emits whenever the connection changes.
  Stream<bool> get onlineChanges;
}

final class PlusConnectivityMonitor implements ConnectivityMonitor {
  PlusConnectivityMonitor({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  static bool _anyConnection(List<ConnectivityResult> results) =>
      results.any((ConnectivityResult result) => result != ConnectivityResult.none);

  @override
  Future<bool> isOnline() async {
    try {
      return _anyConnection(await _connectivity.checkConnectivity());
    } on Object {
      // If the platform cannot tell, try anyway.
      return true;
    }
  }

  @override
  Stream<bool> get onlineChanges =>
      _connectivity.onConnectivityChanged.map<bool>(_anyConnection);
}

/// A monitor that is always online (tests, and the fallback when none is configured).
final class AlwaysOnlineMonitor implements ConnectivityMonitor {
  const AlwaysOnlineMonitor();

  @override
  Future<bool> isOnline() async => true;

  @override
  Stream<bool> get onlineChanges => const Stream<bool>.empty();
}
