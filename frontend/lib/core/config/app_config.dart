import 'package:equatable/equatable.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:gully_umpire/core/utils/app_log.dart';

enum AppEnvironment {
  development,
  staging,
  production;

  static AppEnvironment parse(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'production':
      case 'prod':
        return AppEnvironment.production;
      case 'staging':
        return AppEnvironment.staging;
      default:
        return AppEnvironment.development;
    }
  }
}

/// Typed application configuration, read once at start-up from `.env`.
///
/// This is the ONLY place that touches `flutter_dotenv`. The file is bundled into the app,
/// so it must never contain secrets (see frontend/.env.example).
final class AppConfig extends Equatable {
  const AppConfig({
    required this.environment,
    required this.apiBaseUrl,
    this.simulateCv = false,
    this.enableLiveCv = true,
    this.enableEdgeReview = false,
    this.enableLbwReview = false,
    this.httpTimeout = const Duration(seconds: 20),
  });

  /// Builds a config from raw key/value pairs (used by [load] and by tests).
  factory AppConfig.fromMap(Map<String, String> env) {
    String base = (env['API_BASE_URL'] ?? '').trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }

    bool flag(String key) {
      final String? value = env[key]?.trim().toLowerCase();
      return value == 'true' || value == '1' || value == 'yes';
    }

    // The live camera is on unless a build switches it off.
    final bool liveCv = !env.containsKey('ENABLE_LIVE_CV') || flag('ENABLE_LIVE_CV');

    final int rawTimeout = int.tryParse((env['HTTP_TIMEOUT_SECONDS'] ?? '').trim()) ?? 20;
    final int timeoutSeconds = rawTimeout < 3 ? 3 : (rawTimeout > 120 ? 120 : rawTimeout);

    return AppConfig(
      environment: AppEnvironment.parse(env['APP_ENV']),
      apiBaseUrl: base,
      simulateCv: flag('DEV_SIMULATE_CV'),
      enableLiveCv: liveCv,
      enableEdgeReview: flag('ENABLE_EDGE_REVIEW'),
      enableLbwReview: flag('ENABLE_LBW_REVIEW'),
      httpTimeout: Duration(seconds: timeoutSeconds),
    );
  }

  /// Loads `.env` from the asset bundle. A missing file yields safe local-mode defaults.
  static Future<AppConfig> load() async {
    try {
      await dotenv.load(fileName: '.env');
    } on Object catch (error, stackTrace) {
      AppLog.warn('Could not load .env ($error); using defaults.');
      AppLog.error('dotenv load failure', error: error, stackTrace: stackTrace);
      return AppConfig.fromMap(const <String, String>{});
    }
    return AppConfig.fromMap(dotenv.env);
  }

  final AppEnvironment environment;

  /// Backend base URL without `/api/v1` and without trailing slash. Empty means local-only mode.
  final String apiBaseUrl;

  /// The simulated detections (development only, never in production). It has its own, new key
  /// (`DEV_SIMULATE_CV`) on purpose: an old `.env` that still says `ENABLE_MOCK_CV=true` must not be
  /// able to switch the demo engine on.
  final bool simulateCv;

  /// The live camera umpire assistant (Android). Switch off to run the app as a plain scorer.
  final bool enableLiveCv;
  final bool enableEdgeReview;
  final bool enableLbwReview;
  final Duration httpTimeout;

  bool get isProduction => environment == AppEnvironment.production;

  /// No backend configured: the app works entirely on this device without an account.
  bool get isLocalMode => apiBaseUrl.isEmpty;

  /// Versioned API root, e.g. `https://api.example.com/api/v1`.
  String get apiUrl => '$apiBaseUrl/api/v1';

  /// Human-readable configuration problems. A non-empty list blocks start-up in production.
  List<String> validate() {
    final List<String> issues = <String>[];
    if (isProduction) {
      if (apiBaseUrl.isEmpty) {
        issues.add('API_BASE_URL must be set in production builds.');
      } else if (!apiBaseUrl.startsWith('https://')) {
        issues.add('API_BASE_URL must use https:// in production builds.');
      }
      if (simulateCv) {
        issues.add('DEV_SIMULATE_CV must be false in production builds.');
      }
    } else if (apiBaseUrl.isNotEmpty &&
        !(apiBaseUrl.startsWith('http://') || apiBaseUrl.startsWith('https://'))) {
      issues.add('API_BASE_URL must start with http:// or https://.');
    }
    return issues;
  }

  @override
  List<Object?> get props => <Object?>[
        environment,
        apiBaseUrl,
        simulateCv,
        enableLiveCv,
        enableEdgeReview,
        enableLbwReview,
        httpTimeout,
      ];
}
