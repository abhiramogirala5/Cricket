import 'package:flutter/material.dart';
import 'package:gully_umpire/app/theme/app_colors.dart';
import 'package:gully_umpire/app/theme/app_spacing.dart';
import 'package:gully_umpire/domain/models/models.dart';
import 'package:gully_umpire/domain/scoring/scoring.dart';
import 'package:gully_umpire/features/live_scoring/live_draft_builder.dart';

/// What the scorer chose in the wicket sheet.
final class WicketChoice {
  const WicketChoice({
    required this.kind,
    required this.dismissal,
    required this.dismissedPlayerId,
    required this.runs,
  });

  final BallLegality kind;
  final DismissalType dismissal;
  final String dismissedPlayerId;

  /// Runs completed before a run-out (zero for every other dismissal).
  final int runs;
}

/// Asks how the wicket fell. Returns `null` when dismissed.
Future<WicketChoice?> showWicketSheet(
  BuildContext context, {
  required String strikerId,
  required String strikerName,
  String? nonStrikerId,
  String? nonStrikerName,
}) {
  return showModalBottomSheet<WicketChoice>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext sheetContext) => _WicketSheet(
      strikerId: strikerId,
      strikerName: strikerName,
      nonStrikerId: nonStrikerId,
      nonStrikerName: nonStrikerName,
    ),
  );
}

class _WicketSheet extends StatefulWidget {
  const _WicketSheet({
    required this.strikerId,
    required this.strikerName,
    this.nonStrikerId,
    this.nonStrikerName,
  });

  final String strikerId;
  final String strikerName;
  final String? nonStrikerId;
  final String? nonStrikerName;

  @override
  State<_WicketSheet> createState() => _WicketSheetState();
}

class _WicketSheetState extends State<_WicketSheet> {
  BallLegality _kind = BallLegality.legal;
  DismissalType? _dismissal;
  late String _outId = widget.strikerId;
  int _runs = 0;

  bool get _isRunOut => _dismissal == DismissalType.runOut;

  String get _effectiveOutId {
    final DismissalType? dismissal = _dismissal;
    if (dismissal == null || !nonStrikerCanBeOut(dismissal)) {
      return widget.strikerId;
    }
    return _outId;
  }

  int get _effectiveRuns => _isRunOut ? _runs : 0;

  WicketChoice? get _choice {
    final DismissalType? dismissal = _dismissal;
    if (dismissal == null) {
      return null;
    }
    final draft = buildDraft(
      bowlerId: 'bowler',
      strikerId: widget.strikerId,
      nonStrikerId: widget.nonStrikerId,
      kind: _kind,
      runs: _effectiveRuns,
      dismissal: dismissal,
      dismissedPlayerId: _effectiveOutId,
    );
    if (validateDeliveryInput(DeliveryInput.fromDraft(draft)) != null) {
      return null;
    }
    return WicketChoice(
      kind: _kind,
      dismissal: dismissal,
      dismissedPlayerId: _effectiveOutId,
      runs: _effectiveRuns,
    );
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<DismissalType> allowed = allowedDismissals(_kind);
    final WicketChoice? choice = _choice;
    final String? nonStrikerId = widget.nonStrikerId;
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
            Text('Wicket', style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: AppSpacing.md),
            Text('What kind of ball was it?', style: text.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            SegmentedButton<BallLegality>(
              showSelectedIcon: false,
              segments: const <ButtonSegment<BallLegality>>[
                ButtonSegment<BallLegality>(value: BallLegality.legal, label: Text('Normal')),
                ButtonSegment<BallLegality>(value: BallLegality.wide, label: Text('Wide')),
                ButtonSegment<BallLegality>(value: BallLegality.noBall, label: Text('No-ball')),
              ],
              selected: <BallLegality>{_kind},
              onSelectionChanged: (Set<BallLegality> value) {
                setState(() {
                  _kind = value.first;
                  final DismissalType? current = _dismissal;
                  if (current != null && !allowedDismissals(_kind).contains(current)) {
                    _dismissal = null;
                  }
                });
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('How was the batter out?', style: text.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                for (final DismissalType type in DismissalType.values)
                  ChoiceChip(
                    label: Text(type.label),
                    selected: _dismissal == type,
                    onSelected: allowed.contains(type)
                        ? (_) => setState(() => _dismissal = type)
                        : null,
                  ),
              ],
            ),
            if (_kind != BallLegality.legal) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              Text(
                _kind == BallLegality.wide
                    ? 'On a wide only a run-out, stumping or hit wicket counts.'
                    : 'On a no-ball only a run-out counts.',
                style: text.bodySmall?.copyWith(color: AppColors.inkMuted),
              ),
            ],
            if (_isRunOut && nonStrikerId != null) ...<Widget>[
              const SizedBox(height: AppSpacing.lg),
              Text('Who was run out?', style: text.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: <ButtonSegment<String>>[
                  ButtonSegment<String>(value: widget.strikerId, label: Text(widget.strikerName)),
                  ButtonSegment<String>(
                    value: nonStrikerId,
                    label: Text(widget.nonStrikerName ?? 'Other batter'),
                  ),
                ],
                selected: <String>{_outId},
                onSelectionChanged: (Set<String> value) => setState(() => _outId = value.first),
              ),
            ],
            if (_isRunOut) ...<Widget>[
              const SizedBox(height: AppSpacing.lg),
              Text('Runs completed before the run-out', style: text.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                children: <Widget>[
                  for (final int value in const <int>[0, 1, 2, 3])
                    ChoiceChip(
                      label: Text('$value'),
                      selected: _runs == value,
                      onSelected: (_) => setState(() => _runs = value),
                    ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.ballRed),
              onPressed: choice == null ? null : () => Navigator.of(context).pop(choice),
              child: const Text('Record the wicket'),
            ),
          ],
        ),
      ),
    );
  }
}
