import 'package:gully_umpire/data/remote/api_client.dart';
import 'package:gully_umpire/domain/models/json_helpers.dart';
import 'package:gully_umpire/domain/models/models.dart';
import 'package:gully_umpire/domain/sync/match_snapshot.dart';

/// The read endpoints used to restore data on a new phone (docs/API_CONTRACT.md §4).
abstract interface class RemoteReadApi {
  Future<List<Player>> players();
  Future<List<Team>> teams();

  /// Ids of all the user's matches on the server.
  Future<List<String>> matchIds();

  Future<MatchSnapshot> snapshot(String matchId);
}

final class HttpRemoteReadApi implements RemoteReadApi {
  const HttpRemoteReadApi(this._client);

  /// The largest page the server allows.
  static const int pageSize = 100;

  /// A safety net against a server that never stops paging.
  static const int maxPages = 200;

  final ApiClient _client;

  /// Reads every page of a list endpoint.
  Future<List<Map<String, Object?>>> _readAll(String path) async {
    final List<Map<String, Object?>> items = <Map<String, Object?>>[];
    int offset = 0;
    for (int page = 0; page < maxPages; page++) {
      final Map<String, Object?> body = await _client.sendForMap(
        'GET',
        path,
        query: <String, Object?>{'limit': pageSize, 'offset': offset},
      );
      final List<Object?> pageItems = asJsonListOrNull(body['items']) ?? const <Object?>[];
      for (final Object? item in pageItems) {
        final Map<String, Object?>? map = asJsonMapOrNull(item);
        if (map != null) {
          items.add(map);
        }
      }
      offset += pageItems.length;
      final int total = asIntOrNull(body['total']) ?? offset;
      if (pageItems.isEmpty || offset >= total) {
        break;
      }
    }
    return items;
  }

  @override
  Future<List<Player>> players() async =>
      (await _readAll('/players')).map<Player>(Player.fromJson).toList(growable: false);

  @override
  Future<List<Team>> teams() async =>
      (await _readAll('/teams')).map<Team>(Team.fromJson).toList(growable: false);

  @override
  Future<List<String>> matchIds() async => (await _readAll('/matches'))
      .map<String>((Map<String, Object?> item) => asString(item['id']))
      .toList(growable: false);

  @override
  Future<MatchSnapshot> snapshot(String matchId) async =>
      MatchSnapshot.fromJson(await _client.sendForMap('GET', '/matches/$matchId/snapshot'));
}
