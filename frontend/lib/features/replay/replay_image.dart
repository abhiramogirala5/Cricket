import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Turns a greyscale picture (one byte per pixel) into RGBA bytes (alpha 255).
Uint8List lumaToRgba(Uint8List luma) {
  final Uint8List rgba = Uint8List(luma.length * 4);
  int out = 0;
  for (int i = 0; i < luma.length; i++) {
    final int value = luma[i];
    rgba[out] = value;
    rgba[out + 1] = value;
    rgba[out + 2] = value;
    rgba[out + 3] = 255;
    out += 4;
  }
  return rgba;
}

/// A picture the screen can draw, made from a greyscale replay picture of [width] x [height].
Future<ui.Image> lumaToImage(Uint8List luma, int width, int height) {
  final Completer<ui.Image> completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    lumaToRgba(luma),
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}
