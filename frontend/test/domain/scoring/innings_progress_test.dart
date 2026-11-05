import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/domain/models/models.dart';
import 'package:gully_umpire/domain/scoring/scoring.dart';

import '../../support/scoring_fixtures.dart';

/// [count] legal dot balls by [bowler], numbered like the engine numbers them.
List<Delivery> dots(int count, {String bowler = bowlerId, int firstSequence = 1, int firstLegal = 0}) {
  return <Delivery>[
    for (int i = 0; i < count; i += 1)
      makeDelivery(
        sequence: firstSequence + i,
        over: (firstLegal + i) ~/ 6,
        ball: (firstLegal + i) % 6 + 1,
        bowler: bowler,
      ),
  ];
}

InningsProgress progress(
  List<Delivery> deliveries, {
  int overs = 2,
  int players = 4,
  int? firstTotal,
  Innings? innings,
}) =>
    InningsProgress.from(
      innings: innings ?? makeInnings(),
      oversPerInnings: overs,
      battingPlayerCount: players,
      deliveries: deliveries,
      firstInningsTotal: firstTotal,
    );

void main() {
  test('a new innings needs openers and a bowler', () {
    final InningsProgress p = progress(const <Delivery>[]);
    expect(p.needsOpeners, isTrue);
    expect(p.needsNewBowler, isTrue);
    expect(p.canScore, isTrue);
    expect(p.shouldClose, isFalse);
    expect(p.ballsRemaining, 12);
    expect(p.runsRequired, isNull);
    expect(p.overDeliveries, isEmpty);
  });

  test('mid-over: same bowler, balls of the over listed in order', () {
    final InningsProgress p = progress(dots(3));
    expect(p.needsOpeners, isFalse);
    expect(p.currentBowlerId, bowlerId);
    expect(p.needsNewBowler, isFalse);
    expect(p.overDeliveries.map((Delivery d) => d.deliverySequence), <int>[1, 2, 3]);
    expect(p.isShowingCompletedOver, isFalse);
    expect(p.ballsRemaining, 9);
  });

  test('after six legal balls a new bowler is needed and the last over stays visible', () {
    final InningsProgress p = progress(dots(6));
    expect(p.needsNewBowler, isTrue);
    expect(p.isShowingCompletedOver, isTrue);
    expect(p.overDeliveries.length, 6);
    expect(p.canScore, isTrue);
  });

  test('the bowler of the previous over is reported (no two overs in a row)', () {
    final List<Delivery> all = <Delivery>[
      ...dots(6),
      makeDelivery(sequence: 7, over: 1, ball: 1, bowler: 'player-bowler-2'),
    ];
    final InningsProgress p = progress(all);
    expect(p.currentBowlerId, 'player-bowler-2');
    expect(p.previousOverBowlerId, bowlerId);
    expect(p.isShowingCompletedOver, isFalse);
  });

  test('a wide bowled right after the over belongs to the new over and its bowler', () {
    final List<Delivery> all = <Delivery>[
      ...dots(6),
      makeDelivery(sequence: 7, over: 1, wide: true, runsExtras: 1, bowler: 'player-bowler-2'),
    ];
    final InningsProgress p = progress(all);
    expect(p.currentBowlerId, 'player-bowler-2');
    expect(p.needsNewBowler, isFalse);
  });

  test('after an undo the bowler of the undone ball stays selected', () {
    final List<Delivery> all = <Delivery>[
      ...dots(6),
      makeDelivery(sequence: 7, over: 1, ball: 1, bowler: 'player-bowler-2', voided: true),
    ];
    final InningsProgress p = progress(all);
    expect(p.currentBowlerId, 'player-bowler-2');
    expect(p.needsNewBowler, isFalse);
  });

  test('all out ends the innings (batting team size - 1 wickets)', () {
    final List<Delivery> all = <Delivery>[
      for (int i = 0; i < 3; i += 1)
        makeDelivery(
          sequence: i + 1,
          ball: i + 1,
          striker: 'bat-$i',
          wicket: true,
          dismissal: DismissalType.bowled,
          dismissedId: 'bat-$i',
        ),
    ];
    final InningsProgress p = progress(all);
    expect(p.endReason, InningsEndReason.allOut);
    expect(p.canScore, isFalse);
    expect(p.shouldClose, isTrue);
  });

  test('two wickets are not all out for a four-player team', () {
    final List<Delivery> all = <Delivery>[
      for (int i = 0; i < 2; i += 1)
        makeDelivery(
          sequence: i + 1,
          ball: i + 1,
          striker: 'bat-$i',
          wicket: true,
          dismissal: DismissalType.bowled,
          dismissedId: 'bat-$i',
        ),
    ];
    expect(progress(all).endReason, isNull);
  });

  test('all overs bowled ends the innings', () {
    final InningsProgress p = progress(dots(12));
    expect(p.endReason, InningsEndReason.oversComplete);
    expect(p.ballsRemaining, 0);
    expect(p.shouldClose, isTrue);
  });

  test('wides do not use up the overs', () {
    final List<Delivery> all = <Delivery>[
      ...dots(11),
      makeDelivery(sequence: 12, over: 1, wide: true, runsExtras: 1),
    ];
    expect(progress(all).endReason, isNull);
  });

  test('a closed innings cannot be scored and does not ask to be closed again', () {
    final InningsProgress p = progress(dots(12), innings: makeInnings(endedAt: fixedNow));
    expect(p.isClosed, isTrue);
    expect(p.canScore, isFalse);
    expect(p.shouldClose, isFalse);
  });

  group('second innings', () {
    test('reports the runs still required', () {
      final InningsProgress p = progress(
        <Delivery>[makeDelivery(runsBat: 4)],
        firstTotal: 20,
      );
      expect(p.runsRequired, 17); // 21 to win, 4 scored
      expect(p.endReason, isNull);
    });

    test('ends as soon as the first innings total is passed', () {
      final InningsProgress p = progress(
        <Delivery>[
          makeDelivery(sequence: 1, runsBat: 6),
          makeDelivery(sequence: 2, ball: 2, runsBat: 6),
        ],
        firstTotal: 11,
      );
      expect(p.endReason, InningsEndReason.targetReached);
      expect(p.runsRequired, 0);
    });

    test('equalling the total is not enough', () {
      final InningsProgress p = progress(
        <Delivery>[
          makeDelivery(sequence: 1, runsBat: 6),
          makeDelivery(sequence: 2, ball: 2, runsBat: 6),
        ],
        firstTotal: 12,
      );
      expect(p.endReason, isNull);
      expect(p.runsRequired, 1);
    });
  });

  test('a one-player batting team never divides by zero: one wicket ends the innings', () {
    final InningsProgress p = progress(
      <Delivery>[
        makeDelivery(wicket: true, dismissal: DismissalType.bowled, dismissedId: strikerId),
      ],
      players: 1,
    );
    expect(p.endReason, InningsEndReason.allOut);
  });
}
