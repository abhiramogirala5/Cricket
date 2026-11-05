import 'package:flutter/material.dart';

/// The colours of the app: a light, grassy palette (no dark theme, no purple).
abstract final class AppColors {
  /// Main brand colour: the green of a cricket pitch.
  static const Color pitchGreen = Color(0xFF1F7A4D);
  static const Color pitchGreenDark = Color(0xFF145A37);

  /// Very light green for highlighted areas.
  static const Color grassTint = Color(0xFFE7F4EC);

  /// The red of the ball: errors, wickets, destructive actions.
  static const Color ballRed = Color(0xFFC0392B);
  static const Color ballRedTint = Color(0xFFFBE4E1);

  /// Crease-line amber: warnings and "look at this" notices.
  static const Color creaseAmber = Color(0xFFF2A900);
  static const Color creaseAmberTint = Color(0xFFFFF3CC);
  static const Color creaseAmberInk = Color(0xFF5C4300);

  /// Sky blue: information and the simulation badge.
  static const Color skyBlue = Color(0xFF2E86C1);
  static const Color skyBlueTint = Color(0xFFE3F0FA);
  static const Color skyBlueInk = Color(0xFF1B4F72);

  /// Page background, text and borders.
  static const Color background = Color(0xFFF7F9F6);
  static const Color surface = Colors.white;
  static const Color ink = Color(0xFF1B2B22);
  static const Color inkMuted = Color(0xFF5B6B62);
  static const Color outline = Color(0xFFD5DED8);
}
