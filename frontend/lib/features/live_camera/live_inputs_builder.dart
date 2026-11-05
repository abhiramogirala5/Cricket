import 'package:gully_umpire/core/config/app_config.dart';
import 'package:gully_umpire/cv/device/device_policy.dart';
import 'package:gully_umpire/cv/geometry/polygon.dart';
import 'package:gully_umpire/cv/live/ball_kind.dart';
import 'package:gully_umpire/cv/live/live_analysis.dart';
import 'package:gully_umpire/cv/pipelines/pipelines.dart';
import 'package:gully_umpire/cv/util/length_units.dart';
import 'package:gully_umpire/domain/aggregates/match_bundle.dart';
import 'package:gully_umpire/features/umpiring/umpiring_mappers.dart';

/// What the live camera needs to know about the match right now: the rules, the height of the
/// batter who is facing, the ball, and the marked wicket.
///
/// [strikerId] is the batter on strike (or `null` when nobody has been chosen yet: a default
/// height is used until then). [cameraToBatterFeet] is the distance the umpire entered between the
/// phone and the batter (or `null` when none was entered: no ball speed is then shown).
LiveInputs liveInputsFor({
  required MatchBundle bundle,
  required String? strikerId,
  required DevicePolicy policy,
  required AppConfig config,
  required BallKind ballKind,
  double? cameraToBatterFeet,
}) {
  final WicketTarget? target = wicketTargetFrom(bundle.activeWicket);
  final Polygon? outline = target?.polygon;
  return LiveInputs(
    policy: policy,
    rules: umpiringRulesFor(bundle.rules, config),
    batsmanHeightM: strikerId == null
        ? defaultBatsmanHeightM
        : batsmanHeightMetres(
            matchPlayer: bundle.matchPlayerById(strikerId),
            player: bundle.playerById(strikerId),
          ),
    ballKind: ballKind,
    wicket: outline,
    wicketConfidence: target?.confidence ?? 0.9,
    wicketFamily: target?.family,
    cameraToBatterM: cameraToBatterFeet == null ? null : feetToMetres(cameraToBatterFeet),
  );
}
