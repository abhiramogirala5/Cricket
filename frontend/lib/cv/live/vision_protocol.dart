import 'dart:isolate';
import 'dart:typed_data';

import 'package:gully_umpire/cv/live/live_tracker.dart';
import 'package:gully_umpire/cv/pipelines/ball_observation.dart';
import 'package:gully_umpire/cv/vision/luma_frame.dart';

/// The messages between the app and the background vision worker, as plain lists of numbers (the
/// only thing that can cross an isolate boundary cheaply).
abstract final class VisionProtocol {
  /// App -> worker: `[frame, bytes, width, height, rowStride, rotation, timestampMs]`.
  static const String frame = 'frame';

  /// App -> worker: `[reset]`.
  static const String reset = 'reset';

  /// App -> worker: `[stop]`.
  static const String stop = 'stop';

  /// App -> worker: `[tracking, enabled]`.
  static const String tracking = 'tracking';

  /// Worker -> app: `[ready, commandPort]`.
  static const String ready = 'ready';

  /// Worker -> app: a [LiveFrameReport] (see [encodeReport]).
  static const String report = 'report';

  /// Worker -> app: a finished delivery (see [encodeCapture]).
  static const String capture = 'capture';

  /// Worker -> app: `[error, message, answersFrame]` (see [encodeError]).
  static const String error = 'error';

  /// An error message. [answersFrame] is true when it replaces the report of a picture, so the
  /// app knows the worker is free again.
  static List<Object?> encodeError(String message, {required bool answersFrame}) {
    return <Object?>[VisionProtocol.error, message, answersFrame ? 1 : 0];
  }

  /// Unpacks a message made by [encodeError]. Returns null when it is malformed.
  static DecodedError? decodeError(List<Object?> message) {
    if (message.length < 3) {
      return null;
    }
    final Object? text = message[1];
    final Object? flag = message[2];
    if (text is! String || flag is! int) {
      return null;
    }
    return DecodedError(message: text, answersFrame: flag != 0);
  }

  /// Packs [report] into a list of primitives.
  ///
  /// Layout: `[report, time, stateIndex, fps, noise, threshold, foreground, width, height,
  /// candidates (x, y, diameter, confidence per row), trail (time, x, y, diameter, confidence per row)]`.
  static List<Object?> encodeReport(LiveFrameReport report, {required int width, required int height}) {
    final Float64List candidates = Float64List(report.candidates.length * 4);
    for (int i = 0; i < report.candidates.length; i++) {
      final BallObservation o = report.candidates[i];
      candidates[i * 4] = o.x;
      candidates[i * 4 + 1] = o.y;
      candidates[i * 4 + 2] = o.diameter;
      candidates[i * 4 + 3] = o.confidence;
    }
    return <Object?>[
      VisionProtocol.report,
      report.timestampMs,
      report.state.index,
      report.fps,
      report.noise,
      report.threshold,
      report.foregroundFraction,
      width,
      height,
      candidates,
      _packObservations(report.trail),
    ];
  }

  /// Unpacks a message made by [encodeReport]. Returns null when it is malformed.
  static DecodedReport? decodeReport(List<Object?> message) {
    if (message.length < 11) {
      return null;
    }
    final Object? time = message[1];
    final Object? stateIndex = message[2];
    final Object? fps = message[3];
    final Object? noise = message[4];
    final Object? threshold = message[5];
    final Object? foreground = message[6];
    final Object? width = message[7];
    final Object? height = message[8];
    final Object? candidates = message[9];
    final Object? trail = message[10];
    if (time is! int ||
        stateIndex is! int ||
        fps is! double ||
        noise is! double ||
        threshold is! int ||
        foreground is! double ||
        width is! int ||
        height is! int ||
        candidates is! Float64List ||
        trail is! Float64List ||
        stateIndex < 0 ||
        stateIndex >= LiveWatchState.values.length) {
      return null;
    }
    final List<BallObservation> found = <BallObservation>[];
    for (int i = 0; i + 3 < candidates.length; i += 4) {
      found.add(
        BallObservation(
          timestampMs: time,
          x: candidates[i],
          y: candidates[i + 1],
          diameter: candidates[i + 2],
          confidence: candidates[i + 3],
        ),
      );
    }
    return DecodedReport(
      report: LiveFrameReport(
        timestampMs: time,
        state: LiveWatchState.values[stateIndex],
        candidates: found,
        trail: _unpackObservations(trail),
        fps: fps,
        noise: noise,
        threshold: threshold,
        foregroundFraction: foreground,
      ),
      width: width,
      height: height,
    );
  }

  /// Packs a finished delivery and (optionally) its replay file.
  ///
  /// Layout: `[capture, observations, frameTimes, aspect, framesProcessed, width, height, quality,
  /// startMs, endMs, replay]`.
  static List<Object?> encodeCapture(LiveDeliveryCapture capture, Uint8List? replay) {
    return <Object?>[
      VisionProtocol.capture,
      _packObservations(capture.observations),
      Int32List.fromList(capture.frameTimesMs),
      capture.aspectRatio,
      capture.framesProcessed,
      capture.frameWidth,
      capture.frameHeight,
      capture.trackQuality,
      capture.startMs,
      capture.endMs,
      replay == null ? null : TransferableTypedData.fromList(<TypedData>[replay]),
    ];
  }

  /// Unpacks a message made by [encodeCapture]. Returns null when it is malformed.
  static DecodedCapture? decodeCapture(List<Object?> message) {
    if (message.length < 11) {
      return null;
    }
    final Object? observations = message[1];
    final Object? times = message[2];
    final Object? aspect = message[3];
    final Object? frames = message[4];
    final Object? width = message[5];
    final Object? height = message[6];
    final Object? quality = message[7];
    final Object? start = message[8];
    final Object? end = message[9];
    final Object? replay = message[10];
    if (observations is! Float64List ||
        times is! Int32List ||
        aspect is! double ||
        frames is! int ||
        width is! int ||
        height is! int ||
        quality is! double ||
        start is! int ||
        end is! int) {
      return null;
    }
    Uint8List? replayBytes;
    if (replay is TransferableTypedData) {
      replayBytes = replay.materialize().asUint8List();
    }
    return DecodedCapture(
      capture: LiveDeliveryCapture(
        observations: _unpackObservations(observations),
        frameTimesMs: times.toList(),
        aspectRatio: aspect,
        framesProcessed: frames,
        frameWidth: width,
        frameHeight: height,
        trackQuality: quality,
        startMs: start,
        endMs: end,
      ),
      replay: replayBytes,
    );
  }

  /// Packs the Y plane of a camera picture for the worker.
  static List<Object?> encodeFrame({
    required Uint8List yPlane,
    required int width,
    required int height,
    required int rowStride,
    required int rotationDegrees,
    required int timestampMs,
  }) {
    return <Object?>[
      VisionProtocol.frame,
      TransferableTypedData.fromList(<TypedData>[yPlane]),
      width,
      height,
      rowStride,
      rotationDegrees,
      timestampMs,
    ];
  }

  static Float64List _packObservations(List<BallObservation> observations) {
    final Float64List packed = Float64List(observations.length * 5);
    for (int i = 0; i < observations.length; i++) {
      final BallObservation o = observations[i];
      packed[i * 5] = o.timestampMs.toDouble();
      packed[i * 5 + 1] = o.x;
      packed[i * 5 + 2] = o.y;
      packed[i * 5 + 3] = o.confidence;
      packed[i * 5 + 4] = o.diameter;
    }
    return packed;
  }

  static List<BallObservation> _unpackObservations(Float64List packed) {
    final List<BallObservation> list = <BallObservation>[];
    for (int i = 0; i + 4 < packed.length; i += 5) {
      list.add(
        BallObservation(
          timestampMs: packed[i].round(),
          x: packed[i + 1],
          y: packed[i + 2],
          confidence: packed[i + 3],
          diameter: packed[i + 4],
        ),
      );
    }
    return list;
  }
}

/// A [LiveFrameReport] that arrived from the worker, with the size of the picture it describes.
final class DecodedReport {
  const DecodedReport({required this.report, required this.width, required this.height});

  final LiveFrameReport report;
  final int width;
  final int height;
}

/// A finished delivery that arrived from the worker.
final class DecodedCapture {
  const DecodedCapture({required this.capture, this.replay});

  final LiveDeliveryCapture capture;

  /// The replay file made from the pictures of the delivery, if there were any.
  final Uint8List? replay;
}

/// An error the worker reported.
final class DecodedError {
  const DecodedError({required this.message, required this.answersFrame});

  final String message;

  /// True when the error took the place of a picture's report.
  final bool answersFrame;
}

/// The size of a converted picture the worker uses for [frame].
LumaSize workerPictureSize({
  required int width,
  required int height,
  required int rotationDegrees,
  required int targetLongSide,
}) {
  return LumaConverter.outputSize(
    srcWidth: width,
    srcHeight: height,
    rotationDegrees: rotationDegrees,
    targetLongSide: targetLongSide,
  );
}
