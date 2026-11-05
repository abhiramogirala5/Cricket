import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/cv/live/frame_ring.dart';
import 'package:gully_umpire/cv/vision/luma_frame.dart';

LumaFrame frame(int t, {int fill = 0, int width = 4, int height = 3}) {
  return LumaFrame(
    width: width,
    height: height,
    timestampMs: t,
    pixels: Uint8List(width * height)..fillRange(0, width * height, fill),
  );
}

void main() {
  group('FrameRing', () {
    test('starts empty', () {
      final FrameRing ring = FrameRing(capacity: 3, width: 4, height: 3);

      expect(ring.isEmpty, isTrue);
      expect(ring.length, 0);
      expect(ring.window(0, 1000), isEmpty);
    });

    test('keeps pictures in the order they were pushed', () {
      final FrameRing ring = FrameRing(capacity: 5, width: 4, height: 3);

      for (int i = 0; i < 3; i++) {
        expect(ring.push(frame(i * 33, fill: i + 1)), isTrue);
      }

      final List<LumaFrame> frames = ring.window(0, 1000);
      expect(ring.length, 3);
      expect(frames.map((LumaFrame f) => f.timestampMs), <int>[0, 33, 66]);
      expect(frames.map((LumaFrame f) => f.pixels.first), <int>[1, 2, 3]);
      expect(frames.first.width, 4);
      expect(frames.first.height, 3);
    });

    test('when it is full the oldest picture is overwritten', () {
      final FrameRing ring = FrameRing(capacity: 3, width: 4, height: 3);

      for (int i = 0; i < 5; i++) {
        ring.push(frame(i * 10, fill: i));
      }

      final List<LumaFrame> frames = ring.window(0, 1000);
      expect(ring.length, 3);
      expect(frames.map((LumaFrame f) => f.timestampMs), <int>[20, 30, 40]);
      expect(frames.map((LumaFrame f) => f.pixels.first), <int>[2, 3, 4]);
    });

    test('a window includes both ends and nothing outside', () {
      final FrameRing ring = FrameRing(capacity: 10, width: 4, height: 3);
      for (int i = 0; i < 6; i++) {
        ring.push(frame(i * 10));
      }

      expect(ring.window(10, 30).map((LumaFrame f) => f.timestampMs), <int>[10, 20, 30]);
      expect(ring.window(11, 29).map((LumaFrame f) => f.timestampMs), <int>[20]);
      expect(ring.window(100, 200), isEmpty);
    });

    test('stores a copy, so changing the original later changes nothing', () {
      final FrameRing ring = FrameRing(capacity: 3, width: 4, height: 3);
      final LumaFrame original = frame(0, fill: 50);

      ring.push(original);
      original.pixels.fillRange(0, original.pixels.length, 99);

      expect(ring.window(0, 0).single.pixels.every((int v) => v == 50), isTrue);
    });

    test('a picture of another size is refused', () {
      final FrameRing ring = FrameRing(capacity: 3, width: 4, height: 3);

      expect(ring.push(frame(0, width: 5, height: 3)), isFalse);
      expect(ring.push(frame(0, width: 4, height: 4)), isFalse);
      expect(ring.length, 0);
    });

    test('clear forgets every picture but can be used again', () {
      final FrameRing ring = FrameRing(capacity: 3, width: 4, height: 3);
      ring.push(frame(0));
      ring.push(frame(10));

      ring.clear();
      expect(ring.isEmpty, isTrue);
      expect(ring.window(0, 100), isEmpty);

      ring.push(frame(50, fill: 7));
      expect(ring.window(0, 100).single.timestampMs, 50);
    });

    test('capacityFor fits as many pictures as the budget allows, at least eight', () {
      expect(FrameRing.capacityFor(maxBytes: 1000000, width: 640, height: 360), 8);
      expect(FrameRing.capacityFor(maxBytes: 3000000, width: 640, height: 360), 13);
      expect(FrameRing.capacityFor(maxBytes: 24 * 1024 * 1024, width: 360, height: 640), 109);
      expect(FrameRing.capacityFor(maxBytes: 100, width: 640, height: 360), 8);
      expect(FrameRing.capacityFor(maxBytes: 100, width: 0, height: 0), 8);
    });
  });
}
