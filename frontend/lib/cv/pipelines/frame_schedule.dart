/// Decides which camera frames a model should look at, so that it runs at its target rate even
/// though the camera delivers frames at a different (higher) rate.
///
/// The schedule keeps a "next due" time instead of measuring from the last frame used, so the
/// average rate stays right even when the camera interval does not divide the target interval.
final class FrameSchedule {
  FrameSchedule(this.intervalMs);

  /// Wanted time between two used frames; 0 or less means "never".
  final int intervalMs;

  int? _due;

  /// Whether the frame at [timestampMs] should be used.
  bool take(int timestampMs) {
    if (intervalMs <= 0) {
      return false;
    }
    final int? due = _due;
    if (due == null) {
      _due = timestampMs + intervalMs;
      return true;
    }
    if (timestampMs >= due - intervalMs * 0.25) {
      int next = due + intervalMs;
      if (next < timestampMs - intervalMs) {
        // Fell behind (a long pause): start again from here.
        next = timestampMs + intervalMs;
      }
      _due = next;
      return true;
    }
    return false;
  }
}
