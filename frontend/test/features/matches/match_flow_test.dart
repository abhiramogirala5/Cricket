import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/domain/aggregates/match_bundle.dart';
import 'package:gully_umpire/domain/models/models.dart';
import 'package:gully_umpire/features/matches/match_flow.dart';

import '../../support/bundle_fixtures.dart';
import '../../support/model_fixtures.dart';
import '../../support/scoring_fixtures.dart';

void main() {
  final DateTime ended = DateTime.utc(2026, 10, 8, 8, 30);

  /// A bundle with no innings yet: where a match is before scoring starts.
  MatchBundle beforeInnings({
    Toss? toss,
    List<SceneScan> scans = const <SceneScan>[],
    List<WicketDetection> wickets = const <WicketDetection>[],
    MatchStatus status = MatchStatus.ready,
  }) {
    return makeBundle(
      innings: const <Innings>[],
      toss: toss,
      sceneScans: scans,
      wicketDetections: wickets,
      status: status,
    );
  }

  group('nextMatchStep before the toss', () {
    test('suggests the scan when it is available and has not been done', () {
      final MatchStep step = nextMatchStep(beforeInnings(), scanAvailable: true);
      expect(step.kind, MatchStepKind.scan);
      expect(step.label, 'Scan the pitch');
    });

    test('goes straight to the toss when the scan is not available', () {
      final MatchStep step = nextMatchStep(beforeInnings(), scanAvailable: false);
      expect(step.kind, MatchStepKind.toss);
      expect(step.label, 'Do the toss');
    });

    test('goes to the toss once a scan has been saved', () {
      final MatchStep step = nextMatchStep(
        beforeInnings(scans: <SceneScan>[sampleScan]),
        scanAvailable: true,
      );
      expect(step.kind, MatchStepKind.toss);
    });

    test('goes to the toss once an active wicket has been saved', () {
      final MatchStep step = nextMatchStep(
        beforeInnings(wickets: <WicketDetection>[sampleWicket]),
        scanAvailable: true,
      );
      expect(step.kind, MatchStepKind.toss);
    });

    test('an old inactive wicket alone does not count as a scan', () {
      final MatchStep step = nextMatchStep(
        beforeInnings(wickets: <WicketDetection>[sampleWicket.copyWith(isActive: false)]),
        scanAvailable: true,
      );
      expect(step.kind, MatchStepKind.scan);
    });
  });

  group('nextMatchStep with the live camera (the stumps are marked by hand)', () {
    test('asks the umpire to mark the stumps instead of scanning the pitch', () {
      final MatchStep step = nextMatchStep(beforeInnings(), scanAvailable: true, markByHand: true);

      expect(step.kind, MatchStepKind.scan);
      expect(step.label, 'Mark the stumps');
      expect(step.hint, contains('stumps'));
      expect(step.hint, contains('score by hand'));
      expect(step.label, isNot('Scan the pitch'));
    });

    test('the plain scan keeps its own words', () {
      final MatchStep scan = nextMatchStep(beforeInnings(), scanAvailable: true);

      expect(scan.label, 'Scan the pitch');
      expect(scan.hint, contains('assistant'));
    });

    test('goes to the toss once the stumps are marked, like after a scan', () {
      expect(
        nextMatchStep(
          beforeInnings(wickets: <WicketDetection>[sampleWicket]),
          scanAvailable: true,
          markByHand: true,
        ).kind,
        MatchStepKind.toss,
      );
      expect(
        nextMatchStep(
          beforeInnings(scans: <SceneScan>[sampleScan]),
          scanAvailable: true,
          markByHand: true,
        ).kind,
        MatchStepKind.toss,
      );
    });

    test('goes straight to the toss when the assistant is not available at all', () {
      final MatchStep step = nextMatchStep(beforeInnings(), scanAvailable: false, markByHand: true);

      expect(step.kind, MatchStepKind.toss);
    });

    test('changes nothing after the toss or once scoring has started', () {
      expect(
        nextMatchStep(makeBundle(), scanAvailable: true, markByHand: true),
        nextMatchStep(makeBundle(), scanAvailable: true),
      );
    });
  });

  group('nextMatchStep after the toss', () {
    test('starts the first innings with the team that bats', () {
      // sampleToss: team-b won and chose to bowl, so team-a (Reds) bats.
      final MatchStep step = nextMatchStep(
        beforeInnings(toss: sampleToss),
        scanAvailable: false,
      );
      expect(step.kind, MatchStepKind.startFirstInnings);
      expect(step.battingTeamId, 'team-a');
      expect(step.label, 'Start first innings');
      expect(step.hint, 'Reds bat first.');
    });

    test('the winner choosing to bat means the winner bats first', () {
      final Toss toss = sampleToss.copyWith(winnerDecision: TossDecision.bat);
      final MatchStep step = nextMatchStep(beforeInnings(toss: toss), scanAvailable: false);
      expect(step.kind, MatchStepKind.startFirstInnings);
      expect(step.battingTeamId, 'team-b');
      expect(step.hint, 'Blues bat first.');
    });

    test('a toss without a winner sends the scorer back to the toss', () {
      final Toss toss = Toss(
        id: 'toss-2',
        matchId: matchId,
        callChoice: TossSide.heads,
        result: TossSide.heads,
        createdAt: t0,
      );
      final MatchStep step = nextMatchStep(beforeInnings(toss: toss), scanAvailable: true);
      expect(step.kind, MatchStepKind.toss);
      expect(step.hint, 'The toss needs a winner and a choice to bat or bowl.');
      expect(step.battingTeamId, isNull);
    });

    test('a toss won by a team that is not in the match is not trusted', () {
      final Toss toss = sampleToss.copyWith(winnerTeamId: 'someone-else');
      final MatchStep step = nextMatchStep(beforeInnings(toss: toss), scanAvailable: false);
      expect(step.kind, MatchStepKind.toss);
    });
  });

  group('nextMatchStep during and after the innings', () {
    test('an open innings with no balls says "Start scoring"', () {
      final MatchStep step = nextMatchStep(makeBundle(), scanAvailable: true);
      expect(step.kind, MatchStepKind.score);
      expect(step.label, 'Start scoring');
      expect(step.hint, 'Reds are batting.');
    });

    test('an open innings with balls says "Continue scoring"', () {
      final MatchBundle bundle = makeBundle(
        deliveriesByInnings: <String, List<Delivery>>{
          inningsId: <Delivery>[makeDelivery(runsBat: 1)],
        },
      );
      final MatchStep step = nextMatchStep(bundle, scanAvailable: true);
      expect(step.kind, MatchStepKind.score);
      expect(step.label, 'Continue scoring');
    });

    test('an innings with only undone balls still says "Start scoring"', () {
      final MatchBundle bundle = makeBundle(
        deliveriesByInnings: <String, List<Delivery>>{
          inningsId: <Delivery>[makeDelivery(voided: true)],
        },
      );
      final MatchStep step = nextMatchStep(bundle, scanAvailable: true);
      expect(step.label, 'Start scoring');
    });

    test('the second innings step names the chasing team and the target', () {
      final MatchBundle bundle = makeBundle(
        innings: <Innings>[makeInnings().copyWith(totalRuns: 30, endedAt: ended)],
      );
      final MatchStep step = nextMatchStep(bundle, scanAvailable: true);
      expect(step.kind, MatchStepKind.startSecondInnings);
      expect(step.battingTeamId, 'team-b');
      expect(step.hint, 'Blues chase 31 to win.');
    });

    test('the second innings open means scoring again, with the other team batting', () {
      final MatchBundle bundle = makeBundle(
        innings: <Innings>[
          makeInnings().copyWith(totalRuns: 30, endedAt: ended),
          makeSecondInnings(),
        ],
      );
      final MatchStep step = nextMatchStep(bundle, scanAvailable: true);
      expect(step.kind, MatchStepKind.score);
      expect(step.hint, 'Blues are batting.');
    });

    test('both innings closed means the match can be finished', () {
      final MatchBundle bundle = makeBundle(
        innings: <Innings>[
          makeInnings().copyWith(totalRuns: 30, endedAt: ended),
          makeSecondInnings(endedAt: ended),
        ],
      );
      final MatchStep step = nextMatchStep(bundle, scanAvailable: true);
      expect(step.kind, MatchStepKind.finish);
      expect(step.label, 'Finish the match');
    });

    test('a finished match always shows the scorecard', () {
      for (final MatchStatus status in <MatchStatus>[
        MatchStatus.completed,
        MatchStatus.abandoned,
      ]) {
        final MatchStep step = nextMatchStep(
          makeBundle(status: status, innings: const <Innings>[]),
          scanAvailable: true,
        );
        expect(step.kind, MatchStepKind.scorecard, reason: status.wire);
        expect(step.label, 'View scorecard');
      }
    });
  });

  test('two steps with the same content are equal', () {
    const MatchStep a = MatchStep(kind: MatchStepKind.toss, label: 'x', hint: 'y');
    const MatchStep b = MatchStep(kind: MatchStepKind.toss, label: 'x', hint: 'y');
    expect(a, b);
  });
}
