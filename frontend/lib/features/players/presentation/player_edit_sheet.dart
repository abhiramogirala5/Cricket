import 'package:flutter/material.dart';
import 'package:gully_umpire/app/theme/app_spacing.dart';
import 'package:gully_umpire/domain/models/models.dart';
import 'package:gully_umpire/domain/setup/match_setup.dart';

/// What the sheet hands back. [heightCm] is `null` when the height field was left empty.
final class PlayerEdit {
  const PlayerEdit({required this.name, required this.battingHand, required this.heightCm});

  final String name;
  final BattingHand battingHand;
  final int? heightCm;
}

/// Asks for the name, batting hand and height of a saved player. Pass [initial] to edit one.
/// Returns `null` when dismissed.
Future<PlayerEdit?> showPlayerEditSheet(BuildContext context, {Player? initial}) {
  return showModalBottomSheet<PlayerEdit>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext sheetContext) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
      child: _PlayerEditSheet(initial: initial),
    ),
  );
}

class _PlayerEditSheet extends StatefulWidget {
  const _PlayerEditSheet({this.initial});

  final Player? initial;

  @override
  State<_PlayerEditSheet> createState() => _PlayerEditSheetState();
}

class _PlayerEditSheetState extends State<_PlayerEditSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.initial?.displayName ?? '');
  late final TextEditingController _height =
      TextEditingController(text: widget.initial?.declaredHeightCm?.toString() ?? '');
  late BattingHand _hand = widget.initial?.battingHand ?? BattingHand.unknown;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _height.dispose();
    super.dispose();
  }

  void _save() {
    final String rawHeight = _height.text.trim();
    int? height;
    if (rawHeight.isNotEmpty) {
      height = int.tryParse(rawHeight);
      if (height == null) {
        setState(() => _error = 'Height must be a whole number of centimetres.');
        return;
      }
    }
    final String? problem = validatePlayerFields(name: _name.text, heightCm: height);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    Navigator.of(context).pop(
      PlayerEdit(name: _name.text.trim(), battingHand: _hand, heightCm: height),
    );
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool editing = widget.initial != null;
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
              editing ? 'Edit player' : 'Add a player',
              style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _name,
              autofocus: !editing,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Name'),
              onChanged: (_) {
                if (_error != null) {
                  setState(() => _error = null);
                }
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            Text('Batting hand', style: text.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            SegmentedButton<BattingHand>(
              showSelectedIcon: false,
              segments: const <ButtonSegment<BattingHand>>[
                ButtonSegment<BattingHand>(value: BattingHand.right, label: Text('Right')),
                ButtonSegment<BattingHand>(value: BattingHand.left, label: Text('Left')),
                ButtonSegment<BattingHand>(value: BattingHand.unknown, label: Text('Not set')),
              ],
              selected: <BattingHand>{_hand},
              onSelectionChanged: (Set<BattingHand> value) => setState(() => _hand = value.first),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _height,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'Height in cm (optional)',
                helperText: editing
                    ? 'Empty means no height is saved.'
                    : 'Helps the umpire assistant judge wides and height no-balls.',
              ),
              onChanged: (_) {
                if (_error != null) {
                  setState(() => _error = null);
                }
              },
              onSubmitted: (_) => _save(),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _error!,
                style: text.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            FilledButton(onPressed: _save, child: Text(editing ? 'Save changes' : 'Add player')),
          ],
        ),
      ),
    );
  }
}
