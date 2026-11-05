/// What the app may do with a wicket-scan confidence (spec §7 "User experience thresholds").
///
/// | Confidence | Readiness |
/// |---:|---|
/// | >= 0.85 | [ready]: wide, no-ball, wicket-hit and LBW review assistance |
/// | 0.70 - 0.84 | [moderate]: start the match with a moderate-confidence banner |
/// | 0.50 - 0.69 | [limited]: score-only or limited wide assistance; no LBW or wicket-hit |
/// | < 0.50 | [reposition]: ask the user to reposition the phone; no automated umpiring |
enum ScanReadiness {
  ready,
  moderate,
  limited,
  reposition;

  static const double readyThreshold = 0.85;
  static const double moderateThreshold = 0.70;
  static const double limitedThreshold = 0.50;

  static ScanReadiness fromConfidence(double confidence) {
    if (confidence.isNaN) {
      return ScanReadiness.reposition;
    }
    if (confidence >= readyThreshold) {
      return ScanReadiness.ready;
    }
    if (confidence >= moderateThreshold) {
      return ScanReadiness.moderate;
    }
    if (confidence >= limitedThreshold) {
      return ScanReadiness.limited;
    }
    return ScanReadiness.reposition;
  }

  /// The "Continue" button of the scan screen: automated umpiring may start.
  bool get canStartAutomatedUmpiring =>
      this == ScanReadiness.ready || this == ScanReadiness.moderate;

  /// A wide may be suggested. With [limited] readiness the wicket is too uncertain for a call, so
  /// the suggestion is only ever "not sure", but the umpire still sees that it was tried.
  bool get allowsWideAssist => this != ScanReadiness.reposition;

  /// A height no-ball may be suggested. It does not depend on the wicket, but the umpiring
  /// assistant as a whole is only offered once the wicket has been found well enough.
  bool get allowsNoBallAssist => canStartAutomatedUmpiring;

  /// Wicket-hit, LBW and edge review assistance need a trustworthy wicket.
  bool get allowsWicketDependentReview =>
      this == ScanReadiness.ready || this == ScanReadiness.moderate;

  /// Show the "moderate confidence" banner.
  bool get showsModerateBanner => this == ScanReadiness.moderate;

  /// The user should be told to move the phone and scan again.
  bool get asksToReposition => this == ScanReadiness.reposition;

  String get label {
    switch (this) {
      case ScanReadiness.ready:
        return 'Ready';
      case ScanReadiness.moderate:
        return 'Moderate confidence';
      case ScanReadiness.limited:
        return 'Limited';
      case ScanReadiness.reposition:
        return 'Reposition the phone';
    }
  }

  /// One friendly sentence for the scan screen.
  String get message {
    switch (this) {
      case ScanReadiness.ready:
        return 'Wicket found. Umpire assistance is ready.';
      case ScanReadiness.moderate:
        return 'Wicket found, but not with full confidence. Assistance may say "not sure" more often.';
      case ScanReadiness.limited:
        return 'The wicket is hard to see. You can score manually, with limited wide assistance only.';
      case ScanReadiness.reposition:
        return 'Could not find the wicket. Move the phone behind the bowler\'s end so the wicket is clearly in view, then scan again.';
    }
  }
}
