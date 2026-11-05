import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/cv/live/nv21_crop.dart';
import 'package:gully_umpire/cv/vision/luma_frame.dart';

const int rawWidth = 64;
const int rawHeight = 48;

int yValue(int x, int y) => y * 4 + x + 1;

int chromaValue(int row, int x) => 10 + row + x;

/// A 64 x 48 NV21 picture whose rows are [stride] bytes apart. Padding bytes are 255.
Uint8List nv21({int stride = rawWidth}) {
  final Uint8List bytes = Uint8List(stride * rawHeight * 3 ~/ 2)..fillRange(0, stride * rawHeight * 3 ~/ 2, 255);
  for (int y = 0; y < rawHeight; y++) {
    for (int x = 0; x < rawWidth; x++) {
      bytes[y * stride + x] = yValue(x, y);
    }
  }
  final int chromaStart = stride * rawHeight;
  for (int row = 0; row < rawHeight ~/ 2; row++) {
    for (int x = 0; x < rawWidth; x++) {
      bytes[chromaStart + row * stride + x] = chromaValue(row, x);
    }
  }
  return bytes;
}

void main() {
  group('Nv21Cropper.uprightSize', () {
    test('a quarter turn swaps the sides', () {
      expect(Nv21Cropper.uprightSize(1280, 720, 0), (width: 1280, height: 720));
      expect(Nv21Cropper.uprightSize(1280, 720, 180), (width: 1280, height: 720));
      expect(Nv21Cropper.uprightSize(1280, 720, 90), (width: 720, height: 1280));
      expect(Nv21Cropper.uprightSize(1280, 720, 270), (width: 720, height: 1280));
      expect(Nv21Cropper.uprightSize(1280, 720, -90), (width: 720, height: 1280));
    });
  });

  group('Nv21Cropper.rawRectFor', () {
    const PixelRect upright = PixelRect(100, 200, 300, 600);

    test('without a turn the rectangle is the same', () {
      expect(
        Nv21Cropper.rawRectFor(upright: upright, rawWidth: 1280, rawHeight: 720, rotationDegrees: 0),
        upright,
      );
    });

    test('for a camera picture that is turned 90 degrees to be upright', () {
      expect(
        Nv21Cropper.rawRectFor(upright: upright, rawWidth: 1280, rawHeight: 720, rotationDegrees: 90),
        const PixelRect(200, 420, 600, 620),
      );
    });

    test('for 180 degrees', () {
      expect(
        Nv21Cropper.rawRectFor(upright: upright, rawWidth: 1280, rawHeight: 720, rotationDegrees: 180),
        const PixelRect(980, 120, 1180, 520),
      );
    });

    test('for 270 degrees', () {
      expect(
        Nv21Cropper.rawRectFor(upright: upright, rawWidth: 1280, rawHeight: 720, rotationDegrees: 270),
        const PixelRect(680, 100, 1080, 300),
      );
    });

    test('is made even-sized and even-aligned, as NV21 colour needs', () {
      expect(
        Nv21Cropper.rawRectFor(
          upright: const PixelRect(101, 201, 301, 601),
          rawWidth: 1280,
          rawHeight: 720,
          rotationDegrees: 0,
        ),
        const PixelRect(100, 200, 302, 602),
      );
    });

    test('is limited to the camera picture', () {
      expect(
        Nv21Cropper.rawRectFor(
          upright: const PixelRect(-10, -10, 2000, 2000),
          rawWidth: 1280,
          rawHeight: 720,
          rotationDegrees: 0,
        ),
        const PixelRect(0, 0, 1280, 720),
      );
    });

    test('never reaches past an odd-sized picture', () {
      final PixelRect rect = Nv21Cropper.rawRectFor(
        upright: const PixelRect(0, 0, 641, 481),
        rawWidth: 641,
        rawHeight: 481,
        rotationDegrees: 0,
      );

      expect(rect.right, 640);
      expect(rect.bottom, 480);
    });

    test('agrees with the picture converter about where the pixels are', () {
      // The upright pixel (ux, uy) of a picture turned by `turn` comes from this raw pixel.
      for (final int turn in <int>[90, 180, 270]) {
        final PixelRect raw = Nv21Cropper.rawRectFor(
          upright: upright,
          rawWidth: 1280,
          rawHeight: 720,
          rotationDegrees: turn,
        );
        for (final ({int x, int y}) corner in <({int x, int y})>[
          (x: 100, y: 200),
          (x: 299, y: 200),
          (x: 100, y: 599),
          (x: 299, y: 599),
        ]) {
          final ({int x, int y}) source = switch (turn) {
            90 => (x: corner.y, y: 719 - corner.x),
            180 => (x: 1279 - corner.x, y: 719 - corner.y),
            _ => (x: 1279 - corner.y, y: corner.x),
          };
          expect(source.x, inInclusiveRange(raw.left, raw.right - 1), reason: 'turn $turn x');
          expect(source.y, inInclusiveRange(raw.top, raw.bottom - 1), reason: 'turn $turn y');
        }
      }
    });
  });

  group('Nv21Cropper.uprightRectFor', () {
    test('is the opposite of rawRectFor for aligned rectangles', () {
      const PixelRect upright = PixelRect(100, 200, 300, 600);
      for (final int turn in <int>[0, 90, 180, 270]) {
        final PixelRect raw = Nv21Cropper.rawRectFor(
          upright: upright,
          rawWidth: 1280,
          rawHeight: 720,
          rotationDegrees: turn,
        );

        expect(
          Nv21Cropper.uprightRectFor(raw: raw, rawWidth: 1280, rawHeight: 720, rotationDegrees: turn),
          upright,
          reason: 'turn $turn',
        );
      }
    });
  });

  group('Nv21Cropper.crop', () {
    test('copies the brightness and colour of the region', () {
      final Nv21Crop? crop = Nv21Cropper.crop(
        source: nv21(),
        rawWidth: rawWidth,
        rawHeight: rawHeight,
        rowStride: rawWidth,
        rotationDegrees: 0,
        upright: const PixelRect(16, 8, 48, 40),
      );

      expect(crop, isNotNull);
      expect(crop!.width, 32);
      expect(crop.height, 32);
      expect(crop.upright, const PixelRect(16, 8, 48, 40));
      expect(crop.bytes.length, 32 * 32 * 3 ~/ 2);
      for (int row = 0; row < 32; row++) {
        for (int col = 0; col < 32; col++) {
          expect(crop.bytes[row * 32 + col], yValue(16 + col, 8 + row), reason: 'Y ($col, $row)');
        }
      }
      for (int row = 0; row < 16; row++) {
        for (int col = 0; col < 32; col++) {
          expect(
            crop.bytes[32 * 32 + row * 32 + col],
            chromaValue(4 + row, 16 + col),
            reason: 'colour ($col, $row)',
          );
        }
      }
    });

    test('reads rows that are further apart than the picture is wide', () {
      final Nv21Crop plain = Nv21Cropper.crop(
        source: nv21(),
        rawWidth: rawWidth,
        rawHeight: rawHeight,
        rowStride: rawWidth,
        rotationDegrees: 0,
        upright: const PixelRect(16, 8, 48, 40),
      )!;

      final Nv21Crop padded = Nv21Cropper.crop(
        source: nv21(stride: 72),
        rawWidth: rawWidth,
        rawHeight: rawHeight,
        rowStride: 72,
        rotationDegrees: 0,
        upright: const PixelRect(16, 8, 48, 40),
      )!;

      expect(padded.bytes, plain.bytes);
    });

    test('a turned camera gives the same pixels and reports where the cut-out lies', () {
      // Upright picture is 48 wide and 64 tall when the camera picture is turned by 90 degrees.
      final Nv21Crop crop = Nv21Cropper.crop(
        source: nv21(),
        rawWidth: rawWidth,
        rawHeight: rawHeight,
        rowStride: rawWidth,
        rotationDegrees: 90,
        upright: const PixelRect(8, 16, 40, 48),
      )!;

      // That upright rectangle is the raw rectangle (16, 8, 48, 40), as in the straight case.
      expect(crop.width, 32);
      expect(crop.height, 32);
      expect(crop.upright, const PixelRect(8, 16, 40, 48));
      expect(crop.bytes[0], yValue(16, 8));
      expect(crop.bytes[31], yValue(47, 8));
      expect(crop.bytes[31 * 32], yValue(16, 39));
    });

    test('a cut-out smaller than 16 pixels is refused', () {
      expect(
        Nv21Cropper.crop(
          source: nv21(),
          rawWidth: rawWidth,
          rawHeight: rawHeight,
          rowStride: rawWidth,
          rotationDegrees: 0,
          upright: const PixelRect(16, 8, 24, 16),
        ),
        isNull,
      );
    });

    test('a source that is too short is refused', () {
      expect(
        Nv21Cropper.crop(
          source: Uint8List(rawWidth * rawHeight),
          rawWidth: rawWidth,
          rawHeight: rawHeight,
          rowStride: rawWidth,
          rotationDegrees: 0,
          upright: const PixelRect(16, 8, 48, 40),
        ),
        isNull,
      );
    });

    test('a row stride smaller than the width is refused', () {
      expect(
        Nv21Cropper.crop(
          source: nv21(),
          rawWidth: rawWidth,
          rawHeight: rawHeight,
          rowStride: 60,
          rotationDegrees: 0,
          upright: const PixelRect(16, 8, 48, 40),
        ),
        isNull,
      );
    });

    test('the cut-out can be turned into a brightness picture', () {
      final Nv21Crop crop = Nv21Cropper.crop(
        source: nv21(),
        rawWidth: rawWidth,
        rawHeight: rawHeight,
        rowStride: rawWidth,
        rotationDegrees: 0,
        upright: const PixelRect(16, 8, 48, 40),
      )!;

      final LumaFrame frame = LumaConverter.toFrame(
        source: crop.bytes,
        srcWidth: crop.width,
        srcHeight: crop.height,
        rowStride: crop.width,
        rotationDegrees: 0,
        targetLongSide: 640,
        timestampMs: 0,
      );

      expect(frame.width, 32);
      expect(frame.pixels[0], yValue(16, 8));
    });
  });

  group('PixelRect', () {
    test('has a size and compares by value', () {
      const PixelRect rect = PixelRect(10, 20, 50, 100);

      expect(rect.width, 40);
      expect(rect.height, 80);
      expect(rect, const PixelRect(10, 20, 50, 100));
      expect(rect, isNot(const PixelRect(10, 20, 50, 101)));
    });
  });
}
