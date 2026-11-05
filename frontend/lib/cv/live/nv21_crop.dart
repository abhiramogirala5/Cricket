import 'dart:typed_data';

import 'package:equatable/equatable.dart';

/// A rectangle in whole pixels (`left`/`top` inclusive, `right`/`bottom` exclusive).
final class PixelRect extends Equatable {
  const PixelRect(this.left, this.top, this.right, this.bottom);

  final int left;
  final int top;
  final int right;
  final int bottom;

  int get width => right - left;
  int get height => bottom - top;

  @override
  List<Object?> get props => <Object?>[left, top, right, bottom];

  @override
  String toString() => 'PixelRect($left, $top, $right, $bottom)';
}

/// A cut-out of a camera picture in NV21 format, ready to be given to the body-pose model.
final class Nv21Crop {
  const Nv21Crop({
    required this.bytes,
    required this.width,
    required this.height,
    required this.upright,
  });

  /// `width * height * 3 / 2` bytes: the brightness plane, then the interleaved V/U plane.
  final Uint8List bytes;

  /// Size of the cut-out in the camera's own (unrotated) orientation.
  final int width;
  final int height;

  /// Where the cut-out lies in the upright picture (pixels).
  final PixelRect upright;
}

/// Cuts a region out of a camera picture, and maps between the upright picture (the way the phone is
/// held) and the camera's own unrotated picture.
///
/// The body-pose model picks the most prominent person in its picture. At a ground that is often
/// the bowler or an umpire, so the pose is measured on a cut-out around the batter instead: it is
/// the right person, and the model sees more pixels of him.
abstract final class Nv21Cropper {
  /// The size of the upright picture for a raw picture of [rawWidth] x [rawHeight] that is turned
  /// by [rotationDegrees] to be upright.
  static ({int width, int height}) uprightSize(int rawWidth, int rawHeight, int rotationDegrees) {
    final int turn = _normalise(rotationDegrees);
    return turn == 90 || turn == 270
        ? (width: rawHeight, height: rawWidth)
        : (width: rawWidth, height: rawHeight);
  }

  /// The camera-orientation rectangle that covers the upright rectangle [upright], made even-sized
  /// and even-aligned (NV21 shares one colour sample between 2 x 2 pixels) and clamped to the picture.
  static PixelRect rawRectFor({
    required PixelRect upright,
    required int rawWidth,
    required int rawHeight,
    required int rotationDegrees,
  }) {
    final int turn = _normalise(rotationDegrees);
    int left;
    int top;
    int right;
    int bottom;
    switch (turn) {
      case 90:
        left = upright.top;
        right = upright.bottom;
        top = rawHeight - upright.right;
        bottom = rawHeight - upright.left;
      case 180:
        left = rawWidth - upright.right;
        right = rawWidth - upright.left;
        top = rawHeight - upright.bottom;
        bottom = rawHeight - upright.top;
      case 270:
        left = rawWidth - upright.bottom;
        right = rawWidth - upright.top;
        top = upright.left;
        bottom = upright.right;
      default:
        left = upright.left;
        top = upright.top;
        right = upright.right;
        bottom = upright.bottom;
    }
    left = left < 0 ? 0 : left;
    top = top < 0 ? 0 : top;
    right = right > rawWidth ? rawWidth : right;
    bottom = bottom > rawHeight ? rawHeight : bottom;
    left &= ~1;
    top &= ~1;
    right = (right + 1) & ~1;
    bottom = (bottom + 1) & ~1;
    if (right > rawWidth) {
      right = rawWidth & ~1;
    }
    if (bottom > rawHeight) {
      bottom = rawHeight & ~1;
    }
    return PixelRect(left, top, right, bottom);
  }

  /// Where a camera-orientation rectangle lies in the upright picture.
  static PixelRect uprightRectFor({
    required PixelRect raw,
    required int rawWidth,
    required int rawHeight,
    required int rotationDegrees,
  }) {
    final int turn = _normalise(rotationDegrees);
    switch (turn) {
      case 90:
        return PixelRect(rawHeight - raw.bottom, raw.left, rawHeight - raw.top, raw.right);
      case 180:
        return PixelRect(rawWidth - raw.right, rawHeight - raw.bottom, rawWidth - raw.left, rawHeight - raw.top);
      case 270:
        return PixelRect(raw.top, rawWidth - raw.right, raw.bottom, rawWidth - raw.left);
      default:
        return raw;
    }
  }

  /// Copies the part of the NV21 picture [source] that covers the upright rectangle [upright].
  ///
  /// [rowStride] is the number of bytes from one brightness row to the next. Returns null when the
  /// cut-out would be smaller than 16 x 16 pixels or [source] is too short to be a full NV21 picture.
  static Nv21Crop? crop({
    required Uint8List source,
    required int rawWidth,
    required int rawHeight,
    required int rowStride,
    required int rotationDegrees,
    required PixelRect upright,
  }) {
    if (rowStride < rawWidth || source.length < rowStride * rawHeight * 3 ~/ 2) {
      return null;
    }
    final PixelRect raw = rawRectFor(
      upright: upright,
      rawWidth: rawWidth,
      rawHeight: rawHeight,
      rotationDegrees: rotationDegrees,
    );
    final int width = raw.width;
    final int height = raw.height;
    if (width < 16 || height < 16) {
      return null;
    }
    final Uint8List out = Uint8List(width * height * 3 ~/ 2);
    for (int row = 0; row < height; row++) {
      final int from = (raw.top + row) * rowStride + raw.left;
      out.setRange(row * width, row * width + width, source, from);
    }
    final int chromaStart = rowStride * rawHeight;
    final int chromaRows = height ~/ 2;
    for (int row = 0; row < chromaRows; row++) {
      final int from = chromaStart + (raw.top ~/ 2 + row) * rowStride + raw.left;
      final int to = width * height + row * width;
      out.setRange(to, to + width, source, from);
    }
    return Nv21Crop(
      bytes: out,
      width: width,
      height: height,
      upright: uprightRectFor(
        raw: raw,
        rawWidth: rawWidth,
        rawHeight: rawHeight,
        rotationDegrees: rotationDegrees,
      ),
    );
  }

  static int _normalise(int degrees) {
    final int turn = degrees % 360;
    return turn < 0 ? turn + 360 : turn;
  }
}
