import 'package:gully_umpire/core/utils/formatters.dart';
import 'package:gully_umpire/data/sync/restore_service.dart';

/// What to tell the user after "Get my matches from the server".
String describeRestore(RestoreReport report) {
  final List<String> added = <String>[
    if (report.matchesRestored > 0)
      pluralize(report.matchesRestored, 'match', plural: 'matches'),
    if (report.teamsAdded > 0) pluralize(report.teamsAdded, 'team'),
    if (report.playersAdded > 0) pluralize(report.playersAdded, 'player'),
  ];
  final String first;
  if (added.isNotEmpty) {
    first = 'Added ${added.join(', ')} from your account.';
  } else if (report.matchesFailed == 0) {
    return 'Everything from your account is already on this phone.';
  } else {
    first = 'Nothing new was added.';
  }
  if (report.matchesFailed == 0) {
    return first;
  }
  return '$first ${pluralize(report.matchesFailed, 'match', plural: 'matches')} could not be '
      'fetched this time. Try again later.';
}
