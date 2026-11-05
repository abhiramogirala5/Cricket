import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/cv/pipelines/frame_schedule.dart';

void main() {
  group('FrameSchedule', () {
    test('the first frame is always taken', () {
      expect(FrameSchedule(100).take(12345), isTrue);
    });

    test('frames closer together than the interval are skipped', () {
      final FrameSchedule schedule = FrameSchedule(100);
      expect(schedule.take(0), isTrue);
      expect(schedule.take(30), isFalse);
      expect(schedule.take(60), isFalse);
      expect(schedule.take(100), isTrue);
      expect(schedule.take(130), isFalse);
      expect(schedule.take(200), isTrue);
    });

    test('a frame slightly before the due time is accepted (25% tolerance)', () {
      final FrameSchedule schedule = FrameSchedule(100);
      expect(schedule.take(0), isTrue);
      expect(schedule.take(74), isFalse);
      expect(schedule.take(75), isTrue);
    });

    test('a 30 fps camera gives a steady 100 ms schedule', () {
      final FrameSchedule schedule = FrameSchedule(100);
      final List<int> taken = <int>[];
      for (int i = 0; i < 31; i++) {
        final int ts = (i * 1000 / 30).round();
        if (schedule.take(ts)) {
          taken.add(ts);
        }
      }
      expect(taken, <int>[0, 100, 200, 300, 400, 500, 600, 700, 800, 900, 1000]);
    });

    test('a 60 fps camera feeds a 42 ms detector without drifting', () {
      final FrameSchedule schedule = FrameSchedule(42);
      int taken = 0;
      for (int i = 0; i < 61; i++) {
        if (schedule.take((i * 1000 / 60).round())) {
          taken += 1;
        }
      }
      // One second at about 24 runs per second.
      expect(taken, inInclusiveRange(22, 26));
    });

    test('after a long pause it starts again instead of catching up', () {
      final FrameSchedule schedule = FrameSchedule(100);
      expect(schedule.take(0), isTrue);
      expect(schedule.take(100), isTrue);
      expect(schedule.take(1000), isTrue);
      // Not a burst of catch-up runs.
      expect(schedule.take(1030), isFalse);
      expect(schedule.take(1060), isFalse);
      expect(schedule.take(1100), isTrue);
    });

    test('an interval of zero never takes a frame', () {
      final FrameSchedule schedule = FrameSchedule(0);
      expect(schedule.take(0), isFalse);
      expect(schedule.take(1000), isFalse);
    });
  });
}
