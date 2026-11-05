/// Every screen address of the app in one place, so nobody types a path twice.
abstract final class Routes {
  static const String splash = '/splash';
  static const String signIn = '/sign-in';
  static const String signUp = '/sign-up';

  /// Sign in again from inside the app (the session ended).
  static const String reauth = '/reauth';

  // The three tabs.
  static const String home = '/home';
  static const String matches = '/matches';
  static const String profile = '/profile';

  // Full-screen pages above the tabs.
  static const String createMatch = '/match/create';
  static const String players = '/players';
  static const String syncIssues = '/sync-issues';

  static String match(String matchId) => '/match/$matchId';
  static String autoScan(String matchId) => '/match/$matchId/auto-scan';
  static String toss(String matchId) => '/match/$matchId/toss';
  static String live(String matchId) => '/match/$matchId/live';
  static String scorecard(String matchId) => '/match/$matchId/scorecard';
  static String review(String matchId, String deliveryId) =>
      '/match/$matchId/review/$deliveryId';

  /// The replay of one ball ([replayId] is the id of the replay file, not of the delivery).
  static String replay(String matchId, String replayId) => '/match/$matchId/replay/$replayId';

  /// Pages that can be opened without being signed in.
  static bool isPublic(String location) => location == signIn || location == signUp;
}
