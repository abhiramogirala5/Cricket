import 'package:flutter/material.dart';
import 'package:gully_umpire/app/theme/app_colors.dart';
import 'package:gully_umpire/app/theme/app_spacing.dart';

/// Background and text colours for one ball label (`4`, `W`, `Wd+1`, `Nb`, ...).
({Color background, Color foreground}) ballChipColors(String label) {
  if (label.endsWith('W')) {
    return (background: AppColors.ballRed, foreground: Colors.white);
  }
  if (label == '4' || label == '6') {
    return (background: AppColors.pitchGreen, foreground: Colors.white);
  }
  if (label.startsWith('Wd') || label.startsWith('Nb')) {
    return (background: AppColors.creaseAmberTint, foreground: AppColors.creaseAmberInk);
  }
  return (background: AppColors.grassTint, foreground: AppColors.ink);
}

/// The balls of the over in progress, as round chips.
class OverStrip extends StatelessWidget {
  const OverStrip({
    super.key,
    required this.labels,
    required this.showingCompletedOver,
    this.onBallTap,
  });

  final List<String> labels;
  final bool showingCompletedOver;

  /// Optional callback invoked when the user taps a ball chip with its 0-based index in the over.
  final ValueChanged<int>? onBallTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(
              showingCompletedOver ? 'Last over' : 'This over',
              style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (labels.isNotEmpty && onBallTap != null)
              Text(
                'Tap ball to review',
                style: text.labelSmall?.copyWith(color: AppColors.inkMuted),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (labels.isEmpty)
          Text(
            'No balls yet.',
            style: text.bodyMedium?.copyWith(color: AppColors.inkMuted),
          )
        else
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              for (int i = 0; i < labels.length; i++)
                _BallChip(
                  label: labels[i],
                  index: i,
                  onTap: onBallTap != null ? () => onBallTap!(i) : null,
                ),
            ],
          ),
      ],
    );
  }
}

class _BallChip extends StatelessWidget {
  const _BallChip({
    required this.label,
    this.index,
    this.onTap,
  });

  final String label;
  final int? index;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = ballChipColors(label);
    final Widget chip = Material(
      color: colors.background,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: colors.foreground,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
        ),
      ),
    );

    if (onTap != null) {
      return Tooltip(
        message: 'Review ball ${index != null ? index! + 1 : ""}',
        child: chip,
      );
    }
    return chip;
  }
}
