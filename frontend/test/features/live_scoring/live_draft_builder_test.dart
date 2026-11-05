import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/domain/models/models.dart';
import 'package:gully_umpire/domain/scoring/scoring.dart';
import 'package:gully_umpire/features/live_scoring/live_draft_builder.dart';

DeliveryDraft draft({
  BallLegality kind = BallLegality.legal,
  int runs = 0,
  RunsMode mode = RunsMode.bat,
  DismissalType? dismissal,
  String? dismissedId,
  String? nonStriker = 'non-striker',
}) =>
    buildDraft(
      bowlerId: 'bowler',
      strikerId: 'striker',
      nonStrikerId: nonStriker,
      kind: kind,
      runs: runs,
      runsMode: mode,
      dismissal: dismissal,
      dismissedPlayerId: dismissedId,
    );

/// The same check the scoring engine and the server make.
String? problemWith(DeliveryDraft value) => validateDeliveryInput(DeliveryInput.fromDraft(value));

void main() {
  group('a normal ball', () {
    test('scores its runs off the bat and nothing else', () {
      for (int runs = 0; runs <= 6; runs++) {
        final DeliveryDraft value = draft(runs: runs);
        expect(value.runsBat, runs);
        expect(value.runsExtras, 0);
        expect(value.isWide || value.isNoBall || value.isBye || value.isLegBye, isFalse);
        expect(value.isWicket, isFalse);
        expect(problemWith(value), isNull, reason: '$runs runs');
      }
    });

    test('carries who bowled and who faced', () {
      final DeliveryDraft value = draft(runs: 1);
      expect(value.bowlerId, 'bowler');
      expect(value.strikerId, 'striker');
      expect(value.nonStrikerId, 'non-striker');
    });
  });

  group('extras', () {
    test('a wide is one penalty run plus the runs that were run', () {
      final DeliveryDraft plain = draft(kind: BallLegality.wide);
      expect(plain.isWide, isTrue);
      expect(plain.runsBat, 0);
      expect(plain.runsExtras, 1);
      expect(problemWith(plain), isNull);

      final DeliveryDraft overrun = draft(kind: BallLegality.wide, runs: 2);
      expect(overrun.runsExtras, 3);
      expect(problemWith(overrun), isNull);
    });

    test('on a wide every run is a wide, whatever the runs mode says', () {
      final DeliveryDraft value = draft(kind: BallLegality.wide, runs: 1, mode: RunsMode.bye);
      expect(value.isBye, isFalse);
      expect(value.runsExtras, 2);
      expect(problemWith(value), isNull);
    });

    test('a no-ball with no runs is one extra run', () {
      final DeliveryDraft value = draft(kind: BallLegality.noBall);
      expect(value.isNoBall, isTrue);
      expect(value.runsBat, 0);
      expect(value.runsExtras, 1);
      expect(problemWith(value), isNull);
    });

    test('runs off the bat on a no-ball are added to the penalty run', () {
      final DeliveryDraft value = draft(kind: BallLegality.noBall, runs: 4);
      expect(value.runsBat, 4);
      expect(value.runsExtras, 1);
      expect(value.isBye, isFalse);
      expect(problemWith(value), isNull);
    });

    test('byes and leg byes on a no-ball are extras on top of the penalty run', () {
      final DeliveryDraft byes = draft(kind: BallLegality.noBall, runs: 2, mode: RunsMode.bye);
      expect(byes.isNoBall, isTrue);
      expect(byes.isBye, isTrue);
      expect(byes.runsBat, 0);
      expect(byes.runsExtras, 3);
      expect(problemWith(byes), isNull);

      final DeliveryDraft legByes = draft(kind: BallLegality.noBall, runs: 1, mode: RunsMode.legBye);
      expect(legByes.isLegBye, isTrue);
      expect(legByes.runsExtras, 2);
      expect(problemWith(legByes), isNull);
    });

    test('byes and leg byes on a normal ball are extras and nothing else', () {
      final DeliveryDraft byes = draft(runs: 2, mode: RunsMode.bye);
      expect(byes.isBye, isTrue);
      expect(byes.runsBat, 0);
      expect(byes.runsExtras, 2);
      expect(problemWith(byes), isNull);

      final DeliveryDraft legBye = draft(runs: 1, mode: RunsMode.legBye);
      expect(legBye.isLegBye, isTrue);
      expect(legBye.runsExtras, 1);
      expect(problemWith(legBye), isNull);
    });

    test('everything the buttons and sheets can offer is accepted by the scoring rules', () {
      final List<String> rejected = <String>[];
      void check(String label, DeliveryDraft value) {
        final String? problem = problemWith(value);
        if (problem != null) {
          rejected.add('$label: $problem');
        }
      }

      for (int runs = 0; runs <= 6; runs++) {
        check('pad $runs', draft(runs: runs));
      }
      for (int runs = 0; runs <= 4; runs++) {
        check('wide $runs', draft(kind: BallLegality.wide, runs: runs));
      }
      for (int runs = 0; runs <= 6; runs++) {
        for (final RunsMode mode in RunsMode.values) {
          if (runs == 0 && mode != RunsMode.bat) {
            continue;
          }
          check('no-ball $runs ${mode.name}', draft(kind: BallLegality.noBall, runs: runs, mode: mode));
        }
      }
      for (int runs = 1; runs <= 4; runs++) {
        check('bye $runs', draft(runs: runs, mode: RunsMode.bye));
        check('leg bye $runs', draft(runs: runs, mode: RunsMode.legBye));
      }
      expect(rejected, isEmpty);
    });
  });

  group('wickets', () {
    test('the striker is out unless the scorer says otherwise', () {
      final DeliveryDraft value = draft(dismissal: DismissalType.bowled);
      expect(value.isWicket, isTrue);
      expect(value.dismissalType, DismissalType.bowled);
      expect(value.dismissedPlayerId, 'striker');
      expect(value.runsBat, 0);
      expect(problemWith(value), isNull);
    });

    test('a run-out can take the batter at the other end, with runs completed', () {
      final DeliveryDraft value = draft(
        runs: 1,
        dismissal: DismissalType.runOut,
        dismissedId: 'non-striker',
      );
      expect(value.dismissedPlayerId, 'non-striker');
      expect(value.runsBat, 1);
      expect(problemWith(value), isNull);
    });

    test('a stumping on a wide keeps the wide penalty run', () {
      final DeliveryDraft value = draft(kind: BallLegality.wide, dismissal: DismissalType.stumped);
      expect(value.isWide, isTrue);
      expect(value.runsExtras, 1);
      expect(value.isWicket, isTrue);
      expect(problemWith(value), isNull);
    });

    test('a run-out on a wide with runs and the non-striker out is accepted', () {
      final DeliveryDraft value = draft(
        kind: BallLegality.wide,
        runs: 1,
        dismissal: DismissalType.runOut,
        dismissedId: 'non-striker',
      );
      expect(value.runsExtras, 2);
      expect(problemWith(value), isNull);
    });

    test('a bowled batter at the other end is refused by the rules', () {
      final DeliveryDraft value = draft(dismissal: DismissalType.bowled, dismissedId: 'non-striker');
      expect(problemWith(value), isNotNull);
    });

    test('allowedDismissals is exactly what the scoring rules accept, for every kind of ball', () {
      for (final BallLegality kind in BallLegality.values) {
        final List<DismissalType> allowed = allowedDismissals(kind);
        for (final DismissalType type in DismissalType.values) {
          final bool accepted = problemWith(draft(kind: kind, dismissal: type)) == null;
          expect(accepted, allowed.contains(type), reason: '${kind.name} / ${type.name}');
        }
      }
    });

    test('allowedDismissals lists the dismissals of each kind of ball', () {
      expect(allowedDismissals(BallLegality.legal), DismissalType.values);
      expect(
        allowedDismissals(BallLegality.wide),
        <DismissalType>[DismissalType.runOut, DismissalType.stumped, DismissalType.hitWicket],
      );
      expect(allowedDismissals(BallLegality.noBall), <DismissalType>[DismissalType.runOut]);
    });

    test('only a run-out can dismiss the batter at the other end', () {
      for (final DismissalType type in DismissalType.values) {
        expect(nonStrikerCanBeOut(type), type == DismissalType.runOut);
        final bool accepted =
            problemWith(draft(dismissal: type, dismissedId: 'non-striker')) == null;
        expect(accepted, nonStrikerCanBeOut(type), reason: type.name);
      }
    });

    test('a last-pair ball without a non-striker still builds a valid wicket', () {
      final DeliveryDraft value = draft(dismissal: DismissalType.caught, nonStriker: null);
      expect(value.nonStrikerId, isNull);
      expect(problemWith(value), isNull);
    });
  });
}
