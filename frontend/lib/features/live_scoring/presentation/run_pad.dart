import 'package:flutter/material.dart';
import 'package:gully_umpire/app/theme/app_colors.dart';
import 'package:gully_umpire/app/theme/app_spacing.dart';
import 'package:gully_umpire/features/live_scoring/presentation/extras_sheet.dart';

/// The buttons for scoring a ball: runs, wicket and extras. Every tap on a run button saves the
/// ball straight away; the undo button in the title bar takes it back.
class RunPad extends StatelessWidget {
  const RunPad({
    super.key,
    required this.enabled,
    required this.onRuns,
    required this.onWicket,
    required this.onExtra,
  });

  final bool enabled;
  final ValueChanged<int> onRuns;
  final VoidCallback onWicket;
  final ValueChanged<ExtraType> onExtra;

  static const double _buttonHeight = 60;

  static String _runsLabel(int runs) {
    if (runs == 0) {
      return 'Dot ball';
    }
    return runs == 1 ? '1 run' : '$runs runs';
  }

  Widget _runButton(int runs) {
    final bool boundary = runs == 4 || runs == 6;
    final Widget child = Text(
      '$runs',
      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
    );
    const Size size = Size.fromHeight(_buttonHeight);
    return Expanded(
      child: Tooltip(
        message: _runsLabel(runs),
        child: boundary
            ? FilledButton(
                style: FilledButton.styleFrom(minimumSize: size, padding: EdgeInsets.zero),
                onPressed: enabled ? () => onRuns(runs) : null,
                child: child,
              )
            : FilledButton.tonal(
                style: FilledButton.styleFrom(
                  minimumSize: size,
                  padding: EdgeInsets.zero,
                  foregroundColor: AppColors.ink,
                  backgroundColor: AppColors.grassTint,
                ),
                onPressed: enabled ? () => onRuns(runs) : null,
                child: child,
              ),
      ),
    );
  }

  Widget _extraButton(ExtraType type, String label) {
    return Expanded(
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          foregroundColor: AppColors.creaseAmberInk,
          side: const BorderSide(color: AppColors.creaseAmber),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        onPressed: enabled ? () => onExtra(type) : null,
        child: Text(label, textAlign: TextAlign.center),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const SizedBox gap = SizedBox(width: AppSpacing.sm);
    const SizedBox rowGap = SizedBox(height: AppSpacing.sm);
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            _runButton(0),
            gap,
            _runButton(1),
            gap,
            _runButton(2),
            gap,
            _runButton(3),
          ],
        ),
        rowGap,
        Row(
          children: <Widget>[
            _runButton(4),
            gap,
            _runButton(5),
            gap,
            _runButton(6),
            gap,
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(_buttonHeight),
                  padding: EdgeInsets.zero,
                  backgroundColor: AppColors.ballRed,
                ),
                onPressed: enabled ? onWicket : null,
                child: const Text(
                  'OUT',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
        rowGap,
        Row(
          children: <Widget>[
            _extraButton(ExtraType.wide, 'Wide'),
            gap,
            _extraButton(ExtraType.noBall, 'No-ball'),
            gap,
            _extraButton(ExtraType.bye, 'Bye'),
            gap,
            _extraButton(ExtraType.legBye, 'Leg bye'),
          ],
        ),
      ],
    );
  }
}
