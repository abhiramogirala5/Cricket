import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gully_umpire/app/theme/app_colors.dart';
import 'package:gully_umpire/app/theme/app_spacing.dart';
import 'package:gully_umpire/features/live_camera/camera_distance.dart';

/// The box where the umpire says how far the phone stands from the batter, in feet.
///
/// The ball speed is worked out from this number, so the words say how to get it and what happens
/// when it is left empty.
class CameraDistanceField extends StatelessWidget {
  const CameraDistanceField({
    super.key,
    required this.controller,
    required this.entry,
    required this.onChanged,
    this.isAutoCalculated = false,
    this.onAutoRecalculate,
  });

  final TextEditingController controller;

  /// What the box holds right now (it decides the error text).
  final DistanceEntry entry;

  final ValueChanged<String> onChanged;

  /// True when the distance was automatically estimated from wicket optical height.
  final bool isAutoCalculated;

  /// Optional callback to recalculate distance from current wicket marking.
  final VoidCallback? onAutoRecalculate;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text('How far is the phone from the batter?', style: text.titleSmall),
            if (isAutoCalculated)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.skyBlueTint,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Auto-calculated',
                  style: text.labelSmall?.copyWith(
                    color: AppColors.skyBlueInk,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          children: <Widget>[
            ActionChip(
              visualDensity: VisualDensity.compact,
              label: const Text('66 ft (Full)', style: TextStyle(fontSize: 11)),
              onPressed: () {
                controller.text = '66';
                onChanged('66');
              },
            ),
            ActionChip(
              visualDensity: VisualDensity.compact,
              label: const Text('50 ft (Turf)', style: TextStyle(fontSize: 11)),
              onPressed: () {
                controller.text = '50';
                onChanged('50');
              },
            ),
            ActionChip(
              visualDensity: VisualDensity.compact,
              label: const Text('36 ft (Short)', style: TextStyle(fontSize: 11)),
              onPressed: () {
                controller.text = '36';
                onChanged('36');
              },
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          decoration: InputDecoration(
            labelText: 'Distance in feet',
            suffixText: 'ft',
            errorText: entry.problem,
            helperText: isAutoCalculated ? 'Calculated from wicket optical height. Tap to edit.' : null,
          ),
          onChanged: onChanged,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Walk it heel to toe from the phone to the batter: one shoe length is about a foot. '
          'The ball speed is only as good as this number. Leave it empty and no speed is shown.',
          style: text.bodySmall?.copyWith(color: AppColors.inkMuted),
        ),
      ],
    );
  }
}
