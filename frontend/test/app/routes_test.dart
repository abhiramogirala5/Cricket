import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/app/router/routes.dart';

void main() {
  test('match addresses nest under the match id', () {
    expect(Routes.match('m1'), '/match/m1');
    expect(Routes.autoScan('m1'), '/match/m1/auto-scan');
    expect(Routes.toss('m1'), '/match/m1/toss');
    expect(Routes.live('m1'), '/match/m1/live');
    expect(Routes.scorecard('m1'), '/match/m1/scorecard');
    expect(Routes.review('m1', 'd9'), '/match/m1/review/d9');
  });

  test('only the sign-in and sign-up pages are public', () {
    expect(Routes.isPublic(Routes.signIn), isTrue);
    expect(Routes.isPublic(Routes.signUp), isTrue);
    for (final String location in <String>[
      Routes.splash,
      Routes.reauth,
      Routes.home,
      Routes.createMatch,
    ]) {
      expect(Routes.isPublic(location), isFalse, reason: location);
    }
  });

  test('the tab addresses are distinct', () {
    expect(<String>{Routes.home, Routes.matches, Routes.profile}, hasLength(3));
  });
}
