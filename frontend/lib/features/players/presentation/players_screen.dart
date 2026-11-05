import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gully_umpire/app/theme/app_colors.dart';
import 'package:gully_umpire/app/theme/app_spacing.dart';
import 'package:gully_umpire/core/di/data_providers.dart';
import 'package:gully_umpire/core/widgets/async_body.dart';
import 'package:gully_umpire/core/widgets/dialogs.dart';
import 'package:gully_umpire/core/widgets/empty_state.dart';
import 'package:gully_umpire/core/widgets/friendly_error.dart';
import 'package:gully_umpire/core/widgets/screen_body.dart';
import 'package:gully_umpire/domain/models/models.dart';
import 'package:gully_umpire/features/players/presentation/player_edit_sheet.dart';

/// `Right-handed · 172 cm`, or `Details not set`.
String playerSubtitle(Player player) {
  final List<String> parts = <String>[
    if (player.battingHand != BattingHand.unknown) player.battingHand.label,
    if (player.declaredHeightCm != null) '${player.declaredHeightCm} cm',
  ];
  return parts.isEmpty ? 'Details not set' : parts.join(' · ');
}

/// The user's saved players: add new ones and change the details of existing ones.
class PlayersScreen extends ConsumerStatefulWidget {
  const PlayersScreen({super.key});

  @override
  ConsumerState<PlayersScreen> createState() => _PlayersScreenState();
}

class _PlayersScreenState extends ConsumerState<PlayersScreen> {
  bool _busy = false;

  Future<void> _add() async {
    final PlayerEdit? edit = await showPlayerEditSheet(context);
    if (!mounted) {
      return;
    }
    if (edit == null) {
      return;
    }
    await _run(() async {
      await ref.read(rosterRepositoryProvider).createPlayer(
            displayName: edit.name,
            battingHand: edit.battingHand,
            declaredHeightCm: edit.heightCm,
          );
    });
  }

  Future<void> _edit(Player player) async {
    final PlayerEdit? edit = await showPlayerEditSheet(context, initial: player);
    if (!mounted) {
      return;
    }
    if (edit == null) {
      return;
    }
    await _run(() async {
      await ref.read(rosterRepositoryProvider).updatePlayer(
            player,
            displayName: edit.name,
            battingHand: edit.battingHand,
            declaredHeightCm: edit.heightCm,
            clearHeight: edit.heightCm == null,
          );
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      showMessage(context, friendlyError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Player>> value = ref.watch(playersProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Saved players')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : () => unawaited(_add()),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add player'),
      ),
      body: AsyncBody<List<Player>>(
        value: value,
        onRetry: () => ref.invalidate(playersProvider),
        builder: (BuildContext context, List<Player> players) {
          if (players.isEmpty) {
            return EmptyState(
              icon: Icons.groups_outlined,
              title: 'No saved players yet',
              message: 'Players you add here can be picked again for every match.',
              actionLabel: 'Add a player',
              onAction: () => unawaited(_add()),
            );
          }
          final List<Player> sorted = List<Player>.of(players)
            ..sort(
              (Player a, Player b) =>
                  a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
            );
          return ScreenBody(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenPadding,
              AppSpacing.sm,
              AppSpacing.screenPadding,
              96,
            ),
            children: <Widget>[
              Card(
                child: Column(
                  children: <Widget>[
                    for (int i = 0; i < sorted.length; i++) ...<Widget>[
                      if (i > 0) const Divider(height: 1),
                      ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppColors.grassTint,
                          foregroundColor: AppColors.pitchGreenDark,
                          child: Text(_initial(sorted[i].displayName)),
                        ),
                        title: Text(sorted[i].displayName),
                        subtitle: Text(playerSubtitle(sorted[i])),
                        trailing: const Icon(Icons.edit_outlined),
                        onTap: _busy ? null : () => unawaited(_edit(sorted[i])),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _initial(String name) {
    final String trimmed = name.trim();
    return trimmed.isEmpty ? '?' : trimmed.substring(0, 1).toUpperCase();
  }
}
