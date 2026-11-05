import 'dart:io';
import 'dart:typed_data';

import 'package:gully_umpire/cv/live/replay_codec.dart';
import 'package:gully_umpire/cv/vision/luma_frame.dart';
import 'package:gully_umpire/data/remote/replay_api.dart';

/// A real replay file (two 4 x 4 pictures, 33 ms apart).
Uint8List makeReplayBytes({int seed = 0}) {
  Uint8List picture(int base) => Uint8List.fromList(<int>[
        for (int i = 0; i < 16; i++) (base + i * 3 + seed) % 256,
      ]);
  return ReplayCodec.encode(<LumaFrame>[
    LumaFrame(width: 4, height: 4, timestampMs: 1000, pixels: picture(10)),
    LumaFrame(width: 4, height: 4, timestampMs: 1033, pixels: picture(20)),
  ]);
}

/// A new empty folder for replay files; delete it when the test ends.
Directory makeTempReplayDirectory() => Directory.systemTemp.createTempSync('gu_replays_');

/// A replay server that answers from memory. Every call is written to [calls].
final class FakeReplayApi implements ReplayApi {
  final List<String> calls = <String>[];
  final List<Map<String, Object?>> announced = <Map<String, Object?>>[];
  final Map<String, Uint8List> uploadedBytes = <String, Uint8List>{};
  final Map<String, List<RemoteReplay>> byDelivery = <String, List<RemoteReplay>>{};
  final Map<String, Uint8List> downloads = <String, Uint8List>{};

  /// What [announce] reports: the server already holds the file.
  bool alreadyStored = false;

  /// When set, the call throws this instead of working.
  Object? announceError;
  Object? uploadError;
  Object? completeError;
  Object? listError;
  Object? downloadError;

  @override
  Future<ReplayAnnouncement> announce({
    required String id,
    required String matchId,
    required int sizeBytes,
    String? deliveryId,
    int? width,
    int? height,
    int? frameCount,
    int? durationMs,
  }) async {
    calls.add('announce:$id');
    announced.add(<String, Object?>{
      'id': id,
      'matchId': matchId,
      'sizeBytes': sizeBytes,
      'deliveryId': deliveryId,
      'width': width,
      'height': height,
      'frameCount': frameCount,
      'durationMs': durationMs,
    });
    final Object? error = announceError;
    if (error != null) {
      throw error;
    }
    if (alreadyStored) {
      return const ReplayAnnouncement(alreadyStored: true);
    }
    return ReplayAnnouncement(
      alreadyStored: false,
      upload: ReplayUploadTarget(
        url: 'https://storage.example.com/upload/$id',
        headers: const <String, String>{'Content-Type': 'application/octet-stream'},
      ),
    );
  }

  @override
  Future<void> upload(ReplayUploadTarget target, Uint8List bytes) async {
    final String id = target.url.split('/').last;
    calls.add('upload:$id');
    final Object? error = uploadError;
    if (error != null) {
      throw error;
    }
    uploadedBytes[id] = bytes;
  }

  @override
  Future<void> complete(String id) async {
    calls.add('complete:$id');
    final Object? error = completeError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<List<RemoteReplay>> forDelivery(String deliveryId) async {
    calls.add('list:$deliveryId');
    final Object? error = listError;
    if (error != null) {
      throw error;
    }
    return byDelivery[deliveryId] ?? const <RemoteReplay>[];
  }

  @override
  Future<Uint8List> download(String id) async {
    calls.add('download:$id');
    final Object? error = downloadError;
    if (error != null) {
      throw error;
    }
    final Uint8List? bytes = downloads[id];
    if (bytes == null) {
      throw StateError('No download prepared for $id');
    }
    return bytes;
  }
}
