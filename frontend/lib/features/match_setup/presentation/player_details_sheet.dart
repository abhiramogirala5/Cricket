import 'package:flutter/material.dart';
import 'package:gully_umpire/app/theme/app_spacing.dart';
import 'package:gully_umpire/domain/models/models.dart';
import 'package:gully_umpire/domain/setup/match_setup.dart';

/// What the sheet hands back.
final class PlayerDetails {
  const PlayerDetails({
    required this.isCaptain,
    required this.isWicketkeeper,
    required this.battingHand,
    required this.heightCm,
  });

  final bool isCaptain;
  final bool isWicketkeeper;
  final BattingHand battingHand;
  final int? heightCm;
}

/// Asks for captain, wicketkeeper, batting hand and height of one player in a match.
/// Returns `null` when the sheet is dismissed.
Future<PlayerDetails?> showPlayerDetailsSheet(
  BuildContext context, {
  required String playerName,
  required PlayerDetails initial,
}) {
  return showModalBottomSheet<PlayerDetails>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext sheetContext) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
      child: _PlayerDetailsSheet(playerName: playerName, initial: initial),
    ),
  );
}

class _PlayerDetailsSheet extends StatefulWidget {
  const _PlayerDetailsSheet({required this.playerName, required this.initial});

  final String playerName;
  final PlayerDetails initial;

  @override
  State<_PlayerDetailsSheet> createState() => _PlayerDetailsSheetState();
}

class _PlayerDetailsSheetState extends State<_PlayerDetailsSheet> {
  late bool _captain = widget.initial.isCaptain;
  late bool _keeper = widget.initial.isWicketkeeper;
  late BattingHand _hand = widget.initial.battingHand;
  late final TextEditingController _height =
      TextEditingController(text: widget.initial.heightCm?.toString() ?? '');
  String? _heightError;

  @override
  void dispose() {
    _height.dispose();
    super.dispose();
  }

  void _save() {
    final String raw = _height.text.trim();
    int? height;
    if (raw.isNotEmpty) {
      height = int.tryParse(raw);
      if (height == null ||
          height < MatchSetupLimits.minHeightCm ||
          height > MatchSetupLimits.maxHeightCm) {
        setState(() {
          _heightError = 'Enter a height between ${MatchSetupLimits.minHeightCm} and '
              '${MatchSetupLimits.maxHeightCm} cm.';
        });
        return;
      }
    }
    Navigator.of(context).pop(
      PlayerDetails(
        isCaptain: _captain,
        isWicketkeeper: _keeper,
        battingHand: _hand,
        heightCm: height,
      ),
    );
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
              widget.playerName.isEmpty ? 'Player details' : widget.playerName,
              style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpacing.md),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Captain'),
              value: _captain,
              onChanged: (bool value) => setState(() => _captain = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Wicketkeeper'),
              value: _keeper,
              onChanged: (bool value) => setState(() => _keeper = value),
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
              decoration: InputDecoration(
                labelText: 'Height in cm (optional)',
                helperText: 'Helps the umpire assistant judge wides and height no-balls.',
                errorText: _heightError,
              ),
              onChanged: (_) {
                if (_heightError != null) {
                  setState(() => _heightError = null);
                }
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(onPressed: _save, child: const Text('Save')),
          ],
        ),
      ),
    );
  }
}
