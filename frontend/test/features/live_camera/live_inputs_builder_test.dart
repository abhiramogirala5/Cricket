import 'package:flutter_test/flutter_test.dart';
import 'package:gully_umpire/core/config/app_config.dart';
import 'package:gully_umpire/cv/device/device_policy.dart';
import 'package:gully_umpire/cv/live/ball_kind.dart';
import 'package:gully_umpire/cv/live/live_analysis.dart';
import 'package:gully_umpire/features/live_camera/live_inputs_builder.dart';

import '../../support/bundle_fixtures.dart';

void main() {
  const AppConfig config = AppConfig(environment: AppEnvironment.development, apiBaseUrl: '');

  LiveInputs build({double? feet}) {
    return liveInputsFor(
      bundle: makeBundle(),
      strikerId: null,
      policy: DevicePolicy.live(DeviceProfile.high),
      config: config,
      ballKind: BallKind.cricketBall,
      cameraToBatterFeet: feet,
    );
  }

  group('liveInputsFor and the distance to the batter', () {
    test('turns the feet the umpire typed into metres', () {
      expect(build(feet: 40).cameraToBatterM, closeTo(12.192, 1e-9));
      expect(build(feet: 10).cameraToBatterM, closeTo(3.048, 1e-9));
    });

    test('has no distance when none was entered', () {
      expect(build().cameraToBatterM, isNull);
    });
  });
}
