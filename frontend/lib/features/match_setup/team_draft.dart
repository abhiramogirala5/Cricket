import 'package:flutter/widgets.dart';
import 'package:gully_umpire/domain/models/models.dart';
import 'package:gully_umpire/domain/setup/match_setup.dart';

/// One row of a team sheet while it is being typed.
///
/// A row either holds a brand-new name (typed in) or points at a saved player. Saved players keep
/// the name they have in the roster; their batting hand and height can still be set for this match.
final class PlayerDraft {
  PlayerDraft({
    String name = '',
    this.existingPlayerId,
    this.battingHand = BattingHand.unknown,
    this.heightCm,
    this.isCaptain = false,
    this.isWicketkeeper = false,
  }) : nameController = TextEditingController(text: name);

  /// A row for a player from the saved roster.
  factory PlayerDraft.fromSaved(Player player) => PlayerDraft(
        name: player.displayName,
        existingPlayerId: player.id,
        battingHand: player.battingHand,
        heightCm: player.declaredHeightCm,
      );

  final TextEditingController nameController;
  final String? existingPlayerId;
  BattingHand battingHand;
  int? heightCm;
  bool isCaptain;
  bool isWicketkeeper;

  bool get isSaved => existingPlayerId != null;

  String get trimmedName => nameController.text.trim();

  /// An untouched empty row. It is left out of the match instead of blocking it.
  bool get isBlank => !isSaved && trimmedName.isEmpty;

  /// "Captain, wicketkeeper, left-handed, 175 cm", or an empty string when nothing is set.
  String get detailsLine {
    final List<String> parts = <String>[
      if (isCaptain) 'Captain',
      if (isWicketkeeper) 'Wicketkeeper',
      if (battingHand != BattingHand.unknown) battingHand.label,
      if (heightCm != null) '$heightCm cm',
    ];
    return parts.join(' · ');
  }

  RosterEntryInput toInput() => RosterEntryInput(
        displayName: nameController.text,
        existingPlayerId: existingPlayerId,
        battingHand: battingHand,
        declaredHeightCm: heightCm,
        isCaptain: isCaptain,
        isWicketkeeper: isWicketkeeper,
      );

  void dispose() => nameController.dispose();
}

/// A team sheet while it is being typed: the team name and the players in batting order.
final class TeamDraft {
  TeamDraft({String name = '', int blankPlayers = 2})
      : nameController = TextEditingController(text: name) {
    for (int i = 0; i < blankPlayers; i++) {
      players.add(PlayerDraft());
    }
  }

  final TextEditingController nameController;
  final List<PlayerDraft> players = <PlayerDraft>[];

  String get trimmedName => nameController.text.trim();

  /// Ids of the saved players already on this sheet.
  Set<String> get savedIds => <String>{
        for (final PlayerDraft player in players)
          if (player.existingPlayerId != null) player.existingPlayerId!,
      };

  void addBlank() => players.add(PlayerDraft());

  /// Adds saved players, filling empty rows first so no blank rows are left in the middle.
  void addSaved(Iterable<Player> saved) {
    for (final Player player in saved) {
      if (savedIds.contains(player.id)) {
        continue;
      }
      final int blank = players.indexWhere((PlayerDraft row) => row.isBlank);
      final PlayerDraft row = PlayerDraft.fromSaved(player);
      if (blank >= 0) {
        players[blank].dispose();
        players[blank] = row;
      } else {
        players.add(row);
      }
    }
  }

  void remove(PlayerDraft player) {
    if (players.remove(player)) {
      player.dispose();
    }
  }

  /// Makes [player] the only captain (or clears the captain when [player] is not one).
  void enforceSingleCaptain(PlayerDraft player) {
    if (!player.isCaptain) {
      return;
    }
    for (final PlayerDraft other in players) {
      if (!identical(other, player)) {
        other.isCaptain = false;
      }
    }
  }

  void enforceSingleWicketkeeper(PlayerDraft player) {
    if (!player.isWicketkeeper) {
      return;
    }
    for (final PlayerDraft other in players) {
      if (!identical(other, player)) {
        other.isWicketkeeper = false;
      }
    }
  }

  /// The sheet as the repository wants it. Blank rows are left out.
  TeamInput toInput() => TeamInput(
        name: nameController.text,
        players: <RosterEntryInput>[
          for (final PlayerDraft player in players)
            if (!player.isBlank) player.toInput(),
        ],
      );

  void dispose() {
    nameController.dispose();
    for (final PlayerDraft player in players) {
      player.dispose();
    }
  }
}
