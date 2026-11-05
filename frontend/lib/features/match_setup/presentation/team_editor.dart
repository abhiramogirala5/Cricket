import 'package:flutter/material.dart';
import 'package:gully_umpire/app/theme/app_colors.dart';
import 'package:gully_umpire/app/theme/app_spacing.dart';
import 'package:gully_umpire/domain/models/models.dart';
import 'package:gully_umpire/features/match_setup/presentation/player_details_sheet.dart';
import 'package:gully_umpire/features/match_setup/presentation/saved_players_sheet.dart';
import 'package:gully_umpire/features/match_setup/team_draft.dart';

/// The form for one team: its name and its players in batting order.
class TeamEditor extends StatelessWidget {
  const TeamEditor({
    super.key,
    required this.title,
    required this.draft,
    required this.savedPlayers,
    required this.unavailablePlayerIds,
    required this.savedTeamNames,
    required this.onChanged,
  });

  final String title;
  final TeamDraft draft;

  /// The whole saved player list.
  final List<Player> savedPlayers;

  /// Saved players already used by the other team (they cannot play for both).
  final Set<String> unavailablePlayerIds;

  /// Names of saved teams that can be tapped to fill in the name.
  final List<String> savedTeamNames;

  /// Tell the page to redraw (a row was added, removed or changed).
  final VoidCallback onChanged;

  Future<void> _editDetails(BuildContext context, PlayerDraft player) async {
    final PlayerDetails? result = await showPlayerDetailsSheet(
      context,
      playerName: player.trimmedName,
      initial: PlayerDetails(
        isCaptain: player.isCaptain,
        isWicketkeeper: player.isWicketkeeper,
        battingHand: player.battingHand,
        heightCm: player.heightCm,
      ),
    );
    if (result == null) {
      return;
    }
    player.isCaptain = result.isCaptain;
    player.isWicketkeeper = result.isWicketkeeper;
    player.battingHand = result.battingHand;
    player.heightCm = result.heightCm;
    draft.enforceSingleCaptain(player);
    draft.enforceSingleWicketkeeper(player);
    onChanged();
  }

  Future<void> _addSaved(BuildContext context) async {
    final List<Player>? picked = await showSavedPlayersSheet(
      context,
      players: savedPlayers,
      unavailable: <String>{...unavailablePlayerIds, ...draft.savedIds},
    );
    if (picked == null || picked.isEmpty) {
      return;
    }
    draft.addSaved(picked);
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool canPickSaved = savedPlayers.any(
      (Player player) =>
          !unavailablePlayerIds.contains(player.id) && !draft.savedIds.contains(player.id),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(title, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: draft.nameController,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Team name'),
            ),
            if (savedTeamNames.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: <Widget>[
                  for (final String name in savedTeamNames)
                    ActionChip(
                      label: Text(name),
                      onPressed: () {
                        draft.nameController.text = name;
                        onChanged();
                      },
                    ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Players, in batting order',
              style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (int i = 0; i < draft.players.length; i++)
              _PlayerRow(
                key: ObjectKey(draft.players[i]),
                number: i + 1,
                player: draft.players[i],
                onDetails: () => _editDetails(context, draft.players[i]),
                onRemove: () {
                  draft.remove(draft.players[i]);
                  onChanged();
                },
              ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              children: <Widget>[
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(64, 44)),
                  onPressed: () {
                    draft.addBlank();
                    onChanged();
                  },
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Add player'),
                ),
                if (canPickSaved)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(64, 44)),
                    onPressed: () => _addSaved(context),
                    icon: const Icon(Icons.group_add_outlined),
                    label: const Text('Saved players'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({
    super.key,
    required this.number,
    required this.player,
    required this.onDetails,
    required this.onRemove,
  });

  final int number;
  final PlayerDraft player;
  final VoidCallback onDetails;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final String details = player.detailsLine;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              SizedBox(
                width: 28,
                child: Text(
                  '$number.',
                  style: text.bodyMedium?.copyWith(color: AppColors.inkMuted),
                ),
              ),
              Expanded(
                child: player.isSaved
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        decoration: BoxDecoration(
                          color: AppColors.grassTint,
                          borderRadius: BorderRadius.circular(AppSpacing.radius),
                        ),
                        child: Row(
                          children: <Widget>[
                            const Icon(Icons.bookmark, size: 18, color: AppColors.pitchGreen),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(child: Text(player.trimmedName, style: text.bodyLarge)),
                          ],
                        ),
                      )
                    : TextField(
                        controller: player.nameController,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(hintText: 'Player name'),
                      ),
              ),
              IconButton(
                tooltip: 'Player details',
                onPressed: onDetails,
                icon: const Icon(Icons.tune),
              ),
              IconButton(
                tooltip: 'Remove player',
                onPressed: onRemove,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          if (details.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 28, top: 2),
              child: Text(
                details,
                style: text.bodySmall?.copyWith(color: AppColors.inkMuted),
              ),
            ),
        ],
      ),
    );
  }
}
