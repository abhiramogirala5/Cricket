/// Abstraction over "now" so time-dependent code can be tested deterministically.
abstract interface class AppClock {
  /// The current instant in UTC.
  DateTime now();
}

/// Production [AppClock] backed by the system time.
class SystemClock implements AppClock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now().toUtc();
}
