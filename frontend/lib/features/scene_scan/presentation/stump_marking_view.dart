import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gully_umpire/app/theme/app_colors.dart';
import 'package:gully_umpire/app/theme/app_spacing.dart';
import 'package:gully_umpire/core/di/core_providers.dart';
import 'package:gully_umpire/core/di/cv_providers.dart';
import 'package:gully_umpire/core/di/data_providers.dart';
import 'package:gully_umpire/core/di/live_providers.dart';
import 'package:gully_umpire/core/widgets/friendly_error.dart';
import 'package:gully_umpire/core/widgets/message_banner.dart';
import 'package:gully_umpire/core/widgets/status_chip.dart';
import 'package:gully_umpire/cv/geometry/point2d.dart';
import 'package:gully_umpire/cv/geometry/polygon.dart';
import 'package:gully_umpire/cv/live/ball_kind.dart';
import 'package:gully_umpire/cv/live/live_analysis.dart';
import 'package:gully_umpire/cv/live/live_session.dart';
import 'package:gully_umpire/cv/live/manual_wicket.dart';
import 'package:gully_umpire/cv/live/umpire_camera_controller.dart';
import 'package:gully_umpire/cv/live/zoom_advice.dart';
import 'package:gully_umpire/cv/pipelines/pipelines.dart';
import 'package:gully_umpire/cv/scene/optical_wicket_tracker.dart';
import 'package:gully_umpire/data/settings/live_settings.dart';
import 'package:gully_umpire/domain/aggregates/match_bundle.dart';
import 'package:gully_umpire/domain/decisions/wicket_family.dart';
import 'package:gully_umpire/features/live_camera/camera_distance.dart';
import 'package:gully_umpire/features/live_camera/live_camera_labels.dart';
import 'package:gully_umpire/features/live_camera/live_inputs_builder.dart';
import 'package:gully_umpire/features/live_camera/presentation/camera_distance_field.dart';
import 'package:gully_umpire/features/live_camera/presentation/camera_preview_box.dart';
import 'package:gully_umpire/features/live_camera/presentation/live_overlay_painter.dart';
import 'package:gully_umpire/features/live_camera/stump_handles.dart';
import 'package:gully_umpire/features/umpiring/umpiring_mappers.dart';

/// Marks the wicket on the live camera picture: the umpire drags four corners onto the stumps (or
/// the chair, the pile of bricks, ... that is used as the wicket).
///
/// The live umpire does not guess where the wicket is. The person who stands there says so, and
/// the app uses exactly that outline to judge hits, LBW and the batter's size.
class StumpMarkingView extends ConsumerStatefulWidget {
  const StumpMarkingView({
    super.key,
    required this.bundle,
    required this.onSaved,
    required this.onClose,
    this.onSkip,
  });

  final MatchBundle bundle;

  /// Called after the marked stumps were stored (and the camera released).
  final VoidCallback onSaved;

  /// Called when the person leaves without marking (the camera is released first).
  final VoidCallback onClose;

  /// Lets the person carry on without the assistant. `null` when the page was opened to mark the
  /// stumps again during a match.
  final VoidCallback? onSkip;

  @override
  ConsumerState<StumpMarkingView> createState() => _StumpMarkingViewState();
}

class _StumpMarkingViewState extends ConsumerState<StumpMarkingView> {
  late final UmpireCameraController _controller;
  late List<Point2D> _corners;
  late WicketFamily _family;
  final TextEditingController _distanceText = TextEditingController();
  DistanceEntry _distance = DistanceEntry.empty;
  bool _userEditedDistance = false;
  bool _isAutoCalculated = false;
  final Stopwatch _clock = Stopwatch()..start();
  int? _activeCorner;
  bool _draggingShape = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final WicketTarget? existing = wicketTargetFrom(widget.bundle.activeWicket);
    final List<Point2D>? known = existing?.polygon.vertices;
    _corners = known != null && known.length == 4 ? List<Point2D>.of(known) : defaultWicketCorners();
    _family = existing?.family ?? WicketFamily.traditionalStumps;
    _controller = UmpireCameraController(
      openCamera: ref.read(frameSourceOpenerProvider),
      openSession: ref.read(liveSessionOpenerProvider),
      inputs: _inputs(ref.read(ballKindProvider).valueOrNull ?? BallKind.cricketBall),
      keepAwake: ref.read(keepAwakeProvider),
    );
    unawaited(_open());
  }

  @override
  void dispose() {
    _controller.dispose();
    _distanceText.dispose();
    super.dispose();
  }

  LiveInputs _inputs(BallKind ball) {
    final LiveInputs base = liveInputsFor(
      bundle: widget.bundle,
      strikerId: null,
      policy: ref.read(devicePolicyProvider),
      config: ref.read(appConfigProvider),
      ballKind: ball,
      cameraToBatterFeet: _distance.feet,
    );
    return base.copyWith(
      wicket: Polygon(_corners),
      wicketFamily: _family,
      trackDeliveries: false,
    );
  }

  Future<void> _open() async {
    // Start at the zoom this match was marked at before, so that a second marking sees the same
    // picture as the match will.
    final LiveSettings? settings = ref.read(liveSettingsProvider);
    double? zoom;
    double? feet;
    if (settings != null) {
      try {
        zoom = await settings.zoomFor(widget.bundle.match.id);
        feet = await settings.distanceFeetFor(widget.bundle.match.id);
      } on Object {
        zoom = null;
        feet = null;
      }
    }
    if (!mounted) {
      return;
    }
    if (feet != null && _distanceText.text.isEmpty) {
      _distanceText.text = distanceText(feet);
      setState(() {
        _distance = parseDistanceFeet(_distanceText.text);
        _userEditedDistance = true;
        _isAutoCalculated = false;
      });
      _sendInputs();
    } else if (_distanceText.text.isEmpty) {
      _autoUpdateDistance();
    }
    _controller.setStartZoom(zoom);
    await _controller.start();
  }

  void _autoUpdateDistance() {
    if (_userEditedDistance) {
      return;
    }
    final double autoFeet = estimateDistanceFeetFromWicket(
      _corners,
      zoom: _controller.zoom,
      family: _family,
    );
    final String text = distanceText(autoFeet);
    _distanceText.text = text;
    setState(() {
      _distance = parseDistanceFeet(text);
      _isAutoCalculated = true;
    });
    _sendInputs();
  }

  void _distanceChanged(String raw) {
    setState(() {
      _distance = parseDistanceFeet(raw);
      _userEditedDistance = true;
      _isAutoCalculated = false;
    });
    _sendInputs();
  }

  void _autoDetectWicket() {
    final LiveSessionStatus status = _controller.status;
    final bool hasPose = status.poseSeen && status.batterGroundPoint != null;
    final double currentDist = _distance.isValid ? _distance.feet! : 66.0;

    final Point2D searchCenter = status.batterGroundPoint ?? const Point2D(0.50, 0.65);
    final OpticalWicketResult optical = _controller.detectOrRefineWicket(
      searchCenter: searchCenter,
      family: _family,
      targetDistanceFeet: currentDist,
      zoom: _controller.zoom,
    );

    final List<Point2D> finalCorners;
    if (optical.isOpticallyRefined) {
      finalCorners = optical.corners;
    } else if (hasPose) {
      finalCorners = autoDetectWicketCorners(
        batterGroundPoint: status.batterGroundPoint,
        batterHeightNorm: status.batterHeightNorm,
        candidates: status.candidates,
        family: _family,
        targetDistanceFeet: currentDist,
        zoom: _controller.zoom,
      );
    } else {
      finalCorners = optical.corners;
    }

    setState(() {
      _corners = finalCorners;
      _userEditedDistance = false;
    });

    _controller.lockSpatialAnchor(finalCorners);
    _autoUpdateDistance();
    _sendInputs();

    if (mounted) {
      final String msg = optical.isOpticallyRefined
          ? '🔒 Physical stumps detected (${_family.label})! Spatial motion tracking active.'
          : (hasPose
              ? '🔒 Wicket snapped to batter crease (${_family.label})! Spatial motion tracking active.'
              : '🔒 Wicket locked for ${_family.label}. Spatial motion tracking active.');
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _applyPitchPreset(double feet) {
    final List<Point2D> presetCorners = smartWicketCorners(
      family: _family,
      centerX: 0.50,
      groundY: 0.65,
      targetDistanceFeet: feet,
      zoom: _controller.zoom,
    );
    setState(() {
      _corners = presetCorners;
      _distance = DistanceEntry.valid(feet);
      _distanceText.text = distanceText(feet);
      _userEditedDistance = false;
      _isAutoCalculated = true;
    });
    _sendInputs();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Corners scaled for ${distanceText(feet)} ft pitch (${_family.label})'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _sendInputs() {
    _controller.updateInputs(_inputs(ref.read(ballKindProvider).valueOrNull ?? BallKind.cricketBall));
  }

  // ---- Dragging ----------------------------------------------------------------------------

  Point2D _normalised(Offset local, Size size) {
    final double x = size.width <= 0 ? 0 : local.dx / size.width;
    final double y = size.height <= 0 ? 0 : local.dy / size.height;
    return Point2D(x, y);
  }

  void _dragStart(DragStartDetails details, Size size) {
    _controller.unlockSpatialAnchor();
    final Point2D at = _normalised(details.localPosition, size);
    final int? corner = nearestCorner(_corners, at, maxDistance: 0.16);
    setState(() {
      _activeCorner = corner;
      _draggingShape = corner == null && Polygon(_corners).containsPoint(at);
    });
  }

  void _dragUpdate(DragUpdateDetails details, Size size) {
    final int? corner = _activeCorner;
    if (corner != null) {
      final Point2D at = _normalised(details.localPosition, size);
      setState(() => _corners = movedCorner(_corners, corner, at));
    } else if (_draggingShape && size.width > 0 && size.height > 0) {
      setState(() {
        _corners = shiftedCorners(
          _corners,
          details.delta.dx / size.width,
          details.delta.dy / size.height,
        );
      });
    } else {
      return;
    }
    _sendInputs();
  }

  void _dragEnd() {
    setState(() {
      _activeCorner = null;
      _draggingShape = false;
    });
    _controller.lockSpatialAnchor(_corners);
    _autoUpdateDistance();
  }

  void _onTapToPlace(TapUpDetails details, Size size) {
    final Point2D at = _normalised(details.localPosition, size);
    if (nearestCorner(_corners, at, maxDistance: 0.08) != null) {
      return;
    }
    final double currentDist = _distance.isValid ? _distance.feet! : 66.0;

    // Optical computer vision: detect physical vertical edges & boundaries of stumps/chair!
    final OpticalWicketResult optical = _controller.detectOrRefineWicket(
      searchCenter: at,
      family: _family,
      targetDistanceFeet: currentDist,
      zoom: _controller.zoom,
    );

    setState(() {
      _corners = optical.corners;
      _userEditedDistance = false;
    });

    _controller.lockSpatialAnchor(optical.corners);
    _autoUpdateDistance();
    _sendInputs();

    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      final String msg = optical.isOpticallyRefined
          ? '🔒 Optical Lock: Physical stumps detected! Spatial motion tracking active.'
          : '🔒 Locked onto ${_family.label}! Spatial motion tracking active.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ---- Actions -----------------------------------------------------------------------------

  Future<void> _leave(VoidCallback after) async {
    await _controller.stop();
    if (mounted) {
      after();
    }
  }

  Future<void> _confirm() async {
    final bool ready = wicketCornersProblem(_corners) == null && _distance.isValid;
    if (_saving || !ready || !_controller.isRunning) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final SceneScanOutcome outcome = manualWicketOutcome(corners: _corners, family: _family);
      final int fps = _controller.status.fps.round();
      final double zoom = _controller.zoom;
      final ScanRecords records = scanRecordsFrom(
        matchId: widget.bundle.match.id,
        outcome: outcome,
        scanId: ref.read(matchRepositoryProvider).newId(),
        wicketId: ref.read(matchRepositoryProvider).newId(),
        now: ref.read(clockProvider).now(),
        scanDurationMs: _clock.elapsedMilliseconds,
        captureFps: fps > 0 ? fps : ref.read(devicePolicyProvider).cameraFps,
      );
      await ref.read(matchRepositoryProvider).saveScan(
            matchId: widget.bundle.match.id,
            scan: records.scan,
            wicket: records.wicket,
          );
      final LiveSettings? settings = ref.read(liveSettingsProvider);
      await settings?.setZoomFor(widget.bundle.match.id, zoom);
      await settings?.setDistanceFeetFor(widget.bundle.match.id, _distance.feet);
      if (mounted) {
        // The scoring page reads the distance again.
        ref.invalidate(cameraDistanceFeetProvider(widget.bundle.match.id));
      }
      // The camera must be free before the next page opens it again.
      await _controller.stop();
      if (!mounted) {
        return;
      }
      widget.onSaved();
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _error = friendlyError(error);
      });
    }
  }

  // ---- Building ----------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final BallKind ball = ref.watch(ballKindProvider).valueOrNull ?? BallKind.cricketBall;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) {
          unawaited(_leave(widget.onClose));
        }
      },
      child: ListenableBuilder(
        listenable: _controller,
        builder: (BuildContext context, Widget? _) => _content(context, ball),
      ),
    );
  }

  Widget _content(BuildContext context, BallKind ball) {
    final TextTheme text = Theme.of(context).textTheme;
    final String? problem = wicketCornersProblem(_corners);
    final bool running = _controller.isRunning;
    final LiveSessionStatus status = _controller.status;
    if (status.isSpatialAnchorLocked &&
        status.lockedWicketCorners != null &&
        !_draggingShape &&
        _activeCorner == null) {
      _corners = status.lockedWicketCorners!;
    }
    final VoidCallback? skip = widget.onSkip;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenPadding,
            AppSpacing.sm,
            AppSpacing.screenPadding,
            AppSpacing.xxl,
          ),
          children: <Widget>[
            Text(
              'Mark the stumps',
              style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Stand behind the bowler’s end and point the phone at the batter. '
              'Tap directly on your stumps or chair to lock the box, or drag the amber corners. '
              'Use zoom (1.5x / 2x) for distant pitches.',
              style: text.bodyMedium?.copyWith(color: AppColors.inkMuted),
            ),
            const SizedBox(height: AppSpacing.lg),
            ..._cameraArea(context, status),
            if (running) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              _zoomControls(context),
              const SizedBox(height: AppSpacing.md),
              _framing(status),
              const SizedBox(height: AppSpacing.lg),
              Text('What is the wicket?', style: text.titleSmall),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.sm,
                children: <Widget>[
                  for (final WicketFamily family in WicketFamily.values)
                    ChoiceChip(
                      label: Text(family.label),
                      selected: _family == family,
                      onSelected: (_) {
                        setState(() => _family = family);
                        _autoUpdateDistance();
                        _sendInputs();
                      },
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Which ball is bowled?', style: text.titleSmall),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.sm,
                children: <Widget>[
                  for (final BallKind kind in BallKind.values)
                    ChoiceChip(
                      label: Text(kind.label),
                      selected: ball == kind,
                      onSelected: (_) async {
                        await ref.read(ballKindProvider.notifier).choose(kind);
                        if (mounted) {
                          _sendInputs();
                        }
                      },
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'The size of the ball is how the app works out how far away it is.',
                style: text.bodySmall?.copyWith(color: AppColors.inkMuted),
              ),
              const SizedBox(height: AppSpacing.lg),
              CameraDistanceField(
                controller: _distanceText,
                entry: _distance,
                onChanged: _distanceChanged,
                isAutoCalculated: _isAutoCalculated,
                onAutoRecalculate: () {
                  _userEditedDistance = false;
                  _autoUpdateDistance();
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: <Widget>[
                  ActionChip(
                    avatar: const Icon(Icons.straighten, size: 16),
                    label: const Text('66 ft (Full match)'),
                    onPressed: _saving ? null : () => _applyPitchPreset(66.0),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.straighten, size: 16),
                    label: const Text('50 ft (Medium)'),
                    onPressed: _saving ? null : () => _applyPitchPreset(50.0),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.straighten, size: 16),
                    label: const Text('40 ft (Box/Gully)'),
                    onPressed: _saving ? null : () => _applyPitchPreset(40.0),
                  ),
                ],
              ),
            ],
            if (problem != null && running) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              MessageBanner(kind: BannerKind.warning, message: problem),
            ],
            if (_error != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              MessageBanner(kind: BannerKind.error, message: _error!),
            ],
            const SizedBox(height: AppSpacing.xl),
            FilledButton(
              onPressed: running && problem == null && _distance.isValid && !_saving
                  ? () => unawaited(_confirm())
                  : null,
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : const Text('Use these stumps'),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.auto_awesome, size: 18),
                    onPressed: _saving ? null : _autoDetectWicket,
                    label: const Text('Auto-detect wicket'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving
                        ? null
                        : () => setState(() {
                              _corners = defaultWicketCorners();
                              _autoUpdateDistance();
                            }),
                    child: const Text('Reset corners'),
                  ),
                ),
              ],
            ),
            if (skip != null) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              TextButton(
                onPressed: _saving ? null : () => unawaited(_leave(skip)),
                child: const Text('Skip, I will score by hand'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _cameraArea(BuildContext context, LiveSessionStatus status) {
    switch (_controller.phase) {
      case CameraPhase.idle:
      case CameraPhase.starting:
        return const <Widget>[
          Row(
            children: <Widget>[
              SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: AppSpacing.md),
              Expanded(child: Text('Starting the camera…')),
            ],
          ),
        ];
      case CameraPhase.failed:
        return <Widget>[
          MessageBanner(
            kind: BannerKind.error,
            title: 'The camera is not working',
            message: _controller.error ?? 'The camera could not be started.',
            actionLabel: 'Try again',
            onAction: () => unawaited(_open()),
          ),
        ];
      case CameraPhase.running:
        final bool ready = wicketCornersProblem(_corners) == null;
        return <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: StatusChip(
              label: ready ? 'Stump corners placed' : 'Adjust corners to match wicket',
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          CameraPreviewBox(
            source: _controller.source,
            maxHeight: 420,
            currentZoom: _controller.zoom,
            onZoomSelected: (double z) async {
              await _controller.setZoom(z);
              setState(() {});
              _autoUpdateDistance();
            },
            overlay: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final Size size = constraints.biggest;
                return Stack(
                  children: <Widget>[
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (TapUpDetails details) => _onTapToPlace(details, size),
                      onPanStart: (DragStartDetails details) => _dragStart(details, size),
                      onPanUpdate: (DragUpdateDetails details) => _dragUpdate(details, size),
                      onPanEnd: (_) => _dragEnd(),
                      onPanCancel: _dragEnd,
                      child: CustomPaint(
                        size: size,
                        painter: LiveOverlayPainter(
                          corners: _corners,
                          activeCorner: _activeCorner,
                        ),
                      ),
                    ),
                    if (status.isSpatialAnchorLocked)
                      Positioned(
                        top: 10,
                        left: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.72),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.greenAccent, width: 1.2),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(Icons.lock, size: 12, color: Colors.greenAccent),
                              SizedBox(width: 4),
                              Text(
                                'SPATIAL LOCK: TRACKING CAMERA MOTION',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ];
    }
  }

  Widget _zoomControls(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final double min = _controller.minZoom;
    final double max = _controller.maxZoom;
    if (max - min < 0.05) {
      return Text(
        'This camera cannot zoom. Move closer or further away to fit the batter.',
        style: text.bodySmall?.copyWith(color: AppColors.inkMuted),
      );
    }
    final double value = _controller.zoom.clamp(min, max).toDouble();
    return Row(
      children: <Widget>[
        const Icon(Icons.zoom_in, color: AppColors.inkMuted),
        Expanded(
          child: Slider(
            min: min,
            max: max,
            value: value,
            label: '${value.toStringAsFixed(1)}x',
            onChanged: (double next) => unawaited(_controller.setZoom(next)),
          ),
        ),
        SizedBox(
          width: 44,
          child: Text('${value.toStringAsFixed(1)}x', style: text.bodySmall),
        ),
      ],
    );
  }

  Widget _framing(LiveSessionStatus status) {
    final ZoomAdvice advice = status.zoom;
    return MessageBanner(
      kind: bannerKindFor(advice.level),
      title: advice.level == FramingLevel.unknown ? 'Waiting for the batter' : null,
      message: advice.message,
    );
  }
}
