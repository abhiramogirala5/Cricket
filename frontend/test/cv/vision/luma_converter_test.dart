import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/cv/vision/luma_frame.dart';

/// A 6 x 4 picture with the value `y * 10 + x + 1` at column x, row y, stored with 2 padding
/// bytes (value 255) at the end of every row, so a row is 8 bytes apart from the next.
Uint8List padded6x4() {
  final Uint8List bytes = Uint8List(4 * 8)..fillRange(0, 32, 255);
  for (int y = 0; y < 4; y++) {
    for (int x = 0; x < 6; x++) {
      bytes[y * 8 + x] = y * 10 + x + 1;
    }
  }
  return bytes;
}

int sourceValue(int x, int y) => y * 10 + x + 1;

/// The value at upright position (ux, uy) when the 6 x 4 picture is turned clockwise by [turn].
int expectedUpright(int turn, int ux, int uy) {
  switch (turn) {
    case 90:
      return sourceValue(uy, 3 - ux);
    case 180:
      return sourceValue(5 - ux, 3 - uy);
    case 270:
      return sourceValue(5 - uy, ux);
    default:
      return sourceValue(ux, uy);
  }
}

void main() {
  group('LumaConverter.outputSize', () {
    LumaSize size(int w, int h, int rotation, int target) => LumaConverter.outputSize(
          srcWidth: w,
          srcHeight: h,
          rotationDegrees: rotation,
          targetLongSide: target,
        );

    test('shrinks by a whole factor so that the long side is about the target', () {
      expect(size(1280, 720, 0, 640).factor, 2);
      expect(size(1280, 720, 0, 640).width, 640);
      expect(size(1280, 720, 0, 640).height, 360);
      expect(size(1920, 1080, 0, 640).factor, 3);
      expect(size(1920, 1080, 0, 640).width, 640);
      expect(size(1920, 1080, 0, 640).height, 360);
      expect(size(1000, 500, 0, 640).factor, 2);
      expect(size(1000, 500, 0, 640).width, 500);
      expect(size(1000, 500, 0, 640).height, 250);
    });

    test('a picture that is not larger than the target is not shrunk', () {
      final LumaSize result = size(640, 480, 0, 640);
      expect(result.factor, 1);
      expect(result.width, 640);
      expect(result.height, 480);
      expect(size(16, 12, 0, 640).factor, 1);
    });

    test('a quarter turn swaps the sides of the output', () {
      final LumaSize result = size(1280, 720, 90, 640);
      expect(result.width, 360);
      expect(result.height, 640);
      expect(size(1280, 720, 270, 640).width, 360);
      expect(size(1280, 720, 180, 640).width, 640);
    });

    test('a negative turn is the same as the matching positive one', () {
      final LumaSize result = size(1280, 720, -90, 640);
      expect(result.width, 360);
      expect(result.height, 640);
    });

    test('a target of zero means no shrinking', () {
      expect(size(1280, 720, 0, 0).factor, 1);
    });
  });

  group('LumaConverter.convert', () {
    for (final int turn in <int>[0, 90, 180, 270]) {
      test('turns the picture $turn degrees clockwise and ignores the row padding', () {
        final bool swapped = turn == 90 || turn == 270;
        final int width = swapped ? 4 : 6;
        final int height = swapped ? 6 : 4;
        final Uint8List out = Uint8List(width * height);

        LumaConverter.convert(
          source: padded6x4(),
          srcWidth: 6,
          srcHeight: 4,
          rowStride: 8,
          rotationDegrees: turn,
          size: LumaSize(width: width, height: height, factor: 1),
          out: out,
        );

        for (int uy = 0; uy < height; uy++) {
          for (int ux = 0; ux < width; ux++) {
            expect(
              out[uy * width + ux],
              expectedUpright(turn, ux, uy),
              reason: 'turn $turn at ($ux, $uy)',
            );
          }
        }
      });
    }

    test('a quarter turn puts the top row of the camera picture down the right-hand side', () {
      final Uint8List out = Uint8List(4 * 6);

      LumaConverter.convert(
        source: padded6x4(),
        srcWidth: 6,
        srcHeight: 4,
        rowStride: 8,
        rotationDegrees: 90,
        size: const LumaSize(width: 4, height: 6, factor: 1),
        out: out,
      );

      expect(<int>[for (int y = 0; y < 6; y++) out[y * 4 + 3]], <int>[1, 2, 3, 4, 5, 6]);
    });

    test('shrinking averages each block of pixels, rounding to the nearest', () {
      final Uint8List source = Uint8List.fromList(<int>[
        10, 20, 30, 40, //
        10, 20, 30, 40,
        50, 60, 70, 80,
        50, 60, 70, 80,
      ]);
      final Uint8List out = Uint8List(4);

      LumaConverter.convert(
        source: source,
        srcWidth: 4,
        srcHeight: 4,
        rowStride: 4,
        rotationDegrees: 0,
        size: const LumaSize(width: 2, height: 2, factor: 2),
        out: out,
      );

      // (10+20+10+20+2)/4 = 15, (30+40+30+40+2)/4 = 35, (50+60+50+60+2)/4 = 55, (70+80+70+80+2)/4 = 75
      expect(out, <int>[15, 35, 55, 75]);
    });

    test('rejects a turn that is not a multiple of 90', () {
      expect(
        () => LumaConverter.convert(
          source: padded6x4(),
          srcWidth: 6,
          srcHeight: 4,
          rowStride: 8,
          rotationDegrees: 45,
          size: const LumaSize(width: 6, height: 4, factor: 1),
          out: Uint8List(24),
        ),
        throwsArgumentError,
      );
    });

    test('rejects a row stride smaller than the width', () {
      expect(
        () => LumaConverter.convert(
          source: padded6x4(),
          srcWidth: 6,
          srcHeight: 4,
          rowStride: 5,
          rotationDegrees: 0,
          size: const LumaSize(width: 6, height: 4, factor: 1),
          out: Uint8List(24),
        ),
        throwsArgumentError,
      );
    });

    test('rejects a source that is too short', () {
      expect(
        () => LumaConverter.convert(
          source: Uint8List(29), // needs (4 - 1) * 8 + 6 = 30
          srcWidth: 6,
          srcHeight: 4,
          rowStride: 8,
          rotationDegrees: 0,
          size: const LumaSize(width: 6, height: 4, factor: 1),
          out: Uint8List(24),
        ),
        throwsArgumentError,
      );
    });

    test('rejects an output buffer that is too small', () {
      expect(
        () => LumaConverter.convert(
          source: padded6x4(),
          srcWidth: 6,
          srcHeight: 4,
          rowStride: 8,
          rotationDegrees: 0,
          size: const LumaSize(width: 6, height: 4, factor: 1),
          out: Uint8List(23),
        ),
        throwsArgumentError,
      );
    });

    test('rejects an output size that does not fit the picture', () {
      expect(
        () => LumaConverter.convert(
          source: padded6x4(),
          srcWidth: 6,
          srcHeight: 4,
          rowStride: 8,
          rotationDegrees: 0,
          size: const LumaSize(width: 7, height: 4, factor: 1),
          out: Uint8List(28),
        ),
        throwsArgumentError,
      );
    });
  });

  group('LumaConverter.toFrame', () {
    test('makes a frame of the right size and time', () {
      final Uint8List source = Uint8List(16 * 8);
      for (int i = 0; i < source.length; i++) {
        source[i] = i % 200;
      }

      final LumaFrame frame = LumaConverter.toFrame(
        source: source,
        srcWidth: 16,
        srcHeight: 8,
        rowStride: 16,
        rotationDegrees: 90,
        targetLongSide: 640,
        timestampMs: 1234,
      );

      expect(frame.width, 8);
      expect(frame.height, 16);
      expect(frame.timestampMs, 1234);
      expect(frame.pixels.length, 8 * 16);
      expect(frame.aspectRatio, closeTo(0.5, 1e-12));
    });
  });
}
