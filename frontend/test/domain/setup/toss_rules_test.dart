import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/domain/models/models.dart';
import 'package:gully_umpire/domain/setup/toss_rules.dart';

import '../../support/model_fixtures.dart';

void main() {
  group('tossWinnerTeamId', () {
    test('the calling team wins when its call matches the coin', () {
      expect(
        tossWinnerTeamId(
          callingTeamId: 'team-a',
          otherTeamId: 'team-b',
          call: TossSide.heads,
          result: TossSide.heads,
        ),
        'team-a',
      );
    });

    test('the other team wins when the call is wrong', () {
      expect(
        tossWinnerTeamId(
          callingTeamId: 'team-a',
          otherTeamId: 'team-b',
          call: TossSide.heads,
          result: TossSide.tails,
        ),
        'team-b',
      );
      expect(
        tossWinnerTeamId(
          callingTeamId: 'team-b',
          otherTeamId: 'team-a',
          call: TossSide.tails,
          result: TossSide.heads,
        ),
        'team-a',
      );
    });
  });

  group('battingFirstTeamId', () {
    // sampleMatch is between team-a and team-b; sampleToss is won by team-b who bowl.
    test('the winner choosing to bat bats first', () {
      final Toss toss = sampleToss.copyWith(winnerDecision: TossDecision.bat);
      expect(battingFirstTeamId(toss, sampleMatch), 'team-b');
    });

    test('the winner choosing to bowl means the other team bats first', () {
      expect(battingFirstTeamId(sampleToss, sampleMatch), 'team-a');
    });

    test('team A winning and batting bats first', () {
      final Toss toss = sampleToss.copyWith(
        winnerTeamId: 'team-a',
        winnerDecision: TossDecision.bat,
      );
      expect(battingFirstTeamId(toss, sampleMatch), 'team-a');
    });

    test('team A winning and bowling hands the bat to team B', () {
      final Toss toss = sampleToss.copyWith(
        winnerTeamId: 'team-a',
        winnerDecision: TossDecision.bowl,
      );
      expect(battingFirstTeamId(toss, sampleMatch), 'team-b');
    });

    test('is null until both the winner and the decision are known', () {
      final Toss noWinner = Toss(
        id: 't',
        matchId: 'match-1',
        callChoice: TossSide.heads,
        result: TossSide.heads,
        winnerDecision: TossDecision.bat,
        createdAt: t0,
      );
      final Toss noDecision = Toss(
        id: 't',
        matchId: 'match-1',
        callChoice: TossSide.heads,
        result: TossSide.heads,
        winnerTeamId: 'team-a',
        createdAt: t0,
      );
      expect(battingFirstTeamId(noWinner, sampleMatch), isNull);
      expect(battingFirstTeamId(noDecision, sampleMatch), isNull);
    });

    test('is null when the winner is not one of the two teams', () {
      final Toss toss = sampleToss.copyWith(winnerTeamId: 'team-x');
      expect(battingFirstTeamId(toss, sampleMatch), isNull);
    });
  });
}
