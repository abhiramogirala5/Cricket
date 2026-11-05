import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/domain/models/models.dart';
import 'package:gully_umpire/domain/setup/match_setup.dart';
import 'package:gully_umpire/features/match_setup/team_draft.dart';

import '../../support/model_fixtures.dart';

Player _saved(String id, String name, {BattingHand hand = BattingHand.unknown, int? height}) =>
    Player(
      id: id,
      displayName: name,
      battingHand: hand,
      declaredHeightCm: height,
      createdAt: t0,
      updatedAt: t0,
    );

void main() {
  group('PlayerDraft', () {
    test('an untouched row is blank, a row with a name is not', () {
      final PlayerDraft blank = PlayerDraft();
      final PlayerDraft spaces = PlayerDraft(name: '   ');
      final PlayerDraft named = PlayerDraft(name: 'Ravi');
      addTearDown(blank.dispose);
      addTearDown(spaces.dispose);
      addTearDown(named.dispose);
      expect(blank.isBlank, isTrue);
      expect(spaces.isBlank, isTrue);
      expect(named.isBlank, isFalse);
      expect(named.isSaved, isFalse);
    });

    test('a saved player is never blank and keeps its id', () {
      final PlayerDraft row = PlayerDraft.fromSaved(
        _saved('p1', 'Asha', hand: BattingHand.left, height: 168),
      );
      addTearDown(row.dispose);
      expect(row.isSaved, isTrue);
      expect(row.isBlank, isFalse);
      expect(row.existingPlayerId, 'p1');
      expect(row.trimmedName, 'Asha');
      expect(row.battingHand, BattingHand.left);
      expect(row.heightCm, 168);
    });

    test('detailsLine lists what is set, in a fixed order', () {
      final PlayerDraft full = PlayerDraft(
        name: 'Ravi',
        battingHand: BattingHand.left,
        heightCm: 175,
        isCaptain: true,
        isWicketkeeper: true,
      );
      final PlayerDraft empty = PlayerDraft(name: 'Dev');
      addTearDown(full.dispose);
      addTearDown(empty.dispose);
      expect(full.detailsLine, 'Captain · Wicketkeeper · Left-handed · 175 cm');
      expect(empty.detailsLine, '');
    });

    test('toInput carries every field and the typed name', () {
      final PlayerDraft row = PlayerDraft(
        name: '  Ravi ',
        battingHand: BattingHand.right,
        heightCm: 180,
        isCaptain: true,
      );
      addTearDown(row.dispose);
      final RosterEntryInput input = row.toInput();
      expect(input.trimmedName, 'Ravi');
      expect(input.existingPlayerId, isNull);
      expect(input.battingHand, BattingHand.right);
      expect(input.declaredHeightCm, 180);
      expect(input.isCaptain, isTrue);
      expect(input.isWicketkeeper, isFalse);
    });
  });

  group('TeamDraft', () {
    test('starts with two blank rows unless told otherwise', () {
      final TeamDraft two = TeamDraft();
      final TeamDraft none = TeamDraft(blankPlayers: 0);
      addTearDown(two.dispose);
      addTearDown(none.dispose);
      expect(two.players, hasLength(2));
      expect(two.players.every((PlayerDraft p) => p.isBlank), isTrue);
      expect(none.players, isEmpty);
    });

    test('addBlank appends an empty row', () {
      final TeamDraft team = TeamDraft(blankPlayers: 0);
      addTearDown(team.dispose);
      team.addBlank();
      expect(team.players, hasLength(1));
      expect(team.players.single.isBlank, isTrue);
    });

    test('addSaved fills blank rows first, then appends', () {
      final TeamDraft team = TeamDraft();
      addTearDown(team.dispose);
      team.players[0].nameController.text = 'Typed';
      team.addSaved(<Player>[_saved('p1', 'Asha'), _saved('p2', 'Ravi')]);
      expect(
        team.players.map<String>((PlayerDraft p) => p.trimmedName),
        <String>['Typed', 'Asha', 'Ravi'],
      );
      expect(team.savedIds, <String>{'p1', 'p2'});
    });

    test('addSaved ignores a player who is already on the sheet', () {
      final TeamDraft team = TeamDraft(blankPlayers: 0);
      addTearDown(team.dispose);
      team.addSaved(<Player>[_saved('p1', 'Asha')]);
      team.addSaved(<Player>[_saved('p1', 'Asha'), _saved('p2', 'Ravi')]);
      expect(team.players, hasLength(2));
      expect(team.savedIds, <String>{'p1', 'p2'});
    });

    test('remove takes the row off the sheet', () {
      final TeamDraft team = TeamDraft();
      addTearDown(team.dispose);
      final PlayerDraft first = team.players.first;
      team.remove(first);
      expect(team.players, hasLength(1));
      expect(team.players.contains(first), isFalse);
    });

    test('only one captain at a time', () {
      final TeamDraft team = TeamDraft(blankPlayers: 3);
      addTearDown(team.dispose);
      team.players[0].isCaptain = true;
      team.players[1].isCaptain = true;
      team.enforceSingleCaptain(team.players[1]);
      expect(
        team.players.map<bool>((PlayerDraft p) => p.isCaptain),
        <bool>[false, true, false],
      );
    });

    test('turning a captain off leaves the others alone', () {
      final TeamDraft team = TeamDraft(blankPlayers: 2);
      addTearDown(team.dispose);
      team.players[0].isCaptain = true;
      team.players[1].isCaptain = false;
      team.enforceSingleCaptain(team.players[1]);
      expect(team.players[0].isCaptain, isTrue);
    });

    test('only one wicketkeeper at a time', () {
      final TeamDraft team = TeamDraft(blankPlayers: 2);
      addTearDown(team.dispose);
      team.players[0].isWicketkeeper = true;
      team.players[1].isWicketkeeper = true;
      team.enforceSingleWicketkeeper(team.players[0]);
      expect(
        team.players.map<bool>((PlayerDraft p) => p.isWicketkeeper),
        <bool>[true, false],
      );
    });

    test('toInput leaves out blank rows and keeps the order', () {
      final TeamDraft team = TeamDraft(name: ' Reds ', blankPlayers: 4);
      addTearDown(team.dispose);
      team.players[0].nameController.text = 'Ravi';
      team.players[2].nameController.text = 'Dev';
      team.players[2].heightCm = 170;
      final TeamInput input = team.toInput();
      expect(input.trimmedName, 'Reds');
      expect(
        input.players.map<String>((RosterEntryInput p) => p.trimmedName),
        <String>['Ravi', 'Dev'],
      );
      expect(input.players.last.declaredHeightCm, 170);
    });

    test('toInput keeps saved players with their ids', () {
      final TeamDraft team = TeamDraft(blankPlayers: 0);
      addTearDown(team.dispose);
      team.addSaved(<Player>[_saved('p1', 'Asha')]);
      final TeamInput input = team.toInput();
      expect(input.players.single.existingPlayerId, 'p1');
    });
  });
}
