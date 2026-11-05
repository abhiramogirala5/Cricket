import 'package:flutter/material.dart';
import 'package:gully_umpire/app/theme/app_colors.dart';
import 'package:gully_umpire/app/theme/app_spacing.dart';

/// The one theme of the app (light only).
abstract final class AppTheme {
  static const ColorScheme _scheme = ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.pitchGreen,
    onPrimary: Colors.white,
    primaryContainer: AppColors.grassTint,
    onPrimaryContainer: AppColors.pitchGreenDark,
    secondary: AppColors.skyBlue,
    onSecondary: Colors.white,
    secondaryContainer: AppColors.skyBlueTint,
    onSecondaryContainer: AppColors.skyBlueInk,
    tertiary: AppColors.creaseAmber,
    onTertiary: AppColors.ink,
    tertiaryContainer: AppColors.creaseAmberTint,
    onTertiaryContainer: AppColors.creaseAmberInk,
    error: AppColors.ballRed,
    onError: Colors.white,
    errorContainer: AppColors.ballRedTint,
    onErrorContainer: Color(0xFF7A1F16),
    surface: AppColors.surface,
    onSurface: AppColors.ink,
    onSurfaceVariant: AppColors.inkMuted,
    outline: AppColors.outline,
    outlineVariant: AppColors.outline,
    surfaceTint: Colors.transparent,
  );

  static ThemeData light() {
    final RoundedRectangleBorder shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppSpacing.radius),
    );
    final OutlineInputBorder fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSpacing.radius),
      borderSide: const BorderSide(color: AppColors.outline),
    );
    final TextTheme base = ThemeData(brightness: Brightness.light).textTheme.apply(
          bodyColor: AppColors.ink,
          displayColor: AppColors.ink,
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: _scheme,
      scaffoldBackgroundColor: AppColors.background,
      textTheme: base,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.ink,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          side: const BorderSide(color: AppColors.outline),
        ),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.outline, space: 1, thickness: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, AppSpacing.buttonHeight),
          shape: shape,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, AppSpacing.buttonHeight),
          shape: shape,
          foregroundColor: AppColors.pitchGreenDark,
          side: const BorderSide(color: AppColors.pitchGreen),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: shape,
          foregroundColor: AppColors.pitchGreenDark,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: fieldBorder,
        enabledBorder: fieldBorder,
        focusedBorder: fieldBorder.copyWith(
          borderSide: const BorderSide(color: AppColors.pitchGreen, width: 2),
        ),
        errorBorder: fieldBorder.copyWith(
          borderSide: const BorderSide(color: AppColors.ballRed),
        ),
        focusedErrorBorder: fieldBorder.copyWith(
          borderSide: const BorderSide(color: AppColors.ballRed, width: 2),
        ),
        labelStyle: const TextStyle(color: AppColors.inkMuted),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.grassTint,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>((Set<WidgetState> states) {
          final bool selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? AppColors.pitchGreenDark : AppColors.inkMuted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData>((Set<WidgetState> states) {
          final bool selected = states.contains(WidgetState.selected);
          return IconThemeData(color: selected ? AppColors.pitchGreenDark : AppColors.inkMuted);
        }),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.grassTint,
        side: const BorderSide(color: AppColors.outline),
        labelStyle: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        showCheckmark: false,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.ink,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radius)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radius + 4)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.pitchGreen,
        linearTrackColor: AppColors.grassTint,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: AppColors.grassTint,
          selectedForegroundColor: AppColors.pitchGreenDark,
          foregroundColor: AppColors.ink,
          side: const BorderSide(color: AppColors.outline),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.pitchGreenDark,
        contentPadding: EdgeInsets.symmetric(horizontal: 16),
      ),
    );
  }
}
