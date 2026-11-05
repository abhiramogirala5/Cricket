import 'package:gully_umpire/core/utils/formatters.dart';
import 'package:gully_umpire/domain/aggregates/match_bundle.dart';
import 'package:gully_umpire/domain/models/models.dart';
import 'package:gully_umpire/domain/scoring/scoring.dart';

/// Something the scorer has to choose before the next ball can be scored.
enum LiveRequirement { openers, incomingBatter, bowler }

/// Choices the scorer has made that are not saved yet (they become part of the next ball).
final class LiveChoices {
  const LiveChoices({
    this.openerStrikerId,
    this.openerNonStrikerId,
    this.incomingBatterId,
    this.bowlerId,
    this.endsSwapped = false,
  });

  final String? openerStrikerId;
  final String? openerNonStrikerId;
  final String? incomingBatterId;
  final String? bowlerId;

  /// After a run-out the scorer may swap who faces the next ball.
  final bool endsSwapped;

  LiveChoices copyWith({
    String? openerStrikerId,
    String? openerNonStrikerId,
    String? incomingBatterId,
    String? bowlerId,
    bool? endsSwapped,
  }) =>
      LiveChoices(
        openerStrikerId: openerStrikerId ?? this.openerStrikerId,
        openerNonStrikerId: openerNonStrikerId ?? this.openerNonStrikerId,
        incomingBatterId: incomingBatterId ?? this.incomingBatterId,
        bowlerId: bowlerId ?? this.bowlerId,
        endsSwapped: endsSwapped ?? this.endsSwapped,
      );
}

/// Who is ready to play the next ball, and what is still missing.
final class LiveReadiness {
  const LiveReadiness({required this.missing, this.setup, this.bowlerId});

  final List<LiveRequirement> missing;

  /// The batting pair, once it is known.
  final NextBallSetup? setup;

  /// The bowler of the next ball, once it is known.
  final String? bowlerId;

  String? get strikerId => setup?.strikerId;
  String? get nonStrikerId => setup?.nonStrikerId;

  bool get canScore =>
      missing.isEmpty && (setup?.isComplete ?? false) && bowlerId != null;

  /// Both batters are known (nobody is missing at the crease), whatever the bowler situation.
  bool get batterPairKnown {
    final NextBallSetup? pair = setup;
    return pair != null && pair.isComplete && !pair.needsNewBatter;
  }
}

/// Combines what the deliveries say with the scorer's pending [choices].
LiveReadiness resolveReadiness(InningsProgress progress, LiveChoices choices) {
  final List<LiveRequirement> missing = <LiveRequirement>[];
  NextBallSetup? setup = progress.setup;

  if (setup == null) {
    final String? striker = choices.openerStrikerId;
    final String? nonStriker = choices.openerNonStrikerId;
    if (striker != null && nonStriker != null && striker != nonStriker) {
      setup = NextBallSetup(strikerId: striker, nonStrikerId: nonStriker);
    } else {
      missing.add(LiveRequirement.openers);
    }
  } else if (setup.needsNewBatter) {
    final String? incoming = choices.incomingBatterId;
    if (incoming == null) {
      // The batter who is still at the crease stays visible; the vacant end is shown as empty.
      missing.add(LiveRequirement.incomingBatter);
    } else {
      final bool mayChooseStrike = setup.strikeChoiceAllowed;
      setup = setup.withIncoming(incoming);
      if (choices.endsSwapped && mayChooseStrike) {
        setup = setup.swapped();
      }
    }
  } else if (choices.endsSwapped && setup.strikeChoiceAllowed) {
    setup = setup.swapped();
  }

  final String? bowler = progress.currentBowlerId ?? choices.bowlerId;
  if (bowler == null) {
    missing.add(LiveRequirement.bowler);
  }
  return LiveReadiness(missing: missing, setup: setup, bowlerId: bowler);
}

/// Everything the live-scoring screen shows about one innings, derived from the saved balls.
final class LiveBoard {
  LiveBoard._({
    required this.bundle,
    required this.innings,
    required this.progress,
    required this.scorecard,
    required this.battingOrder,
    required this.bowlingOrder,
    required this.deliveries,
  });

  factory LiveBoard.from(MatchBundle bundle, Innings innings) {
    final List<Delivery> deliveries = bundle.deliveriesOf(innings.id);
    final List<String> battingOrder = bundle.battingOrderIds(innings.battingTeamId);
    final List<String> bowlingOrder = bundle.battingOrderIds(innings.bowlingTeamId);
    final int? firstTotal =
        innings.inningsNumber == 2 ? bundle.inningsByNumber(1)?.totalRuns : null;
    final InningsProgress progress = InningsProgress.from(
      innings: innings,
      oversPerInnings: bundle.match.oversPerInnings,
      battingPlayerCount: battingOrder.length,
      deliveries: deliveries,
      firstInningsTotal: firstTotal,
    );
    final InningsScorecard scorecard =
        InningsScorecard.build(deliveries: deliveries, battingOrder: battingOrder);
    return LiveBoard._(
      bundle: bundle,
      innings: innings,
      progress: progress,
      scorecard: scorecard,
      battingOrder: battingOrder,
      bowlingOrder: bowlingOrder,
      deliveries: deliveries,
    );
  }

  final MatchBundle bundle;
  final Innings innings;
  final InningsProgress progress;
  final InningsScorecard scorecard;

  /// Player ids of the batting team in batting order.
  final List<String> battingOrder;

  /// Player ids of the bowling team.
  final List<String> bowlingOrder;

  /// Every ball of this innings, voided ones included.
  final List<Delivery> deliveries;

  String get battingTeamName => bundle.teamName(innings.battingTeamId);
  String get bowlingTeamName => bundle.teamName(innings.bowlingTeamId);

  int get runs => progress.aggregate.totalRuns;
  int get wickets => progress.aggregate.wickets;
  int get legalBalls => progress.aggregate.legalBalls;

  String get scoreText => '$runs/$wickets';
  String get oversText => formatOvers(legalBalls);
  String get oversLimitText => 'of ${bundle.match.oversPerInnings}';

  /// `Need 12 from 14 balls`, `Target reached`, or `null` in the first innings.
  String? get chaseText {
    final int? needed = progress.runsRequired;
    if (needed == null) {
      return null;
    }
    if (needed == 0) {
      return 'Target reached';
    }
    return 'Need $needed from ${pluralize(progress.ballsRemaining, 'ball')}';
  }

  /// Runs per over so far, or `null` before the first legal ball.
  double? get runRate => legalBalls == 0 ? null : runs / (legalBalls / ballsPerOver);

  /// Short labels of the balls of the over in progress.
  List<String> get overLabels => <String>[
        for (final Delivery delivery in progress.overDeliveries) ballLabel(delivery),
      ];

  bool get hasActiveBall => deliveries.any((Delivery d) => !d.isVoided);

  /// The most recent ball that has not been undone.
  Delivery? get lastActiveBall => ScoreEngine.lastActive(deliveries);

  BatterLine? batterLine(String playerId) {
    for (final BatterLine line in scorecard.batters) {
      if (line.playerId == playerId) {
        return line;
      }
    }
    return null;
  }

  BowlerLine? bowlerLine(String playerId) {
    for (final BowlerLine line in scorecard.bowlers) {
      if (line.playerId == playerId) {
        return line;
      }
    }
    return null;
  }

  /// Batters who can still come in: not out, not at the crease, not yet batted.
  List<String> availableBatterIds({Iterable<String> atCrease = const <String>[]}) =>
      availableBatters(battingOrder: battingOrder, deliveries: deliveries, atCrease: atCrease);

  /// Who can bowl the next over. The bowler of the previous over is left out, unless there is
  /// nobody else.
  List<String> get availableBowlerIds {
    final String? previous = progress.previousOverBowlerId;
    final List<String> others = <String>[
      for (final String id in bowlingOrder)
        if (id != previous) id,
    ];
    return others.isEmpty ? bowlingOrder : others;
  }

  LiveReadiness readiness(LiveChoices choices) => resolveReadiness(progress, choices);
}

/// `1.2 ov · 7 runs · 1 wicket` for the bowler picker and the bowler line.
String bowlerFigures(BowlerLine? line) {
  if (line == null) {
    return 'Has not bowled yet';
  }
  return '${formatOvers(line.legalBalls)} ov · ${pluralize(line.runsConceded, 'run')} '
      '· ${pluralize(line.wickets, 'wicket')}';
}
