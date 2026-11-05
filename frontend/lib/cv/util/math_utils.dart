import 'dart:math' as math;

/// Clamps [value] to 0..1. NaN becomes 0.
double clamp01(double value) {
  if (value.isNaN) {
    return 0;
  }
  if (value < 0) {
    return 0;
  }
  if (value > 1) {
    return 1;
  }
  return value;
}

/// Clamps [value] to [low]..[high]. NaN becomes [low].
double clampDouble(double value, double low, double high) {
  if (value.isNaN) {
    return low;
  }
  if (value < low) {
    return low;
  }
  if (value > high) {
    return high;
  }
  return value;
}

/// Linear interpolation: `a` at `t = 0`, `b` at `t = 1`.
double lerpDouble(double a, double b, double t) => a + (b - a) * t;

/// Degrees to radians.
double degToRad(double degrees) => degrees * math.pi / 180.0;

/// Radians to degrees.
double radToDeg(double radians) => radians * 180.0 / math.pi;

/// Arithmetic mean; 0 for an empty list.
double meanOf(List<double> values) {
  if (values.isEmpty) {
    return 0;
  }
  double sum = 0;
  for (final double value in values) {
    sum += value;
  }
  return sum / values.length;
}

/// Median; 0 for an empty list.
double medianOf(List<double> values) {
  if (values.isEmpty) {
    return 0;
  }
  final List<double> sorted = List<double>.of(values)..sort();
  final int mid = sorted.length ~/ 2;
  if (sorted.length.isOdd) {
    return sorted[mid];
  }
  return (sorted[mid - 1] + sorted[mid]) / 2;
}

/// Population standard deviation; 0 for fewer than two values.
double stdDevOf(List<double> values) {
  if (values.length < 2) {
    return 0;
  }
  final double mean = meanOf(values);
  double sum = 0;
  for (final double value in values) {
    final double d = value - mean;
    sum += d * d;
  }
  return math.sqrt(sum / values.length);
}

/// 1 when [value] <= [good], 0 when [value] >= [bad], linear in between.
/// Requires `good < bad`.
double scoreFalling(double value, {required double good, required double bad}) {
  if (value <= good) {
    return 1;
  }
  if (value >= bad) {
    return 0;
  }
  return (bad - value) / (bad - good);
}

/// 0 when [value] <= [low], 1 when [value] >= [high], linear in between.
/// Requires `low < high`.
double scoreRising(double value, {required double low, required double high}) {
  if (value <= low) {
    return 0;
  }
  if (value >= high) {
    return 1;
  }
  return (value - low) / (high - low);
}
