import 'package:flutter/material.dart';
import 'package:gully_umpire/app/theme/app_colors.dart';

/// A small rounded label such as "Live" or "Completed".
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    this.foreground = AppColors.pitchGreenDark,
    this.background = AppColors.grassTint,
  });

  final String label;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: foreground, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}
