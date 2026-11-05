import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/domain/models/models.dart';
import 'package:gully_umpire/domain/scoring/scoring.dart';

import '../../support/scoring_fixtures.dart';

void main() {
  const Map<String, String> names = <String, String>{'t1': 'Reds', 't2': 'Blues'};

  MatchResult result({
    required int first,
    required int second,
    int secondWickets = 0,
    int secondPlayers = 6,
  }) =>
      computeMatchResult(
        firstTeamId: 't1',
        secondTeamId: 't2',
        firstTotal: first,
        secondTotal: second,
        secondWickets: secondWickets,
        secondPlayerCount: secondPlayers,
        teamNames: names,
      );

  group('computeMatchResult', () {
    test('the chasing team wins by the wickets in hand', () {
      final MatchResult r = result(first: 40, second: 41, secondWickets: 2);
      expect(r.winnerTeamId, 't2');
      expect(r.summary, 'Blues won by 3 wickets');
      expect(r.isTie, isFalse);
    });

    test('a single wicket in hand is singular', () {
      expect(result(first: 40, second: 45, secondWickets: 4).summary, 'Blues won by 1 wicket');
    });

    test('the margin is never below one wicket', () {
      expect(result(first: 10, second: 11, secondWickets: 5).summary, 'Blues won by 1 wicket');
    });

    test('the first team wins by the run difference', () {
      final MatchResult r = result(first: 52, second: 40);
      expect(r.winnerTeamId, 't1');
      expect(r.summary, 'Reds won by 12 runs');
    });

    test('a one-run win is singular', () {
      expect(result(first: 41, second: 40).summary, 'Reds won by 1 run');
    });

    test('equal totals tie the match', () {
      final MatchResult r = result(first: 30, second: 30);
      expect(r.winnerTeamId, isNull);
      expect(r.isTie, isTrue);
      expect(r.summary, 'Match tied');
    });

    test('an unknown team name falls back to "Team"', () {
      final MatchResult r = computeMatchResult(
        firstTeamId: 'x',
        secondTeamId: 'y',
        firstTotal: 5,
        secondTotal: 3,
        secondWickets: 0,
        secondPlayerCount: 4,
        teamNames: const <String, String>{},
      );
      expect(r.summary, 'Team won by 2 runs');
    });
  });

  test('chaseTarget is one more than the first innings total', () {
    expect(chaseTarget(40), 41);
    expect(chaseTarget(0), 1);
  });

  group('ballLabel', () {
    test('runs off the bat', () {
      expect(ballLabel(makeDelivery()), '0');
      expect(ballLabel(makeDelivery(runsBat: 4)), '4');
      expect(ballLabel(makeDelivery(runsBat: 6)), '6');
    });

    test('wides and no-balls show the extra runs on top of the penalty', () {
      expect(ballLabel(makeDelivery(wide: true, runsExtras: 1)), 'Wd');
      expect(ballLabel(makeDelivery(wide: true, runsExtras: 5)), 'Wd+4');
      expect(ballLabel(makeDelivery(noBall: true, runsExtras: 1)), 'Nb');
      expect(ballLabel(makeDelivery(noBall: true, runsExtras: 1, runsBat: 4)), 'Nb+4');
      expect(ballLabel(makeDelivery(noBall: true, legBye: true, runsExtras: 3)), 'Nb+2');
    });

    test('byes and leg-byes', () {
      expect(ballLabel(makeDelivery(bye: true, runsExtras: 2)), 'B2');
      expect(ballLabel(makeDelivery(legBye: true, runsExtras: 1)), 'Lb1');
    });

    test('wickets', () {
      expect(
        ballLabel(makeDelivery(wicket: true, dismissal: DismissalType.bowled, dismissedId: strikerId)),
        'W',
      );
      expect(
        ballLabel(
          makeDelivery(
            runsBat: 1,
            wicket: true,
            dismissal: DismissalType.runOut,
            dismissedId: nonStrikerId,
          ),
        ),
        '1W',
      );
    });
  });
}
