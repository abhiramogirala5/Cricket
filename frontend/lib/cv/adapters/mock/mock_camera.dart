import 'package:gully_umpire/cv/contracts/camera_frame_input.dart';

/// A camera that delivers empty frames at a steady rate, so the mock detectors can be driven
/// without a real camera. The frames carry no picture: only the size and the time.
abstract final class MockCamera {
  /// The frames from [startMs] to [endMs] at [fps] frames per second.
  static List<CameraFrameInput> frameList({
    required int fps,
    required int startMs,
    required int endMs,
    int width = 1280,
    int height = 720,
  }) {
    if (fps <= 0 || endMs < startMs) {
      return const <CameraFrameInput>[];
    }
    final int count = ((endMs - startMs) * fps / 1000).floor() + 1;
    return <CameraFrameInput>[
      for (int i = 0; i < count; i++)
        CameraFrameInput(
          width: width,
          height: height,
          timestampMs: startMs + (i * 1000 / fps).round(),
        ),
    ];
  }

  /// The same frames as a stream.
  static Stream<CameraFrameInput> frames({
    required int fps,
    required int startMs,
    required int endMs,
    int width = 1280,
    int height = 720,
  }) {
    return Stream<CameraFrameInput>.fromIterable(
      frameList(fps: fps, startMs: startMs, endMs: endMs, width: width, height: height),
    );
  }
}
