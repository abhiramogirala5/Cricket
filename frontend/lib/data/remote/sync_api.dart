import 'package:gully_umpire/data/remote/api_client.dart';
import 'package:gully_umpire/domain/sync/sync.dart';

/// The sync endpoint (docs/API_CONTRACT.md §5.1). An interface so the sync engine can be tested
/// without a network.
abstract interface class SyncApi {
  /// Sends 1-100 events in order and returns one result per event.
  Future<SyncPushResponse> push(List<OutboxEvent> events);
}

final class HttpSyncApi implements SyncApi {
  const HttpSyncApi(this._client);

  final ApiClient _client;

  @override
  Future<SyncPushResponse> push(List<OutboxEvent> events) async {
    final Map<String, Object?> json = await _client.sendForMap(
      'POST',
      '/sync/push',
      body: <String, Object?>{
        'events': events.map<Map<String, Object?>>((OutboxEvent e) => e.toRequestJson()).toList(),
      },
    );
    return SyncPushResponse.fromJson(json);
  }
}
