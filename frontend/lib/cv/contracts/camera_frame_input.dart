import 'dart:typed_data';

/// One camera frame as seen by the CV layer.
///
/// The pure-Dart core never touches camera plugins. The Flutter layer converts
/// whatever the camera delivers into this small value. [luma] (the 8-bit
/// brightness plane) is optional: mock adapters ignore it, real adapters may
/// need it. Raw frame data must not be kept in widget or Riverpod state.
final class CameraFrameInput {
  const CameraFrameInput({
    required this.width,
    required this.height,
    required this.timestampMs,
    this.luma,
  });

  /// Frame width in pixels.
  final int width;

  /// Frame height in pixels.
  final int height;

  /// Capture time in milliseconds on any monotonic clock (only differences matter).
  final int timestampMs;

  /// Optional `width * height` brightness bytes.
  final Uint8List? luma;

  /// Width divided by height (1 for a degenerate frame).
  double get aspectRatio => height <= 0 ? 1.0 : width / height;

  @override
  String toString() => 'CameraFrameInput(${width}x$height @ ${timestampMs}ms)';
}
