import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/data/sync/backoff.dart';

void main() {
  group('syncBackoff', () {
    test('doubles with every failure, within +-20%', () {
      final Random random = Random(7);
      for (int failures = 1; failures <= 8; failures++) {
        final double base = pow(2, failures - 1).toDouble();
        for (int i = 0; i < 20; i++) {
          final double seconds = syncBackoff(failures, random: random).inMilliseconds / 1000;
          expect(seconds, greaterThanOrEqualTo(base * 0.8 - 0.002));
          expect(seconds, lessThanOrEqualTo(base * 1.2 + 0.002));
        }
      }
    });

    test('never waits longer than five minutes', () {
      final Random random = Random(3);
      expect(syncBackoff(9, random: Random(3)), lessThanOrEqualTo(maxSyncBackoff));
      for (final int failures in <int>[10, 20, 100, 100000]) {
        for (int i = 0; i < 20; i++) {
          final Duration wait = syncBackoff(failures, random: random);
          expect(wait, lessThanOrEqualTo(maxSyncBackoff));
          expect(wait, greaterThanOrEqualTo(const Duration(seconds: 240)));
        }
      }
    });

    test('treats zero or negative failures as the first failure', () {
      final Duration wait = syncBackoff(0, random: Random(1));
      expect(wait, lessThanOrEqualTo(const Duration(milliseconds: 1200)));
      expect(wait, greaterThanOrEqualTo(const Duration(milliseconds: 800)));
      expect(syncBackoff(-5, random: Random(1)), wait);
    });

    test('is deterministic for the same random source', () {
      expect(syncBackoff(4, random: Random(11)), syncBackoff(4, random: Random(11)));
    });
  });
}
