import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/domain/models/models.dart';
import 'package:gully_umpire/domain/scoring/scoring.dart';
import 'package:gully_umpire/features/scorecard/scorecard_text.dart';

import '../../support/model_fixtures.dart';
import '../../support/scoring_fixtures.dart';

String _name(String id) {
  switch (id) {
    case bowlerId:
      return 'Asha';
    case strikerId:
      return 'Ravi';
    case nonStrikerId:
      return 'Dev';
    default:
      return 'Unknown';
  }
}

BatterLine _line(BatterStatus status, {DismissalType? type, String? bowler}) => BatterLine(
      playerId: strikerId,
      runs: 0,
      balls: 0,
      fours: 0,
      sixes: 0,
      status: status,
      dismissal: type == null
          ? null
          : DismissalInfo(type: type, deliveryId: 'delivery-1', bowlerId: bowler),
    );

void main() {
  group('dismissalText', () {
    test('batters who are not out or did not bat', () {
      expect(dismissalText(_line(BatterStatus.notOut), _name), 'not out');
      expect(dismissalText(_line(BatterStatus.didNotBat), _name), 'did not bat');
    });

    test('an out batter without dismissal details just reads "out"', () {
      expect(dismissalText(_line(BatterStatus.out), _name), 'out');
    });

    test('bowler wickets name the bowler', () {
      String text(DismissalType type) =>
          dismissalText(_line(BatterStatus.out, type: type, bowler: bowlerId), _name);
      expect(text(DismissalType.bowled), 'b Asha');
      expect(text(DismissalType.caught), 'c b Asha');
      expect(text(DismissalType.lbw), 'lbw b Asha');
      expect(text(DismissalType.stumped), 'st b Asha');
      expect(text(DismissalType.hitWicket), 'hit wicket b Asha');
    });

    test('a run out never names the bowler', () {
      expect(
        dismissalText(
          _line(BatterStatus.out, type: DismissalType.runOut, bowler: bowlerId),
          _name,
        ),
        'run out',
      );
      expect(
        dismissalText(_line(BatterStatus.out, type: DismissalType.runOut), _name),
        'run out',
      );
    });

    test('without a bowler the plain word is shown', () {
      String text(DismissalType type) =>
          dismissalText(_line(BatterStatus.out, type: type), _name);
      expect(text(DismissalType.bowled), 'bowled');
      expect(text(DismissalType.caught), 'caught');
      expect(text(DismissalType.lbw), 'lbw');
      expect(text(DismissalType.stumped), 'st');
      expect(text(DismissalType.hitWicket), 'hit wicket');
    });
  });

  test('extrasText lists each kind', () {
    const ExtrasSummary extras =
        ExtrasSummary(wides: 3, noBalls: 1, byes: 2, legByes: 1, total: 7);
    expect(extrasText(extras), 'Extras 7 (wd 3, nb 1, b 2, lb 1)');
    expect(extrasText(const ExtrasSummary()), 'Extras 0 (wd 0, nb 0, b 0, lb 0)');
  });

  test('fallOfWicketText shows score, batter and overs', () {
    const FallOfWicket fall = FallOfWicket(
      wicketNumber: 1,
      teamScore: 12,
      playerId: strikerId,
      legalBalls: 10,
    );
    expect(fallOfWicketText(fall, _name), '1-12 (Ravi, 1.4 ov)');
  });

  group('overBallLabel', () {
    test('a legal ball is shown at its own number', () {
      final Delivery third = makeDelivery(sequence: 3, ball: 3);
      expect(overBallLabel(third, <Delivery>[third]), '0.3');
    });

    test('a wide is shown at the legal ball it was bowled in place of', () {
      final Delivery first = makeDelivery(sequence: 1, ball: 1);
      final Delivery second = makeDelivery(sequence: 2, ball: 2);
      final Delivery wide = makeDelivery(sequence: 3, wide: true, runsExtras: 1);
      final Delivery third = makeDelivery(sequence: 4, ball: 3);
      expect(overBallLabel(wide, <Delivery>[first, second, wide, third]), '0.3');
    });

    test('a wide on the very first ball of the match is 0.1', () {
      final Delivery wide = makeDelivery(sequence: 1, wide: true, runsExtras: 1);
      expect(overBallLabel(wide, <Delivery>[wide]), '0.1');
    });

    test('undone balls do not move the label', () {
      final Delivery undone = makeDelivery(sequence: 1, ball: 1, voided: true);
      final Delivery noBall = makeDelivery(sequence: 2, noBall: true, runsExtras: 1);
      expect(overBallLabel(noBall, <Delivery>[undone, noBall]), '0.1');
    });

    test('only balls from the same over count', () {
      final Delivery oldBall = makeDelivery(sequence: 1, over: 0, ball: 1);
      final Delivery wide = makeDelivery(sequence: 7, over: 1, wide: true, runsExtras: 1);
      expect(overBallLabel(wide, <Delivery>[oldBall, wide]), '1.1');
    });
  });

  group('ballResultText', () {
    test('balls played off the bat', () {
      expect(ballResultText(makeDelivery()), 'No run');
      expect(ballResultText(makeDelivery(runsBat: 1)), '1 run');
      expect(ballResultText(makeDelivery(runsBat: 2)), '2 runs');
      expect(ballResultText(makeDelivery(runsBat: 3)), '3 runs');
      expect(ballResultText(makeDelivery(runsBat: 4)), 'FOUR');
      expect(ballResultText(makeDelivery(runsBat: 6)), 'SIX');
    });

    test('wides show the extra runs run on top of the penalty', () {
      expect(ballResultText(makeDelivery(wide: true, runsExtras: 1)), 'Wide');
      expect(ballResultText(makeDelivery(wide: true, runsExtras: 3)), 'Wide + 2');
    });

    test('no-balls show runs off the bat and byes', () {
      expect(ballResultText(makeDelivery(noBall: true, runsExtras: 1)), 'No-ball');
      expect(
        ballResultText(makeDelivery(noBall: true, runsExtras: 1, runsBat: 4)),
        'No-ball, FOUR',
      );
      expect(
        ballResultText(makeDelivery(noBall: true, runsExtras: 1, runsBat: 1)),
        'No-ball, 1 run',
      );
      expect(
        ballResultText(makeDelivery(noBall: true, runsExtras: 3, bye: true)),
        'No-ball, 2 byes',
      );
      expect(
        ballResultText(makeDelivery(noBall: true, runsExtras: 2, legBye: true)),
        'No-ball, 1 leg bye',
      );
    });

    test('byes and leg byes', () {
      expect(ballResultText(makeDelivery(bye: true, runsExtras: 1)), '1 bye');
      expect(ballResultText(makeDelivery(bye: true, runsExtras: 2)), '2 byes');
      expect(ballResultText(makeDelivery(legBye: true, runsExtras: 1)), '1 leg bye');
      expect(ballResultText(makeDelivery(legBye: true, runsExtras: 3)), '3 leg byes');
    });
  });

  group('ballSentence', () {
    test('names the bowler and the striker', () {
      expect(ballSentence(makeDelivery(runsBat: 4), _name), 'Asha to Ravi: FOUR');
    });

    test('a wicket adds who is out and how', () {
      final Delivery bowled = makeDelivery(
        wicket: true,
        dismissal: DismissalType.bowled,
        dismissedId: strikerId,
      );
      expect(ballSentence(bowled, _name), 'Asha to Ravi: No run. Ravi is out (Bowled)');
    });

    test('a run out of the non-striker names the non-striker', () {
      final Delivery runOut = makeDelivery(
        runsBat: 1,
        wicket: true,
        dismissal: DismissalType.runOut,
        dismissedId: nonStrikerId,
      );
      expect(ballSentence(runOut, _name), 'Asha to Ravi: 1 run. Dev is out (Run out)');
    });

    test('a wicket with missing details is still readable', () {
      final Delivery odd = makeDelivery(wicket: true);
      expect(ballSentence(odd, _name), 'Asha to Ravi: No run. A batter is out');
    });
  });

  group('hasAssistantData', () {
    test('is false for a hand-scored ball with no decisions', () {
      expect(hasAssistantData(makeDelivery(), const <DecisionRecord>[]), isFalse);
    });

    test('is true when the ball has a decision record', () {
      expect(hasAssistantData(makeDelivery(), <DecisionRecord>[sampleDecision]), isTrue);
    });

    test('is true when the ball has a speed or a tracking figure', () {
      expect(hasAssistantData(sampleDelivery, const <DecisionRecord>[]), isTrue);
      final Delivery tracked = Delivery(
        id: 'd',
        inningsId: inningsId,
        deliverySequence: 1,
        overNumber: 0,
        bowlerId: bowlerId,
        strikerId: strikerId,
        ballTrackingConfidence: 0.8,
        createdAt: t0,
      );
      expect(hasAssistantData(tracked, const <DecisionRecord>[]), isTrue);
    });
  });
}
