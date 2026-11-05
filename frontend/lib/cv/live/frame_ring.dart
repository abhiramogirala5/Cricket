import 'dart:typed_data';

import 'package:gully_umpire/cv/vision/luma_frame.dart';

/// A fixed-size ring of the most recent pictures, for building the replay of a delivery.
///
/// All memory is reserved once, so storing a picture is one memory copy and never allocates: the
/// phone keeps running smoothly for hours. When the ring is full the oldest picture is overwritten.
final class FrameRing {
  FrameRing({required this.capacity, required this.width, required this.height})
      : assert(capacity > 0 && width > 0 && height > 0, 'a ring needs a size'),
        _slots = List<Uint8List>.generate(capacity, (int _) => Uint8List(width * height)),
        _times = List<int>.filled(capacity, 0);

  /// How many pictures fit.
  final int capacity;
  final int width;
  final int height;

  final List<Uint8List> _slots;
  final List<int> _times;
  int _start = 0;
  int _count = 0;

  /// The number of pictures stored.
  int get length => _count;

  bool get isEmpty => _count == 0;

  /// The number of pictures that fit in [maxBytes] for pictures of the given size (at least 8).
  static int capacityFor({required int maxBytes, required int width, required int height}) {
    final int perFrame = width * height;
    if (perFrame <= 0) {
      return 8;
    }
    final int fit = maxBytes ~/ perFrame;
    return fit < 8 ? 8 : fit;
  }

  /// Stores a copy of [frame]. Returns false (and stores nothing) when its size differs.
  bool push(LumaFrame frame) {
    if (frame.width != width || frame.height != height) {
      return false;
    }
    final int index = (_start + _count) % capacity;
    _slots[index].setRange(0, _slots[index].length, frame.pixels);
    _times[index] = frame.timestampMs;
    if (_count < capacity) {
      _count += 1;
    } else {
      _start = (_start + 1) % capacity;
    }
    return true;
  }

  /// The stored pictures from [fromMs] to [toMs] (inclusive), oldest first.
  ///
  /// The pictures are views of the ring's own memory: use them before the next [push].
  List<LumaFrame> window(int fromMs, int toMs) {
    final List<LumaFrame> frames = <LumaFrame>[];
    for (int i = 0; i < _count; i++) {
      final int index = (_start + i) % capacity;
      final int time = _times[index];
      if (time >= fromMs && time <= toMs) {
        frames.add(
          LumaFrame(width: width, height: height, timestampMs: time, pixels: _slots[index]),
        );
      }
    }
    return frames;
  }

  /// Forgets every picture (the memory is kept).
  void clear() {
    _start = 0;
    _count = 0;
  }
}
