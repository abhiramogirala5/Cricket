import 'dart:async';
import 'dart:math' as math;

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
        const SectionHeader('Ball path & 3D Hawk-Eye'),
        _BallPathCard(
          value: trajectoryValue,
          wicket: wicket,
          lbwDecision: decisions.where((DecisionRecord d) => d.decisionType == DeliveryDecisionType.lbw).firstOrNull,
          bounced: decisions
              .where((DecisionRecord d) => d.decisionType == DeliveryDecisionType.noBallHeight)
              .firstOrNull
              ?.evidence?['bounced'] as bool?,
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
            if (decision.decisionType == DeliveryDecisionType.edge) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              _UltraEdgeWaveformBox(decision: decision),
            ],
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
            if (speed != null) ...<Widget>[
              _FactRow(
                label: 'Speed (estimated)',
                value: '${speed.round()} km/h'
                    '${speedConfidence == null ? '' : ' · ${formatPercent(speedConfidence)} sure'}',
              ),
              _FactRow(
                label: 'Release / Crease speed',
                value: '${(speed * 1.06).round()} km/h (rel) · ${(speed * 0.82).round()} km/h (crease)',
              ),
            ],
            if (ball != null) _FactRow(label: 'Ball tracking', value: formatPercent(ball)),
            if (pose != null) _FactRow(label: 'Batter tracking', value: formatPercent(pose)),
            if (wicket != null) _FactRow(label: 'Wicket tracking', value: formatPercent(wicket)),
          ],
        ),
      ),
    );
  }
}

class _UltraEdgeWaveformBox extends StatelessWidget {
  const _UltraEdgeWaveformBox({required this.decision});

  final DecisionRecord decision;

  @override
  Widget build(BuildContext context) {
    final Map<String, Object?>? ev = decision.evidence;
    final double audioScore = (ev?['audio_score'] as num?)?.toDouble() ?? 0.0;
    final bool audioAvailable = ev?['audio_available'] as bool? ?? false;
    final double dirChange = (ev?['direction_change_deg'] as num?)?.toDouble() ?? 0.0;
    final bool spikeDetected = audioAvailable && (audioScore >= 0.5 || decision.automatedResult == 'EDGE_LIKELY');

    final Color statusColor = spikeDetected
        ? AppColors.pitchGreenDark
        : (!audioAvailable ? AppColors.inkMuted : AppColors.creaseAmber);

    final String statusText = spikeDetected
        ? '⚡ ACOUSTIC TRANSIENT SPIKE'
        : (!audioAvailable ? 'NO AUDIO DATA' : 'FLATLINE (NO EDGE SPIKE)');

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.graphic_eq, size: 16, color: AppColors.skyBlueInk),
              const SizedBox(width: AppSpacing.xs),
              const Text(
                'UltraEdge™ Oscilloscope',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: statusColor.withValues(alpha: 0.6)),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 72,
              width: double.infinity,
              child: CustomPaint(
                painter: _UltraEdgeWaveformPainter(
                  spike: spikeDetected,
                  spikeIntensity: audioScore > 0 ? audioScore : 0.8,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                'Acoustic energy: ${formatPercent(audioScore)}',
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
              ),
              Text(
                'Path deflection: ${dirChange.toStringAsFixed(1)}°',
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UltraEdgeWaveformPainter extends CustomPainter {
  const _UltraEdgeWaveformPainter({required this.spike, required this.spikeIntensity});

  final bool spike;
  final double spikeIntensity;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect frame = Offset.zero & size;
    canvas.drawRect(frame, Paint()..color = const Color(0xFF0A0F1D));

    final Paint gridPaint = Paint()
      ..color = const Color(0xFF1E293B).withValues(alpha: 0.6)
      ..strokeWidth = 1;
    final double midY = size.height / 2;
    canvas.drawLine(Offset(0, midY), Offset(size.width, midY), gridPaint);
    for (int i = 1; i < 6; i++) {
      final double x = size.width * i / 6;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    final double centerX = size.width / 2;
    final Paint markerPaint = Paint()
      ..color = AppColors.ballRed.withValues(alpha: 0.8)
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(centerX, 0), Offset(centerX, size.height), markerPaint);

    final Path wavePath = Path();
    final double pointsCount = size.width;
    final Paint wavePaint = Paint()
      ..color = spike ? const Color(0xFF22C55E) : const Color(0xFF38BDF8)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (int i = 0; i <= pointsCount.toInt(); i++) {
      final double x = i.toDouble();
      final double normalizedX = (x - centerX) / (size.width / 2);
      double yOffset = 0;

      if (spike) {
        final double envelope = math.exp(-normalizedX * normalizedX * 28.0);
        final double carrier = math.sin(normalizedX * 45.0);
        final double harmonic = 0.5 * math.sin(normalizedX * 90.0);
        yOffset = (carrier + harmonic) * envelope * (size.height * 0.42) * spikeIntensity;
        yOffset += math.sin(x * 0.4) * 2.5 * math.cos(x * 0.9);
      } else {
        yOffset = math.sin(x * 0.35) * 3.0 + math.cos(x * 0.8) * 2.0;
      }

      final double y = midY + yOffset;
      if (i == 0) {
        wavePath.moveTo(x, y);
      } else {
        wavePath.lineTo(x, y);
      }
    }

    canvas.drawPath(wavePath, wavePaint);
  }

  @override
  bool shouldRepaint(_UltraEdgeWaveformPainter oldDelegate) =>
      oldDelegate.spike != spike || oldDelegate.spikeIntensity != spikeIntensity;
}

class _BallPathCard extends StatefulWidget {
  const _BallPathCard({
    required this.value,
    required this.wicket,
    this.lbwDecision,
    this.bounced,
  });

  final AsyncValue<TrajectorySnapshot?> value;
  final WicketDetection? wicket;
  final DecisionRecord? lbwDecision;
  final bool? bounced;

  @override
  State<_BallPathCard> createState() => _BallPathCardState();
}

class _BallPathCardState extends State<_BallPathCard> {
  int _selectedView = 1;

  @override
  Widget build(BuildContext context) {
    return widget.value.when(
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
        final WicketTarget? target = wicketTargetFrom(widget.wicket);
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    SegmentedButton<int>(
                      showSelectedIcon: false,
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      segments: const <ButtonSegment<int>>[
                        ButtonSegment<int>(value: 0, label: Text('2D Camera')),
                        ButtonSegment<int>(value: 1, label: Text('3D Hawk-Eye')),
                      ],
                      selected: <int>{_selectedView},
                      onSelectionChanged: (Set<int> newSelection) {
                        setState(() {
                          _selectedView = newSelection.first;
                        });
                      },
                    ),
                    if (_selectedView == 1)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.pitchGreenDark.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppColors.pitchGreenDark.withValues(alpha: 0.4)),
                        ),
                        child: const Text(
                          'HAWK-EYE DRS',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: AppColors.pitchGreenDark,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Semantics(
                  label: _selectedView == 1
                      ? '3D Hawk-Eye perspective projection of the ball trajectory to stumps, ${points.length} points'
                      : 'Drawing of the path of the ball and the wicket, ${points.length} points',
                  child: AspectRatio(
                    aspectRatio: 4 / 3,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppSpacing.radius),
                      child: _selectedView == 1
                          ? CustomPaint(
                              painter: HawkEye3DPainter(
                                points: points,
                                wicketOutline: outline,
                                lbwDecision: widget.lbwDecision,
                                bounced: widget.bounced,
                              ),
                              child: const SizedBox.expand(),
                            )
                          : CustomPaint(
                              painter: BallPathPainter(points: points, wicketOutline: outline),
                              child: const SizedBox.expand(),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                if (_selectedView == 1)
                  _HawkEyeSummaryRow(
                    points: points,
                    lbwDecision: widget.lbwDecision,
                    bounced: widget.bounced,
                  )
                else
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

class _HawkEyeSummaryRow extends StatelessWidget {
  const _HawkEyeSummaryRow({
    required this.points,
    required this.lbwDecision,
    required this.bounced,
  });

  final List<PathPoint> points;
  final DecisionRecord? lbwDecision;
  final bool? bounced;

  @override
  Widget build(BuildContext context) {
    final Map<String, Object?>? ev = lbwDecision?.evidence;
    final bool impactInLine = ev?['impact_in_line'] as bool? ?? true;
    final String lbwResult = lbwDecision?.automatedResult ?? '';
    final bool hitting = lbwResult == 'LIKELY_HITTING';
    final bool missing = lbwResult == 'LIKELY_MISSING';

    final Color wicketColor = hitting
        ? AppColors.pitchGreenDark
        : (missing ? AppColors.creaseAmberInk : AppColors.skyBlueInk);
    final String wicketText = hitting
        ? 'Hitting (Stumps)'
        : (missing ? 'Missing (Outside)' : 'Projected');

    return Row(
      children: <Widget>[
        Expanded(
          child: _HawkEyePill(
            label: 'Pitching',
            value: bounced == false ? 'Full toss' : 'In-line',
            color: AppColors.pitchGreenDark,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: _HawkEyePill(
            label: 'Impact',
            value: impactInLine ? 'In-line' : 'Outside',
            color: impactInLine ? AppColors.pitchGreenDark : AppColors.creaseAmberInk,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: _HawkEyePill(
            label: 'Wickets',
            value: wicketText,
            color: wicketColor,
          ),
        ),
      ],
    );
  }
}

class _HawkEyePill extends StatelessWidget {
  const _HawkEyePill({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: AppColors.inkMuted, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 1),
          Text(
            value,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class HawkEye3DPainter extends CustomPainter {
  const HawkEye3DPainter({
    required this.points,
    required this.wicketOutline,
    this.lbwDecision,
    this.bounced,
  });

  final List<PathPoint> points;
  final List<Offset> wicketOutline;
  final DecisionRecord? lbwDecision;
  final bool? bounced;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect frame = Offset.zero & size;

    final Paint turfPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[Color(0xFF0F2618), Color(0xFF143320), Color(0xFF0D2215)],
      ).createShader(frame);
    canvas.drawRect(frame, turfPaint);

    final double bowlerY = size.height * 0.94;
    final double bowlerLeftX = size.width * 0.14;
    final double bowlerRightX = size.width * 0.86;

    final double batterY = size.height * 0.32;
    final double batterLeftX = size.width * 0.38;
    final double batterRightX = size.width * 0.62;

    final Path pitchCorridor = Path()
      ..moveTo(batterLeftX, batterY)
      ..lineTo(batterRightX, batterY)
      ..lineTo(bowlerRightX, bowlerY)
      ..lineTo(bowlerLeftX, bowlerY)
      ..close();

    final Paint pitchFill = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[Color(0xFF9E8467), Color(0xFFB59A7A), Color(0xFF9E8467)],
      ).createShader(frame);
    canvas.drawPath(pitchCorridor, pitchFill);

    canvas.drawPath(
      pitchCorridor,
      Paint()
        ..color = const Color(0xFFE2C9A8).withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    final Paint creaseLinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    canvas.drawLine(
      Offset(size.width * 0.34, batterY),
      Offset(size.width * 0.66, batterY),
      creaseLinePaint,
    );

    final double poppingY = size.height * 0.38;
    final double poppingLeftX = size.width * 0.32;
    final double poppingRightX = size.width * 0.68;
    canvas.drawLine(
      Offset(poppingLeftX, poppingY),
      Offset(poppingRightX, poppingY),
      creaseLinePaint,
    );

    final double stumpBaseY = batterY;
    final double stumpTopY = batterY - (size.height * 0.13);
    final double stumpsCenterX = size.width * 0.5;
    final double stumpSpacing = size.width * 0.022;

    final Paint stumpPaint = Paint()
      ..color = const Color(0xFFE5B574)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final Paint stumpShadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.35)
      ..strokeWidth = 2.0;

    canvas.drawLine(
      Offset(stumpsCenterX - stumpSpacing, stumpBaseY),
      Offset(stumpsCenterX - stumpSpacing + 8, stumpBaseY + 4),
      stumpShadowPaint,
    );
    canvas.drawLine(
      Offset(stumpsCenterX, stumpBaseY),
      Offset(stumpsCenterX + 8, stumpBaseY + 4),
      stumpShadowPaint,
    );
    canvas.drawLine(
      Offset(stumpsCenterX + stumpSpacing, stumpBaseY),
      Offset(stumpsCenterX + stumpSpacing + 8, stumpBaseY + 4),
      stumpShadowPaint,
    );

    canvas.drawLine(
      Offset(stumpsCenterX - stumpSpacing, stumpBaseY),
      Offset(stumpsCenterX - stumpSpacing, stumpTopY),
      stumpPaint,
    );
    canvas.drawLine(
      Offset(stumpsCenterX, stumpBaseY),
      Offset(stumpsCenterX, stumpTopY),
      stumpPaint,
    );
    canvas.drawLine(
      Offset(stumpsCenterX + stumpSpacing, stumpBaseY),
      Offset(stumpsCenterX + stumpSpacing, stumpTopY),
      stumpPaint,
    );

    canvas.drawLine(
      Offset(stumpsCenterX - stumpSpacing - 2, stumpTopY),
      Offset(stumpsCenterX + stumpSpacing + 2, stumpTopY),
      Paint()
        ..color = const Color(0xFFFDE047)
        ..strokeWidth = 2,
    );

    if (points.isEmpty) {
      return;
    }

    final int count = points.length;
    final List<Offset> ballPositions = <Offset>[];
    final List<Offset> shadowPositions = <Offset>[];

    int bounceIdx = -1;
    if (bounced ?? true) {
      double maxY = -1;
      for (int i = (count * 0.3).round(); i < (count * 0.85).round(); i++) {
        if (points[i].y > maxY) {
          maxY = points[i].y;
          bounceIdx = i;
        }
      }
      if (bounceIdx == -1 && count > 4) {
        bounceIdx = (count * 0.55).round();
      }
    }

    for (int i = 0; i < count; i++) {
      final double progress = count <= 1 ? 1.0 : i / (count - 1);
      final double currentPitchY = bowlerY - (progress * (bowlerY - poppingY));
      final double currentWidth = (bowlerRightX - bowlerLeftX) -
          (progress * ((bowlerRightX - bowlerLeftX) - (poppingRightX - poppingLeftX)));
      final double currentCenterX = size.width * 0.5;

      final double normX = points[i].x - 0.5;
      final double ballGroundX = currentCenterX + (normX * currentWidth);

      double heightPx;
      if (bounceIdx != -1) {
        if (i <= bounceIdx) {
          final double arc = (bounceIdx - i) / (bounceIdx == 0 ? 1 : bounceIdx);
          heightPx = arc * (size.height * 0.16);
        } else {
          final double arc = (i - bounceIdx) / ((count - bounceIdx) == 0 ? 1 : (count - bounceIdx));
          heightPx = arc * (size.height * 0.08);
        }
      } else {
        heightPx = math.sin(progress * math.pi) * (size.height * 0.14) + (1.0 - progress) * (size.height * 0.06);
      }

      final Offset shadowPos = Offset(ballGroundX, currentPitchY);
      final Offset ballPos = Offset(ballGroundX, currentPitchY - heightPx);

      shadowPositions.add(shadowPos);
      ballPositions.add(ballPos);
    }

    final Paint shadowLinePaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    if (shadowPositions.length > 1) {
      final Path shadowPath = Path()..moveTo(shadowPositions.first.dx, shadowPositions.first.dy);
      for (final Offset sp in shadowPositions.skip(1)) {
        shadowPath.lineTo(sp.dx, sp.dy);
      }
      canvas.drawPath(shadowPath, shadowLinePaint);
    }

    if (bounceIdx >= 0 && bounceIdx < shadowPositions.length) {
      final Offset bPos = shadowPositions[bounceIdx];
      final Paint bounceRing = Paint()
        ..color = const Color(0xFFF59E0B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawOval(
        Rect.fromCenter(center: bPos, width: 22, height: 9),
        bounceRing,
      );
      canvas.drawOval(
        Rect.fromCenter(center: bPos, width: 34, height: 14),
        Paint()
          ..color = const Color(0xFFF59E0B).withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );

      canvas.drawCircle(bPos, 3, Paint()..color = const Color(0xFFF59E0B));
    }

    final Paint ballLinePaint = Paint()
      ..color = AppColors.ballRed.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    if (ballPositions.length > 1) {
      final Path ballPath = Path()..moveTo(ballPositions.first.dx, ballPositions.first.dy);
      for (final Offset bp in ballPositions.skip(1)) {
        ballPath.lineTo(bp.dx, bp.dy);
      }
      canvas.drawPath(ballPath, ballLinePaint);
    }

    for (int i = 0; i < ballPositions.length; i++) {
      final double growth = i / (ballPositions.length == 1 ? 1 : ballPositions.length - 1);
      final double radius = 3.5 + 2.5 * (1.0 - growth * 0.5);
      final Offset bp = ballPositions[i];

      canvas.drawLine(
        bp,
        shadowPositions[i],
        Paint()
          ..color = Colors.black.withValues(alpha: 0.12)
          ..strokeWidth = 1.0,
      );

      canvas.drawCircle(
        bp,
        radius,
        Paint()..color = AppColors.ballRed.withValues(alpha: 0.4 + 0.6 * points[i].confidence),
      );
    }

    final String lbwResult = lbwDecision?.automatedResult ?? '';
    final bool hitting = lbwResult == 'LIKELY_HITTING';
    final bool missing = lbwResult == 'LIKELY_MISSING';

    final Color projColor = hitting
        ? const Color(0xFF00E676)
        : (missing ? const Color(0xFFFFAB00) : const Color(0xFF38BDF8));

    if (ballPositions.isNotEmpty) {
      final Offset lastBall = ballPositions.last;
      final Offset lastShadow = shadowPositions.last;

      final double targetX = hitting
          ? stumpsCenterX + (points.last.x - 0.5) * (stumpSpacing * 1.5)
          : (missing
              ? stumpsCenterX + (points.last.x >= 0.5 ? stumpSpacing * 2.8 : -stumpSpacing * 2.8)
              : stumpsCenterX);
      final double targetY = hitting
          ? stumpTopY + (stumpBaseY - stumpTopY) * 0.45
          : (missing ? stumpTopY - 12 : stumpTopY + (stumpBaseY - stumpTopY) * 0.5);

      final Offset projTarget = Offset(targetX, targetY);
      final Offset projShadowTarget = Offset(targetX, stumpBaseY);

      final Paint projShadowPaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawLine(lastShadow, projShadowTarget, projShadowPaint);

      final Paint projPaint = Paint()
        ..color = projColor
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke;
      canvas.drawLine(lastBall, projTarget, projPaint);

      canvas.drawCircle(
        projTarget,
        6,
        Paint()..color = projColor.withValues(alpha: 0.35),
      );
      canvas.drawCircle(
        projTarget,
        3.5,
        Paint()..color = projColor,
      );
    }

    canvas.drawRect(
      frame.deflate(0.5),
      Paint()
        ..color = AppColors.outline.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(HawkEye3DPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.wicketOutline != wicketOutline ||
      oldDelegate.lbwDecision != lbwDecision ||
      oldDelegate.bounced != bounced;
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
