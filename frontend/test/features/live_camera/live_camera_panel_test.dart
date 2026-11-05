import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/core/di/live_providers.dart';
import 'package:gully_umpire/cv/live/live_analysis.dart';
import 'package:gully_umpire/features/live_camera/presentation/live_camera_panel.dart';

import '../../support/live_fixtures.dart';

void main() {
  late List<String> log;
  late List<FakeFrameSource> cameras;
  late List<FakeLiveSession> sessions;
  late List<bool> awake;

  setUp(() {
    log = <String>[];
    cameras = <FakeFrameSource>[];
    sessions = <FakeLiveSession>[];
    awake = <bool>[];
  });

  Widget buildPanel({
    required LiveInputs inputs,
    required void Function(LiveDeliveryResult) onDelivery,
    Future<void> Function()? onMarkStumps,
  }) {
    return ProviderScope(
      overrides: [
        frameSourceOpenerProvider.overrideWithValue(() async {
          final FakeFrameSource camera = FakeFrameSource('camera${cameras.length + 1}', log);
          cameras.add(camera);
          log.add('${camera.name}.open');
          return camera;
        }),
        liveSessionOpenerProvider.overrideWithValue((LiveInputs given) async {
          final FakeLiveSession session = FakeLiveSession('session${sessions.length + 1}', log, given);
          sessions.add(session);
          log.add('${session.name}.open');
          return session;
        }),
        keepAwakeProvider.overrideWithValue((bool enabled) async {
          awake.add(enabled);
        }),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LiveCameraPanel(
              matchId: 'match-1',
              inputs: inputs,
              onDelivery: onDelivery,
              onMarkStumps: onMarkStumps ?? () async {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('starts with tracking disarmed and shows START DELIVERY button', (
    WidgetTester tester,
  ) async {
    final LiveInputs inputs = makeLiveInputs();
    LiveDeliveryResult? delivered;

    await tester.pumpWidget(
      buildPanel(
        inputs: inputs,
        onDelivery: (LiveDeliveryResult r) => delivered = r,
      ),
    );
    await tester.pumpAndSettle();

    // Verify session was opened with trackDeliveries == false
    expect(sessions, hasLength(1));
    expect(sessions.single.inputs.trackDeliveries, isFalse);

    // Verify Standby status and Start Delivery button
    expect(find.text('Standby (Tap Start)'), findsOneWidget);
    expect(find.text('START DELIVERY'), findsOneWidget);
    expect(delivered, isNull);
  });

  testWidgets('tapping START DELIVERY arms tracking with countdown and cancel button', (
    WidgetTester tester,
  ) async {
    final LiveInputs inputs = makeLiveInputs();
    LiveDeliveryResult? delivered;

    await tester.pumpWidget(
      buildPanel(
        inputs: inputs,
        onDelivery: (LiveDeliveryResult r) => delivered = r,
      ),
    );
    await tester.pumpAndSettle();

    // Tap Start Delivery
    await tester.tap(find.text('START DELIVERY'));
    await tester.pump();

    // Verify armed state UI
    expect(find.textContaining('RECORDING DELIVERY... Bowl now!'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    // Verify session received trackDeliveries == true
    expect(sessions.single.inputs.trackDeliveries, isTrue);

    // Tap Cancel
    await tester.tap(find.text('Cancel'));
    await tester.pump();

    // Returns to standby
    expect(find.text('START DELIVERY'), findsOneWidget);
    expect(sessions.single.inputs.trackDeliveries, isFalse);
    expect(delivered, isNull);
  });

  testWidgets('receiving a delivery invokes onDelivery and automatically disarms', (
    WidgetTester tester,
  ) async {
    final LiveInputs inputs = makeLiveInputs();
    LiveDeliveryResult? delivered;

    await tester.pumpWidget(
      buildPanel(
        inputs: inputs,
        onDelivery: (LiveDeliveryResult r) => delivered = r,
      ),
    );
    await tester.pumpAndSettle();

    // Tap Start Delivery
    await tester.tap(find.text('START DELIVERY'));
    await tester.pump();

    expect(sessions.single.inputs.trackDeliveries, isTrue);

    // Simulate delivery result arriving from camera session
    final LiveDeliveryResult result = makeLiveResult();
    sessions.single.resultController.add(result);
    await tester.pump();

    // Verify delivery callback received result
    expect(delivered, equals(result));

    // Verify automatically disarmed back to Standby and Start Delivery button returns
    expect(find.text('START DELIVERY'), findsOneWidget);
    expect(sessions.single.inputs.trackDeliveries, isFalse);
  });

  testWidgets('delivery window timeout automatically disarms tracking', (
    WidgetTester tester,
  ) async {
    final LiveInputs inputs = makeLiveInputs();
    LiveDeliveryResult? delivered;

    await tester.pumpWidget(
      buildPanel(
        inputs: inputs,
        onDelivery: (LiveDeliveryResult r) => delivered = r,
      ),
    );
    await tester.pumpAndSettle();

    // Tap Start Delivery
    await tester.tap(find.text('START DELIVERY'));
    await tester.pump();
    expect(sessions.single.inputs.trackDeliveries, isTrue);

    // Fast-forward 8 seconds to trigger timeout
    await tester.pump(const Duration(seconds: 8));

    // Verify automatically disarmed after timeout and snackbar displayed
    expect(find.text('START DELIVERY'), findsOneWidget);
    expect(sessions.single.inputs.trackDeliveries, isFalse);
    expect(delivered, isNull);
    expect(find.textContaining('Delivery timed out'), findsOneWidget);
  });
}
