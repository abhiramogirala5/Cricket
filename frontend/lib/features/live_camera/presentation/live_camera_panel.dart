import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gully_umpire/app/theme/app_colors.dart';
import 'package:gully_umpire/app/theme/app_spacing.dart';
import 'package:gully_umpire/core/di/live_providers.dart';
import 'package:gully_umpire/core/widgets/message_banner.dart';
import 'package:gully_umpire/core/widgets/status_chip.dart';
import 'package:gully_umpire/cv/live/live_analysis.dart';
import 'package:gully_umpire/cv/live/live_session.dart';
import 'package:gully_umpire/cv/live/live_tracker.dart';
import 'package:gully_umpire/cv/live/umpire_camera_controller.dart';
import 'package:gully_umpire/cv/live/zoom_advice.dart';
import 'package:gully_umpire/cv/util/length_units.dart';
import 'package:gully_umpire/data/settings/live_settings.dart';
import 'package:gully_umpire/domain/decisions/wicket_family.dart';
import 'package:gully_umpire/features/live_camera/camera_distance.dart';
import 'package:gully_umpire/features/live_camera/live_camera_labels.dart';
import 'package:gully_umpire/features/live_camera/presentation/camera_preview_box.dart';
import 'package:gully_umpire/features/live_camera/presentation/live_overlay_painter.dart';

/// The umpire camera on the scoring page: the live picture with the ball being followed, what the
/// tracker is doing, and advice on where to put the phone.
///
/// The panel opens the camera when it appears and releases it when it goes away or the app is
/// sent to the background. Every delivery that was followed is handed to [onDelivery].
class LiveCameraPanel extends ConsumerStatefulWidget {
  const LiveCameraPanel({
    super.key,
    required this.matchId,
    required this.inputs,
    required this.onDelivery,
    required this.onMarkStumps,
  });

  final String matchId;

  /// The match facts the tracker works with. When they change the tracker is told at once.
  final LiveInputs inputs;

  /// Called for every delivery that was followed.
  final void Function(LiveDeliveryResult result) onDelivery;

  /// Opens the stump-marking page. The returned future completes when that page is closed; the
  /// panel gives the camera to it meanwhile (a phone camera can only be opened once).
  final Future<void> Function() onMarkStumps;

  @override
  ConsumerState<LiveCameraPanel> createState() => _LiveCameraPanelState();
}

class _LiveCameraPanelState extends ConsumerState<LiveCameraPanel> with WidgetsBindingObserver {
  late final UmpireCameraController _controller;
  StreamSubscription<LiveDeliveryResult>? _resultSub;
  bool _expanded = true;
  bool _markingStumps = false;
  bool _inBackground = false;

  bool _deliveryArmed = false;
  int _armedRemainingSeconds = 0;
  Timer? _countdownTimer;
  int _deliveryTimeoutSeconds = LiveSettings.defaultDeliveryTimeoutSeconds;

  LiveInputs _effectiveInputs({required bool trackDeliveries}) {
    LiveInputs effective = widget.inputs.copyWith(trackDeliveries: trackDeliveries);
    if (effective.cameraToBatterM == null && effective.wicket != null && effective.wicket!.isValid) {
      final double autoFeet = estimateDistanceFeetFromWicket(
        effective.wicket!.vertices,
        family: effective.wicketFamily ?? WicketFamily.traditionalStumps,
      );
      effective = effective.copyWith(cameraToBatterM: feetToMetres(autoFeet));
    }
    return effective;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = UmpireCameraController(
      openCamera: ref.read(frameSourceOpenerProvider),
      openSession: ref.read(liveSessionOpenerProvider),
      inputs: _effectiveInputs(trackDeliveries: false),
      keepAwake: ref.read(keepAwakeProvider),
    );
    _resultSub = _controller.results.listen((LiveDeliveryResult result) {
      if (mounted) {
        _disarmDelivery();
        widget.onDelivery(result);
      }
    });
    unawaited(_open());
  }

  @override
  void didUpdateWidget(LiveCameraPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.inputs != widget.inputs) {
      _controller.updateInputs(_effectiveInputs(trackDeliveries: _deliveryArmed));
    }
  }

  void _armDelivery() {
    if (!_controller.isRunning || _deliveryArmed) {
      return;
    }
    setState(() {
      _deliveryArmed = true;
      _armedRemainingSeconds = _deliveryTimeoutSeconds;
    });
    _controller.updateInputs(_effectiveInputs(trackDeliveries: true));

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_armedRemainingSeconds > 1) {
        setState(() {
          _armedRemainingSeconds--;
        });
      } else {
        _disarmDelivery();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Delivery timed out — tap "Start Delivery" when bowler is ready.'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });
  }

  void _disarmDelivery() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    if (_deliveryArmed) {
      setState(() {
        _deliveryArmed = false;
        _armedRemainingSeconds = 0;
      });
      _controller.updateInputs(_effectiveInputs(trackDeliveries: false));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_markingStumps) {
      return;
    }
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _disarmDelivery();
      _inBackground = true;
      unawaited(_controller.stop());
    } else if (state == AppLifecycleState.resumed && _inBackground) {
      _inBackground = false;
      unawaited(_open());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    unawaited(_resultSub?.cancel());
    _controller.dispose();
    super.dispose();
  }

  /// Starts the camera at the zoom the stumps were marked at.
  Future<void> _open() async {
    final LiveSettings? settings = ref.read(liveSettingsProvider);
    double? zoom;
    if (settings != null) {
      try {
        zoom = await settings.zoomFor(widget.matchId);
      } on Object {
        zoom = null;
      }
      try {
        final int savedTimeout = await settings.deliveryTimeoutSeconds();
        if (mounted) {
          setState(() {
            _deliveryTimeoutSeconds = savedTimeout;
          });
        }
      } on Object {
        // Keep default timeout.
      }
    }
    if (!mounted) {
      return;
    }
    _controller.setStartZoom(zoom);
    await _controller.start();
  }

  Future<void> _markStumps() async {
    if (_markingStumps) {
      return;
    }
    _disarmDelivery();
    _markingStumps = true;
    await _controller.stop();
    try {
      await widget.onMarkStumps();
    } finally {
      _markingStumps = false;
    }
    if (mounted) {
      await _open();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ListenableBuilder(
          listenable: _controller,
          builder: (BuildContext context, Widget? _) => _content(context),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final LiveSessionStatus status = _controller.status;
    final bool running = _controller.isRunning;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Icon(Icons.videocam_outlined, color: AppColors.pitchGreen),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'Umpire camera',
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            if (running)
              StatusChip(
                label: _deliveryArmed ? watchLabel(status.watch) : 'Standby (Tap Start)',
              ),
            IconButton(
              tooltip: _expanded ? 'Hide the picture' : 'Show the picture',
              icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
              onPressed: () => setState(() => _expanded = !_expanded),
            ),
          ],
        ),
        ..._body(context, status),
      ],
    );
  }

  List<Widget> _body(BuildContext context, LiveSessionStatus status) {
    final TextTheme text = Theme.of(context).textTheme;
    switch (_controller.phase) {
      case CameraPhase.idle:
      case CameraPhase.starting:
        return <Widget>[
          const SizedBox(height: AppSpacing.sm),
          const Row(
            children: <Widget>[
              SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: AppSpacing.md),
              Expanded(child: Text('Starting the camera…')),
            ],
          ),
        ];
      case CameraPhase.failed:
        return <Widget>[
          const SizedBox(height: AppSpacing.sm),
          MessageBanner(
            kind: BannerKind.error,
            title: 'The camera is not working',
            message: _controller.error ?? 'The camera could not be started.',
            actionLabel: 'Try again',
            onAction: () => unawaited(_open()),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'You can keep scoring by hand without the camera.',
            style: text.bodySmall?.copyWith(color: AppColors.inkMuted),
          ),
        ];
      case CameraPhase.running:
        break;
    }

    final String speed = speedLine(fps: status.fps, latencyMs: status.latencyMs);
    final ZoomAdvice advice = status.zoom;
    final String? problem = _controller.problem;
    return <Widget>[
      if (_expanded) ...<Widget>[
        const SizedBox(height: AppSpacing.sm),
        CameraPreviewBox(
          source: _controller.source,
          currentZoom: _controller.zoom,
          onZoomSelected: (double z) async {
            await _controller.setZoom(z);
            final LiveSettings? settings = ref.read(liveSettingsProvider);
            await settings?.setZoomFor(widget.matchId, z);
          },
          overlay: IgnorePointer(
            child: CustomPaint(
              painter: LiveOverlayPainter(
                candidates: status.candidates,
                trail: status.trail,
                wicket: widget.inputs.wicket,
              ),
            ),
          ),
        ),
      ],
      const SizedBox(height: AppSpacing.md),
      _deliveryArmingControls(context, status),
      const SizedBox(height: AppSpacing.sm),
      Text(
        _hint(status),
        style: text.bodySmall?.copyWith(color: AppColors.inkMuted),
      ),
      if (speed.isNotEmpty)
        Text(speed, style: text.bodySmall?.copyWith(color: AppColors.inkMuted)),
      if (isStruggling(
        fps: status.fps,
        latencyMs: status.latencyMs,
        framesAnalysed: status.framesAnalysed,
        framesDropped: status.framesDropped,
      )) ...<Widget>[
        const SizedBox(height: AppSpacing.sm),
        const MessageBanner(
          kind: BannerKind.warning,
          title: 'This phone is struggling',
          message: 'It cannot look at every picture, so a fast ball may be missed. Close other '
              'apps and keep the phone cool.',
        ),
      ],
      if (advice.level != FramingLevel.unknown) ...<Widget>[
        const SizedBox(height: AppSpacing.sm),
        MessageBanner(kind: bannerKindFor(advice.level), message: advice.message),
      ],
      if (status.sceneChanged) ...<Widget>[
        const SizedBox(height: AppSpacing.sm),
        MessageBanner(
          kind: BannerKind.warning,
          title: 'The picture moved',
          message: 'The phone may have been moved, so the marked stumps may be in the wrong '
              'place. Check that the amber outline sits on the stumps.',
          actionLabel: 'Mark stumps again',
          onAction: () => unawaited(_markStumps()),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _controller.acknowledgeSceneChange,
            child: const Text('The outline is still right'),
          ),
        ),
      ],
      if (problem != null) ...<Widget>[
        const SizedBox(height: AppSpacing.sm),
        MessageBanner(kind: BannerKind.warning, message: problem),
      ],
      const SizedBox(height: AppSpacing.xs),
      Wrap(
        spacing: AppSpacing.sm,
        children: <Widget>[
          TextButton.icon(
            onPressed: () => unawaited(_markStumps()),
            icon: const Icon(Icons.crop_free, size: 18),
            label: const Text('Mark stumps again'),
          ),
          TextButton.icon(
            onPressed: _controller.relearn,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Learn the scene again'),
          ),
        ],
      ),
    ];
  }

  Widget _deliveryArmingControls(BuildContext context, LiveSessionStatus status) {
    if (_deliveryArmed) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.ballRed.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.ballRed.withValues(alpha: 0.50)),
        ),
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.ballRed),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'RECORDING DELIVERY... Bowl now! (${_armedRemainingSeconds}s)',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.ballRed,
                      fontSize: 13,
                    ),
                  ),
                ),
                OutlinedButton(
                  onPressed: _disarmDelivery,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                    minimumSize: const Size(60, 32),
                  ),
                  child: const Text('Cancel', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: _deliveryTimeoutSeconds > 0
                    ? _armedRemainingSeconds / _deliveryTimeoutSeconds
                    : 0.0,
                backgroundColor: AppColors.ballRed.withValues(alpha: 0.20),
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.ballRed),
                minHeight: 4,
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      children: <Widget>[
        Expanded(
          child: SizedBox(
            height: 48,
            child: FilledButton.icon(
              icon: const Icon(Icons.sports_cricket, size: 20),
              label: const Text(
                'START DELIVERY',
                style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.8),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.pitchGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _controller.isRunning ? _armDelivery : null,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        PopupMenuButton<int>(
          icon: const Icon(Icons.timer_outlined, color: AppColors.pitchGreen),
          tooltip: 'Delivery timeout (${_deliveryTimeoutSeconds}s)',
          initialValue: _deliveryTimeoutSeconds,
          onSelected: (int sec) {
            setState(() {
              _deliveryTimeoutSeconds = sec;
            });
            final LiveSettings? settings = ref.read(liveSettingsProvider);
            settings?.setDeliveryTimeoutSeconds(sec);
          },
          itemBuilder: (BuildContext context) => const <PopupMenuEntry<int>>[
            PopupMenuItem<int>(value: 6, child: Text('6s (Fast Bowler)')),
            PopupMenuItem<int>(value: 8, child: Text('8s (Standard)')),
            PopupMenuItem<int>(value: 12, child: Text('12s (Long Run-up / Spin)')),
            PopupMenuItem<int>(value: 16, child: Text('16s (Casual / Kids)')),
          ],
        ),
      ],
    );
  }

  String _hint(LiveSessionStatus status) {
    if (!_deliveryArmed) {
      return 'Camera is on standby. Tap "START DELIVERY" when the bowler is ready to bowl.';
    }
    switch (status.watch) {
      case LiveWatchState.learning:
        return 'Keep the phone still for a moment while it learns the scene. The batter can stand '
            'at the crease, but nobody should walk through the picture.';
      case LiveWatchState.watching:
        if (status.poseSeen) {
          final String h = status.batterHeightM != null
              ? ' (${status.batterHeightM!.toStringAsFixed(2)} m)'
              : '';
          return 'Ready! Batter in view$h; bowl now.';
        }
        return 'Ready! Keep the whole batter and the stumps in the picture; bowl now.';
      case LiveWatchState.tracking:
        return 'Following the ball…';
      case LiveWatchState.cooldown:
        return 'Looking at the delivery…';
    }
  }
}
