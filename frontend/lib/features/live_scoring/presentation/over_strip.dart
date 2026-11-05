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
  const OverStrip({super.key, required this.labels, required this.showingCompletedOver});

  final List<String> labels;
  final bool showingCompletedOver;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          showingCompletedOver ? 'Last over' : 'This over',
          style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
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
              for (final String label in labels) _BallChip(label: label),
            ],
          ),
      ],
    );
  }
}

class _BallChip extends StatelessWidget {
  const _BallChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = ballChipColors(label);
    return Container(
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: colors.foreground,
          fontWeight: FontWeight.w800,
          fontSize: 15,
        ),
      ),
    );
  }
}
