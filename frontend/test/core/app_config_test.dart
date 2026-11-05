import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/core/config/app_config.dart';

void main() {
  group('AppConfig.fromMap', () {
    test('reads every setting', () {
      final AppConfig config = AppConfig.fromMap(const <String, String>{
        'APP_ENV': 'staging',
        'API_BASE_URL': 'https://api.example.com/',
        'DEV_SIMULATE_CV': 'true',
        'ENABLE_EDGE_REVIEW': '1',
        'ENABLE_LBW_REVIEW': 'yes',
        'HTTP_TIMEOUT_SECONDS': '45',
      });
      expect(config.environment, AppEnvironment.staging);
      expect(config.apiBaseUrl, 'https://api.example.com');
      expect(config.apiUrl, 'https://api.example.com/api/v1');
      expect(config.simulateCv, isTrue);
      expect(config.enableEdgeReview, isTrue);
      expect(config.enableLbwReview, isTrue);
      expect(config.httpTimeout, const Duration(seconds: 45));
      expect(config.isLocalMode, isFalse);
      expect(config.isProduction, isFalse);
    });

    test('an empty map gives safe local-only defaults', () {
      final AppConfig config = AppConfig.fromMap(const <String, String>{});
      expect(config.environment, AppEnvironment.development);
      expect(config.apiBaseUrl, isEmpty);
      expect(config.isLocalMode, isTrue);
      expect(config.simulateCv, isFalse);
      expect(config.enableEdgeReview, isFalse);
      expect(config.enableLbwReview, isFalse);
      expect(config.httpTimeout, const Duration(seconds: 20));
      expect(config.validate(), isEmpty);
    });

    test('the live camera is on unless it is switched off', () {
      expect(AppConfig.fromMap(const <String, String>{}).enableLiveCv, isTrue);
      expect(AppConfig.fromMap(const <String, String>{'ENABLE_LIVE_CV': 'true'}).enableLiveCv, isTrue);
      expect(AppConfig.fromMap(const <String, String>{'ENABLE_LIVE_CV': 'false'}).enableLiveCv, isFalse);
      expect(AppConfig.fromMap(const <String, String>{'ENABLE_LIVE_CV': '0'}).enableLiveCv, isFalse);
      expect(AppConfig.fromMap(const <String, String>{'ENABLE_LIVE_CV': ''}).enableLiveCv, isFalse);
    });

    test('the simulation has a key of its own and an old ENABLE_MOCK_CV line does nothing', () {
      expect(AppConfig.fromMap(const <String, String>{}).simulateCv, isFalse);
      expect(AppConfig.fromMap(const <String, String>{'DEV_SIMULATE_CV': 'true'}).simulateCv, isTrue);
      expect(AppConfig.fromMap(const <String, String>{'DEV_SIMULATE_CV': 'false'}).simulateCv, isFalse);
      expect(AppConfig.fromMap(const <String, String>{'ENABLE_MOCK_CV': 'true'}).simulateCv, isFalse);
    });

    test('trailing slashes are removed', () {
      expect(
        AppConfig.fromMap(const <String, String>{'API_BASE_URL': 'http://10.0.2.2:8000///'}).apiBaseUrl,
        'http://10.0.2.2:8000',
      );
    });

    test('the timeout is clamped to 3..120 seconds and bad values use the default', () {
      expect(
        AppConfig.fromMap(const <String, String>{'HTTP_TIMEOUT_SECONDS': '1'}).httpTimeout,
        const Duration(seconds: 3),
      );
      expect(
        AppConfig.fromMap(const <String, String>{'HTTP_TIMEOUT_SECONDS': '999'}).httpTimeout,
        const Duration(seconds: 120),
      );
      expect(
        AppConfig.fromMap(const <String, String>{'HTTP_TIMEOUT_SECONDS': 'abc'}).httpTimeout,
        const Duration(seconds: 20),
      );
    });

    test('environment names are parsed case-insensitively with a safe default', () {
      expect(AppEnvironment.parse('PRODUCTION'), AppEnvironment.production);
      expect(AppEnvironment.parse(' prod '), AppEnvironment.production);
      expect(AppEnvironment.parse('Staging'), AppEnvironment.staging);
      expect(AppEnvironment.parse('anything else'), AppEnvironment.development);
      expect(AppEnvironment.parse(null), AppEnvironment.development);
    });
  });

  group('AppConfig.validate', () {
    test('a production build needs an https backend and no mock CV', () {
      final AppConfig bad = AppConfig.fromMap(const <String, String>{
        'APP_ENV': 'production',
        'API_BASE_URL': 'http://api.example.com',
        'DEV_SIMULATE_CV': 'true',
      });
      expect(bad.validate(), hasLength(2));

      final AppConfig missing = AppConfig.fromMap(const <String, String>{'APP_ENV': 'production'});
      expect(missing.validate(), hasLength(1));

      final AppConfig good = AppConfig.fromMap(const <String, String>{
        'APP_ENV': 'production',
        'API_BASE_URL': 'https://api.example.com',
      });
      expect(good.validate(), isEmpty);
    });

    test('a development build may use plain http but not a bare host', () {
      expect(
        AppConfig.fromMap(const <String, String>{'API_BASE_URL': 'http://10.0.2.2:8000'}).validate(),
        isEmpty,
      );
      expect(
        AppConfig.fromMap(const <String, String>{'API_BASE_URL': 'api.example.com'}).validate(),
        hasLength(1),
      );
    });
  });
}
