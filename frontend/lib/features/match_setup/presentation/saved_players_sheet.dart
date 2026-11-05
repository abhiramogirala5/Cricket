import 'package:flutter/material.dart';
import 'package:gully_umpire/app/theme/app_colors.dart';
import 'package:gully_umpire/app/theme/app_spacing.dart';
import 'package:gully_umpire/domain/models/models.dart';

/// Lets the person tick players from their saved list. Returns the ticked players, or `null`
/// when the sheet is dismissed. [unavailable] holds ids that are already on a team in this match.
Future<List<Player>?> showSavedPlayersSheet(
  BuildContext context, {
  required List<Player> players,
  required Set<String> unavailable,
}) {
  return showModalBottomSheet<List<Player>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext sheetContext) => _SavedPlayersSheet(
      players: <Player>[
        for (final Player player in players)
          if (!unavailable.contains(player.id)) player,
      ],
    ),
  );
}

class _SavedPlayersSheet extends StatefulWidget {
  const _SavedPlayersSheet({required this.players});

  final List<Player> players;

  @override
  State<_SavedPlayersSheet> createState() => _SavedPlayersSheetState();
}

class _SavedPlayersSheetState extends State<_SavedPlayersSheet> {
  final Set<String> _picked = <String>{};

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final double maxHeight = MediaQuery.sizeOf(context).height * 0.75;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
              child: Text(
                'Your saved players',
                style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (widget.players.isEmpty)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.screenPadding),
                child: Text(
                  'No saved players are free to add. Players you type into a match are saved '
                  'here automatically.',
                  style: text.bodyMedium?.copyWith(color: AppColors.inkMuted),
                ),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: <Widget>[
                    for (final Player player in widget.players)
                      CheckboxListTile(
                        value: _picked.contains(player.id),
                        title: Text(player.displayName),
                        subtitle: player.battingHand == BattingHand.unknown
                            ? null
                            : Text(player.battingHand.label),
                        onChanged: (bool? value) {
                          setState(() {
                            if (value ?? false) {
                              _picked.add(player.id);
                            } else {
                              _picked.remove(player.id);
                            }
                          });
                        },
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.screenPadding),
              child: FilledButton(
                onPressed: _picked.isEmpty
                    ? null
                    : () => Navigator.of(context).pop(
                          <Player>[
                            for (final Player player in widget.players)
                              if (_picked.contains(player.id)) player,
                          ],
                        ),
                child: Text(
                  _picked.isEmpty
                      ? 'Choose players'
                      : (_picked.length == 1 ? 'Add 1 player' : 'Add ${_picked.length} players'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
