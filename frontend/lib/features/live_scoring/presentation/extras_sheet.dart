import 'package:flutter/material.dart';
import 'package:gully_umpire/app/theme/app_colors.dart';
import 'package:gully_umpire/app/theme/app_spacing.dart';
import 'package:gully_umpire/domain/scoring/scoring.dart';
import 'package:gully_umpire/features/live_scoring/live_draft_builder.dart';

/// The four kinds of extras the scorer can add.
enum ExtraType {
  wide('Wide'),
  noBall('No-ball'),
  bye('Byes'),
  legBye('Leg byes');

  const ExtraType(this.label);

  final String label;
}

/// What the scorer chose in the extras sheet.
final class ExtraChoice {
  const ExtraChoice({required this.kind, required this.mode, required this.runs});

  final BallLegality kind;
  final RunsMode mode;

  /// Runs run, not counting the penalty run of a wide or a no-ball.
  final int runs;
}

/// Asks how many runs came with a wide, no-ball, bye or leg-bye. Returns `null` when dismissed.
Future<ExtraChoice?> showExtrasSheet(BuildContext context, {required ExtraType type}) {
  return showModalBottomSheet<ExtraChoice>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext sheetContext) => _ExtrasSheet(type: type),
  );
}

class _ExtrasSheet extends StatefulWidget {
  const _ExtrasSheet({required this.type});

  final ExtraType type;

  @override
  State<_ExtrasSheet> createState() => _ExtrasSheetState();
}

class _ExtrasSheetState extends State<_ExtrasSheet> {
  int _runs = 0;
  RunsMode _mode = RunsMode.bat;

  @override
  void initState() {
    super.initState();
    if (widget.type == ExtraType.bye || widget.type == ExtraType.legBye) {
      _runs = 1;
    }
  }

  List<int> get _options {
    switch (widget.type) {
      case ExtraType.wide:
        return const <int>[0, 1, 2, 3, 4];
      case ExtraType.noBall:
        return const <int>[0, 1, 2, 3, 4, 5, 6];
      case ExtraType.bye:
      case ExtraType.legBye:
        return const <int>[1, 2, 3, 4];
    }
  }

  ExtraChoice get _choice {
    switch (widget.type) {
      case ExtraType.wide:
        return ExtraChoice(kind: BallLegality.wide, mode: RunsMode.bat, runs: _runs);
      case ExtraType.noBall:
        return ExtraChoice(
          kind: BallLegality.noBall,
          mode: _runs == 0 ? RunsMode.bat : _mode,
          runs: _runs,
        );
      case ExtraType.bye:
        return ExtraChoice(kind: BallLegality.legal, mode: RunsMode.bye, runs: _runs);
      case ExtraType.legBye:
        return ExtraChoice(kind: BallLegality.legal, mode: RunsMode.legBye, runs: _runs);
    }
  }

  int get _total {
    switch (widget.type) {
      case ExtraType.wide:
      case ExtraType.noBall:
        return 1 + _runs;
      case ExtraType.bye:
      case ExtraType.legBye:
        return _runs;
    }
  }

  String _chipLabel(int value) {
    switch (widget.type) {
      case ExtraType.wide:
        return value == 0 ? 'Wide only' : '+$value';
      case ExtraType.noBall:
        return value == 0 ? 'No-ball only' : '+$value';
      case ExtraType.bye:
      case ExtraType.legBye:
        return '$value';
    }
  }

  String get _question {
    switch (widget.type) {
      case ExtraType.wide:
        return 'Extra runs run on the wide?';
      case ExtraType.noBall:
        return 'Runs scored on the no-ball?';
      case ExtraType.bye:
        return 'How many byes?';
      case ExtraType.legBye:
        return 'How many leg byes?';
    }
  }

  String get _summary {
    final int total = _total;
    final String runs = total == 1 ? '1 run' : '$total runs';
    switch (widget.type) {
      case ExtraType.wide:
        return 'Wide: $runs added. The ball is bowled again.';
      case ExtraType.noBall:
        return 'No-ball: $runs added. The ball is bowled again.';
      case ExtraType.bye:
        return 'Byes: $runs added. Not charged to the bowler.';
      case ExtraType.legBye:
        return 'Leg byes: $runs added. Not charged to the bowler.';
    }
  }

  /// The choice is checked with the same rules the scoring engine uses.
  bool get _valid {
    final ExtraChoice choice = _choice;
    final draft = buildDraft(
      bowlerId: 'bowler',
      strikerId: 'striker',
      nonStrikerId: 'other',
      kind: choice.kind,
      runs: choice.runs,
      runsMode: choice.mode,
    );
    return validateDeliveryInput(DeliveryInput.fromDraft(draft)) == null;
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenPadding,
          0,
          AppSpacing.screenPadding,
          AppSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              widget.type.label,
              style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(_question, style: text.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                for (final int value in _options)
                  ChoiceChip(
                    label: Text(_chipLabel(value)),
                    selected: _runs == value,
                    onSelected: (_) => setState(() => _runs = value),
                  ),
              ],
            ),
            if (widget.type == ExtraType.noBall && _runs > 0) ...<Widget>[
              const SizedBox(height: AppSpacing.lg),
              Text('Where did the runs come from?', style: text.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              SegmentedButton<RunsMode>(
                showSelectedIcon: false,
                segments: const <ButtonSegment<RunsMode>>[
                  ButtonSegment<RunsMode>(value: RunsMode.bat, label: Text('Off the bat')),
                  ButtonSegment<RunsMode>(value: RunsMode.bye, label: Text('Byes')),
                  ButtonSegment<RunsMode>(value: RunsMode.legBye, label: Text('Leg byes')),
                ],
                selected: <RunsMode>{_mode},
                onSelectionChanged: (Set<RunsMode> value) => setState(() => _mode = value.first),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            Text(_summary, style: text.bodyMedium?.copyWith(color: AppColors.inkMuted)),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: _valid ? () => Navigator.of(context).pop(_choice) : null,
              child: const Text('Add to the score'),
            ),
          ],
        ),
      ),
    );
  }
}
