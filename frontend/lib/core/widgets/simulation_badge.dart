import 'package:flutter/material.dart';
import 'package:gully_umpire/app/theme/app_colors.dart';

/// "Simulated" marker. Shown next to anything that came from the simulated vision engine so that
/// nobody mistakes it for a real umpiring call.
class SimulationBadge extends StatelessWidget {
  const SimulationBadge({super.key, this.label = 'Simulated'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Simulated result, not from a real camera model',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.skyBlueTint,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.skyBlue),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.science_outlined, size: 14, color: AppColors.skyBlueInk),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.skyBlueInk,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
