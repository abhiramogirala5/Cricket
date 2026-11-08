import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/cv/geometry/point2d.dart';
import 'package:gully_umpire/cv/scene/optical_wicket_tracker.dart';
import 'package:gully_umpire/cv/vision/luma_frame.dart';
import 'package:gully_umpire/domain/decisions/wicket_family.dart';

void main() {
  group('OpticalWicketTracker', () {
    late OpticalWicketTracker tracker;

    setUp(() {
      tracker = OpticalWicketTracker(searchRadiusPixels: 12, patchRadius: 4);
    });

    test('detectOrRefineWicket returns valid corners on low contrast fallback', () {
      final Uint8List blank = Uint8List(160 * 120);
      final LumaFrame frame = LumaFrame(
        width: 160,
        height: 120,
        timestampMs: 100,
        pixels: blank,
      );

      final OpticalWicketResult result = tracker.detectOrRefineWicket(
        frame: frame,
        searchCenter: const Point2D(0.50, 0.65),
        family: WicketFamily.traditionalStumps,
      );

      expect(result.corners, hasLength(4));
      expect(result.isOpticallyRefined, isFalse);
      expect(result.confidence, greaterThanOrEqualTo(0.50));
      expect(result.family, WicketFamily.traditionalStumps);
    });

    test('detectOrRefineWicket refines bounds when vertical edges of stumps exist', () {
      const int w = 200;
      const int h = 200;
      final Uint8List pixels = Uint8List(w * h);

      // Draw 3 vertical bright bars (stumps: off, middle, leg) between x=90 and x=110, y=70 to y=130
      for (int y = 70; y <= 130; y++) {
        for (final int stumpX in <int>[92, 100, 108]) {
          for (int dx = -1; dx <= 1; dx++) {
            pixels[y * w + stumpX + dx] = 220;
          }
        }
      }

      final LumaFrame frame = LumaFrame(
        width: w,
        height: h,
        timestampMs: 100,
        pixels: pixels,
      );

      final OpticalWicketResult result = tracker.detectOrRefineWicket(
        frame: frame,
        searchCenter: const Point2D(0.50, 0.50),
        family: WicketFamily.traditionalStumps,
      );

      expect(result.corners, hasLength(4));
      expect(result.isOpticallyRefined, isTrue);
      expect(result.confidence, greaterThan(0.85));

      // Left edge should be near x=0.45 (90/200) and right edge near x=0.55 (110/200)
      final double midX = (result.corners[0].x + result.corners[1].x) / 2;
      expect(midX, closeTo(0.50, 0.05));
    });

    test('spatial anchor tracking detects camera ego-motion and shifts corners', () {
      const int w = 160;
      const int h = 120;
      final Uint8List frame1Pixels = Uint8List(w * h);

      // Create a visual target (stump cluster and pitch texture)
      for (int y = 40; y <= 80; y++) {
        for (int x = 70; x <= 90; x++) {
          frame1Pixels[y * w + x] = ((x * 13 + y * 7) % 200) + 30;
        }
      }

      final LumaFrame frame1 = LumaFrame(
        width: w,
        height: h,
        timestampMs: 100,
        pixels: frame1Pixels,
      );

      final List<Point2D> initialCorners = <Point2D>[
        const Point2D(0.44, 0.35),
        const Point2D(0.56, 0.35),
        const Point2D(0.56, 0.65),
        const Point2D(0.44, 0.65),
      ];

      tracker.lockAnchor(initialCorners, frame1);
      expect(tracker.isAnchorLocked, isTrue);

      // Frame 2: The camera panned to the right by 6 pixels horizontally,
      // so the scene shifted left by -6 pixels (dx = -6, dy = 0)
      const int shiftX = -6;
      final Uint8List frame2Pixels = Uint8List(w * h);
      for (int y = 40; y <= 80; y++) {
        for (int x = 70; x <= 90; x++) {
          final int newX = x + shiftX;
          if (newX >= 0 && newX < w) {
            frame2Pixels[y * w + newX] = frame1Pixels[y * w + x];
          }
        }
      }

      final LumaFrame frame2 = LumaFrame(
        width: w,
        height: h,
        timestampMs: 133,
        pixels: frame2Pixels,
      );

      final AnchorTrackingResult tracking = tracker.updateAnchor(frame2);

      expect(tracking.hasMoved, isTrue);
      expect(tracking.confidence, greaterThan(0.50));

      // Initial midX was 0.50. After camera motion of -6px (-6/160 = -0.0375),
      // the tracked polygon must have shifted left by ~0.0375 to stay on the stumps!
      final double newMidX = (tracking.corners[0].x + tracking.corners[1].x) / 2;
      expect(newMidX, closeTo(0.50 - 0.0375, 0.015));

      // Test unlocking
      tracker.unlockAnchor();
      expect(tracker.isAnchorLocked, isFalse);
    });
  });
}

