import 'dart:typed_data';

/// One upright 8-bit brightness picture, as the motion detector sees it.
///
/// "Upright" means rotated the way the person holds the phone, so `x` runs left to right and `y`
/// top to bottom in the same way as on the screen. The picture is usually smaller than what the
/// camera delivers (see [LumaConverter]).
final class LumaFrame {
  LumaFrame({
    required this.width,
    required this.height,
    required this.timestampMs,
    required this.pixels,
  }) : assert(width > 0 && height > 0, 'a frame needs a size'),
       assert(pixels.length == width * height, 'pixels must hold width * height bytes');

  final int width;
  final int height;

  /// Capture time in milliseconds on a steady clock (only differences matter).
  final int timestampMs;

  /// Row by row, `width * height` brightness values, 0 (black) to 255 (white).
  final Uint8List pixels;

  /// Width divided by height.
  double get aspectRatio => width / height;

  @override
  String toString() => 'LumaFrame(${width}x$height @ ${timestampMs}ms)';
}

/// The size of a converted picture.
final class LumaSize {
  const LumaSize({required this.width, required this.height, required this.factor});

  /// Upright width after shrinking.
  final int width;

  /// Upright height after shrinking.
  final int height;

  /// Every output pixel is the average of `factor x factor` source pixels.
  final int factor;
}

/// Turns the brightness plane of a camera frame into an upright, shrunken [LumaFrame].
///
/// Works on the Y plane of an NV21 / YUV420 frame (one byte per pixel, rows `rowStride` bytes
/// apart), which is the brightness picture itself, so no colour conversion is needed. The work
/// is one pass over the source with plain integer arithmetic.
abstract final class LumaConverter {
  /// The output size for a source of [srcWidth] x [srcHeight] that must be turned by
  /// [rotationDegrees] (0, 90, 180 or 270, clockwise) and shrunk so that its longer side is about
  /// [targetLongSide] pixels.
  ///
  /// The shrink factor is a whole number (1, 2, 3, ...), so the picture is never stretched. The
  /// result is never larger than the source and is at least 8 x 8. Using the longer side keeps the
  /// amount of work the same whether the phone is held sideways or upright.
  static LumaSize outputSize({
    required int srcWidth,
    required int srcHeight,
    required int rotationDegrees,
    required int targetLongSide,
  }) {
    final int turn = _normalise(rotationDegrees);
    final bool swap = turn == 90 || turn == 270;
    final int uprightWidth = swap ? srcHeight : srcWidth;
    final int uprightHeight = swap ? srcWidth : srcHeight;
    final int longSide = uprightWidth > uprightHeight ? uprightWidth : uprightHeight;
    int factor = 1;
    if (targetLongSide > 0 && longSide > targetLongSide) {
      factor = (longSide / targetLongSide).round();
      if (factor < 1) {
        factor = 1;
      }
    }
    int width = uprightWidth ~/ factor;
    int height = uprightHeight ~/ factor;
    if (width < 8) {
      width = 8;
    }
    if (height < 8) {
      height = 8;
    }
    return LumaSize(width: width, height: height, factor: factor);
  }

  /// Fills [out] (`size.width * size.height` bytes) from [source].
  ///
  /// [rowStride] is the number of bytes from one source row to the next (it can be larger than
  /// [srcWidth]). Throws an [ArgumentError] when a buffer is too small or the rotation is not a
  /// multiple of 90.
  static void convert({
    required Uint8List source,
    required int srcWidth,
    required int srcHeight,
    required int rowStride,
    required int rotationDegrees,
    required LumaSize size,
    required Uint8List out,
  }) {
    if (rotationDegrees % 90 != 0) {
      throw ArgumentError.value(rotationDegrees, 'rotationDegrees', 'must be a multiple of 90');
    }
    if (rowStride < srcWidth) {
      throw ArgumentError.value(rowStride, 'rowStride', 'is smaller than the picture width');
    }
    if (source.length < (srcHeight - 1) * rowStride + srcWidth) {
      throw ArgumentError.value(source.length, 'source', 'is too short for the picture size');
    }
    final int outWidth = size.width;
    final int outHeight = size.height;
    if (out.length < outWidth * outHeight) {
      throw ArgumentError.value(out.length, 'out', 'is too short for the output size');
    }
    final int k = size.factor;
    final int turn = _normalise(rotationDegrees);
    final bool swapped = turn == 90 || turn == 270;
    final int uprightWidth = swapped ? srcHeight : srcWidth;
    final int uprightHeight = swapped ? srcWidth : srcHeight;
    if (k < 1 || outWidth * k > uprightWidth || outHeight * k > uprightHeight) {
      throw ArgumentError.value(size, 'size', 'does not fit the upright source picture');
    }

    // For an upright pixel (ux, uy) the source pixel is
    //   sx = sx0 + sxDux * ux + sxDuy * uy,  sy = sy0 + syDux * ux + syDuy * uy
    // so the source index is `base + stepX * ux + stepY * uy`.
    int sx0;
    int sy0;
    int sxDux;
    int sxDuy;
    int syDux;
    int syDuy;
    switch (turn) {
      case 90:
        sx0 = 0;
        sy0 = srcHeight - 1;
        sxDux = 0;
        sxDuy = 1;
        syDux = -1;
        syDuy = 0;
      case 180:
        sx0 = srcWidth - 1;
        sy0 = srcHeight - 1;
        sxDux = -1;
        sxDuy = 0;
        syDux = 0;
        syDuy = -1;
      case 270:
        sx0 = srcWidth - 1;
        sy0 = 0;
        sxDux = 0;
        sxDuy = -1;
        syDux = 1;
        syDuy = 0;
      default:
        sx0 = 0;
        sy0 = 0;
        sxDux = 1;
        sxDuy = 0;
        syDux = 0;
        syDuy = 1;
    }
    final int base = sy0 * rowStride + sx0;
    final int stepX = syDux * rowStride + sxDux;
    final int stepY = syDuy * rowStride + sxDuy;
    final int area = k * k;
    final int half = area ~/ 2;

    int outIndex = 0;
    for (int oy = 0; oy < outHeight; oy++) {
      final int uy0 = oy * k;
      for (int ox = 0; ox < outWidth; ox++) {
        final int ux0 = ox * k;
        int sum = 0;
        for (int dy = 0; dy < k; dy++) {
          int index = base + stepX * ux0 + stepY * (uy0 + dy);
          for (int dx = 0; dx < k; dx++) {
            sum += source[index];
            index += stepX;
          }
        }
        out[outIndex] = k == 1 ? sum : (sum + half) ~/ area;
        outIndex += 1;
      }
    }
  }

  /// Convenience wrapper that allocates the output.
  static LumaFrame toFrame({
    required Uint8List source,
    required int srcWidth,
    required int srcHeight,
    required int rowStride,
    required int rotationDegrees,
    required int targetLongSide,
    required int timestampMs,
  }) {
    final LumaSize size = outputSize(
      srcWidth: srcWidth,
      srcHeight: srcHeight,
      rotationDegrees: rotationDegrees,
      targetLongSide: targetLongSide,
    );
    final Uint8List pixels = Uint8List(size.width * size.height);
    convert(
      source: source,
      srcWidth: srcWidth,
      srcHeight: srcHeight,
      rowStride: rowStride,
      rotationDegrees: rotationDegrees,
      size: size,
      out: pixels,
    );
    return LumaFrame(
      width: size.width,
      height: size.height,
      timestampMs: timestampMs,
      pixels: pixels,
    );
  }

  static int _normalise(int degrees) {
    final int turn = degrees % 360;
    return turn < 0 ? turn + 360 : turn;
  }
}
