import 'package:flutter/material.dart';
import 'package:gully_umpire/app/theme/app_colors.dart';
import 'package:gully_umpire/app/theme/app_spacing.dart';
import 'package:gully_umpire/domain/models/models.dart';

/// The umpiring rules of one match, as switches and a slider.
///
/// These rules decide what the umpire assistant may suggest. The person scoring always makes the
/// final call.
class RulesEditor extends StatelessWidget {
  const RulesEditor({
    super.key,
    required this.rules,
    required this.onChanged,
    this.showEdgeReview = false,
    this.showLbwReview = false,
  });

  final MatchRules rules;
  final ValueChanged<MatchRules> onChanged;

  /// Edge and LBW review aids are experimental and switched on in the build's `.env`.
  final bool showEdgeReview;
  final bool showLbwReview;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          childrenPadding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          title: Text(
            'Umpiring rules',
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          subtitle: const Text('Optional. The usual gully rules are already chosen.'),
          children: <Widget>[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Look for wides'),
              value: rules.wideEnabled,
              onChanged: (bool value) => onChanged(rules.copyWith(wideEnabled: value)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Look for no-balls'),
              value: rules.noBallEnabled,
              onChanged: (bool value) => onChanged(rules.copyWith(noBallEnabled: value)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Full toss above the waist is a no-ball'),
              value: rules.fullTossAboveWaistIsNoBall,
              onChanged: rules.noBallEnabled
                  ? (bool value) => onChanged(rules.copyWith(fullTossAboveWaistIsNoBall: value))
                  : null,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Bounced ball above the shoulder is a no-ball'),
              value: rules.bouncedAboveShoulderIsNoBall,
              onChanged: rules.noBallEnabled
                  ? (bool value) => onChanged(rules.copyWith(bouncedAboveShoulderIsNoBall: value))
                  : null,
            ),
            if (showEdgeReview)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Edge review (experimental)'),
                value: rules.edgeReviewEnabled,
                onChanged: (bool value) => onChanged(rules.copyWith(edgeReviewEnabled: value)),
              ),
            if (showLbwReview)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('LBW and wicket-hit review (experimental)'),
                value: rules.lbwReviewEnabled,
                onChanged: (bool value) => onChanged(rules.copyWith(lbwReviewEnabled: value)),
              ),
            const SizedBox(height: AppSpacing.sm),
            Text('How wide is a wide?', style: text.titleSmall),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'A ball is a wide when it passes further from the batter than this share of the '
              'batter’s height.',
              style: text.bodySmall?.copyWith(color: AppColors.inkMuted),
            ),
            Slider(
              min: MatchRules.minLateralReach,
              max: MatchRules.maxLateralReach,
              divisions: 26,
              value: rules.lateralReachMultiplier
                  .clamp(MatchRules.minLateralReach, MatchRules.maxLateralReach)
                  .toDouble(),
              label: '${(rules.lateralReachMultiplier * 100).round()}%',
              onChanged: rules.wideEnabled
                  ? (double value) => onChanged(
                        rules.copyWith(lateralReachMultiplier: _roundToFiveHundredths(value)),
                      )
                  : null,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text('Stricter', style: text.bodySmall),
                Text(
                  '${(rules.lateralReachMultiplier * 100).round()}%',
                  style: text.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text('Looser', style: text.bodySmall),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static double _roundToFiveHundredths(double value) => (value * 20).round() / 20;
}
