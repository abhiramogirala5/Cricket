# Gully Umpire — API Contract (v1)

This document is the single source of truth for the HTTP API between `frontend/` (Flutter) and
`backend/` (FastAPI). If code and this document disagree, fix the code or change this document
in the same pull request — never leave them out of sync.

Related documents: [`SCORING_RULES.md`](SCORING_RULES.md) (delivery validation and aggregates),
[`scoring_test_vectors.json`](scoring_test_vectors.json) (executable examples used by both test suites),
[`SPEC_ADAPTATIONS.md`](SPEC_ADAPTATIONS.md) (how the original React Native/Supabase spec was adapted).

---

## 1. Conventions

| Topic | Rule |
|---|---|
| Base path | `{API_BASE_URL}/api/v1` (health endpoints are unversioned: `/health`, `/health/ready`) |
| Format | JSON, UTF-8, `Content-Type: application/json` |
| Keys | `snake_case` everywhere |
| IDs | UUID v4, lowercase, hyphenated. **Entities created on the device get their ID on the device** (offline-first) |
| Timestamps | RFC 3339 in UTC, always suffixed `Z` (e.g. `2026-10-08T07:33:00Z`). Fractional seconds optional |
| Enums | `UPPER_SNAKE_CASE` strings |
| Auth | `Authorization: Bearer <access_token>` on every endpoint except `/auth/*` (register, login, refresh) and `/health*` |
| Nulls | Optional fields may be omitted or `null`. Unknown fields in **requests** are rejected with `VALIDATION_ERROR` |
| Compatibility | Within `/v1`, only additive changes to **responses** are allowed. Clients must ignore unknown response fields |

### 1.1 Error envelope

Every non-2xx response has this shape (including validation errors and unhandled errors):

```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Human readable summary",
    "details": [ { "loc": ["body", "email"], "msg": "value is not a valid email address", "type": "value_error" } ],
    "request_id": "7f0c3b1e5e2a4c1f9e1d2b3a4c5d6e7f"
  }
}
```

`details` is optional (present for `VALIDATION_ERROR`). `request_id` is also returned in the
`X-Request-ID` response header; clients may send their own `X-Request-ID` (≤ 64 chars, `[A-Za-z0-9._-]`).

| HTTP | `code` | When |
|---|---|---|
| 400 | `BAD_REQUEST` | Malformed request that is not a schema problem |
| 401 | `NOT_AUTHENTICATED` | No `Authorization` header |
| 401 | `TOKEN_EXPIRED` | Access token expired → client should refresh **once** and retry |
| 401 | `INVALID_TOKEN` | Access token malformed / wrong signature / wrong type |
| 401 | `INVALID_CREDENTIALS` | Wrong email or password at login |
| 401 | `INVALID_REFRESH_TOKEN` | Refresh token unknown, expired, revoked or already rotated → client must sign in again |
| 403 | `ACCOUNT_DISABLED` | User exists but `is_active = false` |
| 403 | `PASSWORD_INCORRECT` | Wrong password when deleting an account |
| 404 | `NOT_FOUND` | Resource does not exist **or belongs to another user** (never reveal which) |
| 405 | `METHOD_NOT_ALLOWED` | The path exists but not for this HTTP method (an `Allow` header lists the valid ones) |
| 409 | `EMAIL_ALREADY_REGISTERED` | Register with an existing email |
| 413 | `PAYLOAD_TOO_LARGE` | Request body larger than `MAX_REQUEST_BODY_BYTES` (default 2 MiB) |
| 422 | `VALIDATION_ERROR` | Request body/query failed schema validation |
| 429 | `RATE_LIMITED` | Too many requests; `Retry-After` header (seconds) is set |
| 500 | `INTERNAL_ERROR` | Unhandled server error (message is generic; details only in server logs) |
| 503 | `SERVICE_UNAVAILABLE` | `/health/ready` when the database is unreachable |

Per-event sync errors (inside a `200` response of `/sync/push`) use the separate codes in §5.4.

---

## 2. Health

| Method | Path | Auth | Response |
|---|---|---|---|
| GET | `/health` | none | `200 {"status":"ok"}` — process is up |
| GET | `/health/ready` | none | `200 {"status":"ready","database":"ok"}` or `503` error envelope when the DB check fails |

---

## 3. Auth

All auth endpoints are rate limited per client IP (default **10 requests / 60 s**, configurable).

### 3.1 Shared shapes

```jsonc
// UserRead
{ "id": "uuid", "email": "a@b.com", "display_name": "Asha", "phone": null, "avatar_url": null,
  "created_at": "2026-10-08T07:33:00Z" }

// TokenPair
{ "access_token": "jwt", "refresh_token": "opaque", "token_type": "bearer", "expires_in": 900 }

// AuthResponse
{ "user": UserRead, "tokens": TokenPair }
```

`expires_in` is the access-token lifetime in seconds.

### 3.2 Endpoints

| Method | Path | Request body | Success | Errors |
|---|---|---|---|---|
| POST | `/auth/register` | `{ "email", "password", "display_name" }` | `201 AuthResponse` | 409 `EMAIL_ALREADY_REGISTERED`, 422, 429 |
| POST | `/auth/login` | `{ "email", "password" }` | `200 AuthResponse` | 401 `INVALID_CREDENTIALS`, 403 `ACCOUNT_DISABLED`, 422, 429 |
| POST | `/auth/refresh` | `{ "refresh_token" }` | `200 TokenPair` (**rotated**: old refresh token becomes invalid) | 401 `INVALID_REFRESH_TOKEN`, 403 `ACCOUNT_DISABLED`, 429 |
| POST | `/auth/logout` | `{ "refresh_token" }` | `204` (idempotent; unknown token is still `204`) | 422 |

Validation:

- `email`: valid address, max 255, stored and compared lower-cased and trimmed.
- `password`: 8–128 characters. Stored with Argon2id.
- `display_name`: 1–100 characters after trimming.

Token rules:

- Access token: JWT (HS256), claims `sub` (user id), `type="access"`, `iat`, `exp`, `jti`. Default lifetime 15 minutes.
- Refresh token: opaque random string (≥ 256 bits). Only its SHA-256 hash is stored. Default lifetime 30 days.
- Rotation: every successful `/auth/refresh` revokes the presented token and issues a new pair in the same *family*.
- Reuse detection: presenting an already-rotated token revokes the whole family and returns `INVALID_REFRESH_TOKEN`,
  **except** within a short grace window (`REFRESH_REUSE_GRACE_SECONDS`, default 10) after rotation, where it only returns
  `INVALID_REFRESH_TOKEN` without revoking the family (covers a client retrying after a dropped response).
- Login/register never reveal whether an email exists beyond the documented `EMAIL_ALREADY_REGISTERED` on register.
  Login uses a constant-time-ish path (hash a dummy password when the user does not exist).

### 3.3 Current user

| Method | Path | Request body | Success | Errors |
|---|---|---|---|---|
| GET | `/users/me` | — | `200 UserRead` | 401 |
| PATCH | `/users/me` | `{ "display_name"?, "phone"? }` (at least one field) | `200 UserRead` | 401, 422 |
| DELETE | `/users/me` | `{ "password" }` | `204` — deletes the user, all their data and all refresh tokens | 401, 403 `PASSWORD_INCORRECT`, 422 |

`phone`: optional, 5–25 characters, digits and `+ - ( ) space` only; `null` clears it.

---

## 4. Read endpoints

All read endpoints return only the authenticated user's data. Other users' IDs yield `404 NOT_FOUND`.

Pagination parameters on list endpoints: `limit` (1–100, default 50) and `offset` (≥ 0, default 0).
List envelope: `{ "items": [...], "total": 123, "limit": 50, "offset": 0 }`.

| Method | Path | Response |
|---|---|---|
| GET | `/players` | list of `PlayerRead`, ordered by `display_name` |
| GET | `/teams` | list of `TeamRead`, ordered by `name` |
| GET | `/matches` | list of `MatchSummary`, newest `created_at` first. Optional `status` filter |
| GET | `/matches/{match_id}/snapshot` | `MatchSnapshot` (everything needed to restore a match on a new device) |

### 4.1 `MatchSummary`

```jsonc
{
  "id": "uuid", "match_name": "Sunday finals", "location_name": "Terrace",
  "status": "LIVE", "overs_per_innings": 6,
  "team_a": { "id": "uuid", "name": "Reds" }, "team_b": { "id": "uuid", "name": "Blues" },
  "started_at": null, "completed_at": null, "winner_team_id": null, "result_summary": null,
  "innings": [ { "id": "uuid", "innings_number": 1, "batting_team_id": "uuid", "bowling_team_id": "uuid",
                 "total_runs": 41, "wickets": 2, "legal_balls": 30, "ended_at": null } ],
  "created_at": "…", "updated_at": "…"
}
```

### 4.2 `MatchSnapshot`

```jsonc
{
  "match": MatchRead,
  "rules": MatchRulesRead | null,
  "teams": [TeamRead, TeamRead],
  "players": [PlayerRead],              // only players referenced by match_players
  "match_players": [MatchPlayerRead],
  "toss": TossRead | null,
  "innings": [InningsRead],             // ordered by innings_number
  "deliveries": [DeliveryRead],         // ALL deliveries incl. voided, ordered by (innings_id, delivery_sequence)
  "delivery_decisions": [DeliveryDecisionRead],
  "scene_scans": [SceneScanRead],
  "wicket_detections": [WicketDetectionRead],
  "trajectory_snapshots": [TrajectorySnapshotRead]
}
```

`*Read` shapes are the entity shapes in §5.3 plus the server-managed fields listed there.

---

## 5. Offline sync

The device writes every change to its local SQLite database first and appends an event to a durable
outbox. A background worker sends outbox events (oldest first) to the server.

### 5.1 `POST /sync/push`

Auth required. Request:

```jsonc
{
  "events": [
    {
      "event_id": "uuid",                       // client-generated, unique per event; idempotency key
      "entity_type": "DELIVERY",                // see §5.3
      "action": "UPSERT",                       // UPSERT | VOID | DELETE
      "payload": { /* entity specific, §5.3 */ },
      "client_created_at": "2026-10-08T07:33:00Z"
    }
  ]
}
```

- `events`: 1–100 items. Larger batches → `422 VALIDATION_ERROR`.
- The server processes events **sequentially in array order**. The client must send parents before children.

Response `200`:

```jsonc
{
  "results": [
    { "event_id": "uuid", "status": "APPLIED", "error": null },
    { "event_id": "uuid", "status": "DUPLICATE", "error": null },
    { "event_id": "uuid", "status": "REJECTED", "error": { "code": "INVALID_DELIVERY", "message": "wide deliveries cannot have bat runs" } }
  ],
  "server_time": "2026-10-08T07:33:01Z"
}
```

`results` has exactly one entry per request event, in the same order. The HTTP status is `200` even if
individual events are rejected. Request-level problems (bad token, schema, batch size) use the normal error envelope.

### 5.2 Semantics

1. **Idempotency.** `(user, event_id)` is recorded in the `sync_events` ledger in the same database
   transaction as the change it caused. Re-sending an `APPLIED` event returns `DUPLICATE` and changes nothing.
2. **Only applied events are recorded.** A `REJECTED` event is **not** recorded, so the client may fix the cause and
   re-send the same `event_id` later.
3. **Isolation.** Each event is applied inside its own savepoint; a rejected event never affects the others in the batch.
4. **Statuses.** `APPLIED`: change committed. `DUPLICATE`: already applied earlier, no-op.
   `REJECTED`: permanent for now (see error code); the client marks the event `FAILED` and surfaces it.
5. **Client retry policy.** HTTP/network failure or `5xx`/`429` → keep all events `PENDING`, retry whole batch with
   exponential backoff (1 s, 2 s, 4 s … capped at 5 min, with jitter). `401 TOKEN_EXPIRED` → refresh token, retry.
6. **Ownership.** The server sets `owner_id` from the access token. Clients never send it. Writing to an entity owned by
   another user is rejected with `FORBIDDEN`. Child entities are authorised through their parent match.
7. **Server-authoritative aggregates.** `innings.total_runs`, `innings.wickets`, `innings.legal_balls` and, for deliveries,
   `delivery_sequence`, `over_number`, `legal_ball_number` are computed by the server (see `SCORING_RULES.md`);
   clients must not send them. They are returned by read endpoints.
8. **Locking.** Delivery inserts/voids lock the innings row (`SELECT … FOR UPDATE` on PostgreSQL) so concurrent
   batches cannot interleave sequence numbers.

### 5.3 Entity types and payloads

All `id` values are client-generated UUIDs. `*Read` = payload fields + the "server adds" fields.
Numeric ranges are enforced by the server (`VALIDATION_ERROR`-class problems inside sync become `INVALID_PAYLOAD`).

#### `PLAYER` — action `UPSERT`
Players are roster entries owned by the user; they do **not** need an app account.

| Field | Type | Rules |
|---|---|---|
| `id` | uuid | required |
| `display_name` | string | 1–100, trimmed |
| `batting_hand` | enum | `LEFT`, `RIGHT`, `UNKNOWN` (default `UNKNOWN`) |
| `declared_height_cm` | int \| null | 100–230 |

Server adds: `created_at`, `updated_at`.

#### `TEAM` — action `UPSERT`

| Field | Type | Rules |
|---|---|---|
| `id` | uuid | required |
| `name` | string | 1–100, trimmed |

Server adds: `created_at`, `updated_at`.

#### `MATCH` — actions `UPSERT`, `DELETE`

| Field | Type | Rules |
|---|---|---|
| `id` | uuid | required |
| `team_a_id`, `team_b_id` | uuid | required, must be the user's teams, must differ |
| `match_name` | string \| null | ≤ 150 |
| `location_name` | string \| null | ≤ 255 |
| `scheduled_at`, `started_at`, `completed_at` | timestamp \| null | |
| `status` | enum | `DRAFT`, `SCANNING`, `READY`, `LIVE`, `COMPLETED`, `ABANDONED`. `COMPLETED`/`ABANDONED` are terminal: a later event may not change `status` away from them (`INVALID_STATE`) |
| `overs_per_innings` | int | 1–50, default 6 |
| `local_rules_profile` | string | ≤ 40, default `CASUAL_GULLY` |
| `winner_team_id` | uuid \| null | must be `team_a_id` or `team_b_id` |
| `result_summary` | string \| null | ≤ 255 |

Server adds: `owner_id`, `created_at`, `updated_at`.
`DELETE` payload: `{ "id": "uuid" }` — hard-deletes the match and every child row. Deleting a non-existent match is `APPLIED` (idempotent).
`team_a_id`/`team_b_id` cannot be changed after the first `UPSERT` (`INVALID_STATE`).

#### `MATCH_PLAYER` — action `UPSERT`
Natural key `(match_id, player_id)`.

| Field | Type | Rules |
|---|---|---|
| `match_id` | uuid | must be the user's match |
| `player_id` | uuid | must be the user's player |
| `team_id` | uuid | must be the match's `team_a_id` or `team_b_id` |
| `batting_hand` | enum | as above |
| `declared_height_cm` | int \| null | 100–230 |
| `batting_order` | int \| null | 1–30 |
| `is_captain`, `is_wicketkeeper` | bool | default `false` |

#### `MATCH_RULES` — action `UPSERT`
Natural key `match_id` (one row per match).

| Field | Type | Default / rules |
|---|---|---|
| `match_id` | uuid | |
| `wide_enabled` | bool | `true` |
| `no_ball_enabled` | bool | `true` |
| `front_foot_no_ball_enabled` | bool | `false` |
| `edge_review_enabled` | bool | `true` |
| `lbw_review_enabled` | bool | `true` |
| `full_toss_above_waist_is_no_ball` | bool | `true` |
| `bounced_above_shoulder_is_no_ball` | bool | `false` |
| `max_bouncers_per_over` | int \| null | 0–6 |
| `lateral_reach_multiplier` | number | 0.20–1.50, default 0.60 |

#### `SCENE_SCAN` — action `UPSERT`

| Field | Type | Rules |
|---|---|---|
| `id` | uuid | |
| `match_id` | uuid | |
| `camera_device_model` | string \| null | ≤ 150 |
| `capture_fps` | int \| null | 1–240 |
| `scan_duration_ms` | int | 0–120000 |
| `ground_plane`, `pitch_direction`, `batsman_plane` | json object \| null | |
| `overall_confidence` | number | 0–1 |
| `model_version` | string | 1–100 (e.g. `mock-1`) |
| `created_at` | timestamp | optional |

#### `WICKET_DETECTION` — action `UPSERT`

| Field | Type | Rules |
|---|---|---|
| `id` | uuid | |
| `match_id` | uuid | |
| `scene_scan_id` | uuid \| null | must belong to the same match |
| `wicket_family` | enum | `TRADITIONAL_STUMPS`, `CHAIR`, `BRICK_STACK`, `BOTTLE_STACK`, `CONE_STACK`, `BUCKET`, `BAG_OR_OBJECT`, `WALL_TARGET`, `UNKNOWN_PHYSICAL_OBJECT` |
| `bounding_box` | json object | `{x,y,width,height}` normalised 0–1 |
| `target_polygon` | json array | list of `{x,y}` points, 3–32 points |
| `target_plane`, `ground_contact_line` | json \| null | |
| `object_confidence`, `temporal_stability`, `context_confidence`, `final_confidence` | number | each 0–1 |
| `is_active` | bool | default `true` |
| `model_version` | string | 1–100 |
| `detected_at` | timestamp | optional |

#### `TOSS` — action `UPSERT`
One per match (unique `match_id`).

| Field | Type | Rules |
|---|---|---|
| `id` | uuid | |
| `match_id` | uuid | |
| `called_by_player_id` | uuid \| null | must be a `MATCH_PLAYER` of this match |
| `call_choice` | enum | `HEADS`, `TAILS` |
| `result` | enum | `HEADS`, `TAILS` |
| `winner_team_id` | uuid \| null | match team |
| `winner_decision` | enum \| null | `BAT`, `BOWL` |

#### `INNINGS` — action `UPSERT`
Unique `(match_id, innings_number)`.

| Field | Type | Rules |
|---|---|---|
| `id` | uuid | |
| `match_id` | uuid | |
| `innings_number` | int | 1–4 |
| `batting_team_id`, `bowling_team_id` | uuid | the two match teams, in either order, must differ |
| `started_at` | timestamp | |
| `ended_at` | timestamp \| null | once set, new deliveries are rejected (`INNINGS_CLOSED`) |

Server adds: `total_runs`, `wickets`, `legal_balls` (all ints, recomputed).
`batting_team_id`/`bowling_team_id` cannot change after creation (`INVALID_STATE`).

#### `DELIVERY` — actions `UPSERT` (create-only), `VOID`

`UPSERT` payload:

| Field | Type | Rules |
|---|---|---|
| `id` | uuid | idempotency key at entity level; if the row already exists the event is `APPLIED` as a no-op |
| `innings_id` | uuid | must be the user's innings |
| `bowler_id`, `striker_id` | uuid | must be `MATCH_PLAYER`s of the innings' match |
| `non_striker_id` | uuid \| null | `MATCH_PLAYER`, must differ from `striker_id` |
| `runs_bat` | int | 0–7 |
| `runs_extras` | int | 0–10 (**total** extras on this ball, penalty included) |
| `is_wide`, `is_no_ball`, `is_bye`, `is_leg_bye` | bool | default `false` |
| `is_wicket` | bool | default `false` |
| `dismissal_type` | enum \| null | `BOWLED`, `CAUGHT`, `LBW`, `RUN_OUT`, `STUMPED`, `HIT_WICKET` |
| `dismissed_player_id` | uuid \| null | required iff `is_wicket`; must be `striker_id` or `non_striker_id` |
| `wicket_detection_id` | uuid \| null | same match |
| `speed_kmph` | number \| null | 0–250 |
| `speed_confidence`, `ball_tracking_confidence`, `pose_tracking_confidence`, `wicket_tracking_confidence` | number \| null | 0–1 |
| `created_at` | timestamp | optional (device time); defaults to server time |

Semantic validation of the flag/run/dismissal combination, the innings state and the derived fields is defined in
[`SCORING_RULES.md`](SCORING_RULES.md). Violations → `REJECTED` with `INVALID_DELIVERY`, `INNINGS_CLOSED` or `OVER_LIMIT_EXCEEDED`.

Server adds: `delivery_sequence` (int ≥ 1), `over_number` (int ≥ 0), `legal_ball_number` (int 1–6 \| null),
`is_voided`, `voided_at`, `void_reason`.

`VOID` payload: `{ "id": "uuid", "void_reason": "string ≤ 100 | null" }`. Only the **last non-voided delivery of its innings**
may be voided (`NOT_LAST_DELIVERY`). Voiding an already-voided delivery is `APPLIED` (no-op). Voiding an unknown delivery → `ENTITY_NOT_FOUND`.
Voided deliveries are never deleted; they stay in snapshots with `is_voided = true` and are excluded from aggregates.

#### `DELIVERY_DECISION` — action `UPSERT`

| Field | Type | Rules |
|---|---|---|
| `id` | uuid | |
| `delivery_id` | uuid | the user's delivery |
| `decision_type` | enum | `WIDE`, `NO_BALL_HEIGHT`, `NO_BALL_FRONT_FOOT`, `EDGE`, `LBW`, `WICKET_HIT` |
| `automated_result` | string \| null | ≤ 40 |
| `final_result` | string \| null | ≤ 40 |
| `confidence` | number \| null | 0–1 |
| `decision_status` | enum | `AUTO_CALL`, `REVIEW_RECOMMENDED`, `INCONCLUSIVE`, `MANUAL_OVERRIDE` |
| `decision_source` | enum | `AI_ASSIST`, `MANUAL` |
| `evidence` | json object \| null | free-form evidence; ≤ 64 KiB serialised |
| `created_at` | timestamp | optional |

#### `TRAJECTORY_SNAPSHOT` — action `UPSERT`

| Field | Type | Rules |
|---|---|---|
| `id` | uuid | |
| `delivery_id` | uuid | |
| `sampling_fps` | int | 1–240 |
| `points_compressed` | json array | each element `[timestamp_ms, x, y, confidence]`; max 600 elements |
| `model_version` | string | 1–100 |
| `created_at` | timestamp | optional |

### 5.4 Per-event error codes (`results[].error.code`)

| Code | Meaning |
|---|---|
| `INVALID_PAYLOAD` | Payload failed schema validation (missing field, wrong type, out-of-range value, unknown field) |
| `UNSUPPORTED_EVENT` | Unknown `entity_type`, or an `action` not allowed for that type |
| `FORBIDDEN` | Entity (or its parent) belongs to another user |
| `PARENT_NOT_FOUND` | Referenced parent (match, innings, delivery, team …) does not exist yet |
| `INVALID_REFERENCE` | A referenced entity exists but is not allowed here (e.g. player not in the match, team not in the match, scene scan from another match) |
| `INVALID_STATE` | Transition/immutability violation (e.g. leaving a terminal match status, changing teams, second toss with a different id) |
| `INVALID_DELIVERY` | Delivery flag/run/dismissal combination violates `SCORING_RULES.md` |
| `INNINGS_CLOSED` | Innings has `ended_at` |
| `OVER_LIMIT_EXCEEDED` | Innings already has `overs_per_innings × 6` legal balls |
| `NOT_LAST_DELIVERY` | `VOID` of a delivery that is not the last non-voided one |
| `ENTITY_NOT_FOUND` | Target of `VOID`/`DELETE`-style action does not exist (except `MATCH` delete, which is idempotent) |
| `INTERNAL_ERROR` | Unexpected failure while applying this one event (logged server-side; the event is **not** recorded and may be retried) |

Clients treat `PARENT_NOT_FOUND`, `INTERNAL_ERROR` as *retryable later* (keep `FAILED` with a "Retry" action that re-queues the event
in original order) and the rest as *needs attention* (surface in the "Sync issues" screen; user can retry or discard).

---

## 6. Data model (PostgreSQL)

Portable types are used so the same models run on SQLite in tests: `uuid` ↔ `sa.Uuid`, `jsonb` ↔ `JSON` with a PostgreSQL `JSONB` variant,
`timestamptz` ↔ timezone-aware `DateTime`. All timestamps are stored in UTC.
Foreign keys from `matches`, `match_players`, `deliveries`… to `players`/`teams` use the default `NO ACTION` (not `RESTRICT`) so that deleting a user cascades cleanly in one statement.

| Table | Columns (type, constraints) |
|---|---|
| `users` | `id` uuid PK · `email` varchar(255) unique not null (lower-case) · `password_hash` text not null · `display_name` varchar(100) not null · `phone` varchar(25) · `avatar_url` text · `is_active` bool not null default true · `created_at`, `updated_at` timestamptz not null |
| `refresh_tokens` | `id` uuid PK · `user_id` → users CASCADE · `family_id` uuid not null · `token_hash` char(64) unique not null · `issued_at`, `expires_at` timestamptz not null · `rotated_at`, `revoked_at` timestamptz null · index `(user_id)`, `(family_id)` |
| `players` | `id` uuid PK · `owner_id` → users CASCADE · `display_name` varchar(100) · `batting_hand` varchar(10) default `UNKNOWN` check in (LEFT,RIGHT,UNKNOWN) · `declared_height_cm` smallint null check 100–230 · `created_at`, `updated_at` · index `(owner_id)` |
| `teams` | `id` uuid PK · `owner_id` → users CASCADE · `name` varchar(100) · `created_at`, `updated_at` · index `(owner_id)` |
| `matches` | `id` uuid PK · `owner_id` → users CASCADE · `team_a_id`, `team_b_id` → teams · `match_name` varchar(150) · `location_name` varchar(255) · `scheduled_at`, `started_at`, `completed_at` · `status` varchar(20) not null default `DRAFT` check in (…) · `overs_per_innings` smallint not null default 6 check 1–50 · `local_rules_profile` varchar(40) not null default `CASUAL_GULLY` · `winner_team_id` → teams null · `result_summary` varchar(255) · `created_at`, `updated_at` · check `team_a_id <> team_b_id` · index `(owner_id, created_at)`, `(status)` |
| `match_players` | PK `(match_id, player_id)` · `match_id` → matches CASCADE · `player_id` → players · `team_id` → teams · `batting_hand` varchar(10) default `UNKNOWN` · `declared_height_cm` smallint null · `batting_order` smallint null · `is_captain`, `is_wicketkeeper` bool default false · index `(player_id)` |
| `match_rules` | `match_id` uuid PK → matches CASCADE · the 10 rule columns of §5.3 with the listed defaults · `lateral_reach_multiplier` numeric(4,2) |
| `scene_scans` | `id` uuid PK · `match_id` → matches CASCADE · `camera_device_model` varchar(150) · `capture_fps` smallint · `scan_duration_ms` int not null · `ground_plane`, `pitch_direction`, `batsman_plane` jsonb null · `overall_confidence` numeric(4,3) check 0–1 · `model_version` varchar(100) not null · `created_at` · index `(match_id)` |
| `wicket_detections` | `id` uuid PK · `match_id` → matches CASCADE · `scene_scan_id` → scene_scans SET NULL · `wicket_family` varchar(40) check in (…) · `bounding_box`, `target_polygon` jsonb not null · `target_plane`, `ground_contact_line` jsonb null · 4 confidence columns numeric(4,3) check 0–1 · `is_active` bool default true · `model_version` varchar(100) · `detected_at` · index `(match_id, is_active)` |
| `tosses` | `id` uuid PK · `match_id` uuid unique → matches CASCADE · `called_by_player_id` → players null · `call_choice`, `result` varchar(10) check in (HEADS,TAILS) · `winner_team_id` → teams null · `winner_decision` varchar(10) null check in (BAT,BOWL) · `created_at` |
| `innings` | `id` uuid PK · `match_id` → matches CASCADE · `innings_number` smallint · `batting_team_id`, `bowling_team_id` → teams · `total_runs`, `wickets`, `legal_balls` int not null default 0 · `started_at` not null · `ended_at` null · unique `(match_id, innings_number)` · check `batting_team_id <> bowling_team_id` |
| `deliveries` | `id` uuid PK · `innings_id` → innings CASCADE · `wicket_detection_id` → wicket_detections SET NULL · `delivery_sequence` int not null · `over_number` smallint not null · `legal_ball_number` smallint null check 1–6 · `bowler_id`, `striker_id` → players not null · `non_striker_id`, `dismissed_player_id` → players null · `runs_bat` smallint check 0–7 · `runs_extras` smallint check 0–10 · `is_wide`, `is_no_ball`, `is_bye`, `is_leg_bye`, `is_wicket` bool default false · `dismissal_type` varchar(20) null check in (…) · `speed_kmph` numeric(6,2) null · `speed_confidence`, `ball_tracking_confidence`, `pose_tracking_confidence`, `wicket_tracking_confidence` numeric(4,3) null check 0–1 · `is_voided` bool default false · `voided_at` timestamptz null · `void_reason` varchar(100) null · `created_at` · **unique `(innings_id, delivery_sequence)`** · index `(innings_id, over_number, delivery_sequence)` |
| `delivery_decisions` | `id` uuid PK · `delivery_id` → deliveries CASCADE · `decision_type` varchar(30) check in (…) · `automated_result`, `final_result` varchar(40) null · `confidence` numeric(4,3) null · `decision_status` varchar(30) not null default `REVIEW_RECOMMENDED` check in (…) · `decision_source` varchar(30) not null default `AI_ASSIST` check in (AI_ASSIST,MANUAL) · `evidence` jsonb null · `created_at`, `updated_at` · index `(delivery_id)` |
| `trajectory_snapshots` | `id` uuid PK · `delivery_id` → deliveries CASCADE · `sampling_fps` smallint not null · `points_compressed` jsonb not null · `model_version` varchar(100) not null · `created_at` · index `(delivery_id)` |
| `replay_clips` | `id` uuid PK (made by the phone) · `owner_id` → users CASCADE · `match_id` uuid not null · `delivery_id` uuid null · `storage_path` varchar(200) unique not null · `size_bytes` int not null check > 0 · `sha256` char(64) null · `width`, `height` int null check 1–65535 · `frame_count` int null check 1–600 · `duration_ms` int null check 0–60000 · `status` varchar(10) not null default `PENDING` check in (PENDING,READY) · `created_at` not null · `uploaded_at` null · index `(owner_id, delivery_id)`, `(owner_id, match_id)`. `match_id` and `delivery_id` deliberately have **no** foreign key: the phone uploads in the background and the match or delivery may not have been synced yet |
| `sync_events` | PK `(owner_id, event_id)` · `owner_id` → users CASCADE · `event_id` uuid · `entity_type` varchar(30) · `action` varchar(10) · `applied_at` timestamptz not null |

Constraint and index names follow the SQLAlchemy naming convention configured in `backend/app/db/base.py`
(`ix_`, `uq_`, `ck_`, `fk_`, `pk_` prefixes) so Alembic autogenerate is stable.

Row-level security is enabled on every table (migration `0002`, PostgreSQL only) so that Supabase's Data API cannot expose
them; the API's own connection (the table owner) is not affected.

Deliberately **not** in v1: reusable team rosters (`team_players`), spectator/sharing access, push notifications.
Replay files are stored as described in §8. See `SPEC_ADAPTATIONS.md`.

---

## 7. Security requirements (checklist for reviewers)

- Secrets (`JWT_SECRET_KEY`, DB credentials, Sentry DSN) come **only** from environment variables / `.env`. Startup fails in `production` if
  `JWT_SECRET_KEY` is shorter than 32 characters or is the documented placeholder.
- Every query on user data is scoped by `owner_id` (directly or through the parent match). There is no endpoint that accepts an `owner_id`.
- CORS: explicit allow-list from `CORS_ALLOWED_ORIGINS`; no wildcard in `production`. Native mobile clients do not need CORS.
- Passwords: Argon2id; never logged; never returned.
- Logs are structured JSON, include `request_id`, and never contain tokens, passwords or request bodies.
- Rate limiting on `/auth/*` (per IP) — per-process in-memory limiter; place a gateway/Redis limiter in front when running more than one replica.
- Request body size limit and sync batch limit (100 events) are enforced.
- Replay files never pass through this API: the phone gets a short-lived signed URL (upload: 2 hours, download: `REPLAY_DOWNLOAD_TTL_SECONDS`). The Supabase service key lives only in `backend/.env`; the bucket is private.

---

## 8. Replay files

A replay is the compact file the phone makes for one delivery (ball path, batter pose, camera frames; the
`GUR1` format of the Flutter app). It is stored in a private Supabase Storage bucket; the database keeps one row per file.
All endpoints need a bearer token and only ever see the caller's own replays (another user's replay is `404 NOT_FOUND`).
Without `SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY` on the server every endpoint below answers `503 SERVICE_UNAVAILABLE`.

| Method | Path | Request | Success | Errors |
|---|---|---|---|---|
| POST | `/replays` | `ReplayCreate` | `201 ReplayCreated` (new or retried), `200 ReplayCreated` with `upload: null` (already stored) | 401, 409 `CONFLICT` (id belongs to another account), 413 `PAYLOAD_TOO_LARGE` (`size_bytes` > `REPLAY_MAX_BYTES`), 422, 503 |
| POST | `/replays/{id}/complete` | — | `200 ReplayRead` with `status: READY` (repeating it is harmless) | 404, 409 `UPLOAD_MISSING`, 409 `UPLOAD_SIZE_MISMATCH`, 503 |
| GET | `/replays?delivery_id=&match_id=&limit=&offset=` | — | `200 Page<ReplayRead>`, stored (`READY`) replays only, newest first | 401 |
| GET | `/replays/{id}/download` | — | `200 { "url", "expires_in_seconds" }` | 404 (also while still `PENDING`), 503 |
| DELETE | `/replays/{id}` | — | `204` — deletes the file and the row | 404, 503 |

`ReplayCreate`: `{ id (uuid, made by the phone), match_id, delivery_id?, size_bytes (>= 1), sha256? (64 hex), width?, height?, frame_count? (1–600), duration_ms? (0–60000) }`.

`ReplayCreated`: `{ replay: ReplayRead, upload: { url, method: "PUT", headers, expires_in_seconds } | null }`.
Upload with `PUT url`, the given `headers` and the raw file as the body, then call `/complete`.

`ReplayRead`: `{ id, match_id, delivery_id, size_bytes, sha256, width, height, frame_count, duration_ms, status: "PENDING" | "READY", created_at, uploaded_at }`.

Semantics: announcing the same `id` again is idempotent (details are refreshed and a new upload link is issued until the replay is
`READY`). Announcing a `READY` replay with a `delivery_id` when none was known adopts it, so the phone can upload before the
delivery has been synced. A file is only marked `READY` after the server has seen it in the bucket with exactly `size_bytes`.
