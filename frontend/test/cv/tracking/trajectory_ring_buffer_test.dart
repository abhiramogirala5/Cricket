import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/cv/tracking/ball_track_point.dart';
import 'package:gully_umpire/cv/tracking/trajectory_ring_buffer.dart';

void main() {
  group('TrajectoryRingBuffer', () {
    test('keeps the newest points once it is full', () {
      final TrajectoryRingBuffer buffer = TrajectoryRingBuffer(3);
      expect(buffer.isEmpty, isTrue);
      for (int i = 0; i < 5; i++) {
        buffer.push(i * 10, i / 10, 0.5, 0.9);
      }
      expect(buffer.size, 3);
      expect(buffer.isFull, isTrue);
      expect(buffer.toList().map<int>((BallTrackPoint p) => p.timestampMs), <int>[20, 30, 40]);
      expect(buffer.first!.timestampMs, 20);
      expect(buffer.last!.timestampMs, 40);
      expect(buffer.getAt(1)!.x, closeTo(0.3, 1e-12));
      expect(buffer.getAt(3), isNull);
      expect(buffer.getAt(-1), isNull);
    });

    test('add and clear', () {
      final TrajectoryRingBuffer buffer = TrajectoryRingBuffer(4);
      buffer.add(const BallTrackPoint(timestampMs: 5, x: 0.1, y: 0.2, confidence: 0.3));
      expect(buffer.size, 1);
      expect(buffer.last, const BallTrackPoint(timestampMs: 5, x: 0.1, y: 0.2, confidence: 0.3));
      buffer.clear();
      expect(buffer.isEmpty, isTrue);
      expect(buffer.last, isNull);
    });
  });
}
