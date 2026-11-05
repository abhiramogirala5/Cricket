/// A tiny deterministic pseudo-random generator (Park-Miller "MINSTD").
///
/// The mock adapters must be reproducible for a given seed on every platform,
/// so they never use an unseeded `dart:math` `Random`. All intermediate values
/// stay below 2^53, so results are identical on the VM and on the web.
final class SeededRandom {
  /// Creates a generator. Any integer seed is accepted (negative too).
  SeededRandom(int seed) : _state = _scramble(seed) {
    for (int i = 0; i < 10; i++) {
      nextRaw();
    }
  }

  /// A generator for a sub-stream, so independent parts of a simulation do not
  /// consume each other's numbers: `SeededRandom.derive(seed, 3)`.
  factory SeededRandom.derive(int seed, int salt) => SeededRandom(seed * 7919 + salt * 104729 + 17);

  static const int _modulus = 2147483647;
  static const int _multiplier = 48271;

  int _state;

  static int _scramble(int seed) {
    int s = seed % (_modulus - 1);
    if (s < 0) {
      s += _modulus - 1;
    }
    // 1 .. modulus - 1 (never 0, which would lock the generator).
    return ((s * 16807) % (_modulus - 1)) + 1;
  }

  /// Next raw value in `1 .. 2147483646`.
  int nextRaw() {
    _state = (_state * _multiplier) % _modulus;
    return _state;
  }

  /// Uniform in `[0, 1)`.
  double nextDouble() => (nextRaw() - 1) / (_modulus - 1);

  /// Uniform in `[low, high)`.
  double nextRange(double low, double high) => low + (high - low) * nextDouble();

  /// Uniform integer in `0 .. maxExclusive - 1`. [maxExclusive] must be > 0.
  int nextInt(int maxExclusive) {
    if (maxExclusive <= 0) {
      throw ArgumentError.value(maxExclusive, 'maxExclusive', 'must be positive');
    }
    return nextRaw() % maxExclusive;
  }

  /// True with probability [probability] (0..1).
  bool nextBool(double probability) => nextDouble() < probability;

  /// Approximately standard-normal noise (mean 0, standard deviation 1,
  /// bounded to about +/- 4.2). Built from six uniforms (Irwin-Hall) so it
  /// needs no transcendental functions and is bit-for-bit reproducible.
  double nextGaussian() {
    double sum = 0;
    for (int i = 0; i < 6; i++) {
      sum += nextDouble();
    }
    // Irwin-Hall(6): mean 3, variance 6/12 = 0.5 -> scale by sqrt(2).
    return (sum - 3.0) * 1.4142135623730951;
  }
}
