import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/cv/vision/background_model.dart';
import 'package:gully_umpire/cv/vision/luma_frame.dart';

const int w = 16;
const int h = 16;

/// A 16 x 16 picture of one brightness, with an optional square of another brightness.
LumaFrame picture(
  int base, {
  int square = 0,
  int squareLeft = 4,
  int squareTop = 4,
  int squareSize = 3,
  int t = 0,
}) {
  final Uint8List pixels = Uint8List(w * h)..fillRange(0, w * h, base);
  if (square > 0) {
    for (int y = squareTop; y < squareTop + squareSize; y++) {
      for (int x = squareLeft; x < squareLeft + squareSize; x++) {
        pixels[y * w + x] = square;
      }
    }
  }
  return LumaFrame(width: w, height: h, timestampMs: t, pixels: pixels);
}

/// Feeds [count] identical quiet pictures.
BackgroundState quiet(BackgroundModel model, int count, {int base = 100}) {
  BackgroundState state = BackgroundState.warmup;
  for (int i = 0; i < count; i++) {
    state = model.update(picture(base, t: i * 33));
  }
  return state;
}

void main() {
  group('warming up', () {
    test('the first two pictures only teach, the third is the first valid one', () {
      final BackgroundModel model = BackgroundModel();

      expect(model.update(picture(100)), BackgroundState.warmup);
      expect(model.update(picture(100)), BackgroundState.warmup);
      expect(model.update(picture(100)), BackgroundState.ok);
      expect(model.update(picture(100)), BackgroundState.ok);
    });

    test('the motion picture is not available before the first frame', () {
      expect(() => BackgroundModel().diff, throwsStateError);
    });

    test('reset forgets the scene', () {
      final BackgroundModel model = BackgroundModel();
      quiet(model, 5);

      model.reset();

      expect(model.update(picture(100)), BackgroundState.warmup);
    });

    test('a picture of another size starts the model again', () {
      final BackgroundModel model = BackgroundModel();
      quiet(model, 5);

      final LumaFrame larger = LumaFrame(
        width: 20,
        height: 10,
        timestampMs: 0,
        pixels: Uint8List(200),
      );

      expect(model.update(larger), BackgroundState.warmup);
      expect(model.width, 20);
      expect(model.height, 10);
    });
  });

  group('a quiet scene', () {
    test('has no movement', () {
      final BackgroundModel model = BackgroundModel();

      expect(quiet(model, 6), BackgroundState.ok);

      expect(model.diff.every((int v) => v == 0), isTrue);
      expect(model.foregroundFraction, 0);
      expect(model.threshold, model.minThreshold);
    });
  });

  group('movement', () {
    test('a bright square stands out by exactly its brightness difference', () {
      final BackgroundModel model = BackgroundModel();
      quiet(model, 5);

      final BackgroundState state = model.update(picture(100, square: 200));

      expect(state, BackgroundState.ok);
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final bool inside = x >= 4 && x < 7 && y >= 4 && y < 7;
          expect(model.diff[y * w + x], inside ? 100 : 0, reason: 'pixel ($x, $y)');
        }
      }
      expect(model.foregroundFraction, closeTo(9 / 256, 1e-12));
    });

    test('a dark square stands out as well', () {
      final BackgroundModel model = BackgroundModel();
      quiet(model, 5);

      model.update(picture(100, square: 20));

      expect(model.diff[5 * w + 5], 80);
    });

    test('something that stands out is taken into the background only slowly', () {
      final BackgroundModel model = BackgroundModel();
      quiet(model, 5);

      model.update(picture(100, square: 200));
      model.update(picture(100, square: 200));

      // After the first picture the background moved by (1600 + 32) >> 6 = 25 sixteenths, so the
      // second picture differs by (3200 - 1625 + 8) >> 4 = 98.
      expect(model.diff[5 * w + 5], 98);
    });

    test('movement below the threshold is treated as background', () {
      final BackgroundModel model = BackgroundModel();
      quiet(model, 5);

      model.update(picture(100, square: 108));

      expect(model.diff[5 * w + 5], 8);
      expect(model.foregroundFraction, 0);
    });
  });

  group('changes of light', () {
    test('a sudden brightening of the whole picture is soon taken away', () {
      final BackgroundModel model = BackgroundModel();
      quiet(model, 5);

      model.update(picture(110));
      final int first = model.diff[0];
      model.update(picture(110));
      final int second = model.diff[0];
      model.update(picture(110));
      final int third = model.diff[0];

      // 10, then 9 - 5 = 4, then 9 - 7 = 2: the average brightness offset is measured and removed.
      expect(first, 10);
      expect(second, 4);
      expect(third, 2);
    });
  });

  group('the whole picture changes', () {
    test('after five such pictures in a row the model starts again', () {
      final BackgroundModel model = BackgroundModel();
      quiet(model, 5);

      final List<BackgroundState> states = <BackgroundState>[
        for (int i = 0; i < 5; i++) model.update(picture(250)),
      ];

      expect(states.sublist(0, 4), everyElement(BackgroundState.ok));
      expect(states.last, BackgroundState.restarted);
      // The picture that restarted the model is the first of the new scene.
      expect(model.update(picture(250)), BackgroundState.warmup);
      expect(model.update(picture(250)), BackgroundState.ok);
    });

    test('a short flash does not restart the model', () {
      final BackgroundModel model = BackgroundModel();
      quiet(model, 5);

      for (int i = 0; i < 3; i++) {
        expect(model.update(picture(250)), isNot(BackgroundState.restarted));
      }
      expect(model.update(picture(100)), isNot(BackgroundState.restarted));
      for (int i = 0; i < 3; i++) {
        expect(model.update(picture(250)), isNot(BackgroundState.restarted));
      }
    });
  });

  group('noise', () {
    test('a noisy picture raises the threshold, within its limits', () {
      final BackgroundModel model = BackgroundModel();
      final math.Random random = math.Random(3);
      for (int frame = 0; frame < 60; frame++) {
        final Uint8List pixels = Uint8List(w * h);
        for (int i = 0; i < pixels.length; i++) {
          pixels[i] = 100 + random.nextInt(17) - 8;
        }
        model.update(LumaFrame(width: w, height: h, timestampMs: frame * 33, pixels: pixels));
      }

      expect(model.noise, greaterThan(2.5));
      expect(model.threshold, greaterThan(model.minThreshold));
      expect(model.threshold, lessThanOrEqualTo(model.maxThreshold));
    });
  });
}
