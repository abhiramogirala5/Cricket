import 'package:gully_umpire/core/errors/app_exception.dart';
import 'package:gully_umpire/domain/scoring/score_engine.dart';
import 'package:gully_umpire/domain/setup/match_setup.dart';

/// A sentence for the user for any error that reaches a screen. Never shows stack traces,
/// class names or raw server text.
String friendlyError(Object error) {
  if (error is AppException) {
    return error.userMessage;
  }
  if (error is SetupException) {
    return error.message;
  }
  if (error is ScoringException) {
    return error.userMessage;
  }
  return 'Something went wrong. Please try again.';
}
