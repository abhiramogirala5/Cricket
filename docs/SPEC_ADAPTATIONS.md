# How the original specification was adapted

The inputs were `docs/reference/GULLY_UMPIRE_COMPLETE_AGENT_READY_SPEC.md` (v3.0), `gully_umpire_architecture.md` (v1.1)
and `gully_umpire_uml_diagrams.md`. They describe a React Native + Supabase app. This repository implements the same
product with the stack requested for this build: **Python backend, Flutter frontend, separate folders, env files for keys.**

The product behaviour, the computer-vision contracts, the decision statuses, the zero-touch wicket recognition flow,
the low-end device policy and the offline-first rules are kept. The sections below list every place where the
implementation intentionally differs, and why.

## 1. Stack mapping

| Original | This repository | Notes |
|---|---|---|
| React Native + Expo Router | **Flutter** + `go_router` | `lib/features/*` replace `app/*` routes 1:1 (see §4) |
| Zustand + TanStack Query | **Riverpod** (`flutter_riverpod`) | local state and async/server state in one model |
| Expo SQLite + outbox | **`sqflite`** + outbox table | same durable, idempotent outbox semantics |
| Supabase Auth | **FastAPI** JWT auth (access + rotating refresh tokens, Argon2id) | tokens kept in `flutter_secure_storage` |
| Supabase Postgres + RLS | **Supabase PostgreSQL** (or any PostgreSQL 16) **+ SQLAlchemy 2 + Alembic**; authorisation in the service layer (every query scoped by `owner_id`) | the API connects with `DATABASE_URL` (Supabase direct or session-pooler string, port 5432). Ownership is enforced in code and covered by tests; migration `0002` turns row-level security **on** for every table with no policies, so Supabase's Data API and `anon` key cannot read anything while the API (table owner) is unaffected |
| Supabase Realtime | not in v1 | no spectator mode yet |
| Supabase Storage + signed URLs | **Supabase Storage**, private bucket, signed URLs issued by the API (`/replays`, API_CONTRACT §8) | the phone never holds a Supabase key; the service key is only in `backend/.env` |
| VisionCamera frame processors | the `camera` plug-in (Android) hands brightness frames to a pure-Dart tracker that runs in its own isolate (`cv/live`, `cv/vision`, `cv/tracking`) | no ball model: the ball is found by motion, followed by several Kalman-filter paths and chosen by how ball-like the path is (§5) |
| MediaPipe / TFLite / ONNX adapters | Google ML Kit **pose** model for the batter only (`google_mlkit_pose_detection`); interfaces and **simulated adapters** remain for development (`DEV_SIMULATE_CV`) | the ball, wicket and audio models of the spec were not trained; the wicket is marked by the umpire on the camera picture |
| Sentry (mobile) | Sentry (backend, optional via `SENTRY_DSN`) | mobile crash reporting is future work |
| Turborepo | plain monorepo: `backend/`, `frontend/`, `docs/` | two toolchains, nothing for Turbo to orchestrate |
| `EXPO_PUBLIC_*` env | `frontend/.env` (via `flutter_dotenv`, **non-secret values only**) | anything bundled into a mobile app can be extracted, so secrets live only in `backend/.env` |

## 2. Data-model changes (vs. spec §14 / UML ERD)

| Change | Reason |
|---|---|
| `profiles` → `users` (auth + profile in one table) | there is no Supabase `auth.users` |
| **Players are roster entries (`players`), not user accounts.** `match_players`, `deliveries.bowler_id/striker_id/non_striker_id`, `tosses.called_by` reference `players` | gully-cricket players do not have accounts. The architecture doc and UML ERD already model a separate `PLAYERS` table; the spec's `profile_id` references were not workable |
| `team_members` removed (reusable team rosters) | deferred; per-match rosters live in `match_players` |
| `owner_id` on players, teams, matches | single-owner model (no scorer/captain accounts) replaces the RLS "participants" policies |
| `deliveries` gains `is_wicket`, `dismissal_type`, `dismissed_player_id` | the spec has a manual "wicket" control and a scorecard but no column to store dismissals |
| `deliveries` gains `delivery_sequence` semantics + `is_voided/voided_at/void_reason`; unique `(innings_id, delivery_sequence)` | spec requires append-only undo; the original unique key `(innings_id, over_number, delivery_sequence)` cannot guarantee ordering after undo |
| `client_event_id` on deliveries replaced by client-generated primary keys + `sync_events` ledger | idempotency for **every** entity, not just deliveries |
| `delivery_decisions.reviewer_id` removed, `decision_source` limited to `AI_ASSIST`/`MANUAL` | the reviewer is always the owner |
| `replay_assets` → `replay_clips` | one row per replay file (`PENDING` → `READY`), no foreign keys to match/delivery because the phone uploads in the background before they may have synced |
| `refresh_tokens`, `sync_events` added | auth rotation and sync idempotency |
| `match_players.batting_hand` etc. kept; `players.batting_hand` added | per-match override of a roster default |
| `matches` gains `winner_team_id`, `result_summary` | store the computed result |
| `innings.total_runs/wickets/legal_balls` are **server-computed** | one authoritative aggregate; clients cannot desynchronise it |

## 3. Scope not included in v1 (explicit)

- Video replay. The replay is a compact record (ball path, batter pose and small greyscale frames, about 30 pictures a second) rather than a video file; see `frontend/README.md`.
- Spectator/share links and realtime score updates.
- Reusable team rosters and player statistics aggregation.
- Push notifications, analytics, Mixpanel/Amplitude.
- Release 2/3 features from the spec (bat-zone detector, front-foot no-ball, two-phone capture). The edge/LBW *assessment* logic exists and is review-only, as the spec requires.
- Dataset collection and model training (`ml/` in the spec). Those need real labelled footage and are a separate workstream.

## 4. Route/screen mapping

| Spec route | Flutter route | Screen file |
|---|---|---|
| `/(auth)/sign-in`, `/(auth)/sign-up` | `/sign-in`, `/sign-up` | `features/auth/presentation/*_screen.dart` |
| `/(tabs)` index / matches / profile | `/home`, `/matches`, `/profile` (bottom navigation) | `features/home`, `features/matches`, `features/profile` |
| `/match/create` | `/match/create` | `features/match_setup` |
| `/match/:id/auto-scan` | `/match/:id/auto-scan` | `features/scene_scan` (with the live camera this is "Mark the stumps": the umpire taps the corners of the stumps on the camera picture) |
| `/match/:id/toss` | `/match/:id/toss` | `features/toss` |
| `/match/:id/live` | `/match/:id/live` | `features/live_scoring` (+ `features/live_camera` for the umpire camera) |
| — | `/match/:id/replay/:replayId` | `features/replay` |
| `/match/:id/scorecard` | `/match/:id/scorecard` | `features/scorecard` |
| `/match/:id/review/:deliveryId` | `/match/:id/review/:deliveryId` | `features/review` |
| — | `/sync-issues` | `features/sync` |

## 5. The umpire assistant: what is real and what is not

**Real (on the phone, nothing simulated in the live path):**

- *Ball tracking.* The camera delivers brightness frames at its own speed (about 30 a second). A background model learns the
  empty scene, moving patches are found (run-length labelling), scored for how ball-like they are, and followed as several
  candidate paths at once (Kalman filters, "track before decide"). Things that stay in one place (a head, a post) are
  recognised as clutter. The most ball-like path is chosen when the delivery ends. This follows the idea of motion-based
  sports-ball trackers and of TrackNet-style "pick the trajectory, not the frame" tracking, without the neural network.
- *Batter height and position.* Google's pre-trained ML Kit body-pose model, run on a cut-out around the marked stumps.
- *Height at the batter, bounce, wide, height no-ball.* From the tracked path: the ball's apparent size fixes its distance
  (a 7.2 cm cricket ball or a 6.7 cm tennis ball), the picture is turned into metres on the batter's plane (the batter's
  measured height gives the scale), and the result is compared with the batter's waist / shoulder / head and the match rules,
  with the uncertainty of one camera taken into account.
- *Ball speed (only when the distance is entered).* The umpire types how far the phone is from the batter, in feet, when
  marking the stumps (kept per match, never carried over to another one). Seen from behind the bowler the ball flies away
  from the camera, so `1 / apparent size` grows in a straight line with time and its slope is the speed along the line of
  sight divided by (focal length x ball size). The batter is the ruler that fixes that product: the ball looks
  `planeDiameter` wide at his plane, which is `distance` away, so the speed along the line of sight is
  `slope x planeDiameter x distance`. The sideways and up-down movement come from where the ball is in the picture, and the
  speed is the length of the three together (it does not depend on how the phone is tilted). Only the points before the
  bounce count (the ball is slower afterwards); at least 6 points over 150 ms are needed. The result carries a "give or
  take": how well the points lie on a line, plus 4% for the entered distance and 4% for the batter's height (allowances,
  not measurements). A speed that may be out by more than 25% is not shown, and neither is any speed when no distance was
  entered, when the phone was moved (the scene changed), or when it is not known whether the ball bounced. The formula was
  checked against an exact pinhole camera in the tests; accuracy on real footage has not been measured.
- *Edge and LBW evidence in the replay (for a human to judge).* When the edge / LBW aids are on and the ball's path changes
  suddenly near the batter, the replay marks "Path changed" at that picture and has a "Go to the path change" button. From
  that moment (or from the arrival at the batter when no change was seen) it draws a dashed line: the straight line the
  ball was following over its last few points (after the bounce). Set against the real path it shows how far the ball moved
  off its line: a visual cue for the umpire, not a stand-in for the edge sound. No line is drawn for a path that is too short, not
  straight, or hardly moving. The line is a direction in the picture only; one camera cannot tell depth, so it never says
  that the ball would have hit the stumps. Nothing here is a verdict.
- *Replay.* A compact replay file of the delivery (pictures coded as differences, at most 4 brightness levels of error, each
  picture compressed) with the measurements attached; viewed with the path, bounce, batter lines and wicket drawn on top.
  Stored on the phone, uploaded in the background to Supabase Storage through signed URLs issued by the API (§1,
  API_CONTRACT §8).

**Not real / not done:**

- No ball-detection model, no wicket model, no audio (UltraEdge-style sound) analysis: edges use the visual change of
  direction only.
- *One camera, about 30 pictures a second.* A fast ball is seen only a few times; height is good to about 0.3 m and is
  reported with that uncertainty. A call near a limit is *review recommended* or *inconclusive*, never a sure call. Dark or
  low-contrast balls track poorly.
- *Ball speed is only as good as the ball's measured size.* A ball a few pixels wide has a size that jumps by a pixel from
  picture to picture, and that noise pulls the straight-line fit and makes the speed read low (in an exact-geometry test,
  a +/-20% jump in the measured size gave a speed about 15% low, with a "give or take" wide enough to cover the truth).
  Zoom in so the ball is large, and treat the speed as rough. The 4% + 4% allowances and the 25% cut-off are engineering
  choices, not tuned on footage.
- *Review aids are experimental.* Edge, LBW and wicket-hit evidence needs both the match's own rule switch *and* the
  `ENABLE_EDGE_REVIEW` / `ENABLE_LBW_REVIEW` flag in `frontend/.env`. `ENABLE_LBW_REVIEW` also gates the wicket-hit check.
  They never dismiss a batter; the scorer always decides.
- *Why LBW and edge are not decided automatically.* Seen from behind the bowler the stumps sit right behind the batter,
  so a ball that hits the pad in line with the stumps looks the same in the picture as a ball that hits the stumps; only
  depth tells them apart, and a ball a few pixels wide does not reliably give depth to within the metre or so that separates them (a 10% jump in its measured size is about a metre at 12 m).
  A touch of the bat's edge sends the ball mostly along the line of sight, which hardly moves it in the picture. With
  sound dropped (street noise), the app flags a sudden change of path and leaves the call to the umpire with the replay.
- *Short pitches and the edge / LBW gate.* Edge and LBW are only worked out when the path shows a sudden change near the
  batter (`contactMinSpeedChange`, a number chosen on the simulated camera). From behind the bowler a ball that hits the pad
  mostly moves along the line of sight, which is very little movement in the picture, so such a contact may not pass the
  gate and no LBW is produced; a sideways kick (an edge) is far easier to see. The gate is deliberately strict: loosening it
  without real footage would produce an LBW suggestion for deliveries that never touched the pad. When the gate is not
  passed, the analysis says so in its notes, so the absence of a suggestion is never read as "not out".
- *Android only* for the live camera in this version (iOS is untested). Other platforms run as a plain scorer.
- *Not implemented:* front-foot no-ball detection and the "bouncers per over" rule (the rule is stored and synced, the
  assistant does not use it).
- The methods were checked on synthetic scenes (and a line-by-line Python port of the tracker), **not** on real match
  footage; thresholds will need tuning on a real phone.
- Patent note: some commercial ball-tracking systems are patented (for example US 2023/0146189). Get legal advice before a
  commercial release.

**The simulator.** `DEV_SIMULATE_CV=true` (a new key; the old `ENABLE_MOCK_CV` is ignored so that an old `.env` cannot switch
it on) plays back deterministic simulated detections through the same interpretation code so that the screens can be developed
without a camera. Every simulated result carries a "Simulated" badge and a production build refuses to start with the flag on.
With neither the live camera nor the simulator the app is a plain scorer that never invents a call.

**Scoring is the product.** Every screen works with no assistant at all.

## 6. Known limitations

- The backend's rate limiter is in-process. Behind several workers or instances each one counts separately; put a shared
  limiter (for example at the reverse proxy) in front for a multi-instance deployment.
- When the server refuses a change, later changes to the same match are held back on the phone until the scorer decides
  what to do (*Profile → Sync*). Events that were already in the same batch are still processed by the server in order,
  so those that depended on the refused one are refused as well and are listed together with it.
- The Flutter app targets **Android and iOS**. Web and desktop are not supported (the app uses `dart:io` and a native secure
  store). The live camera is Android-only for now, and the screen is kept awake while the umpire camera runs.
- The bowler cannot be changed in the middle of an over.
- Flutter tests that use SQLite (`sqflite_common_ffi`) need the system library `libsqlite3` on the machine running them.
