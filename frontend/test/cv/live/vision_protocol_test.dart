import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/cv/live/live_tracker.dart';
import 'package:gully_umpire/cv/live/vision_protocol.dart';
import 'package:gully_umpire/cv/pipelines/ball_observation.dart';
import 'package:gully_umpire/cv/vision/luma_frame.dart';

LiveFrameReport sampleReport({
  LiveWatchState state = LiveWatchState.tracking,
  List<BallObservation>? candidates,
  List<BallObservation>? trail,
}) {
  return LiveFrameReport(
    timestampMs: 4321,
    state: state,
    candidates: candidates ??
        const <BallObservation>[
          BallObservation(timestampMs: 4321, x: 0.25, y: 0.5, confidence: 0.75, diameter: 0.03125),
          BallObservation(timestampMs: 4321, x: 0.75, y: 0.125, confidence: 0.5, diameter: 0.0625),
        ],
    trail: trail ??
        const <BallObservation>[
          BallObservation(timestampMs: 4254, x: 0.5, y: 0.875, confidence: 0.9375, diameter: 0.0375),
          BallObservation(timestampMs: 4288, x: 0.5, y: 0.8125, confidence: 0.875, diameter: 0.036),
        ],
    fps: 29.5,
    noise: 1.25,
    threshold: 14,
    foregroundFraction: 0.0078125,
  );
}

LiveDeliveryCapture sampleCapture() {
  return const LiveDeliveryCapture(
    observations: <BallObservation>[
      BallObservation(timestampMs: 1000, x: 0.5, y: 0.875, confidence: 0.9375, diameter: 0.0375),
      BallObservation(timestampMs: 1033, x: 0.5078125, y: 0.8125, confidence: 0.875, diameter: 0.0359375),
      BallObservation(timestampMs: 1066, x: 0.515625, y: 0.75, confidence: 0.8125, diameter: 0.034375),
    ],
    frameTimesMs: <int>[967, 1000, 1033, 1066, 1100],
    aspectRatio: 0.5625,
    framesProcessed: 47,
    frameWidth: 180,
    frameHeight: 320,
    trackQuality: 0.75,
    startMs: 1000,
    endMs: 1066,
  );
}

void main() {
  group('VisionProtocol report', () {
    test('survives the round trip with every field', () {
      final LiveFrameReport report = sampleReport();

      final DecodedReport? decoded = VisionProtocol.decodeReport(
        VisionProtocol.encodeReport(report, width: 180, height: 320),
      );

      expect(decoded, isNotNull);
      expect(decoded!.width, 180);
      expect(decoded.height, 320);
      final LiveFrameReport back = decoded.report;
      expect(back.timestampMs, 4321);
      expect(back.state, LiveWatchState.tracking);
      expect(back.fps, 29.5);
      expect(back.noise, 1.25);
      expect(back.threshold, 14);
      expect(back.foregroundFraction, 0.0078125);
      expect(back.capture, isNull);
      // Candidates carry the time of the picture they were found in.
      expect(back.candidates, report.candidates);
      expect(back.trail, report.trail);
    });

    test('keeps every watch state apart', () {
      for (final LiveWatchState state in LiveWatchState.values) {
        final DecodedReport? decoded = VisionProtocol.decodeReport(
          VisionProtocol.encodeReport(sampleReport(state: state), width: 90, height: 160),
        );

        expect(decoded!.report.state, state);
      }
    });

    test('an empty report has empty lists', () {
      final DecodedReport? decoded = VisionProtocol.decodeReport(
        VisionProtocol.encodeReport(
          sampleReport(candidates: const <BallObservation>[], trail: const <BallObservation>[]),
          width: 180,
          height: 320,
        ),
      );

      expect(decoded!.report.candidates, isEmpty);
      expect(decoded.report.trail, isEmpty);
    });

    test('is made of plain values and typed lists only', () {
      final List<Object?> message = VisionProtocol.encodeReport(sampleReport(), width: 180, height: 320);

      expect(message.first, VisionProtocol.report);
      for (final Object? part in message) {
        expect(
          part is String || part is int || part is double || part is Float64List,
          isTrue,
          reason: 'unexpected ${part.runtimeType}',
        );
      }
    });

    test('a malformed message gives null instead of throwing', () {
      final List<Object?> good = VisionProtocol.encodeReport(sampleReport(), width: 180, height: 320);

      expect(VisionProtocol.decodeReport(const <Object?>[]), isNull);
      expect(VisionProtocol.decodeReport(good.sublist(0, 10)), isNull);
      for (int i = 1; i < good.length; i++) {
        final List<Object?> broken = List<Object?>.of(good)..[i] = 'oops';
        expect(VisionProtocol.decodeReport(broken), isNull, reason: 'field $i');
      }
      final List<Object?> badState = List<Object?>.of(good)..[2] = LiveWatchState.values.length;
      expect(VisionProtocol.decodeReport(badState), isNull);
      final List<Object?> negativeState = List<Object?>.of(good)..[2] = -1;
      expect(VisionProtocol.decodeReport(negativeState), isNull);
      final List<Object?> intFps = List<Object?>.of(good)..[3] = 30;
      expect(VisionProtocol.decodeReport(intFps), isNull);
    });
  });

  group('VisionProtocol capture', () {
    test('survives the round trip with its replay file', () {
      final Uint8List replay = Uint8List.fromList(<int>[71, 85, 82, 49, 0, 255, 128, 7]);

      final DecodedCapture? decoded = VisionProtocol.decodeCapture(
        VisionProtocol.encodeCapture(sampleCapture(), replay),
      );

      expect(decoded, isNotNull);
      final LiveDeliveryCapture back = decoded!.capture;
      final LiveDeliveryCapture original = sampleCapture();
      expect(back.observations, original.observations);
      expect(back.frameTimesMs, original.frameTimesMs);
      expect(back.aspectRatio, original.aspectRatio);
      expect(back.framesProcessed, 47);
      expect(back.frameWidth, 180);
      expect(back.frameHeight, 320);
      expect(back.trackQuality, 0.75);
      expect(back.startMs, 1000);
      expect(back.endMs, 1066);
      expect(decoded.replay, replay);
    });

    test('works without a replay file', () {
      final DecodedCapture? decoded = VisionProtocol.decodeCapture(
        VisionProtocol.encodeCapture(sampleCapture(), null),
      );

      expect(decoded, isNotNull);
      expect(decoded!.replay, isNull);
      expect(decoded.capture.observations, hasLength(3));
    });

    test('carries the replay as transferable data, not as a copy in the list', () {
      final List<Object?> message = VisionProtocol.encodeCapture(sampleCapture(), Uint8List(16));

      expect(message.first, VisionProtocol.capture);
      expect(message.last, isA<TransferableTypedData>());
    });

    test('a malformed message gives null instead of throwing', () {
      final List<Object?> good = VisionProtocol.encodeCapture(sampleCapture(), null);

      expect(VisionProtocol.decodeCapture(const <Object?>[]), isNull);
      expect(VisionProtocol.decodeCapture(good.sublist(0, 10)), isNull);
      for (int i = 1; i < 10; i++) {
        final List<Object?> broken = List<Object?>.of(good)..[i] = 'oops';
        expect(VisionProtocol.decodeCapture(broken), isNull, reason: 'field $i');
      }
    });
  });

  group('VisionProtocol error', () {
    test('survives the round trip', () {
      final DecodedError? asked = VisionProtocol.decodeError(
        VisionProtocol.encodeError('Something broke', answersFrame: true),
      );
      final DecodedError? silent = VisionProtocol.decodeError(
        VisionProtocol.encodeError('Not about a picture', answersFrame: false),
      );

      expect(asked!.message, 'Something broke');
      expect(asked.answersFrame, isTrue);
      expect(silent!.message, 'Not about a picture');
      expect(silent.answersFrame, isFalse);
    });

    test('a malformed message gives null', () {
      expect(VisionProtocol.decodeError(const <Object?>[]), isNull);
      expect(VisionProtocol.decodeError(const <Object?>['error', 'text']), isNull);
      expect(VisionProtocol.decodeError(const <Object?>['error', 5, 1]), isNull);
      expect(VisionProtocol.decodeError(const <Object?>['error', 'text', 'yes']), isNull);
    });
  });

  group('VisionProtocol frame', () {
    test('hands the picture over as transferable data in a fixed layout', () {
      final Uint8List plane = Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6, 7, 8]);

      final List<Object?> message = VisionProtocol.encodeFrame(
        yPlane: plane,
        width: 4,
        height: 2,
        rowStride: 4,
        rotationDegrees: 90,
        timestampMs: 777,
      );

      expect(message, hasLength(7));
      expect(message[0], VisionProtocol.frame);
      expect(message[1], isA<TransferableTypedData>());
      expect(message.sublist(2), <Object?>[4, 2, 4, 90, 777]);
      expect((message[1]! as TransferableTypedData).materialize().asUint8List(), plane);
    });

    test('copies the plane, so the camera may reuse its buffer', () {
      final Uint8List plane = Uint8List.fromList(<int>[9, 9, 9, 9]);

      final List<Object?> message = VisionProtocol.encodeFrame(
        yPlane: plane,
        width: 2,
        height: 2,
        rowStride: 2,
        rotationDegrees: 0,
        timestampMs: 1,
      );
      plane.fillRange(0, plane.length, 0);

      expect((message[1]! as TransferableTypedData).materialize().asUint8List(), <int>[9, 9, 9, 9]);
    });

    test('the message names are all different', () {
      final Set<String> names = <String>{
        VisionProtocol.frame,
        VisionProtocol.reset,
        VisionProtocol.stop,
        VisionProtocol.ready,
        VisionProtocol.report,
        VisionProtocol.capture,
        VisionProtocol.error,
      };

      expect(names, hasLength(7));
    });
  });

  group('workerPictureSize', () {
    test('shrinks a sideways camera picture to an upright one of about the target length', () {
      final LumaSize size = workerPictureSize(width: 1280, height: 720, rotationDegrees: 90, targetLongSide: 640);

      expect(size.width, 360);
      expect(size.height, 640);
      expect(size.factor, 2);
    });

    test('keeps a small picture as it is', () {
      final LumaSize size = workerPictureSize(width: 320, height: 180, rotationDegrees: 0, targetLongSide: 640);

      expect(size.width, 320);
      expect(size.height, 180);
      expect(size.factor, 1);
    });
  });
}
