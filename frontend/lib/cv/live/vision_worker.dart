import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:gully_umpire/cv/live/live_tracker.dart';
import 'package:gully_umpire/cv/live/vision_protocol.dart';
import 'package:gully_umpire/cv/vision/luma_frame.dart';

/// Settings of the background vision worker.
final class VisionWorkerConfig {
  const VisionWorkerConfig({
    this.nominalFps = 30,
    this.analysisLongSide = 640,
    this.replayBudgetBytes = 24 * 1024 * 1024,
    this.maxReplayFrames = 150,
    this.maxInFlight = 2,
  });

  /// The frame rate the camera is asked for (the real rate is measured while running).
  final int nominalFps;

  /// Length, in pixels, of the longer side of the pictures the ball is looked for in. The camera
  /// picture is shrunk by a whole factor to be about this long.
  final int analysisLongSide;

  /// Memory for the pictures kept for the replay of the next delivery.
  final int replayBudgetBytes;
  final int maxReplayFrames;

  /// How many pictures may wait for the worker at once. More are dropped, so the worker never
  /// falls behind and the picture it works on is always the latest one.
  final int maxInFlight;
}

/// The work of the background worker, without the isolate around it (so it can be tested directly).
///
/// It takes the raw messages of [VisionProtocol] and calls [send] with the answers.
final class VisionWorkerCore {
  VisionWorkerCore({VisionWorkerConfig config = const VisionWorkerConfig()})
      : _config = config,
        _tracker = LiveTracker(
          config: LiveTrackerConfig(
            replayBudgetBytes: config.replayBudgetBytes,
            maxReplayFrames: config.maxReplayFrames,
          ),
          nominalFps: config.nominalFps.toDouble(),
        );

  final VisionWorkerConfig _config;
  final LiveTracker _tracker;

  /// The converted picture, reused for every frame (nothing keeps a reference to it).
  Uint8List _scratch = Uint8List(0);

  /// Handles one message from the app.
  void handle(Object? message, void Function(List<Object?> answer) send) {
    if (message is! List<Object?> || message.isEmpty) {
      return;
    }
    switch (message[0]) {
      case VisionProtocol.frame:
        _frame(message, send);
      case VisionProtocol.reset:
        _tracker.reset();
      case VisionProtocol.tracking:
        if (message.length >= 2 && message[1] is int) {
          _tracker.deliveryTrackingEnabled = (message[1] as int) != 0;
        }
      default:
        break;
    }
  }

  void _frame(List<Object?> message, void Function(List<Object?> answer) send) {
    try {
      if (message.length < 7) {
        send(VisionProtocol.encodeError('A picture message was incomplete', answersFrame: true));
        return;
      }
      final Object? data = message[1];
      final Object? width = message[2];
      final Object? height = message[3];
      final Object? rowStride = message[4];
      final Object? rotation = message[5];
      final Object? timestamp = message[6];
      if (data is! TransferableTypedData ||
          width is! int ||
          height is! int ||
          rowStride is! int ||
          rotation is! int ||
          timestamp is! int) {
        send(VisionProtocol.encodeError('A picture message was malformed', answersFrame: true));
        return;
      }
      final Uint8List source = data.materialize().asUint8List();
      final LumaSize size = LumaConverter.outputSize(
        srcWidth: width,
        srcHeight: height,
        rotationDegrees: rotation,
        targetLongSide: _config.analysisLongSide,
      );
      final int needed = size.width * size.height;
      if (_scratch.length != needed) {
        _scratch = Uint8List(needed);
      }
      LumaConverter.convert(
        source: source,
        srcWidth: width,
        srcHeight: height,
        rowStride: rowStride,
        rotationDegrees: rotation,
        size: size,
        out: _scratch,
      );
      final LiveFrameReport report = _tracker.process(
        LumaFrame(
          width: size.width,
          height: size.height,
          timestampMs: timestamp,
          pixels: _scratch,
        ),
      );
      send(VisionProtocol.encodeReport(report, width: size.width, height: size.height));
      final LiveDeliveryCapture? capture = report.capture;
      if (capture != null) {
        _sendCapture(capture, send);
      }
    } on Object catch (error) {
      send(VisionProtocol.encodeError('Picture analysis failed: $error', answersFrame: true));
    }
  }

  void _sendCapture(LiveDeliveryCapture capture, void Function(List<Object?> answer) send) {
    Uint8List? replay;
    try {
      replay = _tracker.encodeReplay(capture);
    } on Object catch (error) {
      // The delivery is still worth analysing without its replay.
      send(VisionProtocol.encodeError('The replay could not be packed: $error', answersFrame: false));
    }
    send(VisionProtocol.encodeCapture(capture, replay));
  }
}

/// Entry point of the background isolate. [args] is
/// `[SendPort toApp, nominalFps, analysisLongSide, replayBudgetBytes, maxReplayFrames]`.
@pragma('vm:entry-point')
void visionWorkerMain(List<Object?> args) {
  final SendPort toApp = args[0] as SendPort;
  final VisionWorkerCore core = VisionWorkerCore(
    config: VisionWorkerConfig(
      nominalFps: args[1] as int,
      analysisLongSide: args[2] as int,
      replayBudgetBytes: args[3] as int,
      maxReplayFrames: args[4] as int,
    ),
  );
  final ReceivePort commands = ReceivePort();
  commands.listen((Object? message) {
    if (message is List<Object?> && message.isNotEmpty && message[0] == VisionProtocol.stop) {
      commands.close();
      return;
    }
    core.handle(message, toApp.send);
  });
  toApp.send(<Object?>[VisionProtocol.ready, commands.sendPort]);
}

/// The app's end of the background vision worker.
///
/// The camera delivers a picture about every 33 ms, and finding the ball in it takes a good part of
/// that time, so the work runs in its own isolate. The app hands over each picture with
/// [offerFrame] and listens to [reports] (one per analysed picture, for the live overlay) and
/// [captures] (one per delivery).
final class VisionWorker {
  VisionWorker._(this.config);

  final VisionWorkerConfig config;

  final StreamController<DecodedReport> _reports = StreamController<DecodedReport>.broadcast();
  final StreamController<DecodedCapture> _captures = StreamController<DecodedCapture>.broadcast();
  final StreamController<String> _errors = StreamController<String>.broadcast();

  final ReceivePort _receive = ReceivePort();
  final ReceivePort _failures = ReceivePort();
  final Stopwatch _clock = Stopwatch()..start();
  StreamSubscription<Object?>? _receiveSub;
  StreamSubscription<Object?>? _failureSub;
  Isolate? _isolate;
  SendPort? _commands;
  final Completer<void> _ready = Completer<void>();

  final List<int> _offerTimes = <int>[];
  double _latencyMs = 0;
  int _inFlight = 0;
  int _lastActivityMs = 0;
  int _dropped = 0;
  int _processed = 0;
  bool _disposed = false;

  /// One report per analysed picture.
  Stream<DecodedReport> get reports => _reports.stream;

  /// One capture per delivery that was followed.
  Stream<DecodedCapture> get captures => _captures.stream;

  /// Problems in the worker (the worker keeps running after most of them).
  Stream<String> get errors => _errors.stream;

  /// Pictures dropped because the worker was busy.
  int get droppedFrames => _dropped;

  /// Pictures the worker has answered.
  int get processedFrames => _processed;

  /// Average time (ms) from handing over a picture to getting its report back. It includes the
  /// time the picture waited, so a number above one frame time means the phone cannot keep up.
  double get averageLatencyMs => _latencyMs;

  bool get isRunning => !_disposed && _commands != null;

  /// Starts the worker. Throws a [StateError] when it does not report ready within 5 seconds.
  static Future<VisionWorker> start({VisionWorkerConfig config = const VisionWorkerConfig()}) async {
    final VisionWorker worker = VisionWorker._(config);
    worker._receiveSub = worker._receive.listen(worker._onMessage);
    worker._failureSub = worker._failures.listen(worker._onFailure);
    try {
      worker._isolate = await Isolate.spawn<List<Object?>>(
        visionWorkerMain,
        <Object?>[
          worker._receive.sendPort,
          config.nominalFps,
          config.analysisLongSide,
          config.replayBudgetBytes,
          config.maxReplayFrames,
        ],
        onError: worker._failures.sendPort,
        debugName: 'gully-vision',
      );
      await worker._ready.future.timeout(const Duration(seconds: 5));
    } on Object catch (error) {
      await worker.dispose();
      throw StateError('The ball tracker could not start: $error');
    }
    return worker;
  }

  /// Hands one camera picture (its brightness plane) to the worker.
  ///
  /// Returns false when the picture was dropped because the worker still has [VisionWorkerConfig.maxInFlight]
  /// pictures to work on. [yPlane] is copied, so the caller may reuse it afterwards.
  bool offerFrame({
    required Uint8List yPlane,
    required int width,
    required int height,
    required int rowStride,
    required int rotationDegrees,
    required int timestampMs,
  }) {
    final SendPort? port = _commands;
    if (_disposed || port == null) {
      return false;
    }
    if (_inFlight > 0 && _clock.elapsedMilliseconds - _lastActivityMs > 3000) {
      // The worker has not answered for 3 seconds: assume the pictures were lost.
      _inFlight = 0;
      _offerTimes.clear();
    }
    if (_inFlight >= config.maxInFlight) {
      _dropped += 1;
      return false;
    }
    if (_inFlight == 0) {
      _lastActivityMs = _clock.elapsedMilliseconds;
    }
    _inFlight += 1;
    _offerTimes.add(_clock.elapsedMilliseconds);
    port.send(
      VisionProtocol.encodeFrame(
        yPlane: yPlane,
        width: width,
        height: height,
        rowStride: rowStride,
        rotationDegrees: rotationDegrees,
        timestampMs: timestampMs,
      ),
    );
    return true;
  }

  /// Makes the worker forget the scene and start learning it again.
  void reset() {
    _commands?.send(<Object?>[VisionProtocol.reset]);
  }

  /// Sets whether delivery tracking is active (false during stump marking).
  void setTrackingEnabled(bool enabled) {
    if (_disposed) {
      return;
    }
    _commands?.send(<Object?>[VisionProtocol.tracking, enabled ? 1 : 0]);
  }

  /// Stops the worker and closes the streams. Safe to call more than once.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _commands?.send(<Object?>[VisionProtocol.stop]);
    _commands = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    await _receiveSub?.cancel();
    await _failureSub?.cancel();
    _receive.close();
    _failures.close();
    if (!_ready.isCompleted) {
      _ready.complete();
    }
    await _reports.close();
    await _captures.close();
    await _errors.close();
  }

  void _onMessage(Object? message) {
    if (_disposed || message is! List<Object?> || message.isEmpty) {
      return;
    }
    switch (message[0]) {
      case VisionProtocol.ready:
        final Object? port = message.length > 1 ? message[1] : null;
        if (port is SendPort && !_ready.isCompleted) {
          _commands = port;
          _ready.complete();
        }
      case VisionProtocol.report:
        _answered();
        final DecodedReport? report = VisionProtocol.decodeReport(message);
        if (report != null) {
          _reports.add(report);
        }
      case VisionProtocol.capture:
        final DecodedCapture? capture = VisionProtocol.decodeCapture(message);
        if (capture != null) {
          _captures.add(capture);
        }
      case VisionProtocol.error:
        final DecodedError? error = VisionProtocol.decodeError(message);
        if (error != null) {
          if (error.answersFrame) {
            _answered();
          }
          _errors.add(error.message);
        }
      default:
        break;
    }
  }

  void _answered() {
    _processed += 1;
    final int now = _clock.elapsedMilliseconds;
    if (_inFlight > 0) {
      _inFlight -= 1;
    }
    if (_offerTimes.isNotEmpty) {
      final int waited = now - _offerTimes.removeAt(0);
      _latencyMs = _processed <= 1 ? waited.toDouble() : _latencyMs * 0.9 + waited * 0.1;
    }
    _lastActivityMs = now;
  }

  void _onFailure(Object? message) {
    if (_disposed) {
      return;
    }
    // The isolate died with an uncaught error: `[errorString, stackString]`.
    _inFlight = 0;
    _offerTimes.clear();
    _errors.add('The ball tracker stopped unexpectedly: ${message is List<Object?> ? message.first : message}');
  }
}
