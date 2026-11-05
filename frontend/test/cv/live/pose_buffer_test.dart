import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/cv/live/pose_buffer.dart';
import 'package:gully_umpire/cv/pipelines/pose_sample.dart';

import '../../support/replay_fixtures.dart';

void main() {
  group('PoseBuffer', () {
    test('starts empty', () {
      final PoseBuffer buffer = PoseBuffer();

      expect(buffer.isEmpty, isTrue);
      expect(buffer.latest, isNull);
      expect(buffer.window(0, 1000), isEmpty);
    });

    test('keeps samples in time order and knows the newest', () {
      final PoseBuffer buffer = PoseBuffer();

      buffer.add(poseAt(100));
      buffer.add(poseAt(300));
      buffer.add(poseAt(500));

      expect(buffer.length, 3);
      expect(buffer.latest?.timestampMs, 500);
    });

    test('a sample that is not newer than the newest is ignored', () {
      final PoseBuffer buffer = PoseBuffer();
      buffer.add(poseAt(100));
      buffer.add(poseAt(300));

      buffer.add(poseAt(300, centerX: 0.1));
      buffer.add(poseAt(200));

      expect(buffer.length, 2);
      expect(buffer.latest?.centerX, 0.5);
    });

    test('a window includes both ends', () {
      final PoseBuffer buffer = PoseBuffer();
      for (int t = 0; t <= 500; t += 100) {
        buffer.add(poseAt(t));
      }

      expect(buffer.window(100, 300).map((PoseSample s) => s.timestampMs), <int>[100, 200, 300]);
      expect(buffer.window(101, 299).map((PoseSample s) => s.timestampMs), <int>[200]);
      expect(buffer.window(600, 900), isEmpty);
    });

    test('samples much older than the newest are dropped', () {
      final PoseBuffer buffer = PoseBuffer(maxAgeMs: 1000);

      buffer.add(poseAt(0));
      buffer.add(poseAt(500));
      buffer.add(poseAt(1200));

      expect(buffer.window(0, 5000).map((PoseSample s) => s.timestampMs), <int>[500, 1200]);
    });

    test('only the most recent samples are kept when there are too many', () {
      final PoseBuffer buffer = PoseBuffer(maxSamples: 3);

      for (int t = 0; t < 6; t++) {
        buffer.add(poseAt(t * 10));
      }

      expect(buffer.length, 3);
      expect(buffer.window(0, 1000).map((PoseSample s) => s.timestampMs), <int>[30, 40, 50]);
    });

    test('clear forgets everything', () {
      final PoseBuffer buffer = PoseBuffer();
      buffer.add(poseAt(0));

      buffer.clear();

      expect(buffer.isEmpty, isTrue);
      buffer.add(poseAt(0));
      expect(buffer.length, 1);
    });
  });
}
