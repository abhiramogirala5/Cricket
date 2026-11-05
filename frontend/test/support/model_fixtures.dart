import 'package:gully_umpire/domain/decisions/decision_status.dart';
import 'package:gully_umpire/domain/decisions/delivery_decision_type.dart';
import 'package:gully_umpire/domain/decisions/wicket_family.dart';
import 'package:gully_umpire/domain/models/models.dart';

/// One fully populated instance of every synced model, built from fixed values so that tests
/// can compare serialisation output exactly.
final DateTime t0 = DateTime.utc(2026, 10, 8, 7, 33);
final DateTime t1 = DateTime.utc(2026, 10, 8, 7, 45, 12);

final Team sampleTeamA = Team(id: 'team-a', name: 'Reds', createdAt: t0, updatedAt: t0);
final Team sampleTeamB = Team(id: 'team-b', name: 'Blues', createdAt: t0, updatedAt: t0);

final Player samplePlayer = Player(
  id: 'player-1',
  displayName: 'Asha Rao',
  battingHand: BattingHand.left,
  declaredHeightCm: 168,
  createdAt: t0,
  updatedAt: t1,
);

final CricketMatch sampleMatch = CricketMatch(
  id: 'match-1',
  teamAId: 'team-a',
  teamBId: 'team-b',
  matchName: 'Sunday finals',
  locationName: 'Terrace',
  scheduledAt: t0,
  startedAt: t1,
  status: MatchStatus.live,
  oversPerInnings: 6,
  createdAt: t0,
  updatedAt: t1,
);

const MatchPlayer sampleMatchPlayer = MatchPlayer(
  matchId: 'match-1',
  playerId: 'player-1',
  teamId: 'team-a',
  battingHand: BattingHand.right,
  declaredHeightCm: 170,
  battingOrder: 3,
  isCaptain: true,
);

const MatchRules sampleRules = MatchRules(
  matchId: 'match-1',
  frontFootNoBallEnabled: true,
  maxBouncersPerOver: 2,
  lateralReachMultiplier: 0.7,
);

final Toss sampleToss = Toss(
  id: 'toss-1',
  matchId: 'match-1',
  calledByPlayerId: 'player-1',
  callChoice: TossSide.heads,
  result: TossSide.tails,
  winnerTeamId: 'team-b',
  winnerDecision: TossDecision.bowl,
  createdAt: t0,
);

final Innings sampleInnings = Innings(
  id: 'innings-1',
  matchId: 'match-1',
  inningsNumber: 1,
  battingTeamId: 'team-a',
  bowlingTeamId: 'team-b',
  totalRuns: 41,
  wickets: 2,
  legalBalls: 30,
  startedAt: t0,
  endedAt: t1,
);

final Delivery sampleDelivery = Delivery(
  id: 'delivery-1',
  inningsId: 'innings-1',
  wicketDetectionId: 'wicket-1',
  deliverySequence: 7,
  overNumber: 1,
  legalBallNumber: 2,
  bowlerId: 'player-9',
  strikerId: 'player-1',
  nonStrikerId: 'player-2',
  runsBat: 4,
  isWicket: true,
  dismissalType: DismissalType.runOut,
  dismissedPlayerId: 'player-2',
  speedKmph: 71.5,
  speedConfidence: 0.55,
  ballTrackingConfidence: 0.9,
  poseTrackingConfidence: 0.88,
  wicketTrackingConfidence: 0.95,
  isVoided: true,
  voidedAt: t1,
  voidReason: 'Scorer mistake',
  createdAt: t0,
);

final DecisionRecord sampleDecision = DecisionRecord(
  id: 'decision-1',
  deliveryId: 'delivery-1',
  decisionType: DeliveryDecisionType.wide,
  automatedResult: 'WIDE',
  finalResult: 'NOT_WIDE',
  confidence: 0.91,
  decisionStatus: DecisionStatus.manualOverride,
  decisionSource: DecisionSource.manual,
  evidence: const <String, Object?>{'distance_m': 1.4},
  createdAt: t0,
);

final SceneScan sampleScan = SceneScan(
  id: 'scan-1',
  matchId: 'match-1',
  cameraDeviceModel: 'Pixel 8',
  captureFps: 30,
  scanDurationMs: 1200,
  groundPlane: const <String, Object?>{'y': 0.66},
  pitchDirection: const <String, Object?>{'dx': 0.0, 'dy': -1.0},
  batsmanPlane: const <String, Object?>{'center_x': 0.5},
  overallConfidence: 0.93,
  modelVersion: 'mock-scene-1.0',
  createdAt: t0,
);

final WicketDetection sampleWicket = WicketDetection(
  id: 'wicket-1',
  matchId: 'match-1',
  sceneScanId: 'scan-1',
  wicketFamily: WicketFamily.traditionalStumps,
  boundingBox: const <String, Object?>{'x': 0.477, 'y': 0.42, 'width': 0.046, 'height': 0.14},
  targetPolygon: const <Object?>[
    <String, Object?>{'x': 0.477, 'y': 0.42},
    <String, Object?>{'x': 0.523, 'y': 0.42},
    <String, Object?>{'x': 0.523, 'y': 0.56},
    <String, Object?>{'x': 0.477, 'y': 0.56},
  ],
  targetPlane: const <String, Object?>{'z': 18},
  groundContactLine: const <String, Object?>{'y': 0.56},
  objectConfidence: 0.92,
  temporalStability: 0.9,
  contextConfidence: 0.95,
  finalConfidence: 0.93,
  modelVersion: 'mock-scene-1.0',
  detectedAt: t0,
);

final TrajectorySnapshot sampleTrajectory = TrajectorySnapshot(
  id: 'trajectory-1',
  deliveryId: 'delivery-1',
  samplingFps: 24,
  pointsCompressed: const <Object?>[
    <Object?>[2000, 0.5, 0.19, 0.95],
    <Object?>[2042, 0.5, 0.31, 0.94],
  ],
  modelVersion: 'mock-ball-1.0',
  createdAt: t0,
);
