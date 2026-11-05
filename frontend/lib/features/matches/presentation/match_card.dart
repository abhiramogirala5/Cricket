import 'package:flutter/material.dart';
import 'package:gully_umpire/app/theme/app_colors.dart';
import 'package:gully_umpire/app/theme/app_spacing.dart';
import 'package:gully_umpire/core/widgets/status_chip.dart';
import 'package:gully_umpire/domain/aggregates/match_list_item.dart';
import 'package:gully_umpire/features/matches/match_presentation.dart';

/// One match in a list: names, status, scores and result.
class MatchCard extends StatelessWidget {
  const MatchCard({super.key, required this.item, required this.onTap});

  final MatchListItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final colors = statusColors(item.match.status);
    final List<String> lines = scoreLines(item);
    final String? result = item.match.resultSummary;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  StatusChip(
                    label: item.match.status.label,
                    foreground: colors.foreground,
                    background: colors.background,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              if (lines.isEmpty)
                Text(
                  '${item.teamAName} vs ${item.teamBName}',
                  style: text.bodyMedium?.copyWith(color: AppColors.inkMuted),
                )
              else
                for (final String line in lines) Text(line, style: text.bodyMedium),
              if (result != null && result.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  result,
                  style: text.bodyMedium?.copyWith(
                    color: AppColors.pitchGreenDark,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              Text(
                '${matchDateLabel(item.match)} · ${item.match.oversPerInnings} overs',
                style: text.bodySmall?.copyWith(color: AppColors.inkMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
