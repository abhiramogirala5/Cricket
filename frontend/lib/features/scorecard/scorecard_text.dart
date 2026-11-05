import 'package:gully_umpire/core/utils/formatters.dart';
import 'package:gully_umpire/domain/models/models.dart';
import 'package:gully_umpire/domain/scoring/scoring.dart';

/// How a batter's innings ended, in scorecard words: `not out`, `b Asha`, `run out`...
///
/// Fielders are not recorded, so a catch reads `c b Asha` (caught, bowled by Asha).
String dismissalText(BatterLine line, String Function(String playerId) playerName) {
  switch (line.status) {
    case BatterStatus.didNotBat:
      return 'did not bat';
    case BatterStatus.notOut:
      return 'not out';
    case BatterStatus.out:
      break;
  }
  final DismissalInfo? info = line.dismissal;
  if (info == null) {
    return 'out';
  }
  final String? bowlerId = info.bowlerId;
  final String bowler = bowlerId == null ? '' : ' b ${playerName(bowlerId)}';
  switch (info.type) {
    case DismissalType.bowled:
      return bowlerId == null ? 'bowled' : 'b ${playerName(bowlerId)}';
    case DismissalType.caught:
      return bowlerId == null ? 'caught' : 'c$bowler';
    case DismissalType.lbw:
      return 'lbw$bowler';
    case DismissalType.runOut:
      return 'run out';
    case DismissalType.stumped:
      return 'st$bowler';
    case DismissalType.hitWicket:
      return 'hit wicket$bowler';
  }
}

/// `Extras 7 (wd 3, nb 1, b 2, lb 1)`.
String extrasText(ExtrasSummary extras) =>
    'Extras ${extras.total} (wd ${extras.wides}, nb ${extras.noBalls}, '
    'b ${extras.byes}, lb ${extras.legByes})';

/// `1-12 (Asha, 1.4 ov)`.
String fallOfWicketText(FallOfWicket fall, String Function(String playerId) playerName) =>
    '${fall.wicketNumber}-${fall.teamScore} (${playerName(fall.playerId)}, '
    '${formatOvers(fall.legalBalls)} ov)';

/// The over and ball of a delivery as cricketers write it: `0.1` is the first ball of the match.
///
/// A wide or a no-ball is shown at the number of the legal ball it was bowled in place of.
/// [inningsDeliveries] are the deliveries of the same innings.
String overBallLabel(Delivery delivery, List<Delivery> inningsDeliveries) {
  final int? legalNumber = delivery.legalBallNumber;
  if (delivery.isLegal && legalNumber != null) {
    return '${delivery.overNumber}.$legalNumber';
  }
  int legalBefore = 0;
  for (final Delivery other in inningsDeliveries) {
    if (other.isVoided ||
        !other.isLegal ||
        other.overNumber != delivery.overNumber ||
        other.deliverySequence >= delivery.deliverySequence) {
      continue;
    }
    legalBefore += 1;
  }
  return '${delivery.overNumber}.${legalBefore + 1}';
}

/// What happened on the ball, in words (`4 runs`, `Wide + 2`, `No-ball, 1 bye`).
String ballResultText(Delivery delivery) {
  final List<String> parts = <String>[];
  if (delivery.isWide) {
    final int more = delivery.runsExtras - 1;
    parts.add(more > 0 ? 'Wide + $more' : 'Wide');
  } else if (delivery.isNoBall) {
    parts.add('No-ball');
    if (delivery.runsBat > 0) {
      parts.add(_batRuns(delivery.runsBat));
    }
    final int more = delivery.runsExtras - 1;
    if (more > 0) {
      parts.add(pluralize(more, delivery.isLegBye ? 'leg bye' : 'bye'));
    }
  } else if (delivery.isBye) {
    parts.add(pluralize(delivery.runsExtras, 'bye'));
  } else if (delivery.isLegBye) {
    parts.add(pluralize(delivery.runsExtras, 'leg bye'));
  } else {
    parts.add(delivery.runsBat == 0 ? 'No run' : _batRuns(delivery.runsBat));
  }
  return parts.join(', ');
}

String _batRuns(int runs) {
  if (runs == 4) {
    return 'FOUR';
  }
  if (runs == 6) {
    return 'SIX';
  }
  return pluralize(runs, 'run');
}

/// One line for the ball-by-ball list: `Asha to Ravi: FOUR`, or with a wicket
/// `Asha to Ravi: No run. Ravi is out (Bowled)`.
String ballSentence(Delivery delivery, String Function(String playerId) playerName) {
  final StringBuffer text = StringBuffer(
    '${playerName(delivery.bowlerId)} to ${playerName(delivery.strikerId)}: '
    '${ballResultText(delivery)}',
  );
  if (delivery.isWicket) {
    final String? outId = delivery.dismissedPlayerId;
    final DismissalType? type = delivery.dismissalType;
    final String who = outId == null ? 'A batter' : playerName(outId);
    text.write('. $who is out${type == null ? '' : ' (${type.label})'}');
  }
  return text.toString();
}

/// Whether the ball has anything for the delivery review page to show.
bool hasAssistantData(Delivery delivery, List<DecisionRecord> decisions) =>
    decisions.isNotEmpty ||
    delivery.speedKmph != null ||
    delivery.ballTrackingConfidence != null ||
    delivery.wicketTrackingConfidence != null;
