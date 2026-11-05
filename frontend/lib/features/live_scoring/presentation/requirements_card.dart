import 'package:flutter/material.dart';
import 'package:gully_umpire/app/theme/app_colors.dart';
import 'package:gully_umpire/app/theme/app_spacing.dart';
import 'package:gully_umpire/features/live_scoring/live_board.dart';

/// Tells the scorer what has to be chosen before the next ball, with one button for each.
class RequirementsCard extends StatelessWidget {
  const RequirementsCard({
    super.key,
    required this.missing,
    required this.onChooseOpeners,
    required this.onChooseBatter,
    required this.onChooseBowler,
  });

  final List<LiveRequirement> missing;
  final VoidCallback onChooseOpeners;
  final VoidCallback onChooseBatter;
  final VoidCallback onChooseBowler;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.creaseAmberTint,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Before the next ball',
            style: text.titleSmall?.copyWith(
              color: AppColors.creaseAmberInk,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final LiveRequirement requirement in missing) ...<Widget>[
            FilledButton.tonal(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.ink,
              ),
              onPressed: switch (requirement) {
                LiveRequirement.openers => onChooseOpeners,
                LiveRequirement.incomingBatter => onChooseBatter,
                LiveRequirement.bowler => onChooseBowler,
              },
              child: Text(switch (requirement) {
                LiveRequirement.openers => 'Choose the opening batters',
                LiveRequirement.incomingBatter => 'Who comes in to bat?',
                LiveRequirement.bowler => 'Who bowls this over?',
              }),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}
