# Gully Umpire — Complete Agent-Ready Build Specification

**Version:** 3.0  
**Purpose:** Complete implementation contract for an AI coding agent such as Antigravity, Cursor, Windsurf, Claude Code, or other IDE agents.  
**Primary target:** Android-first mobile app for small gully-cricket matches in apartments, roads, terraces, parks, and box-cricket spaces.  
**Core requirement:** Detect the **actual physical wicket** automatically. Users must not manually calibrate, tap corners, define virtual wickets, or draw imaginary wicket zones in normal use.

---

# 1. Agent Instructions

Build the repository described by this specification. Do not ask the user to select an architecture, framework, database, folder structure, or implementation order unless a required credential is unavailable.

## Non-negotiable rules

1. Use React Native, TypeScript, Expo Development Build, and Expo Router.
2. Use Supabase for Auth, PostgreSQL, Storage, Realtime, and Row-Level Security.
3. Use Expo SQLite for offline-first local data and the durable sync outbox.
4. Use Zustand for local state and TanStack Query for server state.
5. Use React Native VisionCamera for the camera/frame-processing abstraction.
6. Use MediaPipe Pose Landmarker for pretrained pose estimation.
7. Use custom lightweight on-device object-detection models for ball and wicket-family objects.
8. Keep all CV implementations behind interfaces, with working mock adapters.
9. Real-time decision making must occur on device; do not upload continuous camera frames to the cloud.
10. Do not run frame processing in the React UI thread.
11. Manual scoring must work even when camera/CV is unavailable.
12. LBW and edge remain review-assist features in MVP; never auto-dismiss a batsman from those signals.
13. Never expose Supabase service-role or secret keys in mobile source or any `EXPO_PUBLIC_*` variable.
14. The normal user flow must be zero-touch wicket detection; score-only mode is the fallback.

---

# 2. Product Definition

Gully Umpire is an offline-first mobile cricket scoring and AI umpiring assistant for informal cricket. It supports physical wickets made from:

- Traditional stumps
- Chairs
- Bricks
- Bottles
- Cones
- Buckets
- Bags or similar objects
- Wall targets
- Other stable visible objects

The app identifies the physical object or object cluster currently being used as the wicket. It does not create an imaginary wicket when no target is visible.

## Feature scope

### MVP

- Email/password auth plus local development mode
- Teams, players, matches, innings, and scorecards
- Toss animation and toss result
- Offline-first live scoring
- Auto scene scan and physical wicket detection
- Batsman pose tracking and height reference
- Ball detection/tracking architecture plus mock mode
- Ball speed estimate
- Wide assistance
- Height no-ball/bouncer assistance
- Physical wicket-hit assistance
- Replay buffer and trajectory overlays
- Manual override and undo
- Supabase sync

### Release 2

- Bat-zone detector
- Edge review: trajectory residual + bat proximity + audio impulse
- LBW review: trajectory projection to detected wicket target
- Front-foot no-ball review

### Release 3

- Optional synchronized two-phone capture
- Multi-view reconstruction
- Model updates and device-specific model profiles

---

# 3. Product Truthfulness

The app is not professional stadium DRS.

A single phone camera has depth ambiguity, rolling shutter, motion blur, occlusions, lighting sensitivity, and limited frame rate. The app must show confidence and use clear states:

```ts
export type DecisionStatus =
  | "AUTO_CALL"
  | "REVIEW_RECOMMENDED"
  | "INCONCLUSIVE"
  | "MANUAL_OVERRIDE";
```

- Auto-call only obvious, high-confidence wide/no-ball events.
- Edge and LBW are evidence/review features.
- If wicket/ball/pose confidence is inadequate, mark the result `INCONCLUSIVE`.

---

# 4. Repository Layout

```text
gully-umpire/
├── apps/
│   └── mobile/
│       ├── app/
│       │   ├── _layout.tsx
│       │   ├── index.tsx
│       │   ├── (auth)/
│       │   │   ├── _layout.tsx
│       │   │   ├── sign-in.tsx
│       │   │   └── sign-up.tsx
│       │   ├── (tabs)/
│       │   │   ├── _layout.tsx
│       │   │   ├── index.tsx
│       │   │   ├── matches.tsx
│       │   │   └── profile.tsx
│       │   └── match/
│       │       ├── create.tsx
│       │       └── [matchId]/
│       │           ├── _layout.tsx
│       │           ├── auto-scan.tsx
│       │           ├── toss.tsx
│       │           ├── live.tsx
│       │           ├── scorecard.tsx
│       │           └── review/[deliveryId].tsx
│       ├── src/
│       │   ├── components/
│       │   │   ├── ui/
│       │   │   ├── common/
│       │   │   ├── scene/
│       │   │   │   ├── AutoScanProgress.tsx
│       │   │   │   ├── WicketDetectionOverlay.tsx
│       │   │   │   └── SceneConfidenceBanner.tsx
│       │   │   ├── cricket/
│       │   │   │   ├── CameraUmpireOverlay.tsx
│       │   │   │   ├── BallTrajectoryOverlay.tsx
│       │   │   │   ├── DecisionBanner.tsx
│       │   │   │   ├── Scoreboard.tsx
│       │   │   │   ├── TossAnimation.tsx
│       │   │   │   ├── LbwProjectionView.tsx
│       │   │   │   └── EdgeWaveform.tsx
│       │   │   └── scoring/
│       │   │       ├── ManualScoreControls.tsx
│       │   │       └── DeliveryTimeline.tsx
│       │   ├── features/
│       │   │   ├── auth/
│       │   │   ├── matches/
│       │   │   ├── scene-scan/
│       │   │   ├── scoring/
│       │   │   ├── umpiring/
│       │   │   └── replay/
│       │   ├── domain/
│       │   │   ├── cricket/
│       │   │   ├── decisions/
│       │   │   └── scene/
│       │   ├── computer-vision/
│       │   │   ├── contracts/
│       │   │   ├── adapters/
│       │   │   │   ├── mock/
│       │   │   │   ├── vision-camera/
│       │   │   │   ├── mediapipe/
│       │   │   │   ├── tflite/
│       │   │   │   └── onnx/
│       │   │   ├── pipelines/
│       │   │   ├── tracking/
│       │   │   ├── geometry/
│       │   │   ├── rules/
│       │   │   └── types/
│       │   ├── data/
│       │   │   ├── local/
│       │   │   ├── remote/
│       │   │   └── sync/
│       │   ├── hooks/
│       │   ├── stores/
│       │   ├── lib/
│       │   ├── config/
│       │   └── types/
│       ├── assets/models/
│       └── tests/
├── supabase/
│   ├── migrations/
│   │   ├── 001_initial_schema.sql
│   │   ├── 002_indexes.sql
│   │   └── 003_rls.sql
│   ├── functions/
│   └── seed.sql
├── ml/
│   ├── datasets/
│   ├── annotation/
│   ├── training/
│   ├── evaluation/
│   └── model-cards/
├── docs/
├── scripts/
├── .env.example
├── README.md
├── package.json
└── turbo.json
```

---

# 5. Technology Stack

| Area | Technology | Purpose |
|---|---|---|
| Framework | React Native + TypeScript | Shared Android/iOS codebase |
| Runtime | Expo Development Build | Native module support |
| Routing | Expo Router | File-based navigation |
| Camera | React Native VisionCamera | High-performance camera/frame processors |
| Pose | MediaPipe Pose Landmarker | 33 body landmarks |
| Object/ball models | TFLite or ONNX Runtime Mobile | On-device inference |
| Tracking | Kalman filter, optical flow, RANSAC | Stable ball trajectories |
| Graphics | React Native Skia + Reanimated | Fast overlays/replay/toss animation |
| Local DB | Expo SQLite | Offline score and outbox queue |
| Local state | Zustand | Small app/domain state |
| Server cache | TanStack Query | Remote cache/retry |
| Backend | Supabase | Auth, Postgres, Realtime, Storage |
| Monitoring | Sentry | Production error/performance telemetry |
| CI/CD | GitHub Actions + EAS Build | Tests/builds/releases |

Use Expo Development Build rather than Expo Go because camera frame processors and native ML inference require native modules.

---

# 6. Core Types

```ts
export type Point2D = { x: number; y: number };
export type Point3D = { x: number; y: number; z: number };

export type BoundingBox = {
  x: number;
  y: number;
  width: number;
  height: number;
};

export type WicketFamily =
  | "TRADITIONAL_STUMPS"
  | "CHAIR"
  | "BRICK_STACK"
  | "BOTTLE_STACK"
  | "CONE_STACK"
  | "BUCKET"
  | "BAG_OR_OBJECT"
  | "WALL_TARGET"
  | "UNKNOWN_PHYSICAL_OBJECT";

export type WicketCandidate = {
  id: string;
  family: WicketFamily;
  boundingBox: BoundingBox;
  visibleTargetPolygon: Point2D[];
  confidence: number;
  objectConfidence: number;
  temporalStability: number;
  batsmanRelationshipScore: number;
  pitchAlignmentScore: number;
  frameCount: number;
};

export type BallTrackPoint = {
  frameId: number;
  timestampMs: number;
  imageX: number;
  imageY: number;
  worldX?: number;
  worldY?: number;
  worldZ?: number;
  detectorConfidence: number;
  trackerConfidence: number;
};

export type DeliveryDecisionType =
  | "WIDE"
  | "NO_BALL_HEIGHT"
  | "NO_BALL_FRONT_FOOT"
  | "EDGE"
  | "LBW"
  | "WICKET_HIT";

export type DeliveryDecision = {
  type: DeliveryDecisionType;
  automatedResult: string | null;
  finalResult: string | null;
  confidence: number;
  status: DecisionStatus;
  evidence: Record<string, unknown>;
};
```

---

# 7. Zero-Touch Wicket Recognition

## Principle

Do not create one generic `wicket` object class. The wicket may be an ordinary object being used in a special role.

Use three stages:

```text
1. Object-family detection
   stumps, chair, bottle, brick, cone, bucket, bag, wall target, person

2. Wicket candidate generation
   single object or object cluster converted to visible physical target polygon

3. Context and temporal verification
   static location, batsman relationship, pitch alignment, shape/size, repeated visibility
```

## Candidate logic

- `TRADITIONAL_STUMPS`: detector box/polygon becomes wicket target.
- `CHAIR`: use stable detected chair back/seat/legs as visible wicket target.
- `BRICK_STACK`, `BOTTLE_STACK`, `CONE_STACK`: cluster nearby detections with spatial hashing and create combined target polygon.
- `BUCKET`, `BAG_OR_OBJECT`: accept only when static and highly ranked by cricket context.
- `WALL_TARGET`: identify stable rectangle/high-contrast marked region near batsman end.

## Candidate score

```ts
export function scoreWicketCandidate(input: {
  objectConfidence: number;
  temporalStability: number;
  batsmanRelationshipScore: number;
  pitchAlignmentScore: number;
  physicalTargetQuality: number;
}): number {
  return (
    input.objectConfidence * 0.30 +
    input.temporalStability * 0.25 +
    input.batsmanRelationshipScore * 0.20 +
    input.pitchAlignmentScore * 0.15 +
    input.physicalTargetQuality * 0.10
  );
}
```

## User experience thresholds

| Confidence | Behaviour |
|---:|---|
| >= 0.85 | Ready for wide/no-ball/wicket-hit/LBW review assistance |
| 0.70–0.84 | Start match with moderate-confidence banner |
| 0.50–0.69 | Score-only or limited wide assistance; disable LBW/wicket-hit automation |
| < 0.50 | Ask user to reposition phone; do not start automated umpiring |

## Auto scan flow

```text
Camera view from bowling end
      │
      ▼
1–3 second scene scan
      │
      ▼
Object detector + pose estimator
      │
      ▼
Generate stable wicket candidates
      │
      ▼
Rank by context and temporal stability
      │
      ├── confidence >= threshold -> wicket overlay -> continue
      └── confidence low -> reposition camera or score-only mode
```

No normal-flow manual calibration screen is allowed.

---

# 8. Computer Vision Interfaces

```ts
export type DetectedObject = {
  label: string;
  confidence: number;
  boundingBox: BoundingBox;
};

export interface SceneObjectDetector {
  detect(frame: unknown): Promise<DetectedObject[]>;
}

export interface BallDetector {
  detect(frame: unknown): Promise<DetectedObject[]>;
}

export interface PoseResult {
  landmarks: Array<{ x: number; y: number; z?: number; visibility?: number }>;
  confidence: number;
}

export interface PoseEstimator {
  estimate(frame: unknown): Promise<PoseResult | null>;
}

export interface AudioImpulse {
  timestampMs: number;
  peakAmplitude: number;
  spectralCentroid: number;
  impulseConfidence: number;
}

export interface AudioAnalyzer {
  getRecentImpulses(fromMs: number, toMs: number): Promise<AudioImpulse[]>;
}
```

## Mock mode

Implement deterministic mock adapters for:

- Chair/stump/bottle/brick wicket candidates
- Batsman pose
- Ball path
- Low/moderate/high wicket confidence
- Wide/no-ball results
- Edge evidence
- LBW likely-hit/miss scenarios

The app must run end-to-end in mock mode without model binaries or Supabase credentials.

---

# 9. Tracking and Decision Pipeline

```text
Camera input
  │
  ├─ Motion gate
  ├─ Scene scan / wicket revalidation
  ├─ Ball detector at configured cadence
  ├─ Kalman prediction and correction
  ├─ Optical-flow bridge between detector frames
  ├─ Pose estimator at lower cadence
  ├─ Audio window processing
  └─ Delivery state machine
       │
       └─ Wide/no-ball/speed/edge/LBW decision engine
```

## Ball speed

```ts
export function calculateSpeedKmph(
  distanceMeters: number,
  startTimestampMs: number,
  endTimestampMs: number,
): number {
  const seconds = (endTimestampMs - startTimestampMs) / 1000;
  if (seconds <= 0) return 0;
  return (distanceMeters / seconds) * 3.6;
}
```

Display rounded estimated values, for example `Estimated 68 km/h`.

## Wide decision

```ts
export function classifyWide(input: {
  ballAtBatsmanPlane: Point3D;
  batsmanCenter: Point3D;
  batsmanHeightM: number;
  lateralReachMultiplier: number;
  batsmanMovedTowardBall: boolean;
  wicketConfidence: number;
  trajectoryConfidence: number;
}): "WIDE" | "NOT_WIDE" | "INCONCLUSIVE" {
  if (input.wicketConfidence < 0.7 || input.trajectoryConfidence < 0.7) {
    return "INCONCLUSIVE";
  }

  if (input.batsmanMovedTowardBall) return "NOT_WIDE";

  const reach = input.batsmanHeightM * input.lateralReachMultiplier;
  const distance = Math.abs(
    input.ballAtBatsmanPlane.x - input.batsmanCenter.x,
  );

  return distance > reach ? "WIDE" : "NOT_WIDE";
}
```

## Height no-ball

```ts
export type HeightRuleConfig = {
  fullTossAboveWaistIsNoBall: boolean;
  bouncedAboveShoulderIsNoBall: boolean;
  aboveHeadIsNoBall: boolean;
  waistHeightRatio: number;
  shoulderHeightRatio: number;
};

export function classifyHeightNoBall(
  ballHeightM: number,
  batsmanHeightM: number,
  bounced: boolean,
  rules: HeightRuleConfig,
): "NO_BALL" | "LEGAL" {
  const waist = batsmanHeightM * rules.waistHeightRatio;
  const shoulder = batsmanHeightM * rules.shoulderHeightRatio;

  if (!bounced && rules.fullTossAboveWaistIsNoBall && ballHeightM > waist) {
    return "NO_BALL";
  }

  if (bounced && rules.bouncedAboveShoulderIsNoBall && ballHeightM > shoulder) {
    return "NO_BALL";
  }

  if (rules.aboveHeadIsNoBall && ballHeightM > batsmanHeightM) {
    return "NO_BALL";
  }

  return "LEGAL";
}
```

## Edge review

Use deterministic evidence fusion:

```text
edge confidence =
  visual trajectory deviation
+ bat proximity
+ pre/post direction change
+ synchronized audio impulse
- tracking uncertainty
```

Return one of:

```ts
export type EdgeAssessment = {
  result:
    | "EDGE_LIKELY"
    | "NO_EDGE_EVIDENCE"
    | "REVIEW_RECOMMENDED"
    | "INCONCLUSIVE";
  confidence: number;
  visualScore: number;
  audioScore: number;
  suspectedContactTimestampMs?: number;
};
```

Never declare a final dismissal automatically.

## LBW review

Use deterministic path projection:

1. Track the ball before probable impact.
2. Split bounce/impact trajectory phases.
3. Fit a robust short-window trajectory.
4. Extrapolate toward the detected physical wicket plane.
5. Intersect projected path with detected physical target polygon.
6. Render a bounded uncertainty cone.

```ts
export type LbwAssessment = {
  result:
    | "LIKELY_HITTING"
    | "LIKELY_MISSING"
    | "REVIEW_RECOMMENDED"
    | "INCONCLUSIVE";
  impactInLine?: boolean;
  projectedHitPoint?: Point2D;
  confidence: number;
  reason?: string;
};
```

Never present one thin exact line as certain multi-camera reconstruction.

---

# 10. Research-to-Implementation Traceability

| Product problem | Technique | Reference relationship | Implementation adaptation |
|---|---|---|---|
| Tiny fast ball | Fine-tuned lightweight detector + ROI + temporal tracker | Sports ball detection and YOLO workflows | INT8 custom `cricket_ball` detector, dynamic detector cadence |
| Noisy/lost ball | Kalman prediction + detector correction + gate + short optical-flow bridge | SORT/ByteTrack-type trackers and tiny-object studies | Keep one active ball track; split/reset on bounce/impact |
| One-camera depth ambiguity | Homography + wicket geometry + relative coordinates + confidence cone | Monocular 3D trajectory research | LBW review only, never DRS-grade certainty |
| Batsman location | MediaPipe 33-landmark pose | MediaPipe Pose Landmarker | Lower pose cadence and landmark smoothing |
| Improvised wicket | Object detection + context ranking + temporal stability | Scene/object-context reasoning | Detect object family, then score whether it acts as wicket |
| Wide/no-ball | Deterministic geometry + local-rule config | Rule-based decision engine | Confidence-gated calls |
| Edge | Path residual + audio/video alignment | UltraEdge principle | Replay/evidence, no automatic dismissal |
| LBW | Fit/extrapolate trajectory into wicket polygon | Ball tracking/projection methods | Confidence cone and manual final result |
| Low-end support | Frame decimation + typed arrays + bounded buffers + native processing | Mobile edge inference practice | Adaptive quality profile |

## Links

- CVPR 2025 — *Where Is The Ball: 3D Ball Trajectory Estimation From 2D Monocular Tracking*: https://cvpr.thecvf.com/virtual/2025/35509
- Sports ball detection review: https://pmc.ncbi.nlm.nih.gov/articles/PMC12453710/
- Fast tiny-object Kalman tracking review: https://www.themoonlight.io/en/review/an-analysis-of-kalman-filter-based-object-tracking-methods-for-fast-moving-tiny-objects
- MediaPipe Pose Landmarker: https://developers.google.com/edge/mediapipe/solutions/vision/pose_landmarker
- MediaPipe Object Detector: https://developers.google.com/edge/mediapipe/solutions/vision/object_detector
- VisionCamera: https://github.com/margelo/react-native-vision-camera
- VisionCamera npm package: https://www.npmjs.com/package/react-native-vision-camera
- Cricket object detection dataset: https://universe.roboflow.com/cricket-analysis-tmh8m/cricket-object-detection-j4jrj
- Cricket trajectory repository: https://github.com/sunayana90/AI-Cricket-Ball-Tracking-and-Trajectory-Visualization
- ICC UltraEdge background: https://www.icc-umpireaccreditation.com/post/ultraedge-how-it-works
- TensorFlow Lite: https://www.tensorflow.org/lite
- ONNX Runtime Mobile: https://onnxruntime.ai/docs/tutorials/mobile/
- Supabase Expo quickstart: https://supabase.com/docs/guides/getting-started/quickstarts/expo-react-native
- Supabase React Native auth: https://supabase.com/docs/guides/auth/quickstarts/react-native

---

# 11. Data Structures and Complexity Contract

Do not use unbounded arrays, `Array.shift()`, per-frame JSON serialization, or React/Zustand state for raw camera data.

## Processing budget

| Component | High | Mid | Low |
|---|---:|---:|---:|
| Camera | 60 FPS | 30 FPS | 30 FPS |
| Ball detector | 20–30 FPS | 10–15 FPS | 6–10 FPS |
| Pose | 10–15 FPS | 6–10 FPS | 3–5 FPS |
| Wicket scan | 1–3 sec + sparse revalidation | Same | Same |
| UI updates | <=10 Hz | <=8 Hz | <=5 Hz |
| Ball history | 1–2 sec | 1–2 sec | 1 sec |

## Feature map

| Feature | Structures | Complexity |
|---|---|---:|
| Frame scheduler | timestamps, counters, enum state machine | O(1) per frame |
| Ball history | fixed typed-array ring buffer | O(1) insert |
| Kalman tracker | fixed `[x,y,vx,vy]` state and 4x4 covariance | O(1) |
| Candidate association | one active track + small candidate array | O(k), k <= 10 |
| Outlier gate | small window, median/MAD, Mahalanobis test | O(w), w <= 15 |
| Optical flow | typed-array ROI patches | O(ROI pixels) |
| Pose | `Float32Array(33 * 4)` | O(33) |
| Wicket candidates | capped top-K table, K <= 8 | O(K) |
| Object clusters | spatial hash `Map<GridKey, number[]>` | Average O(n) |
| Audio | PCM ring buffer + FFT windows | O(N log N) per window |
| Edge | bounded pre/post point windows | O(w) |
| LBW | bounded trajectory plus small polygon | O(w + p) |
| Replay | circular queue of encoded segments | O(1) |
| Score/undo | append-only delivery events + reducer | O(1) update |
| Sync | indexed SQLite outbox | indexed fetch |

## Required ball trajectory buffer

```ts
export class TrajectoryRingBuffer {
  private readonly timestamps: Float64Array;
  private readonly xs: Float32Array;
  private readonly ys: Float32Array;
  private readonly confidences: Float32Array;
  private start = 0;
  private count = 0;

  constructor(private readonly capacity: number) {
    this.timestamps = new Float64Array(capacity);
    this.xs = new Float32Array(capacity);
    this.ys = new Float32Array(capacity);
    this.confidences = new Float32Array(capacity);
  }

  push(timestampMs: number, x: number, y: number, confidence: number): void {
    const index = (this.start + this.count) % this.capacity;
    this.timestamps[index] = timestampMs;
    this.xs[index] = x;
    this.ys[index] = y;
    this.confidences[index] = confidence;

    if (this.count < this.capacity) {
      this.count += 1;
    } else {
      this.start = (this.start + 1) % this.capacity;
    }
  }

  get size(): number {
    return this.count;
  }

  getAt(offset: number) {
    if (offset < 0 || offset >= this.count) return null;
    const index = (this.start + offset) % this.capacity;
    return {
      timestampMs: this.timestamps[index],
      x: this.xs[index],
      y: this.ys[index],
      confidence: this.confidences[index],
    };
  }

  clear(): void {
    this.start = 0;
    this.count = 0;
  }
}
```

Reasons:

- `Array.shift()` is O(n) and adds copying/garbage-collection pressure.
- Typed arrays are compact and predictable for high-frequency numeric processing.
- Fixed capacity prevents memory growth during long matches.

## Kalman tracker state

```ts
// [x, y, velocityX, velocityY]
type KalmanState = Float64Array;

// 4x4 covariance stored in length-16 array
type Covariance4x4 = Float64Array;
```

Rules:

- Adapt measurement noise from detector confidence.
- Reject detections outside Mahalanobis-distance gate.
- Split/reset around bounce, bat contact, pad impact, or impossible acceleration.
- Do not force one constant-velocity model through a complete delivery.
- Keep only one active ball track in MVP.

## Wicket candidate tracking

```ts
export type WicketTrack = {
  id: string;
  family: WicketFamily;
  latestBox: BoundingBox;
  score: number;
  seenFrames: number;
  stableFrames: number;
  recentCenters: Float32Array;
  centerWriteIndex: number;
};
```

Wicket scan rules:

1. Run object detection every second or third scene-scan frame.
2. Keep top 8 non-person object candidates near batsman end.
3. Associate candidate boxes by IoU or nearest-centre matching.
4. Score stability using centre displacement and box-size variance.
5. Cluster bottle/brick/cone stacks with a spatial hash.
6. Require repeated stable detection before selecting a wicket.

## Spatial hash for clustered wickets

```ts
export type GridKey = string;

export function toGridKey(x: number, y: number, cellSize: number): GridKey {
  return `${Math.floor(x / cellSize)}:${Math.floor(y / cellSize)}`;
}
```

Store object indexes in `Map<GridKey, number[]>`. For each brick/bottle/cone, inspect only the current cell and eight neighbor cells. This avoids O(n²) all-pairs clustering.

## Pose format

```ts
// x, y, z, visibility for 33 landmarks
export type PackedPose = Float32Array; // 132 values
```

Use EMA smoothing:

```ts
smoothed = alpha * current + (1 - alpha) * previous;
```

Do not run pose estimation every camera frame on mid-range or low-end phones.

## Edge structures

Use:

- Fixed PCM ring buffer, 1–2 seconds
- FFT windows of 256/512/1024 samples
- Fixed pre-contact window: 6–12 ball points
- Fixed post-contact window: 3–8 ball points
- `Float32Array` residual values
- Convex bat-zone polygon

Do not store raw PCM in SQLite. Store only short opt-in replay audio/video assets.

## LBW structures

```ts
export type TrajectorySegment = {
  startIndex: number;
  endIndex: number;
  type: "PRE_BOUNCE" | "POST_BOUNCE" | "PRE_IMPACT";
  confidence: number;
};
```

Use the current delivery buffer only. Store fit coefficients in fixed numeric arrays and render 3–5 uncertainty rays, not hundreds of paths.

---

# 12. Low-End Device Policy

## Device profiles

```ts
export type DeviceProfile = "HIGH" | "MID" | "LOW" | "SCORE_ONLY";
```

| Feature | High | Mid | Low | Score-only |
|---|---|---|---|---|
| Wicket scan | Full | Full, reduced resolution | Sparse | Disabled |
| Ball detector | 20–30 FPS | 10–15 FPS | 6–10 FPS | Disabled |
| Pose | 10–15 FPS | 6–10 FPS | 3–5 FPS | Disabled |
| Optical flow | Enabled | Small ROI | Optional | Disabled |
| Speed | Enabled | If calibration confidence allows | Relative only | Disabled |
| Wide/no-ball | Enabled | High-confidence only | Review only | Manual |
| Edge/LBW | Review | Review with enough points | Disabled by default | Disabled |
| Replay | Enabled | Optional | Disabled | Disabled |

## Rules

- Prefer 640x480 or 960x540 model frames, not 1080p.
- Crop to ball corridor/batsman/wicket region after scene scan.
- Re-run full scene detector only after camera movement, wicket-confidence loss, or innings change.
- Use optical flow between detector frames.
- Keep pipelines cancellable and release camera/model resources on navigation away.
- Never encode/upload replay during active delivery processing.
- Use Skia/worklets for overlays; do not trigger React renders for every frame.

---

# 13. Offline Sync

Every match action is written locally before it is sent to Supabase.

```ts
export type SyncEvent = {
  id: string;
  entityType: string;
  action: "INSERT" | "UPDATE" | "DELETE";
  payloadJson: string;
  createdAtMs: number;
  retryCount: number;
  status: "PENDING" | "SYNCING" | "SYNCED" | "FAILED";
};
```

Rules:

1. Save locally first.
2. Update UI immediately.
3. Queue the remote mutation.
4. Retry with exponential backoff.
5. Use `client_event_id` for idempotent delivery inserts.
6. Do not block scoring due to connection loss.

For undo, use append-only delivery events and a reducer; mark the previous event voided or create a reversal event. Do not destructively delete match history.

---

# 14. Supabase Database Schema

Create:

```text
supabase/migrations/001_initial_schema.sql
supabase/migrations/002_indexes.sql
supabase/migrations/003_rls.sql
```

## `001_initial_schema.sql`

```sql
create extension if not exists "pgcrypto";

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name varchar(100) not null,
  avatar_url text,
  phone varchar(25),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.teams (
  id uuid primary key default gen_random_uuid(),
  name varchar(100) not null,
  created_by uuid not null references public.profiles(id),
  logo_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.team_members (
  team_id uuid not null references public.teams(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  role varchar(30) not null default 'PLAYER',
  joined_at timestamptz not null default now(),
  primary key (team_id, profile_id)
);

create table public.matches (
  id uuid primary key default gen_random_uuid(),
  created_by uuid not null references public.profiles(id),
  team_a_id uuid references public.teams(id),
  team_b_id uuid references public.teams(id),
  match_name varchar(150),
  location_name varchar(255),
  scheduled_at timestamptz,
  started_at timestamptz,
  completed_at timestamptz,
  status varchar(20) not null default 'DRAFT',
  overs_per_innings smallint not null default 6,
  local_rules_profile varchar(40) not null default 'CASUAL_GULLY',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (status in ('DRAFT', 'SCANNING', 'READY', 'LIVE', 'COMPLETED', 'ABANDONED'))
);

create table public.match_players (
  match_id uuid not null references public.matches(id) on delete cascade,
  profile_id uuid not null references public.profiles(id),
  team_id uuid not null references public.teams(id),
  batting_hand varchar(10) not null default 'UNKNOWN',
  declared_height_cm smallint,
  batting_order smallint,
  is_captain boolean not null default false,
  is_wicketkeeper boolean not null default false,
  primary key (match_id, profile_id),
  check (batting_hand in ('LEFT', 'RIGHT', 'UNKNOWN'))
);

create table public.match_rules (
  match_id uuid primary key references public.matches(id) on delete cascade,
  wide_enabled boolean not null default true,
  no_ball_enabled boolean not null default true,
  front_foot_no_ball_enabled boolean not null default false,
  edge_review_enabled boolean not null default true,
  lbw_review_enabled boolean not null default true,
  full_toss_above_waist_is_no_ball boolean not null default true,
  bounced_above_shoulder_is_no_ball boolean not null default false,
  max_bouncers_per_over smallint,
  lateral_reach_multiplier numeric(4,2) not null default 0.60
);

create table public.scene_scans (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches(id) on delete cascade,
  camera_device_model varchar(150),
  capture_fps smallint,
  scan_duration_ms integer not null,
  ground_plane jsonb,
  pitch_direction jsonb,
  batsman_plane jsonb,
  overall_confidence numeric(4,3) not null,
  model_version varchar(100) not null,
  created_at timestamptz not null default now()
);

create table public.wicket_detections (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches(id) on delete cascade,
  scene_scan_id uuid references public.scene_scans(id) on delete set null,
  wicket_family varchar(40) not null,
  bounding_box jsonb not null,
  target_polygon jsonb not null,
  target_plane jsonb,
  ground_contact_line jsonb,
  object_confidence numeric(4,3) not null,
  temporal_stability numeric(4,3) not null,
  context_confidence numeric(4,3) not null,
  final_confidence numeric(4,3) not null,
  is_active boolean not null default true,
  model_version varchar(100) not null,
  detected_at timestamptz not null default now(),
  check (wicket_family in (
    'TRADITIONAL_STUMPS', 'CHAIR', 'BRICK_STACK', 'BOTTLE_STACK',
    'CONE_STACK', 'BUCKET', 'BAG_OR_OBJECT', 'WALL_TARGET',
    'UNKNOWN_PHYSICAL_OBJECT'
  ))
);

create table public.tosses (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null unique references public.matches(id) on delete cascade,
  called_by uuid references public.profiles(id),
  call_choice varchar(10) not null,
  result varchar(10) not null,
  winner_team_id uuid references public.teams(id),
  winner_decision varchar(10),
  created_at timestamptz not null default now(),
  check (call_choice in ('HEADS', 'TAILS')),
  check (result in ('HEADS', 'TAILS')),
  check (winner_decision in ('BAT', 'BOWL'))
);

create table public.innings (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches(id) on delete cascade,
  innings_number smallint not null,
  batting_team_id uuid not null references public.teams(id),
  bowling_team_id uuid not null references public.teams(id),
  total_runs smallint not null default 0,
  wickets smallint not null default 0,
  legal_balls smallint not null default 0,
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  unique (match_id, innings_number)
);

create table public.deliveries (
  id uuid primary key default gen_random_uuid(),
  client_event_id uuid not null unique,
  innings_id uuid not null references public.innings(id) on delete cascade,
  wicket_detection_id uuid references public.wicket_detections(id),
  over_number smallint not null,
  delivery_sequence smallint not null,
  legal_ball_number smallint,
  bowler_id uuid not null references public.profiles(id),
  striker_id uuid not null references public.profiles(id),
  non_striker_id uuid references public.profiles(id),
  runs_bat smallint not null default 0,
  runs_extras smallint not null default 0,
  is_wide boolean not null default false,
  is_no_ball boolean not null default false,
  is_bye boolean not null default false,
  is_leg_bye boolean not null default false,
  speed_kmph numeric(6,2),
  speed_confidence numeric(4,3),
  ball_tracking_confidence numeric(4,3),
  pose_tracking_confidence numeric(4,3),
  wicket_tracking_confidence numeric(4,3),
  created_at timestamptz not null default now(),
  unique (innings_id, over_number, delivery_sequence)
);

create table public.delivery_decisions (
  id uuid primary key default gen_random_uuid(),
  delivery_id uuid not null references public.deliveries(id) on delete cascade,
  decision_type varchar(30) not null,
  automated_result varchar(40),
  final_result varchar(40),
  confidence numeric(4,3),
  decision_status varchar(30) not null default 'REVIEW_RECOMMENDED',
  decision_source varchar(30) not null default 'AI_ASSIST',
  reviewer_id uuid references public.profiles(id),
  evidence jsonb,
  created_at timestamptz not null default now(),
  check (decision_type in ('WIDE', 'NO_BALL_HEIGHT', 'NO_BALL_FRONT_FOOT', 'EDGE', 'LBW', 'WICKET_HIT')),
  check (decision_status in ('AUTO_CALL', 'REVIEW_RECOMMENDED', 'INCONCLUSIVE', 'MANUAL_OVERRIDE'))
);

create table public.trajectory_snapshots (
  id uuid primary key default gen_random_uuid(),
  delivery_id uuid not null references public.deliveries(id) on delete cascade,
  sampling_fps smallint not null,
  points_compressed jsonb not null,
  model_version varchar(100) not null,
  created_at timestamptz not null default now()
);

create table public.replay_assets (
  id uuid primary key default gen_random_uuid(),
  delivery_id uuid not null references public.deliveries(id) on delete cascade,
  storage_path text not null,
  media_type varchar(20) not null,
  start_offset_ms integer,
  end_offset_ms integer,
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  check (media_type in ('VIDEO', 'IMAGE', 'AUDIO'))
);
```

## `002_indexes.sql`

```sql
create index idx_matches_created_by on public.matches(created_by);
create index idx_matches_status on public.matches(status);
create index idx_match_players_profile on public.match_players(profile_id);
create index idx_scene_scans_match on public.scene_scans(match_id);
create index idx_wicket_detections_match_active on public.wicket_detections(match_id, is_active);
create index idx_innings_match on public.innings(match_id);
create index idx_deliveries_innings_over on public.deliveries(innings_id, over_number, delivery_sequence);
create index idx_delivery_decisions_delivery on public.delivery_decisions(delivery_id);
create index idx_trajectory_snapshots_delivery on public.trajectory_snapshots(delivery_id);
create index idx_replay_assets_delivery on public.replay_assets(delivery_id);
```

## `003_rls.sql`

Enable RLS for every public table. Implement policies that enforce:

- Users read/update only their own profile.
- Match creators can create/update their own matches.
- Match participants can read match-related entities.
- Match creators, captains, and scorers can create deliveries/decisions.
- Replay media remains private by default and is accessed through signed URLs.
- No unrestricted public policies.

---

# 15. Environment File

```bash
# .env.example
EXPO_PUBLIC_SUPABASE_URL=
EXPO_PUBLIC_SUPABASE_ANON_KEY=

EXPO_PUBLIC_APP_ENV=development
EXPO_PUBLIC_ENABLE_MOCK_CV=true
EXPO_PUBLIC_ENABLE_EDGE_REVIEW=false
EXPO_PUBLIC_ENABLE_LBW_REVIEW=false
EXPO_PUBLIC_ENABLE_REPLAY_RECORDING=true

EXPO_PUBLIC_SENTRY_DSN=

# Never expose these to the mobile client:
# SUPABASE_SERVICE_ROLE_KEY=
# SUPABASE_SECRET_KEY=
```

If Supabase credentials are absent, show local development mode and use SQLite only. If model binaries are unavailable, use mock CV adapters and show a non-blocking development diagnostic.

---

# 16. Screen Requirements

Routes:

```text
/
/(auth)/sign-in
/(auth)/sign-up
/(tabs)
/(tabs)/matches
/(tabs)/profile
/match/create
/match/:matchId/auto-scan
/match/:matchId/toss
/match/:matchId/live
/match/:matchId/scorecard
/match/:matchId/review/:deliveryId
```

## Auto-scan screen

- Show camera preview.
- Scan for 1–3 seconds.
- Display scanned object/wicket overlay.
- Show progress and confidence.
- Retry scan button.
- Continue button enabled only at confidence >= 0.70.
- Offer score-only mode as fallback.

## Live screen

- Camera feed and physical-wicket overlay.
- Batsman/ball confidence indicators.
- Ball trajectory overlay.
- Current score/over/bowler/batsman.
- Manual scoring controls: dot, 1, 2, 3, 4, 6, wide, no-ball, bye, leg-bye, wicket, undo.
- AI decision banner with confidence.
- Review entry point.
- Manual scoring always functional.

## Review screen

- Show ball path, wicket target, impact estimate, and confidence.
- Edge: show trajectory deviation and audio evidence summary when enabled.
- LBW: show trajectory projection plus uncertainty cone.
- Final actions: `OUT`, `NOT OUT`, `NO DECISION`.
- Persist human final decision and AI evidence.

---

# 17. Dataset and Model Plan

## Required models

| Model | Classes/output | MVP status |
|---|---|---:|
| Ball detector | `cricket_ball` | Required |
| Scene object detector | stumps, chair, bottle, brick, cone, bucket, bag, wall target, bat, person | Required |
| Wicket context scorer | probability that candidate acts as wicket | Required |
| Pose model | 33 human landmarks | Required; pretrained |
| Bat detector | bat box/polygon | Release 2 |
| Audio contact classifier | impact/noise probability | Optional Release 2 |

## Dataset labels

```yaml
object_classes:
  - cricket_ball
  - cricket_bat
  - traditional_stumps
  - chair
  - bottle
  - brick
  - cone
  - bucket
  - bag
  - wall_target
  - batsman
  - bowler

context_labels:
  - is_wicket: true
  - is_wicket: false
  - wicket_family
  - wicket_target_polygon
  - wicket_behind_batsman: true
  - wicket_behind_batsman: false
```

## Collection targets

| Dataset part | Early MVP | Production target |
|---|---:|---:|
| Real gully-cricket clips | 1,500 | 10,000+ |
| Ball instances | 15,000 | 100,000+ |
| Wicket-role examples | 5,000 | 40,000+ |
| Negative chair/bottle/brick examples | 5,000 | 30,000+ |
| Phone models | 8 | 30+ |

Split datasets by location, device, and recording session—not random adjacent frames.

---

# 18. Development Roadmap

1. **Foundation:** monorepo, TypeScript, navigation, lint/test setup.
2. **Data:** Supabase schema/RLS, SQLite schema, auth/local mode.
3. **Scoring:** teams, matches, innings, toss, score engine, scorecard, undo.
4. **Offline:** local outbox, idempotent sync, retry logic.
5. **Scene scan:** mock CV contracts and zero-touch wicket-recognition UX.
6. **Camera:** live camera shell, overlays, performance profiler.
7. **Ball tracking:** detector/tracker contracts, trajectory buffer, mock pipeline.
8. **Rules:** wide, height no-ball, wicket-hit assistance.
9. **Review:** replay UI, edge evidence, LBW projection domain logic.
10. **Native ML:** VisionCamera, MediaPipe, TFLite/ONNX adapters.
11. **Training:** real-world dataset, quantized models, benchmark gates.
12. **Hardening:** CI/CD, telemetry, privacy, Android device test matrix.

Do not start advanced LBW/UltraEdge work before offline scoring, wicket scan, and ball tracking foundations work.

---

# 19. Tests and Acceptance Criteria

## Unit tests

- Score calculations, legal-ball handling, extras, wickets, undo
- Toss state transitions
- Wicket candidate scoring/selection
- Wide/no-ball rules
- Edge and LBW result states
- Ring buffer behavior
- Sync retry/idempotency

## Integration tests

- Create match -> auto scan mock wicket -> toss -> live scoring -> scorecard
- Offline delivery -> queued event -> successful remote sync
- Manual override after AI decision
- Low-confidence scan -> score-only fallback

## Completion checklist

- [ ] Repository structure exists.
- [ ] App runs in mock CV/local-only mode.
- [ ] TypeScript strict mode passes.
- [ ] Lint and unit tests pass.
- [ ] Supabase schema, indexes, and RLS migrations exist.
- [ ] `.env.example` includes no secret credentials.
- [ ] Zero-touch physical wicket detection is implemented in normal UX.
- [ ] Low-confidence wicket scan disables automated umpiring and offers score-only mode.
- [ ] Manual scoring works if camera/CV fails.
- [ ] SQLite outbox is durable and idempotent.
- [ ] Raw camera data is not placed in React/Zustand state.
- [ ] Typed arrays/ring buffers are used for high-rate data.
- [ ] Object clustering uses spatial hashing or equivalent.
- [ ] Edge/LBW operate only on short bounded windows and require review.
- [ ] README includes setup, commands, architecture, model links, and limitations.

---

# 20. Commands

```bash
# Create application
npx create-expo-app@latest gully-umpire --template blank-typescript
cd gully-umpire

# Install core packages
npx expo install expo-router expo-sqlite expo-secure-store expo-av expo-file-system
npm install @supabase/supabase-js zustand @tanstack/react-query
npm install react-native-vision-camera @shopify/react-native-skia react-native-worklets-core

# Setup Supabase
npx supabase init
npx supabase login
npx supabase link --project-ref YOUR_PROJECT_REF
npx supabase db push

# Environment
cp .env.example .env

# Android development build
cd apps/mobile
npx expo prebuild
npx expo run:android

# Development server
npx expo start --dev-client

# Quality checks
npm run lint
npm run typecheck
npm run test
```

---

# 21. Privacy and Security

- Obtain consent before audio/video replay capture.
- Store compact delivery metadata by default.
- Keep replay media opt-in or host-controlled.
- Add automatic expiry/deletion for replay assets.
- Use signed Supabase Storage URLs.
- Apply RLS to every public table.
- Never store Supabase service-role keys in the mobile app.
- Offer match/media deletion.
- Clearly label AI calls as assistance and permit override.
