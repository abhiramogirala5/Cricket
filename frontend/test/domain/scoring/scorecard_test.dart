import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/domain/models/models.dart';
import 'package:gully_umpire/domain/scoring/scoring.dart';

import '../../support/scoring_fixtures.dart';

const String a = 'bat-a';
const String b = 'bat-b';
const String c = 'bat-c';
const String d = 'bat-d';
const String e = 'bat-e';
const String x = 'bowl-x';
const String y = 'bowl-y';

/// A small innings whose figures were worked out by hand (see the comments).
List<Delivery> sampleInnings() => <Delivery>[
      // 1: A hits a four off X
      makeDelivery(sequence: 1, ball: 1, striker: a, nonStriker: b, bowler: x, runsBat: 4),
      // 2: wide (1 run), not a legal ball
      makeDelivery(sequence: 2, striker: a, nonStriker: b, bowler: x, wide: true, runsExtras: 1),
      // 3: A hits a six
      makeDelivery(sequence: 3, ball: 2, striker: a, nonStriker: b, bowler: x, runsBat: 6),
      // 4: B faces, 2 byes
      makeDelivery(
        sequence: 4,
        ball: 3,
        striker: b,
        nonStriker: a,
        bowler: x,
        bye: true,
        runsExtras: 2,
      ),
      // 5: B scores 1 and is caught
      makeDelivery(
        sequence: 5,
        ball: 4,
        striker: b,
        nonStriker: a,
        bowler: x,
        runsBat: 1,
        wicket: true,
        dismissal: DismissalType.caught,
        dismissedId: b,
      ),
      // 6: no-ball off Y, A hits 2 (3 runs in total: 2 + penalty)
      makeDelivery(
        sequence: 6,
        striker: a,
        nonStriker: c,
        bowler: y,
        noBall: true,
        runsBat: 2,
        runsExtras: 1,
      ),
      // 7: C (non-striker) is run out
      makeDelivery(
        sequence: 7,
        ball: 5,
        striker: a,
        nonStriker: c,
        bowler: y,
        wicket: true,
        dismissal: DismissalType.runOut,
        dismissedId: c,
      ),
    ];

InningsScorecard scorecardOf(List<Delivery> deliveries, {Iterable<String> atCrease = const <String>[]}) =>
    InningsScorecard.build(
      deliveries: deliveries,
      battingOrder: <String>[a, b, c, d, e],
      atCrease: atCrease,
    );

void main() {
  late InningsScorecard card;

  setUp(() {
    card = scorecardOf(sampleInnings());
  });

  test('innings totals', () {
    expect(card.total.totalRuns, 17);
    expect(card.total.wickets, 2);
    expect(card.total.legalBalls, 5);
  });

  group('batters', () {
    test('are listed in order of appearance, then those who did not bat', () {
      expect(card.batters.map((BatterLine l) => l.playerId), <String>[a, b, c, d, e]);
      expect(card.didNotBat.map((BatterLine l) => l.playerId), <String>[d, e]);
    });

    test('striker runs, balls faced (no-ball counts, wide does not), boundaries, strike rate', () {
      final BatterLine line = card.batters.first;
      expect(line.runs, 12);
      expect(line.balls, 4);
      expect(line.fours, 1);
      expect(line.sixes, 1);
      expect(line.status, BatterStatus.notOut);
      expect(line.strikeRate, closeTo(300, 0.001));
    });

    test('a bye counts as a ball faced but gives no runs', () {
      final BatterLine line = card.batters[1];
      expect(line.runs, 1);
      expect(line.balls, 2);
    });

    test('dismissals record how, and who (a run-out is not credited to the bowler)', () {
      final BatterLine caught = card.batters[1];
      expect(caught.status, BatterStatus.out);
      expect(caught.dismissal!.type, DismissalType.caught);
      expect(caught.dismissal!.bowlerId, x);

      final BatterLine runOut = card.batters[2];
      expect(runOut.status, BatterStatus.out);
      expect(runOut.dismissal!.type, DismissalType.runOut);
      expect(runOut.dismissal!.bowlerId, isNull);
      expect(runOut.balls, 0);
    });

    test('strike rate is 0 when no ball was faced', () {
      expect(card.batters[2].strikeRate, 0);
    });

    test('a batter waiting at the crease is not-out, not "did not bat"', () {
      final InningsScorecard withCrease = scorecardOf(sampleInnings(), atCrease: <String>[d]);
      final BatterLine line = withCrease.batters.firstWhere((BatterLine l) => l.playerId == d);
      expect(line.status, BatterStatus.notOut);
      expect(line.balls, 0);
      expect(withCrease.didNotBat.map((BatterLine l) => l.playerId), <String>[e]);
    });
  });

  group('bowlers', () {
    test('legal balls, runs (byes excluded, wide and no-ball penalty included), wickets', () {
      final BowlerLine bowlerX = card.bowlers[0];
      expect(bowlerX.playerId, x);
      expect(bowlerX.legalBalls, 4);
      expect(bowlerX.runsConceded, 12); // 4 + wide 1 + 6 + bye 0 + 1
      expect(bowlerX.wickets, 1);
      expect(bowlerX.economy, closeTo(18, 0.001));

      final BowlerLine bowlerY = card.bowlers[1];
      expect(bowlerY.legalBalls, 1);
      expect(bowlerY.runsConceded, 3); // 2 off the bat + no-ball penalty
      expect(bowlerY.wickets, 0); // run-out is not the bowler's wicket
    });

    test('economy is 0 before the first legal ball', () {
      final InningsScorecard onlyWide = scorecardOf(<Delivery>[
        makeDelivery(wide: true, runsExtras: 1, bowler: x),
      ]);
      expect(onlyWide.bowlers.single.legalBalls, 0);
      expect(onlyWide.bowlers.single.economy, 0);
    });
  });

  test('extras are split into wides, no-balls and byes', () {
    expect(card.extras.wides, 1);
    expect(card.extras.noBalls, 1);
    expect(card.extras.byes, 2);
    expect(card.extras.legByes, 0);
    expect(card.extras.total, 4);
  });

  test('leg-byes and a no-ball with byes are split correctly', () {
    final InningsScorecard legByes = scorecardOf(<Delivery>[
      makeDelivery(sequence: 1, ball: 1, legBye: true, runsExtras: 3),
      makeDelivery(sequence: 2, noBall: true, bye: true, runsExtras: 3),
    ]);
    expect(legByes.extras.legByes, 3);
    expect(legByes.extras.byes, 2); // 3 extras minus the no-ball penalty
    expect(legByes.extras.noBalls, 1);
    expect(legByes.extras.total, 6);
  });

  test('fall of wickets: score, wicket number, batter and legal balls at that point', () {
    expect(card.fallOfWickets.length, 2);
    expect(card.fallOfWickets[0].wicketNumber, 1);
    expect(card.fallOfWickets[0].teamScore, 14);
    expect(card.fallOfWickets[0].playerId, b);
    expect(card.fallOfWickets[0].legalBalls, 4);
    expect(card.fallOfWickets[1].wicketNumber, 2);
    expect(card.fallOfWickets[1].teamScore, 17);
    expect(card.fallOfWickets[1].playerId, c);
    expect(card.fallOfWickets[1].legalBalls, 5);
  });

  test('voided deliveries change nothing', () {
    final InningsScorecard withVoided = scorecardOf(<Delivery>[
      ...sampleInnings(),
      makeDelivery(sequence: 8, ball: 6, striker: a, nonStriker: d, bowler: y, runsBat: 6, voided: true),
    ]);
    expect(withVoided.total, card.total);
    expect(withVoided.batters.length, card.batters.length);
    expect(withVoided.batters.first.runs, 12);
    expect(withVoided.bowlers[1].runsConceded, 3);
  });

  test('an empty innings lists everyone as did not bat', () {
    final InningsScorecard empty = scorecardOf(const <Delivery>[]);
    expect(empty.batters.length, 5);
    expect(empty.batters.every((BatterLine l) => !l.hasBatted), isTrue);
    expect(empty.bowlers, isEmpty);
    expect(empty.total.totalRuns, 0);
  });
}
