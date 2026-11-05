import 'dart:async';
import 'dart:typed_data';

import 'package:gully_umpire/core/errors/app_exception.dart';
import 'package:gully_umpire/core/utils/app_log.dart';
import 'package:gully_umpire/cv/live/replay_codec.dart';
import 'package:gully_umpire/data/remote/replay_api.dart';
import 'package:gully_umpire/data/replays/replay_record.dart';
import 'package:gully_umpire/data/replays/replay_store.dart';
import 'package:gully_umpire/data/sync/connectivity_monitor.dart';

/// Sends the replays of scored balls to the server's private storage, in the background.
///
/// A replay is only uploaded once its ball has been scored (the replay is then attached to the
/// delivery), oldest first, a few at a time. A lost connection never loses anything: the file stays
/// on the phone and is tried again when the network is back and every minute while the app is open.
/// A file that the server refuses is tried a limited number of times, then left on the phone.
final class ReplayUploader {
  ReplayUploader({
    required ReplayStore store,
    required ReplayApi api,
    required ConnectivityMonitor connectivity,
    this.pollInterval = const Duration(minutes: 1),
    this.batchSize = 3,
    this.kickDelay = const Duration(seconds: 2),
  })  : _store = store,
        _api = api,
        _connectivity = connectivity;

  final ReplayStore _store;
  final ReplayApi _api;
  final ConnectivityMonitor _connectivity;

  /// How often waiting replays are tried while the app is open.
  final Duration pollInterval;

  /// How many replays one run sends.
  final int batchSize;

  /// How long [kick] waits, so that a ball scored right now is not uploaded half-way through
  /// being saved.
  final Duration kickDelay;

  Future<int>? _running;
  StreamSubscription<bool>? _connectivitySub;
  Timer? _poll;
  Timer? _kick;
  bool _started = false;
  bool _disposed = false;

  /// Starts the automatic triggers and does a first run.
  Future<void> start() async {
    if (_started || _disposed) {
      return;
    }
    _started = true;
    await _store.recoverInterrupted();
    _connectivitySub = _connectivity.onlineChanges.listen((bool online) {
      if (online) {
        kick();
      }
    });
    _poll = Timer.periodic(pollInterval, (_) => unawaited(uploadPending()));
    unawaited(uploadPending());
  }

  /// Asks for a run soon (after a ball with a replay was scored).
  void kick() {
    if (_disposed) {
      return;
    }
    _kick?.cancel();
    _kick = Timer(kickDelay, () => unawaited(uploadPending()));
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _kick?.cancel();
    _poll?.cancel();
    await _connectivitySub?.cancel();
    final Future<int>? running = _running;
    if (running != null) {
      try {
        await running;
      } on Object {
        // The run reports its own problems.
      }
    }
  }

  /// Uploads what is waiting and returns how many replays are now on the server. Calls made while
  /// a run is in progress share that run.
  Future<int> uploadPending() {
    final Future<int>? running = _running;
    if (running != null) {
      return running;
    }
    final Future<int> started = _run().whenComplete(() {
      _running = null;
    });
    _running = started;
    return started;
  }

  Future<int> _run() async {
    if (_disposed || !await _connectivity.isOnline()) {
      return 0;
    }
    int uploaded = 0;
    final List<ReplayRecord> waiting = await _store.pendingUploads(limit: batchSize);
    for (final ReplayRecord record in waiting) {
      if (_disposed) {
        break;
      }
      final _Step step = await _send(record);
      if (step == _Step.sent) {
        uploaded += 1;
      } else if (step == _Step.stop) {
        break;
      }
    }
    return uploaded;
  }

  Future<_Step> _send(ReplayRecord record) async {
    final Uint8List? bytes = await _store.read(record.id);
    if (bytes == null) {
      // The file is gone, so there is nothing to send: forget the record.
      await _store.delete(record.id);
      return _Step.skipped;
    }
    final ReplayReader reader;
    try {
      reader = ReplayReader.parse(bytes);
    } on ReplayFormatException catch (error) {
      await _store.markFailed(record.id, 'Damaged file: ${error.message}');
      return _Step.skipped;
    }
    await _store.markUploading(record.id);
    try {
      final ReplayAnnouncement announcement = await _api.announce(
        id: record.id,
        matchId: record.matchId,
        deliveryId: record.deliveryId,
        sizeBytes: bytes.length,
        width: reader.width,
        height: reader.height,
        frameCount: reader.frameCount,
        durationMs: reader.durationMs,
      );
      final ReplayUploadTarget? target = announcement.upload;
      if (!announcement.alreadyStored && target != null) {
        await _api.upload(target, bytes);
      }
      await _api.complete(record.id);
      await _store.markUploaded(record.id, record.id);
      return _Step.sent;
    } on SessionExpiredException {
      // Signing in again is handled elsewhere; nothing is wrong with the file.
      await _store.markFailed(record.id, 'Sign in again to upload.', countAttempt: false);
      return _Step.stop;
    } on NetworkException catch (error) {
      await _store.markFailed(record.id, error.message, countAttempt: false);
      return _Step.stop;
    } on ApiException catch (error) {
      AppLog.warn('A replay was not accepted (${error.code}).');
      final bool serverSide = error.isServerError || error.isRateLimited;
      // 503 means the server has no storage set up: every replay would fail the same way.
      await _store.markFailed(record.id, error.message, countAttempt: !serverSide);
      return serverSide ? _Step.stop : _Step.failed;
    } on Object catch (error) {
      AppLog.warn('A replay could not be uploaded: ${error.runtimeType}');
      await _store.markFailed(record.id, 'Upload failed.');
      return _Step.failed;
    }
  }
}

enum _Step { sent, failed, skipped, stop }
