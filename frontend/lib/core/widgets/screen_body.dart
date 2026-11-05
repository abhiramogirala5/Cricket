import 'package:flutter/material.dart';
import 'package:gully_umpire/app/theme/app_spacing.dart';

/// A scrolling column that stays readable on a tablet: content is centred and no wider than
/// [AppSpacing.maxContentWidth].
class ScreenBody extends StatelessWidget {
  const ScreenBody({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.screenPadding,
      AppSpacing.sm,
      AppSpacing.screenPadding,
      AppSpacing.xxl,
    ),
    this.controller,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
        child: ListView(
          controller: controller,
          padding: padding,
          children: children,
        ),
      ),
    );
  }
}
