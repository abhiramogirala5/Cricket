import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/core/config/app_config.dart';
import 'package:gully_umpire/core/di/cv_providers.dart';
import 'package:gully_umpire/cv/device/device_policy.dart';
import 'package:gully_umpire/cv/engine/cv_engine.dart';

AppConfig config(Map<String, String> env) => AppConfig.fromMap(env);

void main() {
  group('chooseCvMode', () {
    test('the live camera is used when it is supported and the phone can keep up', () {
      expect(
        chooseCvMode(
          config: config(const <String, String>{}),
          liveSupported: true,
          profile: DeviceProfile.mid,
        ),
        CvMode.live,
      );
      expect(
        chooseCvMode(
          config: config(const <String, String>{}),
          liveSupported: true,
          profile: DeviceProfile.low,
        ),
        CvMode.live,
      );
    });

    test('a phone that is too weak, or a platform without the camera plugins, scores only', () {
      expect(
        chooseCvMode(
          config: config(const <String, String>{}),
          liveSupported: true,
          profile: DeviceProfile.scoreOnly,
        ),
        CvMode.scoreOnly,
      );
      expect(
        chooseCvMode(
          config: config(const <String, String>{}),
          liveSupported: false,
          profile: DeviceProfile.high,
        ),
        CvMode.scoreOnly,
      );
    });

    test('switching the live camera off gives scoring only, never the simulation', () {
      expect(
        chooseCvMode(
          config: config(const <String, String>{'ENABLE_LIVE_CV': 'false'}),
          liveSupported: true,
          profile: DeviceProfile.high,
        ),
        CvMode.scoreOnly,
      );
    });

    test('the simulation is only used when a development build asks for it', () {
      expect(
        chooseCvMode(
          config: config(const <String, String>{'DEV_SIMULATE_CV': 'true'}),
          liveSupported: true,
          profile: DeviceProfile.high,
        ),
        CvMode.simulated,
      );
      expect(
        chooseCvMode(
          config: config(const <String, String>{'APP_ENV': 'staging', 'DEV_SIMULATE_CV': 'true'}),
          liveSupported: false,
          profile: DeviceProfile.scoreOnly,
        ),
        CvMode.simulated,
      );
    });

    test('an old ENABLE_MOCK_CV line in a .env file cannot bring the simulation back', () {
      expect(
        chooseCvMode(
          config: config(const <String, String>{'ENABLE_MOCK_CV': 'true'}),
          liveSupported: true,
          profile: DeviceProfile.high,
        ),
        CvMode.live,
      );
    });

    test('a production build never runs the simulation', () {
      final AppConfig production = config(const <String, String>{
        'APP_ENV': 'production',
        'API_BASE_URL': 'https://api.example.com',
        'DEV_SIMULATE_CV': 'true',
      });

      expect(
        chooseCvMode(config: production, liveSupported: true, profile: DeviceProfile.high),
        CvMode.live,
      );
      expect(
        chooseCvMode(config: production, liveSupported: false, profile: DeviceProfile.high),
        CvMode.scoreOnly,
      );
    });
  });
}
