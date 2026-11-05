import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/domain/models/models.dart';
import 'package:gully_umpire/domain/scoring/scoring.dart';

import '../../support/scoring_fixtures.dart';

void main() {
  group('runsRun', () {
    int run({
      int bat = 0,
      int extras = 0,
      bool wide = false,
      bool noBall = false,
    }) =>
        runsRun(runsBat: bat, runsExtras: extras, isWide: wide, isNoBall: noBall);

    test('plain runs off the bat are run', () {
      expect(run(), 0);
      expect(run(bat: 1), 1);
      expect(run(bat: 2), 2);
      expect(run(bat: 3), 3);
    });

    test('boundaries are not run, but 5 and 7 (overthrows) are', () {
      expect(run(bat: 4), 0);
      expect(run(bat: 6), 0);
      expect(run(bat: 5), 5);
      expect(run(bat: 7), 7);
    });

    test('the penalty run of a wide or no-ball is not run', () {
      expect(run(wide: true, extras: 1), 0);
      expect(run(noBall: true, extras: 1), 0);
      expect(run(noBall: true, extras: 1, bat: 4), 0);
      expect(run(noBall: true, extras: 1, bat: 1), 1);
    });

    test('extra runs beyond the penalty are run', () {
      expect(run(wide: true, extras: 3), 2);
      expect(run(noBall: true, extras: 3), 2);
      expect(run(extras: 2), 2); // byes
    });
  });

  group('setupAfterDelivery', () {
    test('a dot ball keeps the same striker', () {
      final NextBallSetup setup = setupAfterDelivery(makeDelivery());
      expect(setup.strikerId, strikerId);
      expect(setup.nonStrikerId, nonStrikerId);
      expect(setup.overCompleted, isFalse);
      expect(setup.needsNewBatter, isFalse);
    });

    test('odd runs swap the batters, even runs do not', () {
      expect(setupAfterDelivery(makeDelivery(runsBat: 1)).strikerId, nonStrikerId);
      expect(setupAfterDelivery(makeDelivery(runsBat: 3)).strikerId, nonStrikerId);
      expect(setupAfterDelivery(makeDelivery(runsBat: 2)).strikerId, strikerId);
    });

    test('boundaries never swap', () {
      expect(setupAfterDelivery(makeDelivery(runsBat: 4)).strikerId, strikerId);
      expect(setupAfterDelivery(makeDelivery(runsBat: 6)).strikerId, strikerId);
    });

    test('overthrows (5) swap', () {
      expect(setupAfterDelivery(makeDelivery(runsBat: 5)).strikerId, nonStrikerId);
    });

    test('a bye run swaps; a wide with no extra runs does not', () {
      expect(setupAfterDelivery(makeDelivery(bye: true, runsExtras: 1)).strikerId, nonStrikerId);
      expect(setupAfterDelivery(makeDelivery(wide: true, runsExtras: 1)).strikerId, strikerId);
      expect(setupAfterDelivery(makeDelivery(wide: true, runsExtras: 2)).strikerId, nonStrikerId);
    });

    test('after the 6th legal ball the batters swap and a new bowler is due', () {
      final NextBallSetup setup = setupAfterDelivery(makeDelivery(ball: 6));
      expect(setup.overCompleted, isTrue);
      expect(setup.strikerId, nonStrikerId);
      expect(setup.nonStrikerId, strikerId);
    });

    test('a single on the 6th ball swaps twice: same striker, new over', () {
      final NextBallSetup setup = setupAfterDelivery(makeDelivery(ball: 6, runsBat: 1));
      expect(setup.overCompleted, isTrue);
      expect(setup.strikerId, strikerId);
    });

    test('a wide or no-ball never completes an over', () {
      expect(setupAfterDelivery(makeDelivery(wide: true, runsExtras: 1)).overCompleted, isFalse);
      expect(
        setupAfterDelivery(makeDelivery(noBall: true, runsExtras: 1, ball: 6)).overCompleted,
        isFalse,
      );
    });

    test('bowled: the incoming batter takes the striker end', () {
      final NextBallSetup setup = setupAfterDelivery(
        makeDelivery(wicket: true, dismissal: DismissalType.bowled, dismissedId: strikerId),
      );
      expect(setup.strikerId, isNull);
      expect(setup.nonStrikerId, nonStrikerId);
      expect(setup.vacantSlot, BatterSlot.striker);
      expect(setup.needsNewBatter, isTrue);
      expect(setup.strikeChoiceAllowed, isFalse);

      final NextBallSetup filled = setup.withIncoming('player-new');
      expect(filled.strikerId, 'player-new');
      expect(filled.nonStrikerId, nonStrikerId);
      expect(filled.needsNewBatter, isFalse);
    });

    test('caught after a run was run: parity is ignored, incoming takes the striker end', () {
      final NextBallSetup setup = setupAfterDelivery(
        makeDelivery(
          runsBat: 1,
          wicket: true,
          dismissal: DismissalType.caught,
          dismissedId: strikerId,
        ),
      );
      expect(setup.vacantSlot, BatterSlot.striker);
      expect(setup.nonStrikerId, nonStrikerId);
    });

    test('a wicket on the 6th ball: the survivor faces the next over, the new batter is at the other end', () {
      final NextBallSetup setup = setupAfterDelivery(
        makeDelivery(
          ball: 6,
          wicket: true,
          dismissal: DismissalType.lbw,
          dismissedId: strikerId,
        ),
      );
      expect(setup.overCompleted, isTrue);
      expect(setup.strikerId, nonStrikerId);
      expect(setup.nonStrikerId, isNull);
      expect(setup.vacantSlot, BatterSlot.nonStriker);
      expect(setup.withIncoming('player-new').nonStrikerId, 'player-new');
    });

    test('run-out of the non-striker vacates the non-striker end and lets the scorer pick strike', () {
      final NextBallSetup setup = setupAfterDelivery(
        makeDelivery(
          runsBat: 1,
          wicket: true,
          dismissal: DismissalType.runOut,
          dismissedId: nonStrikerId,
        ),
      );
      expect(setup.strikerId, strikerId);
      expect(setup.nonStrikerId, isNull);
      expect(setup.vacantSlot, BatterSlot.nonStriker);
      expect(setup.strikeChoiceAllowed, isTrue);
    });

    test('run-out of the striker vacates the striker end', () {
      final NextBallSetup setup = setupAfterDelivery(
        makeDelivery(
          wicket: true,
          dismissal: DismissalType.runOut,
          dismissedId: strikerId,
        ),
      );
      expect(setup.strikerId, isNull);
      expect(setup.vacantSlot, BatterSlot.striker);
      expect(setup.strikeChoiceAllowed, isTrue);
    });

    test('swapped() exchanges the ends and ignores a single batter', () {
      final NextBallSetup pair = const NextBallSetup(strikerId: 'a', nonStrikerId: 'b').swapped();
      expect(pair.strikerId, 'b');
      expect(pair.nonStrikerId, 'a');

      const NextBallSetup single = NextBallSetup(strikerId: 'a', nonStrikerId: null);
      expect(single.swapped(), single);
    });

    test('withIncoming does nothing when no end is vacant', () {
      const NextBallSetup full = NextBallSetup(strikerId: 'a', nonStrikerId: 'b');
      expect(full.withIncoming('c'), full);
    });
  });

  group('currentSetup', () {
    test('is null before the first ball', () {
      expect(currentSetup(const <Delivery>[]), isNull);
    });

    test('follows the most recent ball', () {
      final NextBallSetup? setup = currentSetup(<Delivery>[
        makeDelivery(sequence: 1, ball: 1, runsBat: 1),
        makeDelivery(sequence: 2, ball: 2, striker: nonStrikerId, nonStriker: strikerId, runsBat: 2),
      ]);
      expect(setup!.strikerId, nonStrikerId);
      expect(setup.nonStrikerId, strikerId);
    });

    test('ignores the order of the list', () {
      final NextBallSetup? setup = currentSetup(<Delivery>[
        makeDelivery(sequence: 2, ball: 2, striker: nonStrikerId, nonStriker: strikerId, runsBat: 2),
        makeDelivery(sequence: 1, ball: 1, runsBat: 1),
      ]);
      expect(setup!.strikerId, nonStrikerId);
    });

    test('after an undo the voided ball\'s own pair is used, so a chosen new batter is kept', () {
      final NextBallSetup? setup = currentSetup(<Delivery>[
        makeDelivery(
          sequence: 1,
          ball: 1,
          wicket: true,
          dismissal: DismissalType.bowled,
          dismissedId: strikerId,
        ),
        makeDelivery(sequence: 2, ball: 2, striker: 'player-new', voided: true),
      ]);
      expect(setup!.strikerId, 'player-new');
      expect(setup.nonStrikerId, nonStrikerId);
      expect(setup.needsNewBatter, isFalse);
    });
  });

  group('availableBatters', () {
    test('excludes batters who batted, were dismissed or are at the crease', () {
      final List<String> available = availableBatters(
        battingOrder: <String>['a', 'b', 'c', 'd', 'e'],
        deliveries: <Delivery>[
          makeDelivery(
            sequence: 1,
            striker: 'a',
            nonStriker: 'b',
            wicket: true,
            dismissal: DismissalType.bowled,
            dismissedId: 'a',
          ),
        ],
        atCrease: <String>['c'],
      );
      expect(available, <String>['d', 'e']);
    });

    test('a batter who only appears in a voided ball is available again', () {
      final List<String> available = availableBatters(
        battingOrder: <String>['a', 'b', 'c'],
        deliveries: <Delivery>[
          makeDelivery(sequence: 1, striker: 'a', nonStriker: 'b'),
          makeDelivery(sequence: 2, striker: 'c', nonStriker: 'b', voided: true),
        ],
      );
      expect(available, <String>['c']);
    });
  });
}
