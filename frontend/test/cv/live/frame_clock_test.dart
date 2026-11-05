import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/cv/live/frame_clock.dart';

double spread(List<int> times) {
  final List<double> gaps = <double>[
    for (int i = 1; i < times.length; i++) (times[i] - times[i - 1]).toDouble(),
  ];
  final double mean = gaps.reduce((double a, double b) => a + b) / gaps.length;
  double sum = 0;
  for (final double gap in gaps) {
    sum += (gap - mean) * (gap - mean);
  }
  return math.sqrt(sum / gaps.length);
}

void main() {
  group('FrameClock', () {
    test('the first time is taken as it is', () {
      final FrameClock clock = FrameClock();

      expect(clock.regularise(12345), 12345);
    });

    test('regular frames keep their times', () {
      final FrameClock clock = FrameClock();

      final List<int> out = <int>[
        for (int i = 0; i < 10; i++) clock.regularise((i * 1000 / 30).round()),
      ];

      for (int i = 0; i < out.length; i++) {
        expect(out[i], closeTo(i * 1000 / 30, 1.0), reason: 'frame $i');
      }
    });

    test('jitter in the arrival times is smoothed away', () {
      final FrameClock clock = FrameClock();
      final math.Random random = math.Random(11);
      final List<int> raw = <int>[];
      final List<int> smooth = <int>[];
      for (int i = 0; i < 120; i++) {
        int time = (i * 1000 / 30 + (random.nextDouble() * 12 - 6)).round();
        if (raw.isNotEmpty && time <= raw.last) {
          time = raw.last + 1;
        }
        raw.add(time);
        smooth.add(clock.regularise(time));
      }

      expect(spread(smooth), lessThan(spread(raw) * 0.5));
    });

    test('the smoothed time never goes backwards', () {
      final FrameClock clock = FrameClock();
      final math.Random random = math.Random(5);
      int previous = clock.regularise(1000);
      int arrival = 1000;
      for (int i = 0; i < 300; i++) {
        arrival += 5 + random.nextInt(60);
        final int next = clock.regularise(arrival);
        expect(next, greaterThan(previous), reason: 'frame $i');
        previous = next;
      }
    });

    test('the same arrival time twice still moves the clock forward', () {
      final FrameClock clock = FrameClock();

      final int a = clock.regularise(100);
      final int b = clock.regularise(100);
      final int c = clock.regularise(100);

      expect(b, greaterThan(a));
      expect(c, greaterThan(b));
    });

    test('a dropped frame leaves a gap of two frame periods', () {
      final FrameClock clock = FrameClock();
      for (int i = 0; i < 10; i++) {
        clock.regularise((i * 1000 / 30).round());
      }

      // Frame 10 never arrived; frame 11 did.
      final int after = clock.regularise((11 * 1000 / 30).round());

      expect(after, closeTo(11 * 1000 / 30, 1.5));
    });

    test('a long stall breaks the lock and the clock starts again from the new time', () {
      final FrameClock clock = FrameClock();
      for (int i = 0; i < 10; i++) {
        clock.regularise((i * 1000 / 30).round());
      }

      // About 30.5 periods later: too far from any expected frame to be a dropped-frame gap.
      final int after = clock.regularise(300 + 1017);

      expect(after, 300 + 1017);
    });

    test('the period follows the real frame rate of the camera', () {
      final FrameClock clock = FrameClock();

      for (int i = 0; i < 300; i++) {
        clock.regularise(i * 40);
      }

      expect(clock.periodMs, closeTo(40, 0.5));
      expect(clock.fps, closeTo(25, 0.5));
    });

    test('the period stays within sensible limits', () {
      final FrameClock clock = FrameClock();
      for (int i = 0; i < 2000; i++) {
        clock.regularise(i * 90);
      }

      expect(clock.periodMs, lessThanOrEqualTo(100));
      expect(clock.periodMs, greaterThanOrEqualTo(8));
    });

    test('reset forgets the lock', () {
      final FrameClock clock = FrameClock();
      clock.regularise(0);
      clock.regularise(33);

      clock.reset();

      expect(clock.regularise(9000), 9000);
    });

    test('an implausible nominal frame interval is refused', () {
      expect(() => FrameClock(nominalIntervalMs: 2), throwsA(isA<AssertionError>()));
      expect(() => FrameClock(nominalIntervalMs: 500), throwsA(isA<AssertionError>()));
    });
  });
}
