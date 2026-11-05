import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/cv/live/ball_kind.dart';
import 'package:gully_umpire/data/local/local_store.dart';
import 'package:gully_umpire/data/local/local_writer.dart';
import 'package:gully_umpire/data/settings/live_settings.dart';

import '../../support/data_test_support.dart';

void main() {
  late LocalStore store;
  late LiveSettings settings;

  setUp(() async {
    store = await openMemoryStore();
    settings = LiveSettings(store);
  });

  tearDown(() async {
    await store.close();
  });

  group('ball kind', () {
    test('is a cricket ball until someone chooses otherwise', () async {
      expect(await settings.ballKind(), BallKind.cricketBall);
    });

    test('remembers the last choice', () async {
      await settings.setBallKind(BallKind.tennisBall);
      expect(await settings.ballKind(), BallKind.tennisBall);
      await settings.setBallKind(BallKind.cricketBall);
      expect(await settings.ballKind(), BallKind.cricketBall);
    });

    test('an unknown stored value gives the cricket ball', () async {
      await store.transaction<void>(
        (LocalWriter writer) => writer.setMeta(LiveSettings.ballKindKey, 'SOMETHING_ELSE'),
        notify: false,
      );
      expect(await settings.ballKind(), BallKind.cricketBall);
    });
  });

  group('zoom per match', () {
    test('is null until one is saved', () async {
      expect(await settings.zoomFor('match-1'), isNull);
    });

    test('is kept separately for each match', () async {
      await settings.setZoomFor('match-1', 2.5);
      await settings.setZoomFor('match-2', 1.0);
      expect(await settings.zoomFor('match-1'), 2.5);
      expect(await settings.zoomFor('match-2'), 1.0);
      expect(await settings.zoomFor('match-3'), isNull);
    });

    test('the latest zoom replaces the earlier one', () async {
      await settings.setZoomFor('match-1', 2.0);
      await settings.setZoomFor('match-1', 3.0);
      expect(await settings.zoomFor('match-1'), 3.0);
    });

    test('a stored value that cannot be a zoom is ignored', () async {
      Future<void> put(String raw) {
        return store.transaction<void>(
          (LocalWriter writer) => writer.setMeta(LiveSettings.zoomKey('m'), raw),
          notify: false,
        );
      }

      await put('banana');
      expect(await settings.zoomFor('m'), isNull);
      await put('0.5');
      expect(await settings.zoomFor('m'), isNull);
      await put('25');
      expect(await settings.zoomFor('m'), isNull);
      await put('NaN');
      expect(await settings.zoomFor('m'), isNull);
      await put('Infinity');
      expect(await settings.zoomFor('m'), isNull);
    });

    test('the key includes the match id', () {
      expect(LiveSettings.zoomKey('abc'), 'live_zoom:abc');
    });
  });

  group('distance to the batter per match', () {
    test('is null until one is saved', () async {
      expect(await settings.distanceFeetFor('match-1'), isNull);
    });

    test('is kept in feet, separately for each match', () async {
      await settings.setDistanceFeetFor('match-1', 45);
      await settings.setDistanceFeetFor('match-2', 38.5);
      expect(await settings.distanceFeetFor('match-1'), 45);
      expect(await settings.distanceFeetFor('match-2'), 38.5);
      expect(await settings.distanceFeetFor('match-3'), isNull);
    });

    test('a new match never inherits the distance of an old one', () async {
      await settings.setDistanceFeetFor('old-match', 45);

      expect(await settings.distanceFeetFor('new-match'), isNull);
    });

    test('the latest distance replaces the earlier one, and null forgets it', () async {
      await settings.setDistanceFeetFor('match-1', 40);
      await settings.setDistanceFeetFor('match-1', 50);
      expect(await settings.distanceFeetFor('match-1'), 50);

      await settings.setDistanceFeetFor('match-1', null);
      expect(await settings.distanceFeetFor('match-1'), isNull);
    });

    test('a stored value that cannot be a distance is ignored', () async {
      Future<void> put(String raw) {
        return store.transaction<void>(
          (LocalWriter writer) => writer.setMeta(LiveSettings.distanceKey('m'), raw),
          notify: false,
        );
      }

      for (final String raw in <String>['banana', '9', '131', '-40', 'NaN', 'Infinity', '']) {
        await put(raw);
        expect(await settings.distanceFeetFor('m'), isNull, reason: raw);
      }
      await put('10');
      expect(await settings.distanceFeetFor('m'), 10);
      await put('130');
      expect(await settings.distanceFeetFor('m'), 130);
    });

    test('the key includes the match id and the unit', () {
      expect(LiveSettings.distanceKey('abc'), 'live_distance_ft:abc');
    });
  });

  group('delivery timeout', () {
    test('defaults to 8 seconds', () async {
      expect(await settings.deliveryTimeoutSeconds(), 8);
    });

    test('stores and clamps valid values', () async {
      await settings.setDeliveryTimeoutSeconds(15);
      expect(await settings.deliveryTimeoutSeconds(), 15);

      await settings.setDeliveryTimeoutSeconds(2); // below min
      expect(await settings.deliveryTimeoutSeconds(), LiveSettings.minDeliveryTimeoutSeconds);

      await settings.setDeliveryTimeoutSeconds(50); // above max
      expect(await settings.deliveryTimeoutSeconds(), LiveSettings.maxDeliveryTimeoutSeconds);
    });

    test('an invalid stored value returns default', () async {
      await store.transaction<void>(
        (LocalWriter writer) => writer.setMeta(LiveSettings.deliveryTimeoutKey, 'invalid'),
        notify: false,
      );
      expect(await settings.deliveryTimeoutSeconds(), LiveSettings.defaultDeliveryTimeoutSeconds);
    });
  });
}
