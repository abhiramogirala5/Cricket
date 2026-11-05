import 'dart:developer' as developer;

/// Minimal logging facade. Never pass tokens, passwords or full request bodies.
abstract final class AppLog {
  static const String _defaultName = 'gully';

  static void info(String message, {String name = _defaultName}) {
    developer.log(message, name: name, level: 800);
  }

  static void warn(String message, {String name = _defaultName}) {
    developer.log(message, name: name, level: 900);
  }

  static void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String name = _defaultName,
  }) {
    developer.log(message, name: name, level: 1000, error: error, stackTrace: stackTrace);
  }
}
