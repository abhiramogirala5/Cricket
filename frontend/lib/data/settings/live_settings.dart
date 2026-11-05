import 'package:gully_umpire/cv/live/ball_kind.dart';
import 'package:gully_umpire/data/local/local_store.dart';
import 'package:gully_umpire/data/local/local_writer.dart';

/// Small settings of the live camera that are kept on the phone (in the account's database):
/// which ball is bowled, the zoom the stumps of a match were marked at, and how far the phone stands
/// from the batter.
final class LiveSettings {
  LiveSettings(this._store);

  final LocalStore _store;

  static const String ballKindKey = 'ball_kind';

  static const String deliveryTimeoutKey = 'live_delivery_timeout_sec';

  static const int defaultDeliveryTimeoutSeconds = 8;
  static const int minDeliveryTimeoutSeconds = 5;
  static const int maxDeliveryTimeoutSeconds = 30;

  /// Pitch length presets in feet for monocular camera calibration.
  static const double pitchFullFeet = 66.0; // Standard 22 yards (ICC / MCC Law 6.1)
  static const double pitchTurfBoxFeet = 50.0; // Box / indoor / turf cricket
  static const double pitchShortFeet = 36.0; // Compact street / gully cricket

  static String zoomKey(String matchId) => 'live_zoom:$matchId';

  static String distanceKey(String matchId) => 'live_distance_ft:$matchId';

  /// The shortest and longest phone-to-batter distance (feet) that is believed.
  static const double minDistanceFeet = 10;
  static const double maxDistanceFeet = 130;

  /// The ball that was chosen last (a cricket ball until someone chooses otherwise).
  Future<BallKind> ballKind() async => BallKind.fromWire(await _store.meta(ballKindKey));

  Future<void> setBallKind(BallKind kind) {
    return _store.transaction<void>(
      (LocalWriter writer) => writer.setMeta(ballKindKey, kind.wire),
      notify: false,
    );
  }

  /// Time (seconds) the camera remains armed for a delivery before auto-timing out.
  Future<int> deliveryTimeoutSeconds() async {
    final String? raw = await _store.meta(deliveryTimeoutKey);
    final int? value = raw == null ? null : int.tryParse(raw);
    if (value == null || value < minDeliveryTimeoutSeconds || value > maxDeliveryTimeoutSeconds) {
      return defaultDeliveryTimeoutSeconds;
    }
    return value;
  }

  Future<void> setDeliveryTimeoutSeconds(int seconds) {
    final int clamped = seconds.clamp(minDeliveryTimeoutSeconds, maxDeliveryTimeoutSeconds);
    return _store.transaction<void>(
      (LocalWriter writer) => writer.setMeta(deliveryTimeoutKey, clamped.toString()),
      notify: false,
    );
  }

  /// The zoom the stumps of [matchId] were marked at, or `null` when none was saved.
  ///
  /// The marked stumps are positions in the picture, so the camera has to be zoomed the same
  /// way again whenever it is opened for this match.
  Future<double?> zoomFor(String matchId) async {
    final String? raw = await _store.meta(zoomKey(matchId));
    final double? value = raw == null ? null : double.tryParse(raw);
    if (value == null || !value.isFinite || value < 1 || value > 20) {
      return null;
    }
    return value;
  }

  Future<void> setZoomFor(String matchId, double zoom) {
    return _store.transaction<void>(
      (LocalWriter writer) => writer.setMeta(zoomKey(matchId), zoom.toString()),
      notify: false,
    );
  }

  /// How far the phone stands from the batter in [matchId], in feet as the umpire entered it, or
  /// `null` when none was entered.
  ///
  /// It is kept for each match on its own and is never carried over to another match: the phone is
  /// put somewhere else each time, and an old distance would make the ball speed wrong.
  Future<double?> distanceFeetFor(String matchId) async {
    final String? raw = await _store.meta(distanceKey(matchId));
    final double? value = raw == null ? null : double.tryParse(raw);
    if (value == null || !value.isFinite || value < minDistanceFeet || value > maxDistanceFeet) {
      return null;
    }
    return value;
  }

  /// Remembers the distance for [matchId]; `null` forgets it (no ball speed is shown then).
  Future<void> setDistanceFeetFor(String matchId, double? feet) {
    return _store.transaction<void>(
      (LocalWriter writer) => writer.setMeta(distanceKey(matchId), feet == null ? '' : feet.toString()),
      notify: false,
    );
  }
}
