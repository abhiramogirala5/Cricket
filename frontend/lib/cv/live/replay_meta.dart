import 'package:equatable/equatable.dart';
import 'package:gully_umpire/cv/geometry/plane.dart';
import 'package:gully_umpire/cv/geometry/point2d.dart';
import 'package:gully_umpire/cv/geometry/polygon.dart';
import 'package:gully_umpire/cv/live/ball_kind.dart';
import 'package:gully_umpire/cv/pipelines/ball_observation.dart';
import 'package:gully_umpire/cv/pipelines/delivery_context.dart';
import 'package:gully_umpire/cv/pipelines/pose_sample.dart';
import 'package:gully_umpire/cv/tracking/ball_track_point.dart';
import 'package:gully_umpire/cv/util/json_read.dart';
import 'package:gully_umpire/domain/decisions/delivery_decision.dart';

/// One ball position in the replay: where, how big it looked, and how sure the detector was.
final class ReplayBallPoint extends Equatable {
  const ReplayBallPoint({
    required this.timestampMs,
    required this.x,
    required this.y,
    required this.diameter,
    required this.confidence,
  });

  factory ReplayBallPoint.fromList(List<Object?> raw) {
    if (raw.length < 5) {
      throw FormatException('A replay ball point has 5 values but got ${raw.length}');
    }
    return ReplayBallPoint(
      timestampMs: numToInt(raw[0]),
      x: numToDouble(raw[1]),
      y: numToDouble(raw[2]),
      diameter: numToDouble(raw[3]),
      confidence: numToDouble(raw[4]),
    );
  }

  final int timestampMs;
  final double x;
  final double y;

  /// Apparent diameter as a share of the picture height.
  final double diameter;
  final double confidence;

  List<num> toList() => <num>[timestampMs, x, y, diameter, confidence];

  @override
  List<Object?> get props => <Object?>[timestampMs, x, y, diameter, confidence];
}

/// One result the app gave for the delivery, in words and numbers only.
final class ReplayVerdict extends Equatable {
  const ReplayVerdict({
    required this.typeWire,
    required this.label,
    required this.result,
    required this.statusWire,
    required this.confidence,
    required this.summary,
  });

  factory ReplayVerdict.fromDecision(DeliveryDecision decision) {
    return ReplayVerdict(
      typeWire: decision.type.wire,
      label: decision.type.label,
      result: decision.automatedResult,
      statusWire: decision.status.wire,
      confidence: decision.confidence,
      summary: decision.summary,
    );
  }

  factory ReplayVerdict.fromJson(Map<String, Object?> json) {
    final Object? summary = json['summary'];
    final Object? label = json['label'];
    return ReplayVerdict(
      typeWire: _readString(json, 'type'),
      label: label is String ? label : _readString(json, 'type'),
      result: _readString(json, 'result'),
      statusWire: _readString(json, 'status'),
      confidence: readDouble(json, 'confidence'),
      summary: summary is String ? summary : '',
    );
  }

  /// `WIDE`, `NO_BALL_HEIGHT`, `LBW`, ...
  final String typeWire;
  final String label;

  /// `NOT_WIDE`, `NO_BALL`, ...
  final String result;
  final String statusWire;
  final double confidence;
  final String summary;

  Map<String, Object?> toJson() => <String, Object?>{
        'type': typeWire,
        'label': label,
        'result': result,
        'status': statusWire,
        'confidence': confidence,
        'summary': summary,
      };

  @override
  List<Object?> get props => <Object?>[typeWire, label, result, statusWire, confidence, summary];
}

/// Everything about one delivery that the replay screen draws on top of the pictures.
///
/// It is stored inside the replay file (see `ReplayCodec.attachMeta`), so a replay opens on any
/// phone and shows exactly what the umpire saw.
final class ReplayMeta extends Equatable {
  const ReplayMeta({
    required this.ballKind,
    required this.aspectRatio,
    required this.batterHeightM,
    required this.track,
    required this.poses,
    required this.verdicts,
    this.wicket,
    this.plane,
    this.arrivalMs,
    this.bounceMs,
    this.bounced,
    this.contactMs,
    this.ballHeightM,
    this.ballLateralM,
    this.heightUncertaintyM,
    this.speedKmph,
    this.trackQuality = 0,
    this.waistRatio = 0.55,
    this.shoulderRatio = 0.82,
    this.notes = const <String>[],
  });

  /// Builds the metadata from what the pipeline worked out.
  factory ReplayMeta.fromAnalysis({
    required DeliveryAnalysis analysis,
    required BallKind ballKind,
    required double aspectRatio,
    required double batterHeightM,
    Polygon? wicket,
    double? heightUncertaintyM,
    double waistRatio = 0.55,
    double shoulderRatio = 0.82,
  }) {
    final List<ReplayBallPoint> track = analysis.observations.isNotEmpty
        ? <ReplayBallPoint>[
            for (final BallObservation o in analysis.observations)
              ReplayBallPoint(
                timestampMs: o.timestampMs,
                x: o.x,
                y: o.y,
                diameter: o.diameter,
                confidence: o.confidence,
              ),
          ]
        : <ReplayBallPoint>[
            for (final BallTrackPoint point in analysis.trajectory)
              ReplayBallPoint(
                timestampMs: point.timestampMs,
                x: point.x,
                y: point.y,
                diameter: 0,
                confidence: point.confidence,
              ),
          ];
    return ReplayMeta(
      ballKind: ballKind.wire,
      aspectRatio: aspectRatio,
      batterHeightM: batterHeightM,
      track: track,
      poses: analysis.poses,
      verdicts: <ReplayVerdict>[
        for (final DeliveryDecision d in analysis.decisions) ReplayVerdict.fromDecision(d),
      ],
      wicket: wicket,
      plane: analysis.plane,
      arrivalMs: analysis.arrivalMs,
      bounceMs: analysis.bounceMs,
      bounced: analysis.bounced,
      contactMs: analysis.contactMs,
      ballHeightM: analysis.ballHeightM,
      ballLateralM: analysis.ballLateralM,
      heightUncertaintyM: heightUncertaintyM,
      speedKmph: analysis.speed?.kmph,
      trackQuality: analysis.trackingConfidence,
      waistRatio: waistRatio,
      shoulderRatio: shoulderRatio,
      notes: analysis.notes,
    );
  }

  /// Parses a document made by [toJson]. Throws a [FormatException] when it is unusable.
  factory ReplayMeta.fromJson(Map<String, Object?> json) {
    final Object? version = json['version'];
    if (version is! int || version != formatVersion) {
      throw FormatException('Unknown replay metadata version: $version');
    }
    final Object? wicketRaw = json['wicket'];
    final Object? planeRaw = json['plane'];
    final Object? bouncedRaw = json['bounced'];
    final Object? notesRaw = json['notes'];
    return ReplayMeta(
      ballKind: _readString(json, 'ball_kind'),
      aspectRatio: readDouble(json, 'aspect_ratio'),
      batterHeightM: readDouble(json, 'batter_height_m'),
      track: <ReplayBallPoint>[
        for (final Object? item in asObjectList(json['track'])) ReplayBallPoint.fromList(asObjectList(item)),
      ],
      poses: <PoseSample>[
        for (final Object? item in asObjectList(json['poses'])) _poseFromList(asObjectList(item)),
      ],
      verdicts: <ReplayVerdict>[
        for (final Object? item in asObjectList(json['verdicts'])) ReplayVerdict.fromJson(asStringMap(item)),
      ],
      wicket: wicketRaw == null ? null : Polygon.fromJson(asObjectList(wicketRaw)),
      plane: planeRaw == null ? null : _planeFromJson(asStringMap(planeRaw)),
      arrivalMs: _optionalInt(json, 'arrival_ms'),
      bounceMs: _optionalInt(json, 'bounce_ms'),
      bounced: bouncedRaw is bool ? bouncedRaw : null,
      contactMs: _optionalInt(json, 'contact_ms'),
      ballHeightM: _optionalDouble(json, 'ball_height_m'),
      ballLateralM: _optionalDouble(json, 'ball_lateral_m'),
      heightUncertaintyM: _optionalDouble(json, 'height_uncertainty_m'),
      speedKmph: _optionalDouble(json, 'speed_kmph'),
      trackQuality: _optionalDouble(json, 'track_quality') ?? 0,
      waistRatio: _optionalDouble(json, 'waist_ratio') ?? 0.55,
      shoulderRatio: _optionalDouble(json, 'shoulder_ratio') ?? 0.82,
      notes: notesRaw is List ? notesRaw.whereType<String>().toList() : const <String>[],
    );
  }

  /// Version of the document layout.
  static const int formatVersion = 1;

  /// Wire value of the [BallKind] that was bowled.
  final String ballKind;

  /// Width divided by height of the pictures.
  final double aspectRatio;

  /// Height of the batter that the scale was based on (metres).
  final double batterHeightM;

  /// The ball path (the pictures' own coordinates, 0..1).
  final List<ReplayBallPoint> track;

  /// The batter's position and size in the picture over time.
  final List<PoseSample> poses;

  final List<ReplayVerdict> verdicts;

  /// The marked wicket (0..1 coordinates), when there was one.
  final Polygon? wicket;

  /// The scale between picture and metres at the batter.
  final ReferencePlane? plane;

  /// Time at which the ball reached the batter.
  final int? arrivalMs;

  /// Time of the lowest point of the bounce.
  final int? bounceMs;

  /// Whether the ball bounced before the batter (null when unknown).
  final bool? bounced;

  /// Time at which the ball's path changed suddenly near the batter, when it did. Replays made
  /// before this was recorded have none.
  final int? contactMs;

  /// Height (metres) and sideways position (metres, + = right) of the ball at the batter.
  final double? ballHeightM;
  final double? ballLateralM;

  /// How far (metres) the height can be off with one camera.
  final double? heightUncertaintyM;

  /// Estimated speed.
  final double? speedKmph;

  /// 0..1 how much the track looks like a thrown ball.
  final double trackQuality;

  /// Waist and shoulder as shares of the batter's height (what the rules used).
  final double waistRatio;
  final double shoulderRatio;

  final List<String> notes;

  /// First and last time of the ball track, or null for an empty track.
  ({int start, int end})? get trackSpan => track.isEmpty
      ? null
      : (start: track.first.timestampMs, end: track.last.timestampMs);

  Map<String, Object?> toJson() => <String, Object?>{
        'version': formatVersion,
        'ball_kind': ballKind,
        'aspect_ratio': aspectRatio,
        'batter_height_m': batterHeightM,
        'track': <List<num>>[for (final ReplayBallPoint p in track) p.toList()],
        'poses': <List<num>>[
          for (final PoseSample p in poses)
            <num>[p.timestampMs, p.centerX, p.groundY, p.topY, p.confidence],
        ],
        'verdicts': <Map<String, Object?>>[for (final ReplayVerdict v in verdicts) v.toJson()],
        if (wicket != null)
          'wicket': <Map<String, double>>[
            for (final Point2D v in wicket!.vertices) <String, double>{'x': v.x, 'y': v.y},
          ],
        if (plane != null) 'plane': plane!.toJson(),
        if (arrivalMs != null) 'arrival_ms': arrivalMs,
        if (bounceMs != null) 'bounce_ms': bounceMs,
        if (bounced != null) 'bounced': bounced,
        if (contactMs != null) 'contact_ms': contactMs,
        if (ballHeightM != null) 'ball_height_m': ballHeightM,
        if (ballLateralM != null) 'ball_lateral_m': ballLateralM,
        if (heightUncertaintyM != null) 'height_uncertainty_m': heightUncertaintyM,
        if (speedKmph != null) 'speed_kmph': speedKmph,
        'track_quality': trackQuality,
        'waist_ratio': waistRatio,
        'shoulder_ratio': shoulderRatio,
        'notes': notes,
      };

  @override
  List<Object?> get props => <Object?>[
        ballKind,
        aspectRatio,
        batterHeightM,
        track,
        poses,
        verdicts,
        wicket,
        plane,
        arrivalMs,
        bounceMs,
        bounced,
        contactMs,
        ballHeightM,
        ballLateralM,
        heightUncertaintyM,
        speedKmph,
        trackQuality,
        waistRatio,
        shoulderRatio,
        notes,
      ];
}

String _readString(Map<String, Object?> json, String key) {
  final Object? raw = json[key];
  if (raw is String) {
    return raw;
  }
  throw FormatException('Expected text for "$key" but got: $raw');
}

int? _optionalInt(Map<String, Object?> json, String key) {
  final Object? raw = json[key];
  return raw is num ? raw.toInt() : null;
}

double? _optionalDouble(Map<String, Object?> json, String key) {
  final Object? raw = json[key];
  if (raw is num && raw.isFinite) {
    return raw.toDouble();
  }
  return null;
}

PoseSample _poseFromList(List<Object?> raw) {
  if (raw.length < 5) {
    throw FormatException('A replay pose has 5 values but got ${raw.length}');
  }
  return PoseSample(
    timestampMs: numToInt(raw[0]),
    centerX: numToDouble(raw[1]),
    groundY: numToDouble(raw[2]),
    topY: numToDouble(raw[3]),
    confidence: numToDouble(raw[4]),
  );
}

ReferencePlane _planeFromJson(Map<String, Object?> json) {
  return ReferencePlane(
    centerX: readDouble(json, 'center_x'),
    groundY: readDouble(json, 'ground_y'),
    metersPerUnitX: readDouble(json, 'meters_per_unit_x'),
    metersPerUnitY: readDouble(json, 'meters_per_unit_y'),
  );
}
