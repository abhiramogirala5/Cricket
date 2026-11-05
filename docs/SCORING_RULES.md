# Gully Umpire — Scoring Rules

Authoritative rules for validating a delivery and computing innings aggregates. The **backend** applies them when
processing sync events; the **Flutter app** applies the same rules locally (offline-first). Both implementations are
tested against [`scoring_test_vectors.json`](scoring_test_vectors.json).

## 1. Delivery fields that matter

| Field | Meaning |
|---|---|
| `runs_bat` | Runs scored off the bat (0–7). Never includes extras |
| `runs_extras` | **Total** extras on the ball (0–10): penalty runs **plus** any additional wide/no-ball/bye/leg-bye runs run |
| `is_wide`, `is_no_ball` | Illegal deliveries: the ball is re-bowled (does not count towards the over) |
| `is_bye`, `is_leg_bye` | Extra runs that were run without the ball touching the bat |
| `is_wicket`, `dismissal_type`, `dismissed_player_id` | Dismissal on this ball |

Define `penalty = 1` if `is_wide` or `is_no_ball`, otherwise `0`.

## 2. Validation (`INVALID_DELIVERY`)

A delivery is invalid if **any** of these hold:

1. `runs_bat` is outside 0–7, or `runs_extras` is outside 0–10.
2. `is_wide` and `is_no_ball` are both true.
3. `is_bye` and `is_leg_bye` are both true.
4. `is_wide` and (`is_bye` or `is_leg_bye`) — all runs off a wide are wides.
5. `is_wide` and `runs_bat > 0`.
6. (`is_bye` or `is_leg_bye`) and `runs_bat > 0`.
7. `runs_extras < penalty`.
8. (`is_bye` or `is_leg_bye`) and `runs_extras < penalty + 1` — a bye flag means at least one bye run was taken.
9. None of `is_wide`, `is_no_ball`, `is_bye`, `is_leg_bye` is set and `runs_extras != 0`.
10. `is_wicket` is true and `dismissal_type` is missing, or `is_wicket` is false and `dismissal_type` is present.
11. `is_wicket` is true and the dismissal is not allowed for the delivery type:
    - on a **no-ball**: only `RUN_OUT`;
    - on a **wide**: only `RUN_OUT`, `STUMPED`, `HIT_WICKET`;
    - on a legal delivery: any of `BOWLED`, `CAUGHT`, `LBW`, `RUN_OUT`, `STUMPED`, `HIT_WICKET`.
12. `is_wicket` is true and `dismissed_player_id` is missing, is neither the striker nor the non-striker, or is the
    **non-striker while `dismissal_type != RUN_OUT`**.
13. `striker_id == non_striker_id`.

Rules 1–13 are a **pure function** of the delivery (it receives `striker_id`, `non_striker_id` and
`dismissed_player_id` as opaque values). It is exercised by `valid_deliveries` / `invalid_deliveries` in the test
vectors; the harness resolves the vector field `"dismissed"` (`STRIKER` / `NON_STRIKER`) into `dismissed_player_id`.
The additional "this player belongs to this match" checks need the database / match roster, so they live in the
backend sync service (`INVALID_REFERENCE`) and in the app's scoring controller.

**Order of checks** when a delivery arrives: (1) schema/range, (2) rules 1–13 → `INVALID_DELIVERY`,
(3) roster membership → `INVALID_REFERENCE`, (4) `INNINGS_CLOSED`, (5) `OVER_LIMIT_EXCEEDED`.

## 3. Derived fields (server-assigned; app mirrors them)

Let `active` be the innings' deliveries that are **not voided**, in sequence order, *before* the new delivery.

- `legal` (the delivery is a legal ball) = not `is_wide` and not `is_no_ball`.
- `legal_balls_before` = number of legal deliveries in `active`.
- `over_number` = `legal_balls_before // 6` (0-based).
- `legal_ball_number` = `(legal_balls_before % 6) + 1` if `legal`, otherwise `null`.
- `delivery_sequence` = `1 + max(delivery_sequence of ALL deliveries ever recorded in the innings, voided included)`,
  or `1` for the first delivery. **Sequence numbers are never reused**, even after an undo.

## 4. Innings state checks

Applied before a delivery is accepted:

1. Innings `ended_at` is set → `INNINGS_CLOSED`.
2. `legal_balls_before >= overs_per_innings × 6` → `OVER_LIMIT_EXCEEDED` (applies to every delivery type, including wides/no-balls bowled after the final legal ball).

## 5. Aggregates (server recomputes after every delivery insert/void)

Over `active` deliveries (non-voided, **including** the new one):

- `total_runs` = Σ (`runs_bat` + `runs_extras`)
- `wickets` = count of deliveries with `is_wicket`
- `legal_balls` = count of legal deliveries

Overs are displayed as `legal_balls // 6` `.` `legal_balls % 6` (e.g. 13 legal balls → `2.1`).

## 6. Void (undo)

- Only the **last non-voided** delivery of the innings may be voided (`NOT_LAST_DELIVERY` otherwise).
- Voiding sets `is_voided = true`, `voided_at`, optional `void_reason`; nothing is deleted.
- The engine-level error for "nothing to void" is `NOTHING_TO_VOID` (app only; the server answers `ENTITY_NOT_FOUND`).
- After a void, the next delivery re-uses the freed `over_number`/`legal_ball_number` but gets a **new** `delivery_sequence`.

## 7. Scorecard rules (client-side only, derived from non-voided deliveries)

| Stat | Rule |
|---|---|
| Batter runs | Σ `runs_bat` while the player is striker |
| Batter balls faced | deliveries as striker that are **not wides** (no-balls count, byes/leg-byes count) |
| Fours / sixes | deliveries as striker with `runs_bat == 4` / `== 6` |
| Strike rate | `runs / balls × 100`, `0` when balls = 0 |
| Dismissal | the delivery where the player is `dismissed_player_id`; otherwise "not out" / "did not bat" |
| Bowler legal balls | legal deliveries bowled → overs `balls // 6 . balls % 6` |
| Bowler runs conceded | `runs_bat` + (wide ? `runs_extras` : 0) + (no-ball ? 1 : 0). Byes/leg-byes are **not** charged to the bowler |
| Bowler wickets | dismissals other than `RUN_OUT` |
| Economy | `runs_conceded / (legal_balls / 6)`, `0` when no legal balls |
| Extras | wides = Σ `runs_extras` on wides; no-balls = count of no-balls; byes/leg-byes = `runs_extras − penalty` on bye/leg-bye deliveries |
| Fall of wickets | `score/wicket-number (over.ball)` at each dismissal |

## 8. Strike rotation and over/innings end (client-side)

- After a delivery, the batters swap ends if the number of **runs physically run** is odd. Define `runs_run`:
  - `runs_bat` is 4 or 6 → treated as a boundary: `runs_run = 0`.
  - otherwise `runs_run = runs_bat` (so 5 and 7 are runs run: overthrows included).
  - plus the extras that were run: `runs_extras − penalty` (byes, leg-byes, or runs taken off a wide / no-ball).
  - If `is_wicket` with `RUN_OUT`, the app asks which end was run out and the incoming batter takes that end; the
    parity rule above is **not** applied on that ball (the scorer chooses the new striker explicitly).
- After the **6th legal ball** the batters swap ends again and a new bowler must be chosen.
- On a wicket the dismissed batter is replaced by the next batter; the incoming batter takes the dismissed batter's end (striker end for a bowled/caught/LBW/stumped/hit-wicket; for a run-out the end of whoever was run out).
- Innings ends when: legal balls reach `overs × 6`, wickets reach `players_on_batting_team − 1`, the chasing team passes the target (2nd innings), or the scorer taps "End innings".
- Result (2nd innings end): chasing total > first total → chasing team wins by `players − 1 − wickets` wickets; first total > chasing total → first team wins by the run difference; equal → tie.
