import 'package:flutter/material.dart';
import 'package:gully_umpire/app/theme/app_colors.dart';
import 'package:gully_umpire/app/theme/app_spacing.dart';
import 'package:gully_umpire/core/utils/formatters.dart';
import 'package:gully_umpire/core/widgets/simulation_badge.dart';
import 'package:gully_umpire/core/widgets/status_chip.dart';
import 'package:gully_umpire/cv/pipelines/pipelines.dart';
import 'package:gully_umpire/cv/tracking/speed_estimator.dart';
import 'package:gully_umpire/domain/decisions/decisions.dart';
import 'package:gully_umpire/features/live_scoring/presentation/extras_sheet.dart';

/// Which scoring button a suggestion points at, or `null` when it is only information.
ExtraType? extraFor(DeliveryDecision decision) {
  if (decision.isInconclusive) {
    return null;
  }
  if (decision.type == DeliveryDecisionType.wide && decision.automatedResult == 'WIDE') {
    return ExtraType.wide;
  }
  if (decision.type == DeliveryDecisionType.noBallHeight &&
      decision.automatedResult == 'NO_BALL') {
    return ExtraType.noBall;
  }
  return null;
}

/// The words under a suggestion that tell how fast the ball was.
///
/// A measured speed says how far out it may be; the simulator's speed cannot, and says it is rough.
String ballSpeedLine(SpeedEstimate speed) {
  final double? give = speed.uncertaintyKmph;
  if (give == null) {
    return 'Speed: about ${speed.kmph.round()} km/h (a rough estimate).';
  }
  final int margin = give.round() < 1 ? 1 : give.round();
  return 'Speed: about ${speed.kmph.round()} km/h, give or take $margin (worked out from the '
      'size of the ball and the distance you entered).';
}

/// What the umpire assistant noticed about the last ball. It only suggests: the scorer decides
/// and the suggestion is kept next to what was finally scored.
class UmpireSuggestionCard extends StatelessWidget {
  const UmpireSuggestionCard({
    super.key,
    required this.analysis,
    required this.onApply,
    required this.onDismiss,
    this.onReplay,
  });

  final DeliveryAnalysis analysis;
  final ValueChanged<ExtraType> onApply;
  final VoidCallback onDismiss;

  /// Opens the replay of this ball (only offered when the camera kept one).
  final VoidCallback? onReplay;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final speed = analysis.speed;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.sports, color: AppColors.pitchGreen),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Umpire assistant',
                    style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                if (analysis.isMock) const SimulationBadge(),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (analysis.decisions.isEmpty)
              Text(
                'No suggestion for this ball. You make the call.',
                style: text.bodyMedium,
              ),
            for (final DeliveryDecision decision in analysis.decisions) ...<Widget>[
              _DecisionTile(decision: decision, onApply: onApply),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (speed != null)
              Text(
                ballSpeedLine(speed),
                style: text.bodySmall?.copyWith(color: AppColors.inkMuted),
              ),
            for (final String note in analysis.notes)
              Text(note, style: text.bodySmall?.copyWith(color: AppColors.inkMuted)),
            const SizedBox(height: AppSpacing.sm),
            if (onReplay != null)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                onPressed: onReplay,
                icon: const Icon(Icons.replay),
                label: const Text('Watch the replay'),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: onDismiss, child: const Text('Dismiss')),
            ),
          ],
        ),
      ),
    );
  }
}

class _DecisionTile extends StatelessWidget {
  const _DecisionTile({required this.decision, required this.onApply});

  final DeliveryDecision decision;
  final ValueChanged<ExtraType> onApply;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ExtraType? extra = extraFor(decision);
    final bool unsure = decision.isInconclusive;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: unsure ? AppColors.background : AppColors.grassTint,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              StatusChip(label: decision.type.label),
              StatusChip(
                label: unsure
                    ? 'Not sure'
                    : '${decision.status.label} · ${formatPercent(decision.confidence)}',
                foreground: unsure ? AppColors.inkMuted : AppColors.pitchGreenDark,
                background: unsure ? AppColors.outline : Colors.white,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(decision.summary, style: text.bodyMedium),
          if (extra != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
              onPressed: () => onApply(extra),
              child: Text('Score as ${extra.label.toLowerCase()}'),
            ),
          ],
        ],
      ),
    );
  }
}
