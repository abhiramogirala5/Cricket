import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gully_umpire/app/router/routes.dart';
import 'package:gully_umpire/app/theme/app_colors.dart';
import 'package:gully_umpire/app/theme/app_spacing.dart';
import 'package:gully_umpire/core/di/data_providers.dart';
import 'package:gully_umpire/core/di/replay_providers.dart';
import 'package:gully_umpire/core/utils/formatters.dart';
import 'package:gully_umpire/core/widgets/friendly_error.dart';
import 'package:gully_umpire/core/widgets/async_body.dart';
import 'package:gully_umpire/core/widgets/empty_state.dart';
import 'package:gully_umpire/core/widgets/message_banner.dart';
import 'package:gully_umpire/core/widgets/screen_body.dart';
import 'package:gully_umpire/core/widgets/section_header.dart';
import 'package:gully_umpire/core/widgets/simulation_badge.dart';
import 'package:gully_umpire/core/widgets/status_chip.dart';
import 'package:gully_umpire/cv/geometry/point2d.dart';
import 'package:gully_umpire/cv/pipelines/pipelines.dart';
import 'package:gully_umpire/data/remote/replay_api.dart';
import 'package:gully_umpire/data/replays/replay_store.dart';
import 'package:gully_umpire/domain/aggregates/match_bundle.dart';
import 'package:gully_umpire/domain/decisions/decisions.dart';
import 'package:gully_umpire/domain/models/models.dart';
import 'package:gully_umpire/domain/scoring/scoring.dart';
import 'package:gully_umpire/features/live_scoring/presentation/over_strip.dart';
import 'package:gully_umpire/features/review/review_data.dart';
import 'package:gully_umpire/features/scorecard/scorecard_text.dart';
import 'package:gully_umpire/features/umpiring/umpiring_mappers.dart';

/// What the umpire assistant saw and said about one ball, next to what was finally scored.
class DeliveryReviewScreen extends ConsumerWidget {
  const DeliveryReviewScreen({super.key, required this.matchId, required this.deliveryId});

  final String matchId;
  final String deliveryId;

  static Delivery? _find(MatchBundle bundle, String deliveryId) {
    for (final List<Delivery> list in bundle.deliveriesByInnings.values) {
      for (final Delivery delivery in list) {
        if (delivery.id == deliveryId) {
          return delivery;
        }
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ball review')),
      body: AsyncBody<MatchBundle?>(
        value: ref.watch(matchBundleProvider(matchId)),
        onRetry: () => ref.invalidate(matchBundleProvider(matchId)),
        builder: (BuildContext context, MatchBundle? bundle) {
          if (bundle == null) {
            return const EmptyState(icon: Icons.search_off, title: 'Match not found');
          }
          final Delivery? delivery = _find(bundle, deliveryId);
          if (delivery == null) {
            return const EmptyState(icon: Icons.search_off, title: 'Ball not found');
          }
          return _ReviewBody(bundle: bundle, delivery: delivery);
        },
      ),
    );
  }
}

class _ReviewBody extends ConsumerWidget {
  const _ReviewBody({required this.bundle, required this.delivery});

  final MatchBundle bundle;
  final Delivery delivery;

  WicketDetection? get _wicket {
    final String? id = delivery.wicketDetectionId;
    if (id == null) {
      return null;
    }
    for (final WicketDetection detection in bundle.wicketDetections) {
      if (detection.id == id) {
        return detection;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme text = Theme.of(context).textTheme;
    final AsyncValue<TrajectorySnapshot?> trajectoryValue =
        ref.watch(trajectoryProvider(delivery.id));
    final TrajectorySnapshot? trajectory = trajectoryValue.valueOrNull;
    final WicketDetection? wicket = _wicket;
    final List<DecisionRecord> decisions = bundle.decisionsOf(delivery.id);
    final List<Delivery> inningsDeliveries = bundle.deliveriesOf(delivery.inningsId);
    final String label = ballLabel(delivery);
    final colors = ballChipColors(label);
    final bool simulated = (trajectory?.isMock ?? false) ||
        (wicket?.modelVersion.startsWith('mock') ?? false);

    return ScreenBody(
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: <Widget>[
                Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: colors.background, shape: BoxShape.circle),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: colors.foreground,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Over ${overBallLabel(delivery, inningsDeliveries)}',
                        style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(ballSentence(delivery, bundle.playerName), style: text.bodyMedium),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (delivery.isVoided) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          const MessageBanner(
            kind: BannerKind.warning,
            message: 'This ball was undone and does not count towards the score.',
          ),
        ],
        if (simulated) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          const Align(alignment: Alignment.centerLeft, child: SimulationBadge()),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'This ball was analysed by the built-in simulation, not by a real camera model.',
            style: text.bodySmall?.copyWith(color: AppColors.inkMuted),
          ),
        ],
        _ReplayCard(matchId: bundle.match.id, deliveryId: delivery.id),
        const SectionHeader('Assistant and final call'),
        if (decisions.isEmpty)
          const _PlainCard(
            message: 'The assistant made no suggestion for this ball. The score is the '
                'umpire\'s own call.',
          ),
        for (final DecisionRecord decision in decisions) ...<Widget>[
          _DecisionCard(decision: decision),
          const SizedBox(height: AppSpacing.md),
        ],
        const SectionHeader('Measurements'),
        _MeasurementsCard(delivery: delivery),
        const SectionHeader('Ball path'),
        _BallPathCard(
          value: trajectoryValue,
          wicket: wicket,
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'These are suggestions to help the umpire. The umpire\'s call is final.',
          style: text.bodySmall?.copyWith(color: AppColors.inkMuted),
        ),
      ],
    );
  }
}

class _PlainCard extends StatelessWidget {
  const _PlainCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text(
          message,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.inkMuted),
        ),
      ),
    );
  }
}

({Color foreground, Color background}) _statusColors(DecisionStatus status) {
  switch (status) {
    case DecisionStatus.autoCall:
      return (foreground: AppColors.pitchGreenDark, background: AppColors.grassTint);
    case DecisionStatus.reviewRecommended:
      return (foreground: AppColors.creaseAmberInk, background: AppColors.creaseAmberTint);
    case DecisionStatus.inconclusive:
      return (foreground: AppColors.inkMuted, background: AppColors.outline);
    case DecisionStatus.manualOverride:
      return (foreground: AppColors.skyBlueInk, background: AppColors.skyBlueTint);
  }
}

class _DecisionCard extends StatelessWidget {
  const _DecisionCard({required this.decision});

  final DecisionRecord decision;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final colors = _statusColors(decision.decisionStatus);
    final double? confidence = decision.confidence;
    final bool overruled = decision.decisionSource == DecisionSource.manual;
    final lines = evidenceLines(decision.evidence);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    decision.decisionType.label,
                    style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                StatusChip(
                  label: decision.decisionStatus.label,
                  foreground: colors.foreground,
                  background: colors.background,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _FactRow(label: 'Assistant said', value: friendlyResult(decision.automatedResult)),
            _FactRow(
              label: 'Final call',
              value: decision.finalResult == null
                  ? 'Not a scoring call'
                  : friendlyResult(decision.finalResult),
            ),
            if (confidence != null)
              _FactRow(label: 'How sure', value: formatPercent(confidence)),
            _FactRow(
              label: 'Decided by',
              value: overruled ? 'Umpire (overruled the assistant)' : 'Assistant, agreed by the umpire',
            ),
            if (lines.isNotEmpty) ...<Widget>[
              const Divider(height: AppSpacing.xl),
              Text(
                'Why',
                style: text.labelLarge?.copyWith(
                  color: AppColors.inkMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              for (final line in lines) _FactRow(label: line.label, value: line.value),
            ],
          ],
        ),
      ),
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            flex: 4,
            child: Text(label, style: text.bodyMedium?.copyWith(color: AppColors.inkMuted)),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            flex: 5,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _MeasurementsCard extends StatelessWidget {
  const _MeasurementsCard({required this.delivery});

  final Delivery delivery;

  @override
  Widget build(BuildContext context) {
    final double? speed = delivery.speedKmph;
    final double? speedConfidence = delivery.speedConfidence;
    final double? ball = delivery.ballTrackingConfidence;
    final double? pose = delivery.poseTrackingConfidence;
    final double? wicket = delivery.wicketTrackingConfidence;
    final bool any = speed != null || ball != null || pose != null || wicket != null;
    if (!any) {
      return const _PlainCard(message: 'Nothing was measured for this ball.');
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: <Widget>[
            if (speed != null)
              _FactRow(
                label: 'Speed (rough estimate)',
                value: '${speed.round()} km/h'
                    '${speedConfidence == null ? '' : ' · ${formatPercent(speedConfidence)} sure'}',
              ),
            if (ball != null) _FactRow(label: 'Ball tracking', value: formatPercent(ball)),
            if (pose != null) _FactRow(label: 'Batter tracking', value: formatPercent(pose)),
            if (wicket != null) _FactRow(label: 'Wicket tracking', value: formatPercent(wicket)),
          ],
        ),
      ),
    );
  }
}

class _BallPathCard extends StatelessWidget {
  const _BallPathCard({required this.value, required this.wicket});

  final AsyncValue<TrajectorySnapshot?> value;
  final WicketDetection? wicket;

  @override
  Widget build(BuildContext context) {
    return value.when(
      skipLoadingOnReload: true,
      skipLoadingOnRefresh: true,
      loading: () => const Card(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.xl),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (Object error, StackTrace stackTrace) =>
          const _PlainCard(message: 'The ball path could not be loaded.'),
      data: (TrajectorySnapshot? snapshot) {
        if (snapshot == null) {
          return const _PlainCard(message: 'No ball path was kept for this ball.');
        }
        final List<PathPoint> points = parsePathPoints(snapshot.pointsCompressed);
        if (points.isEmpty) {
          return const _PlainCard(message: 'The saved ball path has no usable points.');
        }
        final WicketTarget? target = wicketTargetFrom(wicket);
        final List<Offset> outline = <Offset>[
          if (target != null)
            for (final Point2D vertex in target.polygon.vertices) Offset(vertex.x, vertex.y),
        ];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Semantics(
                  label: 'Drawing of the path of the ball and the wicket, '
                      '${points.length} points',
                  child: AspectRatio(
                    aspectRatio: 4 / 3,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppSpacing.radius),
                      child: CustomPaint(
                        painter: BallPathPainter(points: points, wicketOutline: outline),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  '${pluralize(points.length, 'point')} · '
                  '${snapshot.samplingFps} per second. The ball is drawn from first '
                  '(small) to last (large). The amber shape is the wicket.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.inkMuted),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Draws the saved ball path and the wicket on a plain pitch-coloured background.
///
/// Coordinates are fractions of the picture (0..1), so the drawing scales to any size.
class BallPathPainter extends CustomPainter {
  const BallPathPainter({required this.points, required this.wicketOutline});

  final List<PathPoint> points;

  /// Corners of the wicket in the same 0..1 coordinates (empty when there is none).
  final List<Offset> wicketOutline;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect frame = Offset.zero & size;
    canvas.drawRect(frame, Paint()..color = AppColors.grassTint);

    final Paint grid = Paint()
      ..color = AppColors.outline
      ..strokeWidth = 1;
    for (int i = 1; i < 4; i++) {
      final double dx = size.width * i / 4;
      final double dy = size.height * i / 4;
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), grid);
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), grid);
    }

    Offset scaled(Offset unit) => Offset(unit.dx * size.width, unit.dy * size.height);

    if (wicketOutline.length >= 3) {
      final Path path = Path()..moveTo(scaled(wicketOutline.first).dx, scaled(wicketOutline.first).dy);
      for (final Offset corner in wicketOutline.skip(1)) {
        final Offset point = scaled(corner);
        path.lineTo(point.dx, point.dy);
      }
      path.close();
      canvas
        ..drawPath(path, Paint()..color = AppColors.creaseAmber.withValues(alpha: 0.35))
        ..drawPath(
          path,
          Paint()
            ..color = AppColors.creaseAmber
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
    }

    if (points.length > 1) {
      final Path line = Path()
        ..moveTo(points.first.x * size.width, points.first.y * size.height);
      for (final PathPoint point in points.skip(1)) {
        line.lineTo(point.x * size.width, point.y * size.height);
      }
      canvas.drawPath(
        line,
        Paint()
          ..color = AppColors.ballRed.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    final int last = points.length - 1;
    for (int i = 0; i < points.length; i++) {
      final PathPoint point = points[i];
      final double growth = last == 0 ? 1 : i / last;
      final double radius = 3 + 4 * growth;
      canvas.drawCircle(
        Offset(point.x * size.width, point.y * size.height),
        radius,
        Paint()..color = AppColors.ballRed.withValues(alpha: 0.35 + 0.65 * point.confidence),
      );
    }

    canvas.drawRect(
      frame.deflate(0.5),
      Paint()
        ..color = AppColors.outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(BallPathPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.wicketOutline != wicketOutline;
}

/// The replay of the ball: a button to watch it when the camera kept one, nothing otherwise.
class _ReplayCard extends ConsumerStatefulWidget {
  const _ReplayCard({required this.matchId, required this.deliveryId});

  final String matchId;
  final String deliveryId;

  @override
  ConsumerState<_ReplayCard> createState() => _ReplayCardState();
}

class _ReplayCardState extends ConsumerState<_ReplayCard> {
  bool _downloading = false;
  String? _error;

  Future<void> _download(String remoteId) async {
    final ReplayStore? store = ref.read(replayStoreProvider);
    final ReplayApi? api = ref.read(replayApiProvider);
    if (store == null || api == null || _downloading) {
      return;
    }
    setState(() {
      _downloading = true;
      _error = null;
    });
    try {
      final String id = await downloadReplay(
        store: store,
        api: api,
        remoteId: remoteId,
        matchId: widget.matchId,
        deliveryId: widget.deliveryId,
      );
      ref.invalidate(replayLookupProvider(widget.deliveryId));
      if (!mounted) {
        return;
      }
      setState(() => _downloading = false);
      await context.push<void>(Routes.replay(widget.matchId, id));
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _downloading = false;
        _error = friendlyError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ReplayLookup? lookup = ref.watch(replayLookupProvider(widget.deliveryId)).valueOrNull;
    if (lookup == null || lookup.availability == ReplayAvailability.none) {
      return const SizedBox.shrink();
    }
    final String? replayId = lookup.replayId;
    if (replayId == null) {
      return const SizedBox.shrink();
    }
    final TextTheme text = Theme.of(context).textTheme;
    final bool local = lookup.availability == ReplayAvailability.onThisPhone;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(Icons.replay_circle_filled_outlined, color: AppColors.pitchGreen),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Replay',
                      style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                local
                    ? 'Watch the ball again with its path, the batter’s waist and shoulder lines '
                        'and the measured height.'
                    : 'The replay of this ball is saved online. Download it to watch it here.',
                style: text.bodySmall?.copyWith(color: AppColors.inkMuted),
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton.icon(
                onPressed: _downloading
                    ? null
                    : () {
                        if (local) {
                          unawaited(context.push<void>(Routes.replay(widget.matchId, replayId)));
                        } else {
                          unawaited(_download(replayId));
                        }
                      },
                icon: _downloading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Icon(local ? Icons.play_arrow : Icons.download),
                label: Text(local ? 'Watch the replay' : 'Download the replay'),
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                MessageBanner(kind: BannerKind.error, message: _error!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
