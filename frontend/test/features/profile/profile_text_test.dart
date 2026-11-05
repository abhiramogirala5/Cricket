import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/data/sync/restore_service.dart';
import 'package:gully_umpire/features/profile/profile_text.dart';

void main() {
  group('describeRestore', () {
    test('says so when nothing was missing', () {
      expect(
        describeRestore(const RestoreReport()),
        'Everything from your account is already on this phone.',
      );
    });

    test('lists what was added, in the singular and the plural', () {
      expect(
        describeRestore(const RestoreReport(matchesRestored: 1, teamsAdded: 1, playersAdded: 1)),
        'Added 1 match, 1 team, 1 player from your account.',
      );
      expect(
        describeRestore(const RestoreReport(matchesRestored: 3, teamsAdded: 2, playersAdded: 14)),
        'Added 3 matches, 2 teams, 14 players from your account.',
      );
    });

    test('leaves out the kinds that were not added', () {
      expect(
        describeRestore(const RestoreReport(playersAdded: 2)),
        'Added 2 players from your account.',
      );
      expect(
        describeRestore(const RestoreReport(matchesRestored: 2)),
        'Added 2 matches from your account.',
      );
    });

    test('mentions matches that could not be fetched', () {
      expect(
        describeRestore(const RestoreReport(matchesRestored: 1, matchesFailed: 2)),
        'Added 1 match from your account. 2 matches could not be fetched this time. '
        'Try again later.',
      );
    });

    test('says nothing new was added when everything failed', () {
      expect(
        describeRestore(const RestoreReport(matchesFailed: 1)),
        'Nothing new was added. 1 match could not be fetched this time. Try again later.',
      );
    });
  });
}
