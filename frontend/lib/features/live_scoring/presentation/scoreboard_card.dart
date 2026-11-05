import 'package:flutter/material.dart';
import 'package:gully_umpire/app/theme/app_colors.dart';
import 'package:gully_umpire/app/theme/app_spacing.dart';
import 'package:gully_umpire/core/utils/formatters.dart';
import 'package:gully_umpire/core/widgets/status_chip.dart';
import 'package:gully_umpire/features/live_scoring/live_board.dart';

/// The big score at the top of the live-scoring page.
class ScoreboardCard extends StatelessWidget {
  const ScoreboardCard({super.key, required this.board});

  final LiveBoard board;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final String? chase = board.chaseText;
    final double? rate = board.runRate;
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
                    board.battingTeamName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                StatusChip(label: 'Innings ${board.innings.inningsNumber}'),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Text(
                  board.scoreText,
                  style: text.displayMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: AppSpacing.md),
                Flexible(
                  child: Text(
                    '${board.oversText} ov ${board.oversLimitText}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleMedium?.copyWith(color: AppColors.inkMuted),
                  ),
                ),
              ],
            ),
            if (rate != null) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Run rate ${formatDecimal(rate)}',
                style: text.bodyMedium?.copyWith(color: AppColors.inkMuted),
              ),
            ],
            if (chase != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: AppColors.grassTint,
                  borderRadius: BorderRadius.circular(AppSpacing.radius),
                ),
                child: Text(
                  chase,
                  style: text.titleSmall?.copyWith(
                    color: AppColors.pitchGreenDark,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
