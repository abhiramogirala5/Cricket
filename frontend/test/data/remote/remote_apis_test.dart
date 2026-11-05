import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/data/remote/api_client.dart';
import 'package:gully_umpire/data/remote/auth_api.dart';
import 'package:gully_umpire/data/remote/remote_read_api.dart';
import 'package:gully_umpire/data/remote/sync_api.dart';
import 'package:gully_umpire/data/session/session_keeper.dart';
import 'package:gully_umpire/data/session/session_models.dart';
import 'package:gully_umpire/data/session/session_storage.dart';
import 'package:gully_umpire/domain/models/models.dart';
import 'package:gully_umpire/domain/sync/match_snapshot.dart';
import 'package:gully_umpire/domain/sync/sync.dart';

import '../../support/data_test_support.dart';
import '../../support/model_fixtures.dart';
import 'scripted_adapter.dart';

void main() {
  late SessionKeeper keeper;
  late ScriptedAdapter adapter;
  late ApiClient client;

  setUp(() async {
    keeper = SessionKeeper(
      MemorySessionStorage(
        StoredSession(
          tokens: const AuthTokens(accessToken: 'a', refreshToken: 'r'),
          user: UserProfile(
            id: 'user-1',
            email: 'asha@example.com',
            displayName: 'Asha Rao',
            createdAt: t0,
          ),
        ),
      ),
    );
    await keeper.load();
    adapter = ScriptedAdapter((RequestOptions options) async => jsonReply(200, <String, Object?>{}));
    client = ApiClient(
      baseUrl: 'http://test.local/api/v1',
      session: keeper,
      ids: SequenceIds(),
      dio: Dio()..httpClientAdapter = adapter,
    );
  });

  tearDown(() async {
    client.close();
    await keeper.dispose();
  });

  group('AccountApi', () {
    test('login sends the credentials without a token and parses the answer', () async {
      adapter.onRequest = (RequestOptions options) async => jsonReply(200, <String, Object?>{
            'user': userJson(),
            'tokens': tokenPair('acc', 'ref'),
          });
      final AuthResult result =
          await AccountApi(client).login(email: 'asha@example.com', password: 'secret-pass');
      expect(adapter.paths.single, '/api/v1/auth/login');
      expect(adapter.sentJson(0), <String, Object?>{
        'email': 'asha@example.com',
        'password': 'secret-pass',
      });
      expect(adapter.requests.single.headers.containsKey('Authorization'), isFalse);
      expect(result.user.displayName, 'Asha Rao');
      expect(result.tokens.accessToken, 'acc');
      expect(result.tokens.refreshToken, 'ref');
    });

    test('register sends display_name', () async {
      adapter.onRequest = (RequestOptions options) async => jsonReply(201, <String, Object?>{
            'user': userJson(),
            'tokens': tokenPair('acc', 'ref'),
          });
      await AccountApi(client)
          .register(email: 'asha@example.com', password: 'secret-pass', displayName: 'Asha Rao');
      expect(adapter.sentJson(0), <String, Object?>{
        'email': 'asha@example.com',
        'password': 'secret-pass',
        'display_name': 'Asha Rao',
      });
    });

    test('logout sends the refresh token', () async {
      adapter.onRequest = (RequestOptions options) async => emptyReply(204);
      await AccountApi(client).logout('ref-9');
      expect(adapter.paths.single, '/api/v1/auth/logout');
      expect(adapter.sentJson(0), <String, Object?>{'refresh_token': 'ref-9'});
    });

    test('me reads the profile with the token', () async {
      adapter.onRequest = (RequestOptions options) async => jsonReply(200, userJson());
      final UserProfile me = await AccountApi(client).me();
      expect(me.email, 'asha@example.com');
      expect(adapter.requests.single.headers['Authorization'], 'Bearer a');
    });

    test('updateMe sends only the given fields, and null to clear the phone', () async {
      adapter.onRequest = (RequestOptions options) async => jsonReply(200, userJson());
      await AccountApi(client).updateMe(displayName: 'New Name');
      await AccountApi(client).updateMe(clearPhone: true);
      await AccountApi(client).updateMe(phone: '+91 99999 11111');
      expect(adapter.sentJson(0), <String, Object?>{'display_name': 'New Name'});
      expect(adapter.sentJson(1), <String, Object?>{'phone': null});
      expect(adapter.sentJson(2), <String, Object?>{'phone': '+91 99999 11111'});
      expect(adapter.requests.first.method, 'PATCH');
    });

    test('deleteMe sends the password in the body', () async {
      adapter.onRequest = (RequestOptions options) async => emptyReply(204);
      await AccountApi(client).deleteMe(password: 'secret-pass');
      expect(adapter.requests.single.method, 'DELETE');
      expect(adapter.paths.single, '/api/v1/users/me');
      expect(adapter.sentJson(0), <String, Object?>{'password': 'secret-pass'});
    });

    test('an answer without tokens is refused', () async {
      adapter.onRequest = (RequestOptions options) async =>
          jsonReply(200, <String, Object?>{'user': userJson()});
      await expectLater(
        AccountApi(client).login(email: 'a@b.co', password: 'secret-pass'),
        throwsFormatException,
      );
    });
  });

  group('HttpSyncApi', () {
    test('posts the events in the contract shape and parses every result', () async {
      adapter.onRequest = (RequestOptions options) async => jsonReply(200, <String, Object?>{
            'results': <Object?>[
              <String, Object?>{'event_id': 'e1', 'status': 'APPLIED', 'error': null},
              <String, Object?>{'event_id': 'e2', 'status': 'DUPLICATE', 'error': null},
              <String, Object?>{
                'event_id': 'e3',
                'status': 'REJECTED',
                'error': <String, Object?>{'code': 'INVALID_DELIVERY', 'message': 'bad ball'},
              },
            ],
            'server_time': '2026-10-08T07:33:01Z',
          });
      final List<OutboxEvent> events = <OutboxEvent>[
        for (int i = 1; i <= 3; i++)
          OutboxEvent(
            eventId: 'e$i',
            entityType: SyncEntityType.team,
            action: SyncAction.upsert,
            payload: <String, Object?>{'id': 't$i', 'name': 'Team $i'},
            clientCreatedAt: t0,
          ),
      ];
      final SyncPushResponse response = await HttpSyncApi(client).push(events);

      expect(adapter.paths.single, '/api/v1/sync/push');
      final Map<String, Object?> sent = adapter.sentJson(0);
      expect(sent.keys, <String>['events']);
      final List<Object?> sentEvents = sent['events']! as List<Object?>;
      expect(sentEvents, hasLength(3));
      expect(sentEvents.first, <String, Object?>{
        'event_id': 'e1',
        'entity_type': 'TEAM',
        'action': 'UPSERT',
        'payload': <String, Object?>{'id': 't1', 'name': 'Team 1'},
        'client_created_at': '2026-10-08T07:33:00.000Z',
      });

      expect(response.results, hasLength(3));
      expect(response.results[0].status, SyncResultStatus.applied);
      expect(response.results[1].status, SyncResultStatus.duplicate);
      expect(response.results[2].status, SyncResultStatus.rejected);
      expect(response.results[2].errorCode, 'INVALID_DELIVERY');
      expect(response.results[2].errorMessage, 'bad ball');
      expect(response.serverTime, DateTime.utc(2026, 10, 8, 7, 33, 1));
    });
  });

  group('HttpRemoteReadApi', () {
    Map<String, Object?> page(List<Object?> items, {required int total, required int offset}) =>
        <String, Object?>{'items': items, 'total': total, 'limit': 100, 'offset': offset};

    test('reads every page of the players', () async {
      Map<String, Object?> playerJson(int n) => <String, Object?>{
            'id': 'p$n',
            'display_name': 'Player $n',
            'batting_hand': 'RIGHT',
            'declared_height_cm': null,
            'created_at': '2026-10-08T07:33:00Z',
            'updated_at': '2026-10-08T07:33:00Z',
          };
      adapter.onRequest = (RequestOptions options) async {
        final int offset = int.parse(options.uri.queryParameters['offset']!);
        if (offset == 0) {
          return jsonReply(
            200,
            page(<Object?>[for (int i = 0; i < 100; i++) playerJson(i)], total: 130, offset: 0),
          );
        }
        return jsonReply(
          200,
          page(<Object?>[for (int i = 100; i < 130; i++) playerJson(i)], total: 130, offset: 100),
        );
      };
      final List<Player> players = await HttpRemoteReadApi(client).players();
      expect(players, hasLength(130));
      expect(players.last.displayName, 'Player 129');
      expect(adapter.requests, hasLength(2));
      expect(adapter.requests.first.uri.queryParameters, <String, String>{'limit': '100', 'offset': '0'});
      expect(adapter.requests.last.uri.queryParameters['offset'], '100');
    });

    test('lists match ids from the summaries', () async {
      adapter.onRequest = (RequestOptions options) async => jsonReply(
            200,
            page(<Object?>[
              <String, Object?>{'id': 'm1', 'status': 'LIVE'},
              <String, Object?>{'id': 'm2', 'status': 'COMPLETED'},
            ], total: 2, offset: 0),
          );
      expect(await HttpRemoteReadApi(client).matchIds(), <String>['m1', 'm2']);
    });

    test('an empty list is fine', () async {
      adapter.onRequest = (RequestOptions options) async => jsonReply(200, page(<Object?>[], total: 0, offset: 0));
      expect(await HttpRemoteReadApi(client).teams(), isEmpty);
      expect(adapter.requests, hasLength(1));
    });

    test('a server that keeps returning empty pages cannot loop forever', () async {
      adapter.onRequest = (RequestOptions options) async => jsonReply(200, page(<Object?>[], total: 999, offset: 0));
      expect(await HttpRemoteReadApi(client).teams(), isEmpty);
      expect(adapter.requests, hasLength(1));
    });

    test('parses a full match snapshot', () async {
      adapter.onRequest = (RequestOptions options) async => jsonReply(200, <String, Object?>{
            'match': <String, Object?>{
              ...sampleMatch.toJson(),
              'owner_id': 'user-1',
            },
            'rules': sampleRules.toJson(),
            'teams': <Object?>[sampleTeamA.toJson(), sampleTeamB.toJson()],
            'players': <Object?>[samplePlayer.toJson()],
            'match_players': <Object?>[sampleMatchPlayer.toJson()],
            'toss': sampleToss.toJson(),
            'innings': <Object?>[sampleInnings.toJson()],
            'deliveries': <Object?>[sampleDelivery.toJson()],
            'delivery_decisions': <Object?>[sampleDecision.toJson()],
            'scene_scans': <Object?>[sampleScan.toJson()],
            'wicket_detections': <Object?>[sampleWicket.toJson()],
            'trajectory_snapshots': <Object?>[sampleTrajectory.toJson()],
          });
      final MatchSnapshot snapshot = await HttpRemoteReadApi(client).snapshot('match-1');
      expect(adapter.paths.single, '/api/v1/matches/match-1/snapshot');
      expect(snapshot.match, sampleMatch);
      expect(snapshot.rules, sampleRules);
      expect(snapshot.teams, <Team>[sampleTeamA, sampleTeamB]);
      expect(snapshot.players, <Player>[samplePlayer]);
      expect(snapshot.matchPlayers, <MatchPlayer>[sampleMatchPlayer]);
      expect(snapshot.toss, sampleToss);
      expect(snapshot.innings, <Innings>[sampleInnings]);
      expect(snapshot.deliveries, <Delivery>[sampleDelivery]);
      expect(snapshot.decisions, <DecisionRecord>[sampleDecision]);
      expect(snapshot.sceneScans, <SceneScan>[sampleScan]);
      expect(snapshot.wicketDetections, <WicketDetection>[sampleWicket]);
      expect(snapshot.trajectories, <TrajectorySnapshot>[sampleTrajectory]);
    });

    test('a snapshot without optional parts is accepted', () async {
      adapter.onRequest = (RequestOptions options) async => jsonReply(200, <String, Object?>{
            'match': sampleMatch.toJson(),
            'rules': null,
            'teams': <Object?>[sampleTeamA.toJson(), sampleTeamB.toJson()],
            'players': <Object?>[],
            'match_players': <Object?>[],
            'toss': null,
            'innings': <Object?>[],
            'deliveries': <Object?>[],
            'delivery_decisions': <Object?>[],
            'scene_scans': <Object?>[],
            'wicket_detections': <Object?>[],
            'trajectory_snapshots': <Object?>[],
          });
      final MatchSnapshot snapshot = await HttpRemoteReadApi(client).snapshot('match-1');
      expect(snapshot.rules, isNull);
      expect(snapshot.toss, isNull);
      expect(snapshot.deliveries, isEmpty);
    });
  });
}
