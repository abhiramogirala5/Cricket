import 'package:gully_umpire/cv/adapters/mock/mock_scenario.dart';

/// Plain words for the simulation settings of the scan screen.
String wicketKindLabel(MockWicketKind kind) {
  switch (kind) {
    case MockWicketKind.stumps:
      return 'Stumps';
    case MockWicketKind.chair:
      return 'Chair';
    case MockWicketKind.bricks:
      return 'Bricks';
    case MockWicketKind.bottles:
      return 'Bottles';
    case MockWicketKind.cones:
      return 'Cones';
    case MockWicketKind.bucket:
      return 'Bucket';
    case MockWicketKind.wallTarget:
      return 'Wall mark';
    case MockWicketKind.none:
      return 'Nothing';
  }
}

String scanQualityLabel(MockScanQuality quality) {
  switch (quality) {
    case MockScanQuality.high:
      return 'Clear view';
    case MockScanQuality.moderate:
      return 'Shaky view';
    case MockScanQuality.low:
      return 'Poor view';
  }
}
