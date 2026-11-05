import 'package:equatable/equatable.dart';

import 'decision_status.dart';
import 'delivery_decision_type.dart';

/// One automated (or manually overridden) umpiring result for a delivery.
///
/// The JSON produced by [toJson] is the part of the API `DELIVERY_DECISION`
/// payload that the CV layer owns (docs/API_CONTRACT.md §5.3). The data layer
/// adds `id`, `delivery_id`, `decision_source` and `final_result`.
/// [summary] is UI text and is **not** persisted; [DeliveryDecision.fromJson]
/// regenerates a generic one when it is absent.
final class DeliveryDecision extends Equatable {
  /// Creates a decision. [confidence] is clamped to 0..1 (NaN becomes 0),
  /// [evidence] is deep-copied into JSON-safe values (non-finite numbers become
  /// null) and [automatedResult] must be at most [maxResultLength] characters.
  DeliveryDecision({
    required this.type,
    required String automatedResult,
    required double confidence,
    required this.status,
    Map<String, Object?> evidence = const <String, Object?>{},
    required this.summary,
  })  : automatedResult = _checkedResult(automatedResult),
        confidence = _clamp01(confidence),
        evidence = Map<String, Object?>.unmodifiable(jsonSafeMap(evidence));

  /// Parses the API-shaped map produced by [toJson].
  factory DeliveryDecision.fromJson(Map<String, Object?> json) {
    final DeliveryDecisionType type = DeliveryDecisionType.fromWire(json['decision_type']);
    final Object? rawResult = json['automated_result'];
    if (rawResult is! String) {
      throw FormatException('automated_result must be a string: $rawResult');
    }
    final Object? rawConfidence = json['confidence'];
    if (rawConfidence is! num) {
      throw FormatException('confidence must be a number: $rawConfidence');
    }
    final Object? rawEvidence = json['evidence'];
    final Map<String, Object?> evidence;
    if (rawEvidence == null) {
      evidence = const <String, Object?>{};
    } else if (rawEvidence is Map) {
      evidence = jsonSafeMap(rawEvidence);
    } else {
      throw FormatException('evidence must be an object: $rawEvidence');
    }
    final Object? rawSummary = json['summary'];
    return DeliveryDecision(
      type: type,
      automatedResult: rawResult,
      confidence: rawConfidence.toDouble(),
      status: DecisionStatus.fromWire(json['decision_status']),
      evidence: evidence,
      summary: rawSummary is String ? rawSummary : '${type.label}: $rawResult',
    );
  }

  /// Confidence at or above which an obvious wide / height no-ball may be an
  /// `AUTO_CALL` (spec §7 "Ready" row).
  static const double autoCallThreshold = 0.85;

  /// Minimum confidence for the app to say anything (spec §7 and
  /// `classifyWide`'s 0.7 gate). Below this the result is `INCONCLUSIVE`.
  static const double reviewThreshold = 0.70;

  /// Database limit for `automated_result`.
  static const int maxResultLength = 40;

  /// What the decision is about.
  final DeliveryDecisionType type;

  /// e.g. `WIDE`, `NOT_WIDE`, `NO_BALL`, `LEGAL`, `OUT`, `NOT_OUT`,
  /// `EDGE_LIKELY`, `LIKELY_HITTING`, `INCONCLUSIVE` (at most 40 characters).
  final String automatedResult;

  /// Belief (0..1) that [automatedResult] is correct.
  final double confidence;

  /// How to present the result.
  final DecisionStatus status;

  /// JSON-safe, unmodifiable evidence for the review screen.
  final Map<String, Object?> evidence;

  /// One friendly sentence for the umpire card.
  final String summary;

  /// Generic confidence -> status mapping from the spec thresholds:
  /// `>= 0.85` AUTO_CALL, `>= 0.70` REVIEW_RECOMMENDED, otherwise INCONCLUSIVE.
  ///
  /// The spec does not define this mapping for decisions explicitly. It reuses
  /// the scene-scan thresholds (§7: 0.85 ready, 0.70 minimum) and the 0.7
  /// confidence gate in `classifyWide` (§9). Per-type caps (review-only types
  /// never auto-call) are applied by [statusFor].
  static DecisionStatus statusForConfidence(double confidence) {
    if (confidence.isNaN) {
      return DecisionStatus.inconclusive;
    }
    if (confidence >= autoCallThreshold) {
      return DecisionStatus.autoCall;
    }
    if (confidence >= reviewThreshold) {
      return DecisionStatus.reviewRecommended;
    }
    return DecisionStatus.inconclusive;
  }

  /// [statusForConfidence] with the per-type cap: edge, LBW, wicket-hit and
  /// front-foot results never exceed `REVIEW_RECOMMENDED`.
  static DecisionStatus statusFor(DeliveryDecisionType type, double confidence) {
    final DecisionStatus status = statusForConfidence(confidence);
    if (status == DecisionStatus.autoCall && !type.allowsAutoCall) {
      return DecisionStatus.reviewRecommended;
    }
    return status;
  }

  /// True when the app is allowed to present the result as a call.
  bool get isAutoCall => status == DecisionStatus.autoCall;

  /// True when there was not enough reliable data.
  bool get isInconclusive => status == DecisionStatus.inconclusive;

  /// A copy with some fields replaced.
  DeliveryDecision copyWith({
    DeliveryDecisionType? type,
    String? automatedResult,
    double? confidence,
    DecisionStatus? status,
    Map<String, Object?>? evidence,
    String? summary,
  }) {
    return DeliveryDecision(
      type: type ?? this.type,
      automatedResult: automatedResult ?? this.automatedResult,
      confidence: confidence ?? this.confidence,
      status: status ?? this.status,
      evidence: evidence ?? this.evidence,
      summary: summary ?? this.summary,
    );
  }

  /// API-shaped JSON (snake_case keys, UPPER_SNAKE_CASE enums). Excludes [summary].
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'decision_type': type.wire,
      'automated_result': automatedResult,
      'confidence': confidence,
      'decision_status': status.wire,
      'evidence': evidence,
    };
  }

  @override
  List<Object?> get props => <Object?>[type, automatedResult, confidence, status, evidence, summary];

  @override
  String toString() =>
      'DeliveryDecision(${type.wire}: $automatedResult, ${confidence.toStringAsFixed(3)}, ${status.wire})';

  static String _checkedResult(String value) {
    if (value.isEmpty || value.length > maxResultLength) {
      throw ArgumentError.value(
        value,
        'automatedResult',
        'must be 1..$maxResultLength characters',
      );
    }
    return value;
  }

  static double _clamp01(double value) {
    if (value.isNaN) {
      return 0;
    }
    if (value < 0) {
      return 0;
    }
    if (value > 1) {
      return 1;
    }
    return value;
  }
}

/// Deep-copies [source] into plain JSON values: `null`, `bool`, `num`
/// (non-finite doubles become `null`), `String`, `List` and `Map<String, Object?>`.
/// Anything else is converted with `toString()` (`DateTime` becomes ISO 8601 UTC).
Map<String, Object?> jsonSafeMap(Map<Object?, Object?> source) {
  final Map<String, Object?> result = <String, Object?>{};
  source.forEach((Object? key, Object? value) {
    result[key.toString()] = jsonSafeValue(value);
  });
  return result;
}

/// See [jsonSafeMap].
Object? jsonSafeValue(Object? value) {
  if (value == null || value is bool || value is String || value is int) {
    return value;
  }
  if (value is double) {
    return value.isFinite ? value : null;
  }
  if (value is Map) {
    return jsonSafeMap(value);
  }
  if (value is Iterable) {
    return value.map<Object?>(jsonSafeValue).toList();
  }
  if (value is DateTime) {
    return value.toUtc().toIso8601String();
  }
  return value.toString();
}
