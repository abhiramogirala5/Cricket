# Gully Umpire — UML Diagrams

**Version:** 1.0  
**Notation:** Mermaid UML-compatible diagrams  
**How to render:** GitHub, GitLab, many Markdown editors, Mermaid Live Editor, or VS Code with a Mermaid extension.

> Mermaid is used so the diagrams remain editable as text. For formal deliverables, render this file to SVG/PDF/PNG through a Mermaid-compatible tool.

---

## Diagram index

1. System context diagram
2. Use-case diagram
3. Component diagram
4. Mobile Clean Architecture diagram
5. Computer-vision pipeline activity diagram
6. Live delivery sequence diagram
7. Offline synchronization sequence diagram
8. Match lifecycle state diagram
9. Delivery decision state diagram
10. Database entity-relationship diagram
11. Class diagram: match and scoring domain
12. Class diagram: umpiring and vision domain
13. Class diagram: repositories and adapters
14. Deployment diagram
15. Calibration activity diagram
16. Edge/LBW review sequence diagram
17. Event-driven integration diagram
18. User authentication sequence diagram
19. Media upload state diagram

---

## 1. System context diagram

```mermaid
flowchart TB
    Player[Player / Scorer]
    Umpire[Umpire / Match Owner]
    Spectator[Spectator]
    Mobile[Gully Umpire Mobile App]
    Camera[Phone Camera and Microphone]
    DeviceML[On-device CV and ML Runtime]
    LocalDB[(Local SQLite Database)]
    Supabase[Supabase Platform]
    Push[Push Notification Provider]
    AppStore[App Store / Google Play]

    Player --> Mobile
    Umpire --> Mobile
    Spectator --> Mobile
    Camera --> Mobile
    Mobile <--> DeviceML
    Mobile <--> LocalDB
    Mobile <--> Supabase
    Supabase --> Push
    Push --> Mobile
    AppStore --> Mobile
```

### Context responsibilities

| Actor/system | Responsibility |
|---|---|
| Player | Participates in match; may view scorecards, clips, and statistics |
| Umpire / scorer | Sets up match, calibrates wicket, reviews or overrides calls |
| Spectator | Receives live score and shared match information |
| Mobile app | Captures delivery, evaluates assistance rules, scores, syncs data |
| On-device CV runtime | Detects/tracks ball and batsman; provides confidence values |
| Supabase | Authentication, persistence, storage, realtime synchronization |

---

## 2. Use-case diagram

```mermaid
flowchart LR
    Owner[Match Owner / Scorer]
    Player[Player]
    Viewer[Viewer / Spectator]
    Admin[System Administrator]

    subgraph GullyUmpire[Gully Umpire Application]
        UC1((Sign in / Sign up))
        UC2((Create match))
        UC3((Configure local rules))
        UC4((Add teams and players))
        UC5((Auto-scan physical wicket))
        UC6((Start live delivery capture))
        UC7((Track ball and batsman))
        UC8((Receive wide / no-ball assistance))
        UC9((Review LBW / edge candidate))
        UC10((Override decision))
        UC11((Record runs, extras, wickets))
        UC12((View live scorecard))
        UC13((View replay and graphics))
        UC14((Upload clips / synchronize match))
        UC15((View player statistics))
        UC16((Share scorecard / highlights))
        UC17((Delete account or data))
        UC18((Monitor failures and usage))
    end

    Owner --> UC1
    Owner --> UC2
    Owner --> UC3
    Owner --> UC4
    Owner --> UC5
    Owner --> UC6
    Owner --> UC8
    Owner --> UC9
    Owner --> UC10
    Owner --> UC11
    Owner --> UC12
    Owner --> UC13
    Owner --> UC14
    Owner --> UC15
    Owner --> UC16
    Owner --> UC17

    Player --> UC12
    Player --> UC13
    Player --> UC15
    Player --> UC16

    Viewer --> UC12
    Viewer --> UC13

    UC6 --> UC7
    UC7 --> UC8
    UC7 --> UC9
    UC8 --> UC11
    UC9 --> UC11
    UC10 --> UC11

    Admin --> UC18
```

---

## 3. Component diagram

```mermaid
flowchart TB
    subgraph MobileApp[Mobile App — React Native]
        UI[Presentation Layer
Live Camera, Scorecard, Replay, Settings]
        App[Application Layer
Use Cases, Commands, Queries]
        Domain[Domain Layer
Match Rules, Scoring, Decision Engine]
        Repos[Repository Interfaces]
        Local[Local Persistence Adapter
SQLite / WatermelonDB]
        Sync[Sync and Outbox Adapter]
        Native[Native Vision Adapter
Kotlin / Swift / C++]
        CameraAdapter[Camera and Audio Adapter]
        Cloud[Supabase Adapter]
    end

    subgraph NativeVision[On-device Vision Runtime]
        Detector[Ball Detector]
        Pose[Pose Estimator]
        Tracker[Kalman / Multi-object Tracker]
        Audio[Audio Transient Analyzer]
        Renderer[Trajectory Graphics Renderer]
    end

    subgraph SupabaseBackend[Supabase Backend]
        Auth[Supabase Auth]
        Postgres[(PostgreSQL + RLS)]
        Realtime[Realtime Channels]
        Storage[Storage Buckets]
        Edge[Edge Functions]
    end

    UI --> App
    App --> Domain
    App --> Repos
    Repos --> Local
    Repos --> Sync
    Sync --> Cloud
    Cloud --> Auth
    Cloud --> Postgres
    Cloud --> Realtime
    Cloud --> Storage
    Cloud --> Edge

    CameraAdapter --> Native
    Native --> Detector
    Native --> Pose
    Native --> Tracker
    Native --> Audio
    Native --> Renderer
    Native --> Domain
    UI --> Renderer
```

---

## 4. Mobile Clean Architecture diagram

```mermaid
flowchart TB
    subgraph Presentation[Presentation]
        Screens[Screens / Routes]
        ViewModels[View Models / Hooks]
        Widgets[Components / Overlays]
    end

    subgraph Application[Application]
        StartDelivery[Start Delivery Use Case]
        RecordDelivery[Record Delivery Use Case]
        SyncMatch[Sync Match Use Case]
        ReviewDecision[Review Decision Use Case]
        SetupMatch[Setup Match Use Case]
    end

    subgraph Domain[Domain]
        MatchAggregate[Match Aggregate]
        Scoring[Score Calculator]
        Rules[Wide / No-ball / LBW Rules]
        Decisions[Decision Engine]
        Trajectory[Trajectory Model]
        Events[Domain Events]
    end

    subgraph Ports[Ports / Interfaces]
        MatchRepo[Match Repository]
        DeliveryRepo[Delivery Repository]
        MediaRepo[Media Repository]
        VisionPort[Vision Service]
        Clock[Clock]
    end

    subgraph Infrastructure[Infrastructure]
        SQLite[SQLite Adapter]
        SupabaseAdapter[Supabase Adapter]
        Camera[Camera Adapter]
        ML[ML Runtime Adapter]
        StorageAdapter[Storage Adapter]
        Notification[Notification Adapter]
    end

    Screens --> ViewModels
    ViewModels --> Widgets
    ViewModels --> StartDelivery
    ViewModels --> RecordDelivery
    ViewModels --> ReviewDecision
    ViewModels --> SetupMatch

    StartDelivery --> VisionPort
    RecordDelivery --> MatchAggregate
    RecordDelivery --> DeliveryRepo
    ReviewDecision --> Decisions
    SyncMatch --> MatchRepo

    MatchAggregate --> Scoring
    MatchAggregate --> Rules
    Decisions --> Trajectory
    MatchAggregate --> Events

    MatchRepo --> SQLite
    MatchRepo --> SupabaseAdapter
    DeliveryRepo --> SQLite
    DeliveryRepo --> SupabaseAdapter
    MediaRepo --> StorageAdapter
    VisionPort --> Camera
    VisionPort --> ML
    Notification --> SupabaseAdapter
```

---

## 5. Computer-vision pipeline activity diagram

```mermaid
flowchart TD
    Start([Delivery capture starts]) --> Capture[Capture timestamped camera frame and audio buffer]
    Capture --> Queue{Frame queue has capacity?}
    Queue -- No --> Drop[Drop stale frame; retain newest frame]
    Drop --> Capture
    Queue -- Yes --> Preprocess[Crop pitch ROI; resize; normalize]
    Preprocess --> Cadence{Detection frame?}

    Cadence -- Yes --> BallDetect[Run quantized ball detector]
    BallDetect --> DetectionFound{Ball detected?}
    DetectionFound -- Yes --> TrackUpdate[Update tracker with observation]
    DetectionFound -- No --> Predict[Predict location with Kalman filter]

    Cadence -- No --> Predict
    TrackUpdate --> PoseCadence{Pose frame?}
    Predict --> PoseCadence

    PoseCadence -- Yes --> Pose[Estimate batsman pose / position]
    PoseCadence -- No --> WicketPlane
    Pose --> WicketPlane[Read calibrated wicket plane]

    WicketPlane --> CriticalEvent{Release, bounce, impact, or crossing event?}
    CriticalEvent -- No --> Render[Render trail and confidence overlay]
    Render --> Capture

    CriticalEvent -- Yes --> Evaluate[Evaluate rule candidates]
    Evaluate --> Confidence{Confidence above threshold?}
    Confidence -- Yes --> Candidate[Create automatic candidate decision]
    Confidence -- No --> Review[Create REVIEW_REQUIRED decision]
    Candidate --> Persist[Persist local delivery evidence]
    Review --> Persist
    Persist --> End([Delivery completed])
```

---

## 6. Live delivery sequence diagram

```mermaid
sequenceDiagram
    autonumber
    actor Scorer as Scorer/Umpire
    participant UI as Mobile UI
    participant Camera as Camera Service
    participant Vision as Native Vision Pipeline
    participant Rules as Decision Engine
    participant Local as Local Database
    participant Outbox as Sync Outbox
    participant Realtime as Supabase Realtime
    participant Cloud as Supabase PostgreSQL

    Scorer->>UI: Tap “Start ball”
    UI->>Camera: Start capture / mark delivery start
    loop Frames until ball is dead
        Camera->>Vision: Timestamped frame + audio samples
        Vision->>Vision: Detect or predict ball position
        Vision->>Vision: Update batsman pose / wicket geometry
        Vision-->>UI: Overlay state (trajectory/confidence)
    end
    Scorer->>UI: Mark ball dead or app detects event
    UI->>Rules: Evaluate delivery evidence
    Rules-->>UI: Candidate decision + confidence
    alt High confidence
        UI->>Local: Save delivery + automatic decision
    else Low confidence or occlusion
        UI->>Local: Save REVIEW_REQUIRED candidate
        UI-->>Scorer: Show replay and review controls
        Scorer->>UI: Confirm or override decision
        UI->>Local: Save reviewed/manual decision
    end
    Local->>Outbox: Enqueue idempotent sync operation
    Outbox->>Cloud: Upsert match/delivery/decision when online
    Cloud-->>Realtime: Database change event
    Realtime-->>UI: Live score refresh on other devices
```

---

## 7. Offline synchronization sequence diagram

```mermaid
sequenceDiagram
    autonumber
    participant UI as Mobile UI
    participant Local as SQLite Database
    participant Outbox as Outbox Queue
    participant Network as Connectivity Monitor
    participant API as Supabase API
    participant DB as PostgreSQL

    UI->>Local: Commit delivery transaction
    Local->>Outbox: Add operation with client_operation_id
    Outbox-->>UI: Local operation complete

    Network-->>Outbox: Offline
    Note over Outbox: Retain queued operation; retry later

    Network-->>Outbox: Connection restored
    Outbox->>API: Send idempotent upsert(operation ID)
    API->>DB: Apply transaction + RLS validation
    DB-->>API: Success / conflict response

    alt Success
        API-->>Outbox: Acknowledgement
        Outbox->>Local: Mark operation synced
    else Transient failure
        API-->>Outbox: Retryable error
        Outbox->>Outbox: Backoff and retry
    else Conflict
        API-->>Outbox: Conflict details
        Outbox->>Local: Mark needs-resolution
        Local-->>UI: Show scorer resolution UI
    end
```

---

## 8. Match lifecycle state diagram

```mermaid
stateDiagram-v2
    [*] --> Setup
    Setup --> Ready: teams + rules configured
    Ready --> Live: start match
    Live --> Paused: pause match
    Paused --> Live: resume match
    Live --> InningsBreak: innings completed
    InningsBreak --> Live: next innings started
    Live --> Completed: result confirmed
    Paused --> Abandoned: abandon match
    Live --> Abandoned: abandon match
    Setup --> Abandoned: cancel before start
    Completed --> Archived: archive / sync completed
    Abandoned --> Archived: archive partial match
    Archived --> [*]
```

---

## 9. Delivery decision state diagram

```mermaid
stateDiagram-v2
    [*] --> Pending
    Pending --> Tracking: ball capture begins
    Tracking --> EvidenceCollected: delivery ends
    EvidenceCollected --> Candidate: vision/rules evaluated

    Candidate --> AutomaticConfirmed: confidence >= threshold
    Candidate --> ReviewRequired: confidence < threshold
    Candidate --> ReviewRequired: occlusion / calibration invalid

    ReviewRequired --> ManualConfirmed: umpire confirms
    ReviewRequired --> Overridden: umpire changes result
    AutomaticConfirmed --> Overridden: later manual correction

    AutomaticConfirmed --> Persisted
    ManualConfirmed --> Persisted
    Overridden --> Persisted
    Persisted --> Synced: cloud acknowledgement
    Persisted --> [*]: retained locally/offline
    Synced --> [*]
```

---

## 10. Database entity-relationship diagram

```mermaid
erDiagram
    AUTH_USERS ||--|| PROFILES : has
    AUTH_USERS ||--o{ PLAYERS : owns
    AUTH_USERS ||--o{ MATCHES : creates
    AUTH_USERS ||--o{ RULE_PROFILES : owns

    MATCHES ||--o{ INNINGS : contains
    MATCHES ||--o{ MATCH_PARTICIPANTS : includes
    MATCHES ||--o{ MEDIA_ASSETS : owns
    RULE_PROFILES ||--o{ MATCHES : configures

    PLAYERS ||--o{ MATCH_PARTICIPANTS : joins
    PLAYERS ||--o{ DELIVERIES : striker
    PLAYERS ||--o{ DELIVERIES : bowler

    INNINGS ||--o{ DELIVERIES : contains
    DELIVERIES ||--o{ DELIVERY_DECISIONS : has
    DELIVERIES ||--o{ MEDIA_ASSETS : references

    AUTH_USERS {
        uuid id PK
        text email
    }

    PROFILES {
        uuid id PK,FK
        text display_name
        text avatar_path
        timestamptz created_at
    }

    PLAYERS {
        uuid id PK
        uuid owner_user_id FK
        text display_name
        text dominant_hand
        smallint declared_height_cm
    }

    RULE_PROFILES {
        uuid id PK
        uuid owner_user_id FK
        text name
        text ball_type
        text wicket_mode
        jsonb settings
        int version
    }

    MATCHES {
        uuid id PK
        uuid owner_user_id FK
        uuid rule_profile_id FK
        text name
        text status
        smallint format_overs
        timestamptz started_at
        timestamptz completed_at
    }

    MATCH_PARTICIPANTS {
        uuid id PK
        uuid match_id FK
        uuid player_id FK
        text team_side
        text role
    }

    INNINGS {
        uuid id PK
        uuid match_id FK
        int innings_number
        int total_runs
        int wickets_lost
        int legal_balls
        text status
    }

    DELIVERIES {
        uuid id PK
        uuid innings_id FK
        int sequence_no
        int legal_ball_no
        uuid striker_player_id FK
        uuid bowler_player_id FK
        int runs_bat
        int extras_wide
        int extras_no_ball
        boolean is_legal_ball
        text decision_status
    }

    DELIVERY_DECISIONS {
        uuid id PK
        uuid delivery_id FK
        text decision_type
        text decision_value
        numeric confidence
        jsonb evidence
        text model_version
        text source
    }

    MEDIA_ASSETS {
        uuid id PK
        uuid owner_user_id FK
        uuid match_id FK
        uuid delivery_id FK
        text storage_path
        text media_type
        text upload_status
    }
```

---

## 11. Class diagram: match and scoring domain

```mermaid
classDiagram
    class Match {
        +UUID id
        +UUID ownerUserId
        +String name
        +MatchStatus status
        +Integer formatOvers
        +start()
        +pause()
        +resume()
        +complete()
        +abandon()
    }

    class Innings {
        +UUID id
        +Integer inningsNumber
        +Integer totalRuns
        +Integer wicketsLost
        +Integer legalBalls
        +addDelivery(delivery)
        +score()
        +overs()
    }

    class Delivery {
        +UUID id
        +Integer sequenceNo
        +Integer legalBallNo
        +Integer runsBat
        +Integer extrasWide
        +Integer extrasNoBall
        +Boolean isLegalBall
        +DeliveryStatus status
        +totalRuns()
    }

    class DeliveryDecision {
        +UUID id
        +DecisionType type
        +DecisionValue value
        +Decimal confidence
        +DecisionSource source
        +Json evidence
        +supersede(previousDecision)
    }

    class ScoreCalculator {
        +applyDelivery(innings, delivery)
        +isLegalBall(delivery)
        +calculateTotal(delivery)
        +calculateOvers(legalBalls)
    }

    class RuleProfile {
        +UUID id
        +String name
        +BallType ballType
        +WicketMode wicketMode
        +Boolean lbwEnabled
        +Json settings
        +getWideThreshold()
        +getBouncerThreshold()
    }

    class Player {
        +UUID id
        +String displayName
        +Hand dominantHand
        +Integer declaredHeightCm
    }

    Match "1" --> "1..*" Innings : contains
    Match "1" --> "1" RuleProfile : uses
    Innings "1" --> "0..*" Delivery : contains
    Delivery "1" --> "0..*" DeliveryDecision : has
    Delivery --> Player : striker
    Delivery --> Player : bowler
    ScoreCalculator ..> Innings : updates
    ScoreCalculator ..> Delivery : evaluates
```

---

## 12. Class diagram: umpiring and vision domain

```mermaid
classDiagram
    class VisionService {
        <<interface>>
        +startDeliveryCapture(context) VisionSession
        +stopDeliveryCapture() DeliveryEvidence
        +calibrateWicket(input) WicketCalibration
    }

    class VisionSession {
        +UUID sessionId
        +onFrame(frame)
        +onAudio(samples)
        +getOverlayState() OverlayState
        +complete() DeliveryEvidence
    }

    class BallDetector {
        <<interface>>
        +detect(frame) BallDetection[]
    }

    class PoseEstimator {
        <<interface>>
        +estimate(frame) BatsmanPose
    }

    class BallTracker {
        +TrackState state
        +update(detection, timestamp)
        +predict(timestamp) BallObservation
        +getTrajectory() BallTrajectory
    }

    class KalmanFilter {
        +Vector state
        +Matrix covariance
        +predict(deltaTime)
        +update(measurement)
    }

    class DecisionEngine {
        +evaluate(evidence, ruleProfile) DecisionResult
    }

    class WideRule {
        +evaluate(trajectory, batsman, wicket, rules) RuleResult
    }

    class NoBallRule {
        +evaluate(trajectory, batsman, rules) RuleResult
    }

    class LbwRule {
        +evaluate(trajectory, batsman, wicket, edge) RuleResult
    }

    class EdgeAnalyzer {
        +findCandidate(audio, batPose, ballTrack) EdgeEvidence
    }

    class DeliveryEvidence {
        +BallTrajectory trajectory
        +BatsmanPose batsmanPose
        +WicketCalibration wicket
        +AudioEvidence audio
        +Float qualityScore
    }

    VisionService --> VisionSession
    VisionSession --> BallDetector
    VisionSession --> PoseEstimator
    VisionSession --> BallTracker
    BallTracker --> KalmanFilter
    VisionSession --> DeliveryEvidence
    DecisionEngine --> WideRule
    DecisionEngine --> NoBallRule
    DecisionEngine --> LbwRule
    DecisionEngine --> EdgeAnalyzer
    DecisionEngine --> DeliveryEvidence
```

---

## 13. Class diagram: repositories and adapters

```mermaid
classDiagram
    class MatchRepository {
        <<interface>>
        +create(match) Match
        +getById(id) Match
        +save(match) void
        +listByOwner(ownerId) Match[]
    }

    class DeliveryRepository {
        <<interface>>
        +append(delivery) Delivery
        +findByInnings(inningsId) Delivery[]
        +saveDecision(decision) void
    }

    class MediaRepository {
        <<interface>>
        +queue(asset) void
        +getPending() MediaAsset[]
        +markUploaded(assetId) void
    }

    class LocalMatchRepository {
        +SQLiteDatabase db
        +create(match) Match
        +save(match) void
    }

    class SupabaseMatchRepository {
        +SupabaseClient client
        +create(match) Match
        +save(match) void
    }

    class SyncCoordinator {
        +OutboxRepository outbox
        +NetworkMonitor network
        +syncPending()
        +resolveConflict(conflict)
    }

    class OutboxRepository {
        <<interface>>
        +enqueue(operation) void
        +nextPending() SyncOperation
        +markSucceeded(id) void
        +markFailed(id, error) void
    }

    MatchRepository <|.. LocalMatchRepository
    MatchRepository <|.. SupabaseMatchRepository
    SyncCoordinator --> OutboxRepository
    SyncCoordinator --> SupabaseMatchRepository
    LocalMatchRepository --> OutboxRepository : records writes
```

---

## 14. Deployment diagram

```mermaid
flowchart TB
    subgraph UserDevice[Android / iOS Device]
        RN[React Native Application]
        CameraX[CameraX / AVFoundation]
        NativeML[Native ML Runtime
TFLite / Core ML / CPU delegate]
        LocalStore[(SQLite / Local Media Cache)]
        SecureStore[Secure Storage]
        RN --> CameraX
        RN --> NativeML
        RN --> LocalStore
        RN --> SecureStore
    end

    subgraph SupabaseCloud[Supabase Cloud]
        Auth[Auth]
        REST[PostgREST / GraphQL if enabled]
        DB[(PostgreSQL)]
        RT[Realtime WebSocket]
        Bucket[Object Storage]
        Functions[Edge Functions]
        Auth --> DB
        REST --> DB
        RT --> DB
        Functions --> DB
        Functions --> Bucket
    end

    subgraph External[External Managed Services]
        FCM[FCM / APNs]
        Monitoring[Sentry / Crash Reporting]
        Analytics[Product Analytics]
    end

    RN -->|HTTPS| Auth
    RN -->|HTTPS| REST
    RN <-->|WebSocket| RT
    RN -->|Signed upload / HTTPS| Bucket
    Functions --> FCM
    RN --> Monitoring
    RN --> Analytics
```

---

## 15. Wicket and camera calibration activity diagram

```mermaid
flowchart TD
    Start([Open calibration]) --> SelectMode{Choose wicket mode}
    SelectMode -->|Stumps| Stumps[Detect or manually confirm stumps]
    SelectMode -->|Chair| Chair[Mark chair/wicket reference edges]
    SelectMode -->|Custom| Custom[Tap four points for virtual wicket]

    Stumps --> Pitch[Mark pitch/reference line]
    Chair --> Pitch
    Custom --> Pitch

    Pitch --> Height{Known player height available?}
    Height -->|Yes| UseHeight[Use saved/calibrated height]
    Height -->|No| EnterHeight[Ask player/scorer to enter approximate height]

    UseHeight --> Validate[Validate geometric consistency]
    EnterHeight --> Validate
    Validate --> Valid{Calibration confidence sufficient?}
    Valid -->|No| Reposition[Ask user to reposition camera and retry]
    Reposition --> SelectMode
    Valid -->|Yes| Save[Save wicket plane and calibration profile]
    Save --> Ready([Ready for live delivery capture])
```

---

## 16. LBW and edge review sequence diagram

```mermaid
sequenceDiagram
    autonumber
    actor Umpire
    participant UI as Review UI
    participant Evidence as Delivery Evidence
    participant Edge as Edge Analyzer
    participant Lbw as LBW Rule Engine
    participant Wicket as Wicket Geometry
    participant Local as Local Database

    Umpire->>UI: Open delivery review
    UI->>Evidence: Load trajectory, pose, audio, calibration
    Evidence-->>UI: Render slow-motion replay + trail

    UI->>Edge: Analyze candidate contact window
    Edge-->>UI: Edge confidence + timestamps

    UI->>Lbw: Evaluate projected path
    Lbw->>Wicket: Check virtual wicket intersection
    Wicket-->>Lbw: Hit/miss geometry
    Lbw-->>UI: LBW candidate + confidence + reasons

    alt Evidence is strong
        UI-->>Umpire: Suggest OUT / NOT OUT
    else Evidence is weak
        UI-->>Umpire: REVIEW REQUIRED
    end

    Umpire->>UI: Confirm or override
    UI->>Local: Save manual/review decision with audit trail
```

---

## 17. Event-driven integration diagram

```mermaid
flowchart LR
    Capture[Delivery Capture] --> E1((delivery.completed))
    E1 --> Persist[Persist Delivery Locally]
    E1 --> Replay[Mark Replay Clip]
    E1 --> Rules[Evaluate Decision Rules]

    Rules --> E2((decision.created))
    E2 --> UI[Update Live UI]
    E2 --> Score[Apply Score Update]
    E2 --> Audit[Create Audit Record]

    Score --> E3((score.updated))
    E3 --> LocalOutbox[Queue Offline Sync]
    E3 --> Spectators[Publish Realtime Score]

    LocalOutbox --> CloudWrite[Cloud Upsert]
    CloudWrite --> E4((delivery.synced))
    E4 --> Media[Queue Media Upload]
    E4 --> Analytics[Refresh Async Analytics]

    Media --> E5((media.uploaded))
    E5 --> Share[Enable Share Link / Highlight]
```

---

## 18. Authentication sequence diagram

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant App as Mobile App
    participant Auth as Supabase Auth
    participant DB as PostgreSQL / Profiles
    participant Secure as Device Secure Storage

    User->>App: Choose phone OTP / email sign-in
    App->>Auth: Request OTP / sign-in
    Auth-->>User: Deliver OTP or email link
    User->>App: Enter OTP / return from link
    App->>Auth: Verify credentials
    Auth-->>App: JWT access token + refresh token
    App->>Secure: Store session securely
    App->>DB: Read/create application profile (RLS)
    DB-->>App: Profile and preferences
    App-->>User: Signed-in session
```

---

## 19. Media upload state diagram

```mermaid
stateDiagram-v2
    [*] --> LocalOnly: clip created
    LocalOnly --> Queued: user enables upload / auto-sync permitted
    Queued --> Uploading: network available
    Uploading --> Ready: upload succeeds
    Uploading --> Failed: non-retryable failure
    Uploading --> Queued: retryable failure
    Failed --> Queued: user retries
    Ready --> Archived: retention policy / local cleanup
    LocalOnly --> Deleted: user deletes local clip
    Queued --> Deleted: user cancels upload
    Ready --> Deleted: user deletes cloud media
    Archived --> [*]
    Deleted --> [*]
```

---

## Recommended diagram usage

| Diagram | Primary audience | Purpose |
|---|---|---|
| System context | Founder, product, stakeholders | Explains the product boundary and external systems |
| Use cases | Product, UX, QA | Defines supported user outcomes |
| Components | Technical leads | Shows major software modules and integrations |
| Clean Architecture | Mobile developers | Defines dependency and implementation boundaries |
| Vision activity | CV/ML and native developers | Defines real-time inference flow |
| Sequences | Mobile/backend developers | Defines interaction timing and ownership |
| State diagrams | Developers, QA | Defines legal transitions and test cases |
| ERD | Backend developers | Defines database relationships |
| Deployment | DevOps, security | Defines runtime topology and trust boundaries |

## Notes for implementation

- Treat Mermaid diagrams as living architecture artifacts. Update them with every meaningful change to modules, tables, event names, or deployment boundaries.
- Live decisions must remain on-device; network latency or cloud availability must never block a ball result.
- A `REVIEW_REQUIRED` state is mandatory for responsible behavior when visual/audio confidence is inadequate.
- Wicket calibration should be an explicit user flow because informal cricket wickets can be stumps, chairs, bricks, or a virtual target.
- Keep event names versioned and stable once other modules or clients depend on them.
