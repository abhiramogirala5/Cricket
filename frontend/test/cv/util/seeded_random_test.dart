import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/cv/util/seeded_random.dart';

void main() {
  group('SeededRandom', () {
    test('gives the same numbers for the same seed (golden values)', () {
      final SeededRandom random = SeededRandom(1);
      final List<int> values = <int>[for (int i = 0; i < 5; i++) random.nextRaw()];
      expect(values, <int>[255363033, 72832163, 250610034, 421567663, 2085105348]);
    });

    test('different seeds give different numbers', () {
      final SeededRandom first = SeededRandom(1);
      final SeededRandom second = SeededRandom(2);
      final List<double> a = <double>[first.nextDouble(), first.nextDouble(), first.nextDouble()];
      final List<double> b = <double>[second.nextDouble(), second.nextDouble(), second.nextDouble()];
      expect(a, isNot(equals(b)));
    });

    test('derive is deterministic and depends on the salt', () {
      final SeededRandom first = SeededRandom.derive(7, 100);
      expect(first.nextDouble(), closeTo(0.472757, 1e-6));
      expect(first.nextDouble(), closeTo(0.451562, 1e-6));
      expect(first.nextDouble(), closeTo(0.358864, 1e-6));
      expect(
        SeededRandom.derive(7, 100).nextDouble(),
        isNot(equals(SeededRandom.derive(7, 101).nextDouble())),
      );
    });

    test('nextDouble stays in [0, 1)', () {
      final SeededRandom random = SeededRandom(99);
      for (int i = 0; i < 2000; i++) {
        final double value = random.nextDouble();
        expect(value, greaterThanOrEqualTo(0));
        expect(value, lessThan(1));
      }
    });

    test('nextRange and nextInt respect their bounds', () {
      final SeededRandom random = SeededRandom(5);
      for (int i = 0; i < 500; i++) {
        final double value = random.nextRange(0.35, 0.65);
        expect(value, inInclusiveRange(0.35, 0.65));
        expect(random.nextInt(10), inInclusiveRange(0, 9));
      }
      expect(() => random.nextInt(0), throwsArgumentError);
    });

    test('nextBool handles the extreme probabilities', () {
      final SeededRandom random = SeededRandom(3);
      for (int i = 0; i < 200; i++) {
        expect(random.nextBool(0), isFalse);
        expect(random.nextBool(1), isTrue);
      }
    });

    test('nextGaussian has mean near 0 and standard deviation near 1', () {
      final SeededRandom random = SeededRandom(42);
      const int count = 20000;
      double sum = 0;
      final List<double> values = <double>[];
      for (int i = 0; i < count; i++) {
        final double value = random.nextGaussian();
        values.add(value);
        sum += value;
      }
      final double mean = sum / count;
      double squares = 0;
      for (final double value in values) {
        squares += (value - mean) * (value - mean);
      }
      final double deviation = math.sqrt(squares / count);
      expect(mean.abs(), lessThan(0.05));
      expect(deviation, inInclusiveRange(0.95, 1.05));
    });
  });
}
