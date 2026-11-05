import 'package:flutter/material.dart';
import 'package:gully_umpire/app/theme/app_colors.dart';
import 'package:gully_umpire/app/theme/app_spacing.dart';
import 'package:gully_umpire/core/widgets/simulation_badge.dart';
import 'package:gully_umpire/cv/adapters/mock/mock_scenario.dart';
import 'package:gully_umpire/features/live_scoring/simulation_labels.dart';

/// Lets a tester pick which simulated delivery the assistant should look at. Only shown in
/// development builds that run the simulated vision engine. Returns `null` when dismissed.
Future<MockDeliveryKind?> showSimulateDeliverySheet(BuildContext context) {
  return showModalBottomSheet<MockDeliveryKind>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext sheetContext) {
      final TextTheme text = Theme.of(sheetContext).textTheme;
      final double maxHeight = MediaQuery.sizeOf(sheetContext).height * 0.8;
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'Simulate a delivery',
                        style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SimulationBadge(),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenPadding,
                  AppSpacing.xs,
                  AppSpacing.screenPadding,
                  AppSpacing.sm,
                ),
                child: Text(
                  'Nothing is filmed. The assistant looks at a made-up ball so you can try the '
                  'app without trained models.',
                  style: text.bodySmall?.copyWith(color: AppColors.inkMuted),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                  children: <Widget>[
                    for (final MockDeliveryKind kind in MockDeliveryKind.values)
                      ListTile(
                        title: Text(mockDeliveryLabel(kind)),
                        onTap: () => Navigator.of(sheetContext).pop(kind),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
