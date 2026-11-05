/// The ball that is being bowled. Its real size is what lets one camera work out how far away the
/// ball is (a smaller-looking ball is further away), so it has to be right.
enum BallKind {
  cricketBall('CRICKET_BALL', 'Cricket ball', 0.072),
  tennisBall('TENNIS_BALL', 'Tennis ball', 0.067);

  const BallKind(this.wire, this.label, this.diameterM);

  /// Value stored on the phone.
  final String wire;

  /// Plain words for the screen.
  final String label;

  /// Real diameter in metres (a cricket ball is 7.1 - 7.3 cm, a tennis ball 6.5 - 6.9 cm).
  final double diameterM;

  /// Parses a stored value; anything unknown gives the cricket ball.
  static BallKind fromWire(String? raw) {
    for (final BallKind kind in BallKind.values) {
      if (kind.wire == raw) {
        return kind;
      }
    }
    return BallKind.cricketBall;
  }
}
