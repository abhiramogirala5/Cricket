import 'dart:io';
import 'dart:typed_data';

import 'package:gully_umpire/core/utils/clock.dart';
import 'package:gully_umpire/data/local/local_store.dart';
import 'package:gully_umpire/data/local/local_writer.dart';
import 'package:gully_umpire/data/replays/replay_record.dart';
import 'package:path/path.dart' as p;

/// Keeps the replay files of deliveries on the phone.
///
/// A replay is one file (see `ReplayCodec`): the pictures of the delivery with what the app worked
/// out about it. The file is written to a folder next to the database; a small row in the
/// database says which delivery it belongs to and whether a copy is on the server. Files are not
/// put into the database itself because Android cannot read a database row bigger than about 2 MB.
///
/// The store keeps itself small: a replay of a ball that was never scored is dropped after a few
/// hours, and when the folder grows past its budget the oldest replays go first (those that already
/// have a copy on the server before those that do not).
final class ReplayStore {
  ReplayStore({
    required LocalStore store,
    required Future<Directory> Function() resolveDirectory,
    required AppClock clock,
    this.maxPacks = 80,
    this.maxBytes = 200 * 1024 * 1024,
    this.unattachedTtl = const Duration(hours: 6),
  })  : _store = store,
        _resolveDirectory = resolveDirectory,
        _clock = clock;

  final LocalStore _store;
  final Future<Directory> Function() _resolveDirectory;
  final AppClock _clock;

  /// Most replays kept.
  final int maxPacks;

  /// Most bytes kept.
  final int maxBytes;

  /// How long a replay of a ball that was never scored is kept.
  final Duration unattachedTtl;

  Directory? _directory;

  Future<Directory> _folder() async {
    final Directory? known = _directory;
    if (known != null) {
      return known;
    }
    final Directory directory = await _resolveDirectory();
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
    _directory = directory;
    return directory;
  }

  /// Writes [bytes] as the replay [id] of [matchId]. The file is complete before the row exists,
  /// so a crash never leaves a row that points at half a file.
  Future<ReplayRecord> save({
    required String id,
    required String matchId,
    required Uint8List bytes,
    String? deliveryId,
  }) async {
    final Directory directory = await _folder();
    final String fileName = '$id.gur';
    final File temp = File(p.join(directory.path, '$fileName.tmp'));
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(p.join(directory.path, fileName));
    final ReplayRecord record = ReplayRecord(
      id: id,
      matchId: matchId,
      deliveryId: deliveryId,
      fileName: fileName,
      sizeBytes: bytes.length,
      createdAtMs: _clock.now().millisecondsSinceEpoch,
    );
    await _store.transaction<void>(
      (LocalWriter writer) => writer.putReplayRecord(record),
      notify: false,
    );
    await prune();
    return record;
  }

  /// Says that the replay [id] belongs to the scored ball [deliveryId].
  Future<void> attachDelivery(String id, String deliveryId) async {
    await _store.transaction<void>(
      (LocalWriter writer) async {
        final ReplayRecord? record = await writer.replayRecord(id);
        if (record != null) {
          await writer.putReplayRecord(record.copyWith(deliveryId: deliveryId));
        }
      },
    );
  }

  Future<ReplayRecord?> record(String id) => _store.replayRecord(id);

  Future<ReplayRecord?> forDelivery(String deliveryId) => _store.replayRecordForDelivery(deliveryId);

  /// True when the replay [id] has a record and its file is still there.
  Future<bool> hasFile(String id) async {
    final ReplayRecord? record = await _store.replayRecord(id);
    if (record == null) {
      return false;
    }
    return File(p.join((await _folder()).path, record.fileName)).existsSync();
  }

  /// The bytes of the replay file, or null when the record or the file is gone.
  Future<Uint8List?> read(String id) async {
    final ReplayRecord? record = await _store.replayRecord(id);
    if (record == null) {
      return null;
    }
    final File file = File(p.join((await _folder()).path, record.fileName));
    if (!file.existsSync()) {
      return null;
    }
    return file.readAsBytes();
  }

  /// Replays of scored balls that still have to go to the server.
  Future<List<ReplayRecord>> pendingUploads({int limit = 5}) =>
      _store.replayRecordsToUpload(limit: limit);

  Future<void> markUploading(String id) => _update(
        id,
        (ReplayRecord r) => r.copyWith(uploadState: ReplayUploadState.uploading),
      );

  Future<void> markUploaded(String id, String remoteId) => _update(
        id,
        (ReplayRecord r) => r.copyWith(
          uploadState: ReplayUploadState.uploaded,
          remoteId: remoteId,
          clearError: true,
        ),
      );

  /// Records that an upload did not work. It counts as an attempt only when [countAttempt] is
  /// true (the server refused the file); a lost connection is not the file's fault and never
  /// uses up its attempts.
  Future<void> markFailed(String id, String error, {bool countAttempt = true}) => _update(
        id,
        (ReplayRecord r) => r.copyWith(
          uploadState: ReplayUploadState.failed,
          lastError: error,
          attempts: countAttempt ? r.attempts + 1 : r.attempts,
        ),
      );

  /// Puts replays that were left "uploading" by a crash back in the queue.
  Future<void> recoverInterrupted() async {
    final List<ReplayRecord> all = await _store.replayRecordsOldestFirst();
    for (final ReplayRecord record in all) {
      if (record.uploadState == ReplayUploadState.uploading) {
        await _update(record.id, (ReplayRecord r) => r.copyWith(uploadState: ReplayUploadState.failed));
      }
    }
  }

  Future<void> _update(String id, ReplayRecord Function(ReplayRecord record) change) {
    return _store.transaction<void>(
      (LocalWriter writer) async {
        final ReplayRecord? record = await writer.replayRecord(id);
        if (record != null) {
          await writer.putReplayRecord(change(record));
        }
      },
      notify: false,
    );
  }

  /// Removes the replay [id] (file and row).
  Future<void> delete(String id) async {
    final ReplayRecord? record = await _store.replayRecord(id);
    if (record != null) {
      final File file = File(p.join((await _folder()).path, record.fileName));
      if (file.existsSync()) {
        await file.delete();
      }
    }
    await _store.transaction<void>(
      (LocalWriter writer) => writer.deleteReplayRecord(id),
      notify: false,
    );
  }

  /// Applies the size and age limits.
  Future<void> prune() async {
    final List<ReplayRecord> all = await _store.replayRecordsOldestFirst();
    final int nowMs = _clock.now().millisecondsSinceEpoch;
    final List<ReplayRecord> kept = <ReplayRecord>[];
    for (final ReplayRecord record in all) {
      final bool stale =
          record.deliveryId == null && nowMs - record.createdAtMs > unattachedTtl.inMilliseconds;
      if (stale) {
        await delete(record.id);
      } else {
        kept.add(record);
      }
    }
    int total = 0;
    for (final ReplayRecord record in kept) {
      total += record.sizeBytes;
    }
    // Over budget: drop copies that are safe on the server first, then the oldest of the rest.
    final List<ReplayRecord> order = <ReplayRecord>[
      ...kept.where((ReplayRecord r) => r.isUploaded),
      ...kept.where((ReplayRecord r) => !r.isUploaded),
    ];
    int count = kept.length;
    for (final ReplayRecord record in order) {
      if (count <= maxPacks && total <= maxBytes) {
        break;
      }
      await delete(record.id);
      count -= 1;
      total -= record.sizeBytes;
    }
  }
}
