import 'package:gully_umpire/domain/models/delivery.dart';

/// Compact text for one ball in the "this over" strip.
///
/// `0`, `1`, `4` runs off the bat; `W` wicket (`1W` when a run was also scored);
/// `Wd`/`Wd+2` wide; `Nb`/`Nb+4` no-ball (runs off the bat or byes added); `B2`/`Lb1` byes.
String ballLabel(Delivery delivery) {
  String label;
  if (delivery.isWide) {
    final int more = delivery.runsExtras - 1;
    label = more > 0 ? 'Wd+$more' : 'Wd';
  } else if (delivery.isNoBall) {
    final int more = delivery.runsBat + delivery.runsExtras - 1;
    label = more > 0 ? 'Nb+$more' : 'Nb';
  } else if (delivery.isBye) {
    label = 'B${delivery.runsExtras}';
  } else if (delivery.isLegBye) {
    label = 'Lb${delivery.runsExtras}';
  } else {
    label = '${delivery.runsBat}';
  }

  if (delivery.isWicket) {
    label = label == '0' ? 'W' : '${label}W';
  }
  return label;
}
