/// Removes the jitter from camera frame times.
///
/// The phone reports a frame when it arrives in the app, and that moment wobbles by several
/// milliseconds (busy threads, garbage collection). The sensor itself captures frames at a very
/// regular rate, so a clock that locks on to that rate gives much cleaner times. The ball's
/// arrival time is worked out from differences between frame times, so this directly improves
/// the accuracy of every call.
///
/// It is a small phase-locked loop: the next frame is expected one (or, after dropped frames,
/// several) periods after the previous one; the arrival time is pulled a fraction of the way
/// towards that expectation, and the period itself follows the camera's real rate slowly. When the
/// arrival time is too far from any expectation (the app was paused, the camera stalled) the clock
/// simply starts again from the new time.
final class FrameClock {
  FrameClock({double nominalIntervalMs = 1000 / 30})
      : _period = nominalIntervalMs,
        assert(nominalIntervalMs > 4 && nominalIntervalMs < 200, 'implausible frame interval');

  /// Share of the lock error that is corrected per frame.
  static const double _phaseGain = 0.2;

  /// Share of the measured period that is taken over per frame.
  static const double _periodGain = 0.03;

  /// A frame further than this share of a period from the expectation breaks the lock.
  static const double _lockWindow = 0.4;

  double _period;
  double? _last;

  /// The current estimate of the time between two frames (milliseconds).
  double get periodMs => _period;

  /// Frames per second implied by [periodMs].
  double get fps => 1000.0 / _period;

  /// Forgets the lock.
  void reset() {
    _last = null;
  }

  /// Smoothed time for a frame that arrived at [rawMs].
  ///
  /// The result always grows from one frame to the next, so no two frames get the same time:
  /// by about a period while the clock is locked, and by at least 1 ms when it starts again.
  int regularise(int rawMs) {
    final double? previous = _last;
    if (previous == null) {
      _last = rawMs.toDouble();
      return rawMs;
    }
    final double elapsed = rawMs - previous;
    int periods = (elapsed / _period).round();
    if (periods < 1) {
      periods = 1;
    }
    final double expected = previous + periods * _period;
    final double error = rawMs - expected;
    double next;
    if (error.abs() <= _lockWindow * _period) {
      final double measured = elapsed / periods;
      double period = (1 - _periodGain) * _period + _periodGain * measured;
      if (period < 8) {
        period = 8;
      } else if (period > 100) {
        period = 100;
      }
      _period = period;
      next = expected + _phaseGain * error;
    } else {
      next = rawMs.toDouble();
      if (next <= previous + 1) {
        next = previous + _period;
      }
    }
    _last = next;
    return next.round();
  }
}
