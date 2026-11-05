import 'dart:math' as math;
import 'dart:typed_data';

import 'package:gully_umpire/cv/vision/luma_frame.dart';

/// What [BackgroundModel.update] found out about a frame.
enum BackgroundState {
  /// The model is still learning the scene; no motion picture is available yet.
  warmup,

  /// The motion picture ([BackgroundModel.diff]) is valid.
  ok,

  /// Almost the whole picture changed for several frames in a row (the phone was moved or the
  /// light changed suddenly). The model started again from this frame.
  restarted,
}

/// Learns what the scene looks like when nothing moves, so that anything that moves stands out.
///
/// This is a running average per pixel, kept in fixed point (four extra bits) so that it needs
/// no floating-point work and no allocation per frame:
///
/// * pixels that look like the background follow the picture quickly ([shift]), which makes the
///   model follow slow light changes;
/// * pixels that stand out (a ball, a person) follow it very slowly ([foregroundShift]), so a ball
///   that crosses the picture in a fraction of a second is never absorbed;
/// * a global brightness offset is measured on the background pixels and removed, which keeps the
///   picture quiet when the camera's automatic exposure changes;
/// * the detection threshold follows the measured noise of the picture.
///
/// A person who stands still for a while becomes part of the background; a person who sways
/// leaves thin outlines that the tracker later recognises as stationary clutter.
final class BackgroundModel {
  BackgroundModel({
    this.shift = 4,
    this.foregroundShift = 6,
    this.minThreshold = 12,
    this.noiseMultiplier = 6.0,
    this.maxThreshold = 60,
    this.restartFraction = 0.7,
    this.restartFrames = 5,
    this.warmupFrames = 2,
  }) : assert(shift > 0 && foregroundShift >= shift, 'invalid adaptation rates'),
       assert(minThreshold > 0 && maxThreshold >= minThreshold, 'invalid threshold range');

  /// Adaptation of background pixels is `1 / 2^shift` per frame.
  final int shift;

  /// Adaptation of pixels that stand out is `1 / 2^foregroundShift` per frame.
  final int foregroundShift;

  /// Smallest brightness difference that counts as movement.
  final int minThreshold;

  /// The threshold is this many times the measured noise (clamped to the range).
  final double noiseMultiplier;

  final int maxThreshold;

  /// When more than this share of the picture stands out ...
  final double restartFraction;

  /// ... for this many frames in a row the model starts again.
  final int restartFrames;

  /// Frames needed before the first valid motion picture.
  final int warmupFrames;

  Uint16List? _background;
  Uint8List? _diff;
  int _width = 0;
  int _height = 0;
  int _frames = 0;
  int _highRun = 0;
  double _noise = 2.0;
  double _bias = 0;
  int _threshold = 12;
  double _foregroundFraction = 0;

  /// `|picture - background|` per pixel of the last frame (valid when the state was [BackgroundState.ok]).
  Uint8List get diff {
    final Uint8List? value = _diff;
    if (value == null) {
      throw StateError('The background model has not seen a frame yet');
    }
    return value;
  }

  int get width => _width;
  int get height => _height;

  /// Brightness difference above which a pixel counts as movement (used for the last frame).
  int get threshold => _threshold;

  /// Typical brightness noise of the picture (brightness levels).
  double get noise => _noise;

  /// Share of pixels that stood out in the last frame.
  double get foregroundFraction => _foregroundFraction;

  /// Forgets everything; the next frame starts the model again.
  void reset() {
    _background = null;
    _diff = null;
    _frames = 0;
    _highRun = 0;
    _bias = 0;
    _noise = 2.0;
    _foregroundFraction = 0;
  }

  /// Compares [frame] with the background, then lets the background learn from it.
  BackgroundState update(LumaFrame frame) {
    final Uint16List? known = _background;
    if (known == null || frame.width != _width || frame.height != _height) {
      _start(frame);
      return BackgroundState.warmup;
    }
    final Uint16List background = known;
    final Uint8List diff = _diff!;
    final Uint8List pixels = frame.pixels;
    final int count = pixels.length;
    final int threshold = _threshold;
    final int bias = _bias.round();
    final int roundBackground = 1 << (shift - 1);
    final int roundForeground = 1 << (foregroundShift - 1);

    int foreground = 0;
    int backgroundCount = 0;
    int backgroundAbsSum = 0;
    int backgroundSignedSum = 0;
    for (int i = 0; i < count; i++) {
      final int scaled = pixels[i] << 4;
      final int delta = scaled - background[i];
      final int raw = (delta + 8) >> 4;
      int residual = raw - bias;
      if (residual < 0) {
        residual = -residual;
      }
      diff[i] = residual > 255 ? 255 : residual;
      if (residual > threshold) {
        foreground += 1;
        background[i] = background[i] + ((delta + roundForeground) >> foregroundShift);
      } else {
        backgroundCount += 1;
        backgroundAbsSum += residual;
        backgroundSignedSum += raw;
        background[i] = background[i] + ((delta + roundBackground) >> shift);
      }
    }

    final double fraction = foreground / count;
    _foregroundFraction = fraction;
    if (fraction >= restartFraction) {
      _highRun += 1;
      if (_highRun >= restartFrames) {
        _start(frame);
        return BackgroundState.restarted;
      }
    } else {
      _highRun = 0;
    }

    if (backgroundCount > 0) {
      final double meanAbs = backgroundAbsSum / backgroundCount;
      _noise = 0.9 * _noise + 0.1 * math.max(0.5, meanAbs);
      final double meanSigned = backgroundSignedSum / backgroundCount;
      _bias = 0.5 * _bias + 0.5 * meanSigned;
    }
    final int next = (noiseMultiplier * _noise).round();
    _threshold = next < minThreshold ? minThreshold : (next > maxThreshold ? maxThreshold : next);
    _frames += 1;
    return _frames <= warmupFrames ? BackgroundState.warmup : BackgroundState.ok;
  }

  void _start(LumaFrame frame) {
    _width = frame.width;
    _height = frame.height;
    final int count = frame.pixels.length;
    final Uint16List background = Uint16List(count);
    for (int i = 0; i < count; i++) {
      background[i] = frame.pixels[i] << 4;
    }
    _background = background;
    _diff = Uint8List(count);
    _frames = 1;
    _highRun = 0;
    _bias = 0;
    _foregroundFraction = 0;
    _threshold = minThreshold;
  }
}
