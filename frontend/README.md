# Gully Umpire — Flutter app

Offline-first cricket scoring for gully cricket, with an umpire assistant that watches the delivery through the phone's
camera. The scoring works on Android and iOS; the live camera assistant is Android-only for now.

The app keeps every match in a database on the phone, so scoring works with no signal. When an account and a server
are configured it signs in, sends the changes in the background and can fetch matches onto a new phone.
The HTTP contract is [`../docs/API_CONTRACT.md`](../docs/API_CONTRACT.md); the scoring rules are
[`../docs/SCORING_RULES.md`](../docs/SCORING_RULES.md), and both the app and the backend are checked against the shared
vectors in `../docs/scoring_test_vectors.json`.

## First run

Requires the Flutter SDK (Dart 3.9+, Flutter 3.35+) and, for tests, the system library `libsqlite3`.

```bash
cd frontend
python3 tool/bootstrap_platforms.py   # creates .env, android/ and ios/, applies the platform settings
flutter pub get
flutter analyze
flutter test
flutter run
```

`tool/bootstrap_platforms.py` is safe to run again (`--skip-create` when `android/` and `ios/` already exist). It adds the
camera permission, raises the minimum Android version to 24 (what the camera and body-pose plug-ins need) and tells you
about lines in an old `.env` that changed. If you prefer to do it by hand: `cp .env.example .env`, then
`flutter create . --project-name gully_umpire --org com.gullyumpire --platforms android,ios`, add the `INTERNET`,
`ACCESS_NETWORK_STATE` and `CAMERA` permissions to `android/app/src/main/AndroidManifest.xml` and set `minSdk` to 24 in
`android/app/build.gradle(.kts)`. **`.env` must exist**, because it is declared as an asset in `pubspec.yaml`.
The tests of the script itself: `python3 -m unittest discover -s tool`.

## Configuration (`.env`)

`.env` is bundled into the app, so it holds **non-secret values only**. Real secrets (JWT key, database password, Sentry
DSN) live in `backend/.env`. The only code that reads `.env` is `lib/core/config/app_config.dart`.

| Key | Meaning |
|---|---|
| `APP_ENV` | `development`, `staging` or `production` |
| `API_BASE_URL` | server address without `/api/v1`. Android emulator → `http://10.0.2.2:8000`, iOS simulator → `http://localhost:8000`. **Empty = local-only mode** (no account, no sync; not allowed in production) |
| `ENABLE_LIVE_CV` | the live camera umpire assistant (Android). On unless you set it to `false`, which makes the app a plain scorer |
| `DEV_SIMULATE_CV` | **development only**: play back simulated detections instead of using the camera. Everything it shows is labelled "Simulated". An old `ENABLE_MOCK_CV` line is ignored on purpose, so an old `.env` cannot switch the demo engine on |
| `ENABLE_EDGE_REVIEW`, `ENABLE_LBW_REVIEW` | review aids drawn from the tracked ball path (`ENABLE_LBW_REVIEW` also turns on the wicket-hit check). A match must also switch the rule on |
| `HTTP_TIMEOUT_SECONDS` | 3–120 |

A **production** build refuses to start unless `API_BASE_URL` is an `https://` address and `DEV_SIMULATE_CV` is `false`.
For a release build write a production `.env` first (for example in your CI), then `flutter build appbundle` or
`flutter build ipa`.

Plain `http://` is only allowed in debug and profile builds on Android; release builds are HTTPS-only.

## The umpire assistant (live camera)

Nothing in the live path is simulated and no ball-detection model is used. The assistant works like this:

1. **Mark the stumps.** On the match page, *Mark the stumps* opens the camera. Place the phone **behind the bowler,
   facing the batter**, with the whole batter and the stumps in the picture (the screen tells you when you are too far
   away), and tap the corners of the stumps. If you want ball speeds, also type the distance from the phone to the batter in feet.
   The zoom and the distance are remembered for the match; if you move the phone or change the
   zoom afterwards, mark the stumps again.
2. **Learn the scene.** The camera picture is brightness-only and is handled on a separate worker (isolate) at the
   camera's own speed (about 30 pictures a second). It first learns the empty scene, then finds everything that moves,
   keeps the patches that look like a ball, follows several possible paths at once (Kalman filters) and chooses the most
   ball-like one. A swaying head or a standing umpire is recognised as clutter and ignored.
3. **Measure the batter.** The batter's height and position come from Google's pre-trained ML Kit body-pose model, run on
   a cut-out around the stumps a few times a second while the ball is not in flight. This is the only trained model.
4. **Decide from the path.** When a delivery ends, its path is turned into a height above the ground at the batter
   (from the ball's apparent size, which fixes how far away it is), whether and where it bounced, and how far to the side
   it passed. Those are compared with the batter's waist, shoulder and head and with the rules of the match to suggest
   *wide*, *no-ball* (height), and, when the review aids are on, edge / LBW / wicket-hit evidence.
5. **Replay.** Every delivery is kept as a short replay (compressed brightness pictures plus the measurements). The
   replay screen draws the path, the bounce, the batter's lines and the wicket on top, with slow motion and *Go to the
   bounce* / *Go to the batter*. A replay is saved with the ball when you score it and uploaded in the background
   (Supabase Storage through the backend); on another phone it is downloaded on demand.

Suggestions are only ever suggestions: the scorer decides, and every ball can be undone.

Things to know:

* A phone camera at ~30 pictures a second sees a fast ball only a few times. Height is good to about 0.3 m with one
  camera, so a call close to a limit is reported as *review recommended* or *inconclusive*, never as a sure call.
* A dark or low-contrast ball (a black ball at night) is tracked poorly. A white or bright ball against a darker
  background works best.
* **Ball speed needs the distance.** When you mark the stumps, type how far the phone is from the batter **in feet**
  (walk it heel to toe: a shoe is about a foot). The speed is worked out from how fast the ball shrinks in the picture
  and shown as "about 78 km/h, give or take 9". With no distance entered, or after the phone was moved, no speed is shown
  and the screen says why. The distance is kept for that match only. The speed is rough: the ball is only a few pixels
  wide, so zoom in, and expect it to read low when the ball is small. It has not been checked against real deliveries.
* Only the visual change of direction is used for edges; the sound is not analysed. When the path changes suddenly near
  the batter, the replay marks it ("Path changed", with a button to jump there) and draws a dashed line of where the ball
  was heading, so you can see how far it moved off its line frame by frame. That is evidence for you to judge, not a
  verdict: bat, pad and glove cannot be told apart from behind the bowler.
* Edge and LBW are looked for only when the ball's path shows a clear sudden change near the batter. When it does not,
  the screen says so ("the edge and LBW checks were not made, that is not a verdict") instead of staying silent,
  so a missing edge or LBW suggestion never means "not out". The numbers behind this check were chosen on a simulated
  camera, not on real footage: check them against real deliveries before relying on them.
* Moving the phone or a big change of light makes the assistant learn the scene again and asks you to check the stumps.
* `DEV_SIMULATE_CV=true` is for developing the screens without a camera. It is refused in production builds and its
  results always carry a "Simulated" badge.

See `../docs/SPEC_ADAPTATIONS.md` §5 for the design notes and the limits.

## Layout

```
lib/
├── main.dart            bootstrap only
├── app/                 App widget, router (routes.dart, app_router.dart), shell with the three tabs, theme
├── core/                config, DI wiring (di/), errors, utils, shared widgets
├── domain/              pure Dart: models, scoring engine, scorecard, decisions, setup rules
├── cv/                  pure Dart: contracts, geometry, tracking, scene scan, pipelines, the live tracker (cv/live,
│                        cv/vision, cv/tracking) and its camera / body-pose plug-in glue (cv/live/platform)
├── data/                local (sqflite), remote (dio), repositories, session, sync outbox, replay files and uploads
└── features/<feature>/  screens (presentation/) and the pure helpers beside them
test/                    mirrors lib/; test/support/ holds fixtures
tool/                    developer scripts
```

Dependencies point one way: `features` → `data` / `domain` / `cv` / `core`; `data` → `domain`; `domain` imports no Flutter
code. Naming and structure rules are in [`../docs/CONVENTIONS.md`](../docs/CONVENTIONS.md).

Screens: sign in / sign up, Home, Matches, New match, Mark the stumps, Toss, Live scoring (with the umpire camera),
Replay, Scorecard, Delivery review, Saved players, Profile and Sync issues.

## How data flows

1. Every change (a ball, an undo, a new player) is written to the local database and, in the same transaction, to an
   **outbox**.
2. The sync engine sends the outbox oldest-first in batches; the server answers per event. Accepted and duplicate events
   leave the outbox. A refused event waits on the *Sync issues* page and holds back later changes to the same match.
3. Network errors and server errors keep everything queued and retry with back-off.
4. Each account has its own database file, so signing in as someone else never mixes data. Signing out keeps the file.

## Useful commands

| Command | What it does |
|---|---|
| `make bootstrap` | `python3 tool/bootstrap_platforms.py` |
| `make check` | `flutter analyze` and `flutter test` |
| `make run` | `flutter run` |
| `dart format lib test` | format the code |
