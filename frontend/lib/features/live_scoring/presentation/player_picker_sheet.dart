import 'package:flutter/material.dart';
import 'package:gully_umpire/app/theme/app_colors.dart';
import 'package:gully_umpire/app/theme/app_spacing.dart';

/// One choice in the player picker.
final class PickerOption {
  const PickerOption({required this.id, required this.title, this.subtitle});

  final String id;
  final String title;
  final String? subtitle;
}

/// Lets the scorer tap one player. Returns the chosen id, or `null` when dismissed.
Future<String?> showPlayerPicker(
  BuildContext context, {
  required String title,
  required List<PickerOption> options,
  String emptyMessage = 'Nobody is available.',
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext sheetContext) {
      final TextTheme text = Theme.of(sheetContext).textTheme;
      final double maxHeight = MediaQuery.sizeOf(sheetContext).height * 0.75;
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
                child: Text(title, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (options.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.screenPadding),
                  child: Text(
                    emptyMessage,
                    style: text.bodyMedium?.copyWith(color: AppColors.inkMuted),
                  ),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                    children: <Widget>[
                      for (final PickerOption option in options)
                        ListTile(
                          title: Text(option.title),
                          subtitle: option.subtitle == null ? null : Text(option.subtitle!),
                          onTap: () => Navigator.of(sheetContext).pop(option.id),
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
