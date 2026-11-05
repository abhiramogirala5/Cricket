import 'dart:math' as math;

/// Longest wait between two sync attempts (docs/API_CONTRACT.md §5.2: "capped at 5 min").
const Duration maxSyncBackoff = Duration(minutes: 5);

/// How long to wait after [consecutiveFailures] failed attempts in a row.
///
/// 1 s, 2 s, 4 s, 8 s ... capped at [maxSyncBackoff], then spread by +-20% so that many phones
/// that lost the network at the same moment do not all retry at the same moment. The result is
/// never longer than [maxSyncBackoff].
Duration syncBackoff(int consecutiveFailures, {math.Random? random}) {
  final int failures = consecutiveFailures < 1 ? 1 : consecutiveFailures;
  // 2^9 = 512 s is already above the cap, so a bigger exponent changes nothing (and cannot overflow).
  final int exponent = math.min(failures - 1, 9);
  final double baseSeconds = math.min(math.pow(2, exponent).toDouble(), maxSyncBackoff.inSeconds.toDouble());
  final double factor = 0.8 + 0.4 * (random ?? math.Random()).nextDouble();
  final int milliseconds = math.min((baseSeconds * factor * 1000).round(), maxSyncBackoff.inMilliseconds);
  return Duration(milliseconds: milliseconds);
}
