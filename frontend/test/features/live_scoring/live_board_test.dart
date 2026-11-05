import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/domain/aggregates/match_bundle.dart';
import 'package:gully_umpire/domain/models/models.dart';
import 'package:gully_umpire/domain/scoring/scoring.dart';
import 'package:gully_umpire/features/live_scoring/live_board.dart';

import '../../support/bundle_fixtures.dart';
import '../../support/scoring_fixtures.dart';

/// A legal ball of the first over by `b1`, faced by `a1` with `a2` at the other end.
Delivery ball(
  int number, {
  int runsBat = 0,
  bool wicket = false,
  DismissalType? dismissal,
  String? dismissedId,
  bool voided = false,
  String striker = 'a1',
  String? nonStriker = 'a2',
  String bowler = 'b1',
}) =>
    makeDelivery(
      sequence: number,
      over: (number - 1) ~/ 6,
      ball: (number - 1) % 6 + 1,
      bowler: bowler,
      striker: striker,
      nonStriker: nonStriker,
      runsBat: runsBat,
      wicket: wicket,
      dismissal: dismissal,
      dismissedId: dismissedId,
      voided: voided,
    );

LiveBoard boardOf(
  List<Delivery> deliveries, {
  int overs = 2,
  int teamASize = 4,
  int teamBSize = 4,
}) {
  final MatchBundle bundle = makeBundle(
    deliveriesByInnings: <String, List<Delivery>>{inningsId: deliveries},
    overs: overs,
    teamASize: teamASize,
    teamBSize: teamBSize,
  );
  return LiveBoard.from(bundle, bundle.innings.single);
}

void main() {
  group('resolveReadiness', () {
    test('a new innings needs the openers and the bowler', () {
      final LiveBoard board = boardOf(const <Delivery>[]);
      final LiveReadiness readiness = board.readiness(const LiveChoices());
      expect(readiness.missing, <LiveRequirement>[LiveRequirement.openers, LiveRequirement.bowler]);
      expect(readiness.canScore, isFalse);
      expect(readiness.batterPairKnown, isFalse);
    });

    test('openers and a bowler make the first ball scorable', () {
      final LiveBoard board = boardOf(const <Delivery>[]);
      final LiveReadiness readiness = board.readiness(
        const LiveChoices(openerStrikerId: 'a1', openerNonStrikerId: 'a2', bowlerId: 'b1'),
      );
      expect(readiness.missing, isEmpty);
      expect(readiness.strikerId, 'a1');
      expect(readiness.nonStrikerId, 'a2');
      expect(readiness.bowlerId, 'b1');
      expect(readiness.canScore, isTrue);
      expect(readiness.batterPairKnown, isTrue);
    });

    test('the same player cannot open at both ends', () {
      final LiveBoard board = boardOf(const <Delivery>[]);
      final LiveReadiness readiness = board.readiness(
        const LiveChoices(openerStrikerId: 'a1', openerNonStrikerId: 'a1', bowlerId: 'b1'),
      );
      expect(readiness.missing, <LiveRequirement>[LiveRequirement.openers]);
      expect(readiness.canScore, isFalse);
    });

    test('only one opener chosen is not enough', () {
      final LiveBoard board = boardOf(const <Delivery>[]);
      final LiveReadiness readiness = board.readiness(const LiveChoices(openerStrikerId: 'a1'));
      expect(readiness.missing, contains(LiveRequirement.openers));
    });

    test('in the middle of an over nothing has to be chosen', () {
      final LiveBoard board = boardOf(<Delivery>[ball(1), ball(2), ball(3)]);
      final LiveReadiness readiness = board.readiness(const LiveChoices());
      expect(readiness.missing, isEmpty);
      expect(readiness.strikerId, 'a1');
      expect(readiness.nonStrikerId, 'a2');
      expect(readiness.bowlerId, 'b1');
      expect(readiness.canScore, isTrue);
    });

    test('an odd number of runs changes ends', () {
      final LiveBoard board = boardOf(<Delivery>[ball(1, runsBat: 1)]);
      final LiveReadiness readiness = board.readiness(const LiveChoices());
      expect(readiness.strikerId, 'a2');
      expect(readiness.nonStrikerId, 'a1');
    });

    test('after the sixth ball the batters swap and a new bowler is needed', () {
      final LiveBoard board = boardOf(<Delivery>[for (int i = 1; i <= 6; i++) ball(i)]);
      final LiveReadiness waiting = board.readiness(const LiveChoices());
      expect(waiting.missing, <LiveRequirement>[LiveRequirement.bowler]);
      expect(waiting.strikerId, 'a2');
      expect(waiting.nonStrikerId, 'a1');
      expect(waiting.canScore, isFalse);

      final LiveReadiness ready = board.readiness(const LiveChoices(bowlerId: 'b2'));
      expect(ready.missing, isEmpty);
      expect(ready.bowlerId, 'b2');
      expect(ready.canScore, isTrue);
    });

    test('a wicket needs the incoming batter, and the batter still at the crease stays visible', () {
      final LiveBoard board = boardOf(<Delivery>[
        ball(1),
        ball(2, wicket: true, dismissal: DismissalType.bowled, dismissedId: 'a1'),
      ]);
      final LiveReadiness waiting = board.readiness(const LiveChoices());
      expect(waiting.missing, <LiveRequirement>[LiveRequirement.incomingBatter]);
      expect(waiting.nonStrikerId, 'a2');
      expect(waiting.strikerId, isNull);
      expect(waiting.canScore, isFalse);
      expect(waiting.batterPairKnown, isFalse);

      final LiveReadiness ready = board.readiness(const LiveChoices(incomingBatterId: 'a3'));
      expect(ready.missing, isEmpty);
      expect(ready.strikerId, 'a3');
      expect(ready.nonStrikerId, 'a2');
      expect(ready.canScore, isTrue);
      expect(ready.batterPairKnown, isTrue);
    });

    test('after a run-out the scorer may swap who faces; otherwise the choice is ignored', () {
      final LiveBoard board = boardOf(<Delivery>[
        ball(1, wicket: true, dismissal: DismissalType.runOut, dismissedId: 'a1'),
      ]);
      final LiveReadiness plain = board.readiness(const LiveChoices(incomingBatterId: 'a3'));
      expect(plain.strikerId, 'a3');
      expect(plain.nonStrikerId, 'a2');

      final LiveReadiness swapped =
          board.readiness(const LiveChoices(incomingBatterId: 'a3', endsSwapped: true));
      expect(swapped.strikerId, 'a2');
      expect(swapped.nonStrikerId, 'a3');

      final LiveBoard normal = boardOf(<Delivery>[ball(1), ball(2)]);
      final LiveReadiness ignored = normal.readiness(const LiveChoices(endsSwapped: true));
      expect(ignored.strikerId, 'a1');
      expect(ignored.nonStrikerId, 'a2');
    });

    test('an incoming batter who had already faced an undone ball is kept', () {
      final LiveBoard board = boardOf(<Delivery>[
        ball(1, wicket: true, dismissal: DismissalType.runOut, dismissedId: 'a1'),
        // The incoming batter a3 faced a ball, then the scorer undid it.
        ball(2, striker: 'a3', nonStriker: 'a2', voided: true),
      ]);
      final LiveReadiness readiness = board.readiness(const LiveChoices());
      expect(readiness.missing, isEmpty);
      expect(readiness.strikerId, 'a3');
      expect(readiness.nonStrikerId, 'a2');
    });

    test('after an undone ball the same two batters and bowler are used again', () {
      final LiveBoard board = boardOf(<Delivery>[
        ball(1),
        ball(2, wicket: true, dismissal: DismissalType.bowled, dismissedId: 'a1', voided: true),
      ]);
      final LiveReadiness readiness = board.readiness(const LiveChoices());
      expect(readiness.missing, isEmpty);
      expect(readiness.strikerId, 'a1');
      expect(readiness.nonStrikerId, 'a2');
      expect(readiness.bowlerId, 'b1');
      expect(readiness.canScore, isTrue);
    });
  });

  group('LiveBoard', () {
    final List<Delivery> sample = <Delivery>[
      ball(1, runsBat: 4),
      ball(2, runsBat: 1),
      makeDelivery(
        sequence: 3,
        over: 0,
        ball: null,
        wide: true,
        runsExtras: 2,
        striker: 'a2',
        nonStriker: 'a1',
        bowler: 'b1',
      ),
      makeDelivery(
        sequence: 4,
        over: 0,
        ball: 3,
        wicket: true,
        dismissal: DismissalType.bowled,
        dismissedId: 'a2',
        striker: 'a2',
        nonStriker: 'a1',
        bowler: 'b1',
      ),
    ];

    test('shows the score, overs, run rate and the balls of the over', () {
      final LiveBoard board = boardOf(sample);
      expect(board.runs, 7);
      expect(board.wickets, 1);
      expect(board.legalBalls, 3);
      expect(board.scoreText, '7/1');
      expect(board.oversText, '0.3');
      expect(board.oversLimitText, 'of 2');
      expect(board.runRate, closeTo(14.0, 1e-9));
      expect(board.overLabels, <String>['4', '1', 'Wd+1', 'W']);
      expect(board.battingTeamName, 'Reds');
      expect(board.bowlingTeamName, 'Blues');
    });

    test('has no run rate before the first legal ball and no chase in the first innings', () {
      final LiveBoard board = boardOf(const <Delivery>[]);
      expect(board.runRate, isNull);
      expect(board.chaseText, isNull);
      expect(board.hasActiveBall, isFalse);
      expect(board.lastActiveBall, isNull);
      expect(board.overLabels, isEmpty);
    });

    test('finds the last ball that has not been undone', () {
      final LiveBoard board = boardOf(<Delivery>[ball(1), ball(2), ball(3, voided: true)]);
      expect(board.hasActiveBall, isTrue);
      expect(board.lastActiveBall?.deliverySequence, 2);

      final LiveBoard allUndone = boardOf(<Delivery>[ball(1, voided: true)]);
      expect(allUndone.hasActiveBall, isFalse);
      expect(allUndone.lastActiveBall, isNull);
    });

    test('looks up the figures of a batter and a bowler', () {
      final LiveBoard board = boardOf(sample);
      final BatterLine? a1 = board.batterLine('a1');
      expect(a1?.runs, 5);
      expect(a1?.balls, 2);
      expect(board.batterLine('a2')?.balls, 1, reason: 'the wide does not count as a ball faced');
      final BowlerLine? b1 = board.bowlerLine('b1');
      expect(b1?.runsConceded, 7);
      expect(b1?.wickets, 1);
      expect(board.batterLine('a4')?.hasBatted, isFalse, reason: 'listed, but has not batted');
      expect(board.batterLine('nobody'), isNull);
      expect(board.bowlerLine('b4'), isNull);
    });

    test('offers only batters who have not batted and are not at the crease', () {
      final LiveBoard board = boardOf(<Delivery>[
        ball(1),
        ball(2, wicket: true, dismissal: DismissalType.bowled, dismissedId: 'a1'),
      ]);
      expect(board.availableBatterIds(atCrease: <String>['a2']), <String>['a3', 'a4']);
      expect(boardOf(const <Delivery>[]).availableBatterIds(), <String>['a1', 'a2', 'a3', 'a4']);
    });

    test('does not offer the bowler of the previous over', () {
      final LiveBoard board = boardOf(<Delivery>[for (int i = 1; i <= 6; i++) ball(i)]);
      expect(board.availableBowlerIds, <String>['b2', 'b3', 'b4']);
    });

    test('offers the only bowler again when there is nobody else', () {
      final LiveBoard board = boardOf(
        <Delivery>[for (int i = 1; i <= 6; i++) ball(i)],
        teamBSize: 1,
      );
      expect(board.availableBowlerIds, <String>['b1']);
    });

    test('says what the chasing side needs', () {
      final MatchBundle bundle = makeBundle(
        innings: <Innings>[
          Innings(
            id: inningsId,
            matchId: matchId,
            inningsNumber: 1,
            battingTeamId: 'team-a',
            bowlingTeamId: 'team-b',
            totalRuns: 30,
            startedAt: fixedNow,
            endedAt: fixedNow,
          ),
          makeSecondInnings(),
        ],
        deliveriesByInnings: <String, List<Delivery>>{
          'innings-2': <Delivery>[
            makeDelivery(sequence: 1, over: 0, ball: 1, runsBat: 4, striker: 'b1', nonStriker: 'b2', bowler: 'a1'),
            makeDelivery(sequence: 2, over: 0, ball: 2, runsBat: 1, striker: 'b1', nonStriker: 'b2', bowler: 'a1'),
            makeDelivery(sequence: 3, over: 0, ball: 3, runsBat: 2, striker: 'b2', nonStriker: 'b1', bowler: 'a1'),
          ],
        },
      );
      final LiveBoard board = LiveBoard.from(bundle, bundle.inningsByNumber(2)!);
      // 30 to beat means 31 to win; 7 scored; 12 - 3 balls left.
      expect(board.chaseText, 'Need 24 from 9 balls');
      expect(board.progress.runsRequired, 24);
    });

    test('says when the target has been reached', () {
      final MatchBundle bundle = makeBundle(
        innings: <Innings>[
          Innings(
            id: inningsId,
            matchId: matchId,
            inningsNumber: 1,
            battingTeamId: 'team-a',
            bowlingTeamId: 'team-b',
            totalRuns: 3,
            startedAt: fixedNow,
            endedAt: fixedNow,
          ),
          makeSecondInnings(),
        ],
        deliveriesByInnings: <String, List<Delivery>>{
          'innings-2': <Delivery>[
            makeDelivery(sequence: 1, over: 0, ball: 1, runsBat: 4, striker: 'b1', nonStriker: 'b2', bowler: 'a1'),
          ],
        },
      );
      final LiveBoard board = LiveBoard.from(bundle, bundle.inningsByNumber(2)!);
      expect(board.chaseText, 'Target reached');
      expect(board.progress.shouldClose, isTrue);
      expect(board.progress.endReason, InningsEndReason.targetReached);
    });
  });

  group('bowlerFigures', () {
    test('says so when the bowler has not bowled', () {
      expect(bowlerFigures(null), 'Has not bowled yet');
    });

    test('shows overs, runs and wickets', () {
      const BowlerLine line =
          BowlerLine(playerId: 'b1', legalBalls: 8, runsConceded: 7, wickets: 1);
      expect(bowlerFigures(line), '1.2 ov · 7 runs · 1 wicket');
      const BowlerLine none =
          BowlerLine(playerId: 'b1', legalBalls: 6, runsConceded: 1, wickets: 0);
      expect(bowlerFigures(none), '1.0 ov · 1 run · 0 wickets');
    });
  });
}
