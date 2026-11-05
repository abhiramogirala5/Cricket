import 'dart:typed_data';

import 'package:gully_umpire/cv/vision/luma_frame.dart';

/// A bright or dark disc in a [SyntheticScene].
///
/// A pixel belongs to the disc when `4 * ((x - cx)^2 + (y - cy)^2) <= diameter^2`, so the disc is
/// exactly symmetric around the middle of pixel (cx, cy), that is around (cx + 0.5, cy + 0.5) in
/// the picture units that the detector reports.
final class SceneDisc {
  const SceneDisc({
    required this.cx,
    required this.cy,
    required this.diameter,
    required this.value,
  });

  final int cx;
  final int cy;
  final int diameter;
  final int value;
}

/// A filled rectangle in a [SyntheticScene].
final class SceneRect {
  const SceneRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.value,
  });

  final int x;
  final int y;
  final int width;
  final int height;
  final int value;
}

/// Renders small upright pictures with plain integer arithmetic, so that the expectations of the
/// tests do not depend on floating point or on a random generator.
///
/// The same scene was run through a line-by-line port of the tracker in Python to find out what
/// it reports; the numbers in the tests come from there (with generous margins).
abstract final class SyntheticScene {
  static const int width = 180;
  static const int height = 320;

  /// Camera frame rate of the scene.
  static const int fps = 30;

  /// A very faintly textured wall.
  static int background(int x, int y) => 100 + ((x * 7 + y * 13) % 5);

  /// A repeatable "noise" of -2..2 brightness levels.
  static int noise(int x, int y, int frameIndex) =>
      (((x * 73856093) ^ (y * 19349663) ^ (frameIndex * 83492791)) % 5) - 2;

  /// Camera time of picture [index] at 30 frames per second.
  static int timestampOf(int index) => (index * 1000) ~/ fps;

  /// Picture index closest to a camera time that came out of [timestampOf].
  static int indexOfTime(int timestampMs) => (timestampMs * fps / 1000).round();

  /// The ball in step [step] of a flight of [steps] pictures: it starts near the bottom of the
  /// picture, moves up by [speed] pixels per picture, drifts right a little and (flying away from
  /// the camera) shrinks from [startDiameter] to [endDiameter].
  static SceneDisc ball(
    int step,
    int steps, {
    int speed = 5,
    int startDiameter = 12,
    int endDiameter = 7,
    int value = 230,
  }) {
    // Integer division that rounds towards zero in both directions of change.
    final int change = endDiameter - startDiameter;
    final int grown = change < 0
        ? -((-change * step) ~/ (steps - 1))
        : (change * step) ~/ (steps - 1);
    return SceneDisc(
      cx: 90 + (step * 3) ~/ 10,
      cy: 300 - speed * step,
      diameter: startDiameter + grown,
      value: value,
    );
  }

  /// Renders picture [index].
  ///
  /// Order of drawing: background, rectangles, discs (later ones cover earlier ones), then the
  /// global [brightness] offset, then the noise, and finally the clamp to 0..255.
  static LumaFrame frame(
    int index, {
    List<SceneDisc> discs = const <SceneDisc>[],
    List<SceneRect> rects = const <SceneRect>[],
    bool noisy = false,
    int brightness = 0,
    int? timestampMs,
  }) {
    final Uint8List pixels = Uint8List(width * height);
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        int value = background(x, y);
        for (final SceneRect rect in rects) {
          if (x >= rect.x && x < rect.x + rect.width && y >= rect.y && y < rect.y + rect.height) {
            value = rect.value;
          }
        }
        for (final SceneDisc disc in discs) {
          final int dx = x - disc.cx;
          final int dy = y - disc.cy;
          if (4 * (dx * dx + dy * dy) <= disc.diameter * disc.diameter) {
            value = disc.value;
          }
        }
        value += brightness;
        if (noisy) {
          value += noise(x, y, index);
        }
        pixels[y * width + x] = value < 0 ? 0 : (value > 255 ? 255 : value);
      }
    }
    return LumaFrame(
      width: width,
      height: height,
      timestampMs: timestampMs ?? timestampOf(index),
      pixels: pixels,
    );
  }
}
