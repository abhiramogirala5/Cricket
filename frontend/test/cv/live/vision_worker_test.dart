import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/cv/live/live_tracker.dart';
import 'package:gully_umpire/cv/live/replay_codec.dart';
import 'package:gully_umpire/cv/live/vision_protocol.dart';
import 'package:gully_umpire/cv/live/vision_worker.dart';
import 'package:gully_umpire/cv/pipelines/ball_observation.dart';
import 'package:gully_umpire/cv/vision/luma_frame.dart';

import '../../support/synthetic_scene.dart';

const int ballStart = 12;
const int ballFrames = 22;
const int totalFrames = ballStart + ballFrames + 30;

LumaFrame sceneFrame(int index) {
  final int step = index - ballStart;
  return SyntheticScene.frame(
    index,
    discs: step >= 0 && step < ballFrames
        ? <SceneDisc>[SyntheticScene.ball(step, ballFrames)]
        : const <SceneDisc>[],
  );
}

/// What the camera hands over for an upright [frame] when the sensor is turned by [rotation]
/// degrees and every row is padded to [padding] extra bytes (filled with a marker value).
({Uint8List bytes, int width, int height, int rowStride}) cameraPlane(
  LumaFrame frame, {
  int rotation = 0,
  int padding = 0,
}) {
  final int uprightWidth = frame.width;
  final int uprightHeight = frame.height;
  final bool swapped = rotation == 90 || rotation == 270;
  final int sourceWidth = swapped ? uprightHeight : uprightWidth;
  final int sourceHeight = swapped ? uprightWidth : uprightHeight;
  final int stride = sourceWidth + padding;
  final Uint8List bytes = Uint8List(stride * sourceHeight)..fillRange(0, stride * sourceHeight, 255);
  for (int uy = 0; uy < uprightHeight; uy++) {
    for (int ux = 0; ux < uprightWidth; ux++) {
      final int value = frame.pixels[uy * uprightWidth + ux];
      final int sx;
      final int sy;
      switch (rotation) {
        case 90:
          sx = uy;
          sy = sourceHeight - 1 - ux;
        case 180:
          sx = sourceWidth - 1 - ux;
          sy = sourceHeight - 1 - uy;
        case 270:
          sx = sourceWidth - 1 - uy;
          sy = ux;
        default:
          sx = ux;
          sy = uy;
      }
      bytes[sy * stride + sx] = value;
    }
  }
  return (bytes: bytes, width: sourceWidth, height: sourceHeight, rowStride: stride);
}

List<Object?> frameMessage(LumaFrame frame, {int rotation = 0, int padding = 0}) {
  final ({Uint8List bytes, int width, int height, int rowStride}) plane =
      cameraPlane(frame, rotation: rotation, padding: padding);
  return VisionProtocol.encodeFrame(
    yPlane: plane.bytes,
    width: plane.width,
    height: plane.height,
    rowStride: plane.rowStride,
    rotationDegrees: rotation,
    timestampMs: frame.timestampMs,
  );
}

/// Runs a whole delivery through a worker core and returns everything it answered.
List<List<Object?>> runCore({int rotation = 0, int padding = 0}) {
  final VisionWorkerCore core = VisionWorkerCore();
  final List<List<Object?>> answers = <List<Object?>>[];
  for (int i = 0; i < totalFrames; i++) {
    core.handle(frameMessage(sceneFrame(i), rotation: rotation, padding: padding), answers.add);
  }
  return answers;
}

List<DecodedReport> reportsOf(List<List<Object?>> answers) {
  return <DecodedReport>[
    for (final List<Object?> answer in answers)
      if (answer.first == VisionProtocol.report) VisionProtocol.decodeReport(answer)!,
  ];
}

List<DecodedCapture> capturesOf(List<List<Object?>> answers) {
  return <DecodedCapture>[
    for (final List<Object?> answer in answers)
      if (answer.first == VisionProtocol.capture) VisionProtocol.decodeCapture(answer)!,
  ];
}

void expectOneGoodDelivery(List<List<Object?>> answers) {
  final List<DecodedReport> reports = reportsOf(answers);
  final List<DecodedCapture> captures = capturesOf(answers);

  expect(reports, hasLength(totalFrames));
  expect(reports.first.width, SyntheticScene.width);
  expect(reports.first.height, SyntheticScene.height);
  expect(captures, hasLength(1));
  final LiveDeliveryCapture capture = captures.single.capture;
  expect(capture.isUsable, isTrue);
  expect(capture.observations.length, greaterThanOrEqualTo(15));
  for (final BallObservation o in capture.observations) {
    final int index = SyntheticScene.indexOfTime(o.timestampMs);
    final SceneDisc truth = SyntheticScene.ball(index - ballStart, ballFrames);
    expect(o.x * SyntheticScene.width, closeTo(truth.cx + 0.5, 1.5));
    expect(o.y * SyntheticScene.height, closeTo(truth.cy + 0.5, 1.5));
  }
  final Uint8List? replay = captures.single.replay;
  expect(replay, isNotNull);
  final ReplayReader reader = ReplayReader.parse(replay!);
  expect(reader.width, SyntheticScene.width);
  expect(reader.height, SyntheticScene.height);
  expect(reader.frameCount, greaterThanOrEqualTo(ballFrames));
}

void main() {
  group('VisionWorkerCore', () {
    test('turns upright camera pictures into reports and one capture with its replay', () {
      final List<List<Object?>> answers = runCore();

      expectOneGoodDelivery(answers);
    });

    test('the capture follows the report of the picture that ended the delivery', () {
      final List<List<Object?>> answers = runCore();

      final int captureAt = answers.indexWhere((List<Object?> a) => a.first == VisionProtocol.capture);
      expect(captureAt, greaterThan(0));
      expect(answers[captureAt - 1].first, VisionProtocol.report);
      expect(VisionProtocol.decodeReport(answers[captureAt - 1])!.report.state, LiveWatchState.cooldown);
    });

    test('ignores the padding at the end of every camera row', () {
      expectOneGoodDelivery(runCore(padding: 12));
    });

    test('turns a sideways sensor picture upright (90, 180 and 270 degrees)', () {
      for (final int rotation in <int>[90, 180, 270]) {
        expectOneGoodDelivery(runCore(rotation: rotation, padding: 4));
      }
    });

    test('shrinks a large picture by a whole factor before looking for the ball', () {
      final VisionWorkerCore core = VisionWorkerCore(
        config: const VisionWorkerConfig(analysisLongSide: 160),
      );
      final List<List<Object?>> answers = <List<Object?>>[];

      core.handle(frameMessage(sceneFrame(0)), answers.add);

      final DecodedReport report = reportsOf(answers).single;
      // 320 / 160 = 2: the 180 x 320 camera picture becomes 90 x 160.
      expect(report.width, 90);
      expect(report.height, 160);
    });

    test('a reset makes it learn the scene again', () {
      final VisionWorkerCore core = VisionWorkerCore();
      final List<List<Object?>> answers = <List<Object?>>[];
      for (int i = 0; i < 5; i++) {
        core.handle(frameMessage(sceneFrame(i)), answers.add);
      }
      expect(reportsOf(answers).last.report.state, LiveWatchState.watching);

      core.handle(<Object?>[VisionProtocol.reset], answers.add);
      core.handle(frameMessage(sceneFrame(5)), answers.add);

      expect(reportsOf(answers).last.report.state, LiveWatchState.learning);
    });

    test('answers nothing to messages it does not understand', () {
      final VisionWorkerCore core = VisionWorkerCore();
      final List<List<Object?>> answers = <List<Object?>>[];

      core.handle('hello', answers.add);
      core.handle(null, answers.add);
      core.handle(<Object?>[], answers.add);
      core.handle(<Object?>['unknown'], answers.add);
      core.handle(<Object?>[VisionProtocol.stop], answers.add);

      expect(answers, isEmpty);
    });

    test('answers a broken picture message with an error that stands in for its report', () {
      final VisionWorkerCore core = VisionWorkerCore();
      final List<List<Object?>> answers = <List<Object?>>[];

      core.handle(<Object?>[VisionProtocol.frame, 1, 2], answers.add);
      core.handle(<Object?>[VisionProtocol.frame, 'bytes', 180, 320, 180, 0, 0], answers.add);
      // A real picture message whose data is far too short for the stated size.
      core.handle(
        VisionProtocol.encodeFrame(
          yPlane: Uint8List(100),
          width: 180,
          height: 320,
          rowStride: 180,
          rotationDegrees: 0,
          timestampMs: 0,
        ),
        answers.add,
      );

      expect(answers, hasLength(3));
      for (final List<Object?> answer in answers) {
        final DecodedError? error = VisionProtocol.decodeError(answer);
        expect(error, isNotNull);
        expect(error!.answersFrame, isTrue);
        expect(error.message, isNotEmpty);
      }
      expect(VisionProtocol.decodeError(answers.last)!.message, contains('Picture analysis failed'));
    });

    test('keeps working after a broken picture', () {
      final VisionWorkerCore core = VisionWorkerCore();
      final List<List<Object?>> answers = <List<Object?>>[];
      core.handle(<Object?>[VisionProtocol.frame], answers.add);

      core.handle(frameMessage(sceneFrame(0)), answers.add);

      expect(reportsOf(answers), hasLength(1));
    });
  });

  group('VisionWorker (in its own isolate)', () {
    late VisionWorker worker;

    setUp(() async {
      worker = await VisionWorker.start();
    });

    tearDown(() async {
      await worker.dispose();
    });

    Future<DecodedReport> offerAndWait(LumaFrame frame) async {
      final Future<DecodedReport> next = worker.reports.first.timeout(const Duration(seconds: 20));
      final bool accepted = worker.offerFrame(
        yPlane: frame.pixels,
        width: frame.width,
        height: frame.height,
        rowStride: frame.width,
        rotationDegrees: 0,
        timestampMs: frame.timestampMs,
      );
      expect(accepted, isTrue);
      return next;
    }

    test('is running after it has started', () {
      expect(worker.isRunning, isTrue);
      expect(worker.droppedFrames, 0);
      expect(worker.processedFrames, 0);
    });

    test('finds a delivery in pictures sent from this isolate and sends back the replay', () async {
      final Completer<DecodedCapture> capture = Completer<DecodedCapture>();
      final StreamSubscription<DecodedCapture> subscription = worker.captures.listen(capture.complete);
      addTearDown(subscription.cancel);

      DecodedReport? last;
      for (int i = 0; i < totalFrames; i++) {
        last = await offerAndWait(sceneFrame(i));
      }

      final DecodedCapture found = await capture.future.timeout(const Duration(seconds: 20));
      expect(last!.report.state, LiveWatchState.cooldown);
      expect(found.capture.isUsable, isTrue);
      expect(found.capture.observations.length, greaterThanOrEqualTo(15));
      expect(found.replay, isNotNull);
      expect(ReplayReader.parse(found.replay!).frameCount, greaterThanOrEqualTo(ballFrames));
      expect(worker.processedFrames, totalFrames);
      expect(worker.droppedFrames, 0);
      expect(worker.averageLatencyMs, inInclusiveRange(0, 5000));
    });

    test('drops pictures instead of falling behind', () async {
      final LumaFrame frame = sceneFrame(0);
      bool offer() => worker.offerFrame(
            yPlane: frame.pixels,
            width: frame.width,
            height: frame.height,
            rowStride: frame.width,
            rotationDegrees: 0,
            timestampMs: frame.timestampMs,
          );
      final Future<List<DecodedReport>> two = worker.reports.take(2).toList();

      final List<bool> accepted = <bool>[offer(), offer(), offer(), offer()];

      expect(accepted, <bool>[true, true, false, false]);
      expect(worker.droppedFrames, 2);
      await two.timeout(const Duration(seconds: 20));
      expect(worker.processedFrames, 2);
      // The worker is free again.
      expect(offer(), isTrue);
    });

    test('forgets the scene when asked to', () async {
      for (int i = 0; i < 5; i++) {
        await offerAndWait(sceneFrame(i));
      }

      worker.reset();
      final DecodedReport report = await offerAndWait(sceneFrame(5));

      expect(report.report.state, LiveWatchState.learning);
    });

    test('reports an error for a picture it cannot read and stays usable', () async {
      final Future<String> error = worker.errors.first.timeout(const Duration(seconds: 20));

      expect(
        worker.offerFrame(
          yPlane: Uint8List(10),
          width: 180,
          height: 320,
          rowStride: 180,
          rotationDegrees: 0,
          timestampMs: 0,
        ),
        isTrue,
      );

      expect(await error, contains('Picture analysis failed'));
      final DecodedReport report = await offerAndWait(sceneFrame(0));
      expect(report.width, SyntheticScene.width);
    });

    test('refuses pictures after it was disposed, and can be disposed twice', () async {
      await worker.dispose();
      await worker.dispose();

      expect(worker.isRunning, isFalse);
      expect(
        worker.offerFrame(
          yPlane: Uint8List(4),
          width: 2,
          height: 2,
          rowStride: 2,
          rotationDegrees: 0,
          timestampMs: 0,
        ),
        isFalse,
      );
    });
  });
}
