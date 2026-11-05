import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gully_umpire/core/di/core_providers.dart';
import 'package:gully_umpire/core/di/data_providers.dart';
import 'package:gully_umpire/cv/live/replay_codec.dart';
import 'package:gully_umpire/data/remote/api_client.dart';
import 'package:gully_umpire/data/remote/replay_api.dart';
import 'package:gully_umpire/data/replays/replay_record.dart';
import 'package:gully_umpire/data/replays/replay_store.dart';

/// The replay endpoints, or `null` in local-only mode.
final Provider<ReplayApi?> replayApiProvider = Provider<ReplayApi?>((ref) {
  final ApiClient? client = ref.watch(apiClientProvider);
  return client == null ? null : HttpReplayApi(client);
});

/// Where the replay of a ball can be found.
enum ReplayAvailability {
  /// The ball has no replay (it was scored by hand, or the replay was cleared).
  none,

  /// The file is on this phone.
  onThisPhone,

  /// Only the server has it (for example on a new phone): it has to be downloaded first.
  online,
}

/// The answer to "is there a replay of this ball, and where".
final class ReplayLookup {
  const ReplayLookup(this.availability, {this.replayId});

  static const ReplayLookup none = ReplayLookup(ReplayAvailability.none);

  final ReplayAvailability availability;

  /// The id of the replay file (on the phone, or on the server).
  final String? replayId;
}

/// Looks for the replay of one ball: first on the phone, then (when signed in) on the server.
/// A server that cannot be reached simply means "no replay": the question is never an error.
final replayLookupProvider =
    FutureProvider.autoDispose.family<ReplayLookup, String>((ref, String deliveryId) async {
  ref.watch(dataChangesProvider);
  final ReplayStore? store = ref.watch(replayStoreProvider);
  if (store != null) {
    final ReplayRecord? record = await store.forDelivery(deliveryId);
    if (record != null && await store.hasFile(record.id)) {
      return ReplayLookup(ReplayAvailability.onThisPhone, replayId: record.id);
    }
  }
  final ReplayApi? api = ref.watch(replayApiProvider);
  if (api == null || store == null) {
    return ReplayLookup.none;
  }
  try {
    final List<RemoteReplay> remote = await api.forDelivery(deliveryId);
    if (remote.isNotEmpty) {
      return ReplayLookup(ReplayAvailability.online, replayId: remote.first.id);
    }
  } on Object {
    // Offline or not signed in: there is just nothing to show.
  }
  return ReplayLookup.none;
});

/// Downloads a replay that only the server has and keeps it on the phone. Returns the id of the
/// local file.
Future<String> downloadReplay({
  required ReplayStore store,
  required ReplayApi api,
  required String remoteId,
  required String matchId,
  required String deliveryId,
}) async {
  final Uint8List bytes = await api.download(remoteId);
  // Refuse a file that cannot be played before keeping it.
  ReplayReader.parse(bytes);
  await store.save(id: remoteId, matchId: matchId, bytes: bytes, deliveryId: deliveryId);
  await store.markUploaded(remoteId, remoteId);
  return remoteId;
}
