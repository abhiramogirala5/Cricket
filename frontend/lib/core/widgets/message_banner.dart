import 'package:flutter/material.dart';
import 'package:gully_umpire/app/theme/app_colors.dart';
import 'package:gully_umpire/app/theme/app_spacing.dart';

enum BannerKind { error, warning, info, success }

/// A coloured notice inside a screen (not a pop-up): a problem, a warning or a tip.
class MessageBanner extends StatelessWidget {
  const MessageBanner({
    super.key,
    required this.message,
    this.kind = BannerKind.info,
    this.actionLabel,
    this.onAction,
    this.title,
  });

  final String message;
  final String? title;
  final BannerKind kind;
  final String? actionLabel;
  final VoidCallback? onAction;

  Color get _background {
    switch (kind) {
      case BannerKind.error:
        return AppColors.ballRedTint;
      case BannerKind.warning:
        return AppColors.creaseAmberTint;
      case BannerKind.info:
        return AppColors.skyBlueTint;
      case BannerKind.success:
        return AppColors.grassTint;
    }
  }

  Color get _foreground {
    switch (kind) {
      case BannerKind.error:
        return const Color(0xFF7A1F16);
      case BannerKind.warning:
        return AppColors.creaseAmberInk;
      case BannerKind.info:
        return AppColors.skyBlueInk;
      case BannerKind.success:
        return AppColors.pitchGreenDark;
    }
  }

  IconData get _icon {
    switch (kind) {
      case BannerKind.error:
        return Icons.error_outline;
      case BannerKind.warning:
        return Icons.warning_amber_rounded;
      case BannerKind.info:
        return Icons.info_outline;
      case BannerKind.success:
        return Icons.check_circle_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: _background,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(_icon, color: _foreground, size: 22),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (title != null)
                  Text(
                    title!,
                    style: text.titleSmall?.copyWith(
                      color: _foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                Text(message, style: text.bodyMedium?.copyWith(color: _foreground)),
                if (actionLabel != null && onAction != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      style: TextButton.styleFrom(foregroundColor: _foreground),
                      onPressed: onAction,
                      child: Text(actionLabel!),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
