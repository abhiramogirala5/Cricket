import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gully_umpire/app/router/routes.dart';
import 'package:gully_umpire/app/theme/app_colors.dart';
import 'package:gully_umpire/app/theme/app_spacing.dart';
import 'package:gully_umpire/core/di/core_providers.dart';
import 'package:gully_umpire/core/di/cv_providers.dart';
import 'package:gully_umpire/core/di/data_providers.dart';
import 'package:gully_umpire/core/utils/formatters.dart';
import 'package:gully_umpire/core/widgets/async_body.dart';
import 'package:gully_umpire/core/widgets/empty_state.dart';
import 'package:gully_umpire/core/widgets/friendly_error.dart';
import 'package:gully_umpire/core/widgets/message_banner.dart';
import 'package:gully_umpire/core/widgets/screen_body.dart';
import 'package:gully_umpire/core/widgets/simulation_badge.dart';
import 'package:gully_umpire/cv/adapters/mock/mock_scenario.dart';
import 'package:gully_umpire/cv/device/device_policy.dart';
import 'package:gully_umpire/cv/engine/cv_engine.dart';
import 'package:gully_umpire/cv/pipelines/pipelines.dart';
import 'package:gully_umpire/cv/scene/scene.dart';
import 'package:gully_umpire/data/repositories/match_repository.dart';
import 'package:gully_umpire/domain/aggregates/match_bundle.dart';
import 'package:gully_umpire/domain/models/models.dart';
import 'package:gully_umpire/features/scene_scan/presentation/stump_marking_view.dart';
import 'package:gully_umpire/features/scene_scan/scan_labels.dart';
import 'package:gully_umpire/features/umpiring/umpiring_mappers.dart';

enum _Phase { idle, scanning, finished }

/// Tells the assistant where the wicket is, before the match (and again whenever the phone was
/// moved).
///
/// With the live camera the umpire marks the stumps by dragging four corners over the live
/// picture ([StumpMarkingView]). In a development build with the simulated engine the scan plays
/// back made-up detections, and every result says so. On a phone that cannot run the camera this
/// page only explains that scoring is by hand.
class SceneScanScreen extends ConsumerStatefulWidget {
  const SceneScanScreen({super.key, required this.matchId});

  final String matchId;

  @override
  ConsumerState<SceneScanScreen> createState() => _SceneScanScreenState();
}

class _SceneScanScreenState extends ConsumerState<SceneScanScreen> {
  _Phase _phase = _Phase.idle;
  SceneScanOutcome? _outcome;
  WicketScanResult? _interim;
  CancellationFlag? _cancel;
  int _durationMs = 0;
  bool _saving = false;
  String? _error;

  MockWicketKind _wicketKind = MockWicketKind.stumps;
  MockScanQuality _quality = MockScanQuality.high;

  @override
  void initState() {
    super.initState();
    final CvEngine engine = ref.read(cvEngineProvider);
    if (engine is SimulatedCvEngine) {
      _wicketKind = engine.scenario.wicketKind;
      _quality = engine.scenario.scanQuality;
    }
  }

  @override
  void dispose() {
    _cancel?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    final CvEngine engine = ref.read(cvEngineProvider);
    final DevicePolicy policy = ref.read(devicePolicyProvider);
    if (engine is SimulatedCvEngine) {
      engine.configure(wicketKind: _wicketKind, scanQuality: _quality);
    }
    final CancellationFlag flag = CancellationFlag();
    setState(() {
      _phase = _Phase.scanning;
      _cancel = flag;
      _interim = null;
      _outcome = null;
      _error = null;
    });
    final Stopwatch watch = Stopwatch()..start();
    try {
      final SceneScanOutcome outcome = await engine.scanScene(
        policy: policy,
        cancel: flag,
        onProgress: (WicketScanResult interim) {
          if (mounted && !flag.isCancelled) {
            setState(() => _interim = interim);
          }
        },
      );
      watch.stop();
      if (!mounted || flag.isCancelled) {
        return;
      }
      setState(() {
        _phase = _Phase.finished;
        _outcome = outcome;
        _durationMs = watch.elapsedMilliseconds;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _phase = _Phase.idle;
        _error = friendlyError(error);
      });
    }
  }

  void _stop() {
    _cancel?.cancel();
    setState(() {
      _phase = _Phase.idle;
      _interim = null;
    });
  }

  Future<void> _save(SceneScanOutcome outcome) async {
    if (_saving) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final MatchRepository repo = ref.read(matchRepositoryProvider);
      final DevicePolicy policy = ref.read(devicePolicyProvider);
      final ScanRecords records = scanRecordsFrom(
        matchId: widget.matchId,
        outcome: outcome,
        scanId: repo.newId(),
        wicketId: repo.newId(),
        now: ref.read(clockProvider).now(),
        scanDurationMs: _durationMs,
        captureFps: policy.cameraFps > 0 ? policy.cameraFps : null,
      );
      await repo.saveScan(matchId: widget.matchId, scan: records.scan, wicket: records.wicket);
      if (!mounted) {
        return;
      }
      context.pushReplacement(Routes.toss(widget.matchId));
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

  void _skip() {
    context.pushReplacement(Routes.toss(widget.matchId));
  }

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.match(widget.matchId));
    }
  }

  /// The live camera: the stumps are marked by hand on the live picture.
  Widget _buildMarking(BuildContext context) {
    final AsyncValue<MatchBundle?> value = ref.watch(matchBundleProvider(widget.matchId));
    return Scaffold(
      appBar: AppBar(title: const Text('Mark the stumps')),
      body: AsyncBody<MatchBundle?>(
        value: value,
        onRetry: () => ref.invalidate(matchBundleProvider(widget.matchId)),
        builder: (BuildContext context, MatchBundle? bundle) {
          if (bundle == null) {
            return EmptyState(
              icon: Icons.search_off,
              title: 'Match not found',
              actionLabel: 'Go back',
              onAction: _close,
            );
          }
          // Marking the stumps again in the middle of a match goes back to the scoring page; before
          // the match it goes on to the toss.
          final bool duringPlay = bundle.match.status == MatchStatus.live;
          return StumpMarkingView(
            key: ValueKey<String>(bundle.match.id),
            bundle: bundle,
            onSaved: duringPlay ? _close : _skip,
            onClose: _close,
            onSkip: duringPlay ? null : _skip,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final CvEngine engine = ref.watch(cvEngineProvider);
    if (engine.mode == CvMode.live) {
      return _buildMarking(context);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Scan the pitch')),
      body: ScreenBody(
        children: <Widget>[
          if (!engine.isAvailable)
            _NotAvailable(onContinue: _skip)
          else ...<Widget>[
            if (engine.isSimulated) ...<Widget>[
              const MessageBanner(
                kind: BannerKind.info,
                title: 'Simulated scan',
                message: 'Nothing is being filmed. The scan plays back made-up detections so you '
                    'can try the whole flow.',
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            switch (_phase) {
              _Phase.idle => _IdleView(
                  simulated: engine.isSimulated,
                  wicketKind: _wicketKind,
                  quality: _quality,
                  onWicketKind: (MockWicketKind kind) => setState(() => _wicketKind = kind),
                  onQuality: (MockScanQuality quality) => setState(() => _quality = quality),
                  onStart: _start,
                  onSkip: _skip,
                ),
              _Phase.scanning => _ScanningView(interim: _interim, onCancel: _stop),
              _Phase.finished => _FinishedView(
                  outcome: _outcome!,
                  saving: _saving,
                  onUse: () => _save(_outcome!),
                  onAgain: _start,
                  onSkip: _skip,
                ),
            },
            if (_error != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              MessageBanner(message: _error!, kind: BannerKind.error),
            ],
          ],
        ],
      ),
    );
  }
}

class _NotAvailable extends StatelessWidget {
  const _NotAvailable({required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const MessageBanner(
          kind: BannerKind.info,
          title: 'You score every ball yourself',
          message: 'The umpire camera needs an Android phone with enough processing power, so it is '
              'off on this phone and there is nothing to mark. Scoring works the same way.',
        ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton(onPressed: onContinue, child: const Text('Continue to the toss')),
      ],
    );
  }
}

class _IdleView extends StatelessWidget {
  const _IdleView({
    required this.simulated,
    required this.wicketKind,
    required this.quality,
    required this.onWicketKind,
    required this.onQuality,
    required this.onStart,
    required this.onSkip,
  });

  final bool simulated;
  final MockWicketKind wicketKind;
  final MockScanQuality quality;
  final ValueChanged<MockWicketKind> onWicketKind;
  final ValueChanged<MockScanQuality> onQuality;
  final VoidCallback onStart;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'Find the wicket',
          style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Stand behind the bowler’s end with the wicket in view. The assistant looks for '
          'it (stumps, a chair, a stack of bricks or bottles) and takes about three seconds.',
          style: text.bodyMedium?.copyWith(color: AppColors.inkMuted),
        ),
        if (simulated) ...<Widget>[
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Simulation settings',
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SimulationBadge(),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('What is the wicket?', style: text.bodySmall),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            children: <Widget>[
              for (final MockWicketKind kind in MockWicketKind.values)
                ChoiceChip(
                  label: Text(wicketKindLabel(kind)),
                  selected: wicketKind == kind,
                  onSelected: (_) => onWicketKind(kind),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text('How well is it seen?', style: text.bodySmall),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            children: <Widget>[
              for (final MockScanQuality value in MockScanQuality.values)
                ChoiceChip(
                  label: Text(scanQualityLabel(value)),
                  selected: quality == value,
                  onSelected: (_) => onQuality(value),
                ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        FilledButton.icon(
          onPressed: onStart,
          icon: const Icon(Icons.center_focus_strong),
          label: const Text('Start scan'),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextButton(onPressed: onSkip, child: const Text('Skip, I will score by hand')),
      ],
    );
  }
}

class _ScanningView extends StatelessWidget {
  const _ScanningView({required this.interim, required this.onCancel});

  final WicketScanResult? interim;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final int maxFrames = const SceneScanConfig().maxFrames;
    final WicketScanResult? current = interim;
    final double progress =
        current == null ? 0 : (current.framesScanned / maxFrames).clamp(0.0, 1.0).toDouble();
    final String guess = (current != null && current.foundWicket)
        ? 'Best guess so far: ${formatPercent(current.confidence)} sure.'
        : 'Nothing clear yet…';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Looking for the wicket…',
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpacing.md),
            LinearProgressIndicator(value: current == null ? null : progress, minHeight: 8),
            const SizedBox(height: AppSpacing.md),
            Text(guess, style: text.bodyMedium),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton(onPressed: onCancel, child: const Text('Cancel')),
          ],
        ),
      ),
    );
  }
}

class _FinishedView extends StatelessWidget {
  const _FinishedView({
    required this.outcome,
    required this.saving,
    required this.onUse,
    required this.onAgain,
    required this.onSkip,
  });

  final SceneScanOutcome outcome;
  final bool saving;
  final VoidCallback onUse;
  final VoidCallback onAgain;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final WicketScanCandidate? best = outcome.result.best;
    if (outcome.skipped) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const MessageBanner(
            kind: BannerKind.info,
            title: 'Scan skipped',
            message: 'This phone is set to score only, so the umpire assistant is off.',
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(onPressed: onSkip, child: const Text('Continue to the toss')),
        ],
      );
    }
    final ScanReadiness readiness = best == null
        ? ScanReadiness.reposition
        : ScanReadiness.fromConfidence(outcome.result.confidence);
    final bool usable = best != null && readiness != ScanReadiness.reposition;
    final BannerKind kind = switch (readiness) {
      ScanReadiness.ready => BannerKind.success,
      ScanReadiness.moderate => BannerKind.warning,
      ScanReadiness.limited => BannerKind.warning,
      ScanReadiness.reposition => BannerKind.error,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        MessageBanner(kind: kind, title: readiness.label, message: readiness.message),
        const SizedBox(height: AppSpacing.md),
        if (best != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.sports_cricket, color: AppColors.pitchGreen),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      '${best.family.label} · ${formatPercent(best.finalConfidence)} sure',
                      style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (outcome.isMock) const SimulationBadge(),
                ],
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.lg),
        if (usable)
          FilledButton(
            onPressed: saving ? null : onUse,
            child: saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                  )
                : const Text('Use this scan'),
          ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton(onPressed: saving ? null : onAgain, child: const Text('Scan again')),
        const SizedBox(height: AppSpacing.xs),
        TextButton(
          onPressed: saving ? null : onSkip,
          child: const Text('Skip, I will score by hand'),
        ),
      ],
    );
  }
}
