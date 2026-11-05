import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/app/theme/app_colors.dart';
import 'package:gully_umpire/features/live_scoring/presentation/over_strip.dart';

void main() {
  group('ballChipColors', () {
    test('wickets are red with white text, with or without runs', () {
      for (final String label in <String>['W', '1W', '4W', 'WdW', 'NbW']) {
        final ({Color background, Color foreground}) colors = ballChipColors(label);
        expect(colors.background, AppColors.ballRed, reason: label);
        expect(colors.foreground, Colors.white, reason: label);
      }
    });

    test('fours and sixes are green with white text', () {
      for (final String label in <String>['4', '6']) {
        final ({Color background, Color foreground}) colors = ballChipColors(label);
        expect(colors.background, AppColors.pitchGreen, reason: label);
        expect(colors.foreground, Colors.white, reason: label);
      }
    });

    test('wides and no-balls are amber', () {
      for (final String label in <String>['Wd', 'Wd+2', 'Nb', 'Nb+4']) {
        final ({Color background, Color foreground}) colors = ballChipColors(label);
        expect(colors.background, AppColors.creaseAmberTint, reason: label);
        expect(colors.foreground, AppColors.creaseAmberInk, reason: label);
      }
    });

    test('everything else is the plain tint', () {
      for (final String label in <String>['0', '1', '2', '3', '5', 'B2', 'Lb1']) {
        final ({Color background, Color foreground}) colors = ballChipColors(label);
        expect(colors.background, AppColors.grassTint, reason: label);
        expect(colors.foreground, AppColors.ink, reason: label);
      }
    });
  });

  group('OverStrip', () {
    testWidgets('shows one chip per ball and the heading', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OverStrip(labels: <String>['1', 'W', 'Wd', '4'], showingCompletedOver: false),
          ),
        ),
      );
      expect(find.text('This over'), findsOneWidget);
      for (final String label in <String>['1', 'W', 'Wd', '4']) {
        expect(find.text(label), findsOneWidget);
      }
    });

    testWidgets('calls a finished over "Last over"', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OverStrip(labels: <String>['0'], showingCompletedOver: true),
          ),
        ),
      );
      expect(find.text('Last over'), findsOneWidget);
    });

    testWidgets('says so before the first ball', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OverStrip(labels: <String>[], showingCompletedOver: false),
          ),
        ),
      );
      expect(find.text('No balls yet.'), findsOneWidget);
    });
  });
}
