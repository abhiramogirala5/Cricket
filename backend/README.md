# Gully Umpire — backend

FastAPI service for accounts, offline-first sync, match storage and replay files. Python 3.12+ (developed on 3.13),
SQLAlchemy 2 (async), Alembic, PostgreSQL 16 in production (Supabase Postgres works as is) and SQLite for the default
test run. Replay files live in Supabase Storage.

The HTTP contract is [`../docs/API_CONTRACT.md`](../docs/API_CONTRACT.md); the scoring rules the server enforces are
[`../docs/SCORING_RULES.md`](../docs/SCORING_RULES.md). The Flutter app in `../frontend` follows the same two documents
and the shared vectors in `../docs/scoring_test_vectors.json`.

## Quick start

```bash
cd backend
cp .env.example .env            # then edit: DATABASE_URL and JWT_SECRET_KEY at minimum
make install                    # creates .venv and installs requirements-dev.txt
make migrate                    # alembic upgrade head
make run                        # http://127.0.0.1:8000 (interactive docs at /docs)
```

Generate a signing secret with `python -c "import secrets; print(secrets.token_hex(32))"`.

For a throw-away local database use Docker (`docker compose up db` from the repository root) or any PostgreSQL 16 server
and put its URL into `DATABASE_URL`, for example
`postgresql+asyncpg://gully:change_me@localhost:5432/gully_umpire`.

## Configuration

All configuration comes from environment variables (loaded from `backend/.env` in development).
`app/core/config.py` is the only module that reads them; `.env.example` documents every variable.
**Real values never go into the repository** — `.env` is git-ignored and the Docker image never contains it.

| Variable | Required | Meaning |
|---|---|---|
| `DATABASE_URL` | yes | SQLAlchemy URL. `postgres://` and `postgresql://` are rewritten to the asyncpg driver |
| `JWT_SECRET_KEY` | yes | HS256 signing key for access tokens |
| `APP_ENV` | no | `development` (default), `staging`, `production`, `test` |
| `ACCESS_TOKEN_EXPIRE_MINUTES` / `REFRESH_TOKEN_EXPIRE_DAYS` | no | 15 minutes / 30 days |
| `REFRESH_REUSE_GRACE_SECONDS` | no | tolerance for a client retrying a refresh after a lost response (10) |
| `CORS_ALLOWED_ORIGINS` | no | comma-separated browser origins; native apps do not need CORS |
| `RATE_LIMIT_AUTH_REQUESTS` / `RATE_LIMIT_AUTH_WINDOW_SECONDS` | no | per-IP limit on `/auth/*` (10 per 60 s) |
| `TRUSTED_PROXY` | no | `true` only behind a reverse proxy you control: the client IP is read from `X-Forwarded-For` |
| `MAX_REQUEST_BODY_BYTES` | no | larger bodies get `413` (2 MiB) |
| `SENTRY_DSN` | no | empty disables error reporting |
| `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY` | no | turn on replay storage (set both or neither); the key stays on the server |
| `SUPABASE_REPLAY_BUCKET` | no | private bucket for replay files (`replays`, created at start-up if missing) |
| `REPLAY_MAX_BYTES` / `REPLAY_DOWNLOAD_TTL_SECONDS` | no | largest replay file (8 MiB) / lifetime of a download link (600 s) |

`APP_ENV=production` turns on start-up checks: the process refuses to start with a JWT secret shorter than 32
characters (or the placeholder), a `*` CORS origin, or a non-PostgreSQL database, and it disables `/docs`, `/redoc`
and `/openapi.json`.

## Using Supabase

Supabase gives this API two things: the PostgreSQL database and Storage for the replay files. Nothing else of Supabase
is used (no Supabase Auth, no Data API, no realtime): accounts, sync and every rule stay in this API.

1. **Database.** In the Supabase dashboard press **Connect** and copy the *Direct connection* string (or the *Session
   pooler* string when your network has no IPv6). Put it into `DATABASE_URL` in `backend/.env`; replace `[YOUR-PASSWORD]`
   and URL-encode special characters in the password. Both strings use port **5432**. The *Transaction pooler* (port
   6543) is refused at start-up because it does not support the prepared statements the driver uses. TLS is added
   automatically for `*.supabase.co` / `*.supabase.com`.
2. **Tables.** `make migrate` (`alembic upgrade head`) creates every table. Migration `0002` also switches **row-level
   security** on for all of them. This API connects as the table owner, which is not subject to those rules, so nothing
   changes for it; but Supabase's automatic REST (Data API) and its public `anon` key can no longer read or write any
   row, which is what you want because the phone only ever talks to this API.
3. **Replay storage.** Put `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` (Project settings → API keys; the *secret* or
   legacy *service_role* key) into `backend/.env`. When the API starts it creates the private bucket named by
   `SUPABASE_REPLAY_BUCKET` if it is missing. To create it by hand instead, run in the SQL editor:

   ```sql
   insert into storage.buckets (id, name, public, file_size_limit)
   values ('replays', 'replays', false, 8388608)
   on conflict (id) do nothing;
   ```

4. **Run only the API in Docker** when you use Supabase: `docker compose up --build api` would still start the local
   database because of `depends_on`, and compose overrides `DATABASE_URL` with the local one. Use instead
   `docker build -t gully-umpire-api ./backend && docker run --rm --env-file backend/.env -p 8000:8000 gully-umpire-api`,
   or run `make run` directly.

How a replay travels: the phone announces it (`POST /replays`), the API stores a row and answers with a short-lived signed
upload URL, the phone `PUT`s the file straight to Supabase Storage, then calls `POST /replays/{id}/complete`; the API
checks that the object exists with the announced size before marking it `READY`. Downloads work the same way with a
signed link. The phone never receives a Supabase key. Details: [`API_CONTRACT.md` §8](../docs/API_CONTRACT.md).

SSL note: `ssl=require` encrypts the connection but does not verify the server certificate. For certificate
verification follow Supabase's "SSL enforcement" page and pass the root certificate in your own deployment.

## Layout

```
backend/
├── app/
│   ├── main.py                 application factory (create_app)
│   ├── core/                   config, security (Argon2id, JWT), errors, logging, middleware, rate limit
│   ├── db/                     declarative base, portable column types, engine/session
│   ├── models/                 SQLAlchemy models, one file per table
│   ├── schemas/                Pydantic request/response models (auth, read, sync payloads)
│   ├── services/               business logic; scoring.py is pure (no I/O)
│   │   ├── replay_service.py   replay announce/complete/list/download/delete
│   │   ├── storage.py          ObjectStorage interface + Supabase Storage client (httpx)
│   │   └── sync/               POST /sync/push: registry, handlers, per-event savepoints
│   └── api/                    routers: health.py and v1/endpoints/*
├── alembic/                    migrations (env.py is async and reads app settings)
├── tests/                      mirrors app/: api/, services/, core/, db/
├── scripts/entrypoint.sh       container entrypoint (migrate, then uvicorn)
├── Dockerfile · .dockerignore · Makefile · pyproject.toml · requirements*.txt
```

Imports point downward only: `api` → `services` → `models`/`db`; `core` is used by everyone.

## How the important parts work

**Authentication.** Passwords are hashed with Argon2id (off the event loop). Access tokens are short-lived JWTs.
Refresh tokens are opaque random strings stored only as a SHA-256 hash and rotated on every use. Presenting an
already-rotated token after the grace window revokes the entire token family (theft detection). Disabled accounts are
rejected on login, refresh and every authenticated request. Unknown emails take as long to reject as known ones.

**Sync.** `POST /api/v1/sync/push` takes 1–100 events, applies them in order, and reports a status per event
(`APPLIED`, `DUPLICATE`, `REJECTED`). Each event runs in its own savepoint together with its idempotency-ledger row, so a
rejected event rolls back only itself and can be corrected and re-sent. The server derives `delivery_sequence`,
`over_number`, `legal_ball_number` and the innings totals; clients never send them. Delivery rules 1–13 live in
`app/services/scoring.py` and are tested against `docs/scoring_test_vectors.json`, both as pure functions and through the
HTTP API.

**Ownership.** Every read and write is scoped to the authenticated user (directly by `owner_id`, or through the parent
match). Another user's data is reported as not found, never as forbidden, on read endpoints.

**Deleting an account** removes matches first, then the roster, then the user, in one transaction. The order matters on
PostgreSQL because match data references players and teams with plain foreign keys. Replay rows go with the user
(cascade); the replay files are deleted from the bucket afterwards, and a file that cannot be deleted is logged and left
behind rather than failing a deletion that has already happened.

## Commands

| Command | What it does |
|---|---|
| `make test` | test suite on in-memory SQLite |
| `make cov` | same, with coverage; fails below 90 % |
| `make lint` / `make format` | ruff check + format check / fix |
| `make typecheck` | `mypy --strict` on `app/` |
| `make check` | lint + typecheck + test (what CI should run) |
| `make migrate` | `alembic upgrade head` |
| `make migration m="add foo"` | autogenerate a migration after changing a model, then review it by hand |
| `make docker-build` | build the production image |

### Running the tests against PostgreSQL

The same suite runs on PostgreSQL when `TEST_DATABASE_URL` is set. **Use a throw-away database**: every test drops and
re-creates the schema.

```bash
TEST_DATABASE_URL=postgresql+asyncpg://postgres:postgres@localhost:5432/gully_test make test
```

SQLite is a convenient default but PostgreSQL is what production runs; run both before a release. (This is how the
account-deletion ordering bug above was found.) The replay and storage tests use an in-memory fake storage and a mocked
HTTP transport, so they never contact Supabase; the Supabase Storage client was therefore only checked against its
documented API, not against a live project.

## Migrations

`alembic/versions/` holds one revision per schema change. `tests/db/test_migrations.py` checks, on every run, that the
migration upgrades and downgrades cleanly, has a single head, and produces exactly the schema the models describe
(including constraint and index names). After changing a model: `make migration m="…"`, edit the generated file (it must
not import application code), and run the tests.

## Docker

```bash
docker build -t gully-umpire-api ./backend
docker run --rm --env-file backend/.env -p 8000:8000 gully-umpire-api
```

The container runs as an unprivileged user, applies migrations at start (`RUN_MIGRATIONS=false` to skip), and exposes
`GET /health` (liveness) and `GET /health/ready` (checks the database). From the repository root, `docker compose up`
starts PostgreSQL and the API together. Set `WEB_CONCURRENCY` to run several worker processes.

## Operational notes

- **Rate limiting is per process.** With several workers or replicas the effective limit is multiplied; put a gateway
  or a Redis-backed limiter in front for real traffic.
- **Logs** are one JSON object per line on stdout with a request id (also returned as `X-Request-ID`). Bodies, tokens and
  passwords are never logged.
- **Backups and TLS** are the deployment's job: terminate TLS at a reverse proxy and back up PostgreSQL.
