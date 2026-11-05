import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/cv/vision/blob_finder.dart';

/// A picture of [width] x [height] with no movement.
class Diff {
  Diff(this.width, this.height) : pixels = Uint8List(width * height);

  final int width;
  final int height;
  final Uint8List pixels;

  /// Sets the rectangle from (x0, y0) to (x1, y1), both included.
  void fill(int x0, int y0, int x1, int y1, int value) {
    for (int y = y0; y <= y1; y++) {
      for (int x = x0; x <= x1; x++) {
        pixels[y * width + x] = value;
      }
    }
  }

  List<Blob> find(BlobFinder finder, {int threshold = 12}) =>
      finder.find(diff: pixels, width: width, height: height, threshold: threshold);
}

void main() {
  group('one patch', () {
    test('a 3 x 3 square is measured exactly', () {
      final Diff canvas = Diff(32, 32)..fill(5, 5, 7, 7, 100);

      final List<Blob> blobs = canvas.find(BlobFinder());

      expect(blobs, hasLength(1));
      final Blob blob = blobs.single;
      expect(blob.area, 9);
      expect(blob.cx, closeTo(6.5, 1e-12));
      expect(blob.cy, closeTo(6.5, 1e-12));
      expect(<int>[blob.left, blob.top, blob.right, blob.bottom], <int>[5, 5, 7, 7]);
      // Variance of three columns is 2/3, plus 1/12 for the pixel itself: 0.75 each way.
      expect(blob.major, closeTo(4 * math.sqrt(0.75), 1e-9));
      expect(blob.minor, closeTo(4 * math.sqrt(0.75), 1e-9));
      expect(blob.elongation, closeTo(1.0, 1e-9));
      expect(blob.meanDiff, 100);
      expect(blob.peakDiff, 100);
      expect(blob.p90Diff, 100);
      expect(blob.halfArea, 9);
    });

    test('two pixels in a row have their centre between them', () {
      final Diff canvas = Diff(32, 32)..fill(10, 5, 11, 5, 50);

      final Blob blob = canvas.find(BlobFinder()).single;

      expect(blob.cx, closeTo(11.0, 1e-12));
      expect(blob.cy, closeTo(5.5, 1e-12));
      expect(blob.elongation, closeTo(2.0, 1e-9));
    });

    test('a soft patch has its half-brightness area measured', () {
      // A bright middle with dimmer pixels around it, like a blurred ball.
      final Diff canvas = Diff(32, 32)
        ..fill(10, 10, 12, 12, 60)
        ..fill(11, 11, 11, 11, 200);

      final Blob blob = canvas.find(BlobFinder()).single;

      expect(blob.area, 9);
      expect(blob.peakDiff, 200);
      expect(blob.p90Diff, 200);
      expect(blob.halfArea, 1, reason: 'only the middle pixel reaches half of 200');
      expect(blob.meanDiff, closeTo((200 + 8 * 60) / 9, 1e-9));
    });

    test('a pixel exactly at the threshold does not move', () {
      final Diff canvas = Diff(32, 32)..fill(5, 5, 7, 7, 12);

      expect(canvas.find(BlobFinder()), isEmpty);
      expect(canvas.find(BlobFinder(), threshold: 11), hasLength(1));
    });
  });

  group('several patches', () {
    test('two far-apart squares are two patches, the upper one first', () {
      final Diff canvas = Diff(64, 64)
        ..fill(40, 40, 42, 42, 100)
        ..fill(5, 5, 7, 7, 100);

      final List<Blob> blobs = canvas.find(BlobFinder());

      expect(blobs, hasLength(2));
      expect(blobs.first.cx, closeTo(6.5, 1e-12));
      expect(blobs.last.cx, closeTo(41.5, 1e-12));
    });

    test('the finder can be used again and starts afresh each time', () {
      final BlobFinder finder = BlobFinder();
      final Diff first = Diff(32, 32)
        ..fill(5, 5, 7, 7, 100)
        ..fill(20, 20, 22, 22, 100);
      final Diff second = Diff(32, 32)..fill(10, 10, 12, 12, 100);

      expect(first.find(finder), hasLength(2));
      expect(second.find(finder), hasLength(1));
      expect(Diff(32, 32).find(finder), isEmpty);
      expect(first.find(finder), hasLength(2));
    });

    test('at most maxBlobs patches are measured', () {
      final Diff canvas = Diff(64, 64);
      for (int i = 0; i < 5; i++) {
        canvas.fill(4 + i * 10, 10, 6 + i * 10, 12, 100);
      }

      expect(canvas.find(BlobFinder(maxBlobs: 3)), hasLength(3));
      expect(canvas.find(BlobFinder()), hasLength(5));
    });
  });

  group('joining pieces', () {
    test('a ball cut in two by a one-pixel gap is put back together', () {
      final Diff canvas = Diff(32, 32)
        ..fill(5, 10, 6, 10, 100)
        ..fill(8, 10, 9, 10, 100);

      final List<Blob> joined = canvas.find(BlobFinder());
      final List<Blob> apart = canvas.find(BlobFinder(joinRadius: 1));

      expect(joined, hasLength(1));
      expect(joined.single.area, 4);
      expect(apart, hasLength(2));
    });

    test('a gap of two pixels is not bridged', () {
      final Diff canvas = Diff(32, 32)
        ..fill(5, 10, 6, 10, 100)
        ..fill(9, 10, 10, 10, 100);

      expect(canvas.find(BlobFinder()), hasLength(2));
    });

    test('a ball cut in two by an empty row is put back together', () {
      final Diff canvas = Diff(32, 32)
        ..fill(5, 10, 7, 10, 100)
        ..fill(5, 12, 7, 12, 100);

      final List<Blob> joined = canvas.find(BlobFinder());
      final List<Blob> apart = canvas.find(BlobFinder(joinRadius: 1));

      expect(joined, hasLength(1));
      expect(joined.single.area, 6);
      expect(apart, hasLength(2));
    });

    test('diagonal neighbours are one patch', () {
      final Diff canvas = Diff(32, 32)
        ..fill(5, 5, 6, 5, 100)
        ..fill(7, 6, 8, 6, 100);

      expect(canvas.find(BlobFinder(joinRadius: 1)), hasLength(1));
    });
  });

  group('what is not a ball', () {
    test('a single pixel is noise', () {
      final Diff canvas = Diff(32, 32)..fill(5, 5, 5, 5, 200);

      expect(canvas.find(BlobFinder()), isEmpty);
      expect(canvas.find(BlobFinder(minArea: 1)), hasLength(1));
    });

    test('a patch wider than 12 percent of the picture height is too big', () {
      // The picture is 64 high, so 12 percent is 8 pixels (7.68 rounded).
      final Diff tooWide = Diff(64, 64)..fill(10, 10, 18, 11, 100);
      final Diff fits = Diff(64, 64)..fill(10, 10, 17, 12, 100);

      expect(tooWide.find(BlobFinder()), isEmpty);
      expect(fits.find(BlobFinder()), hasLength(1));
    });

    test('a patch with too many pixels is too big', () {
      final Diff canvas = Diff(200, 200)..fill(10, 10, 24, 24, 100);

      // 225 pixels: above the 216 that 0.54 percent of the picture allows (and above the floor of 200).
      expect(canvas.find(BlobFinder()), isEmpty);
    });

    test('a long thin streak is not a ball', () {
      final Diff canvas = Diff(200, 200)..fill(10, 50, 29, 50, 100);

      expect(canvas.find(BlobFinder()), isEmpty);
    });

    test('a frame with far too much movement gives nothing', () {
      final Diff canvas = Diff(32, 32);
      for (int y = 0; y < 32; y += 2) {
        canvas.fill(0, y, 31, y, 100);
      }

      expect(canvas.find(BlobFinder(maxRuns: 8)), isEmpty);
    });

    test('a picture with no movement gives nothing', () {
      expect(Diff(32, 32).find(BlobFinder()), isEmpty);
    });
  });
}
