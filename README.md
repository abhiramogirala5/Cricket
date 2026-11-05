# Gully Umpire

Cricket scoring and an AI umpiring assistant for informal "gully" cricket. Score a match ball by ball on the phone, even
with no signal; the app keeps everything on the device and syncs to your account when it can.

| Folder | What is in it |
|---|---|
| [`backend/`](backend/README.md) | Python 3.12+ · FastAPI · SQLAlchemy 2 (async) · Alembic · PostgreSQL. Accounts, sync, match storage |
| [`frontend/`](frontend/README.md) | Flutter (Android and iOS) · Riverpod · go_router · sqflite · dio. The app |
| [`docs/`](docs/) | API contract, scoring rules, shared test vectors, conventions, how the original spec was adapted |

The two apps never import each other. They share only three files in `docs/`: `API_CONTRACT.md`, `SCORING_RULES.md` and
`scoring_test_vectors.json`. Both sides test against the vectors, so the scoring maths cannot drift apart.

## Run it locally

```bash
# 1. Backend (needs Python 3.12+ and PostgreSQL, or Docker)
cd backend
cp .env.example .env          # set JWT_SECRET_KEY (python -c "import secrets; print(secrets.token_hex(32))") and DATABASE_URL
make install && make migrate && make run        # http://127.0.0.1:8000, docs at /docs

# or the whole backend with Docker:
cp .env.example .env && cp backend/.env.example backend/.env   # from the repository root; set the secrets in both
docker compose up --build

# 2. App (needs the Flutter SDK)
cd frontend
python3 tool/bootstrap_platforms.py
flutter pub get && flutter run
```

On the Android emulator the app reaches the backend at `http://10.0.2.2:8000` (already the default in
`frontend/.env.example`). Leave `API_BASE_URL` empty to try the app without any server.

## Secrets and configuration

All keys live in env files that are git-ignored; each has a committed `.env.example` that explains every value.

| File | Holds |
|---|---|
| `backend/.env` | `DATABASE_URL`, `JWT_SECRET_KEY`, `SENTRY_DSN`, CORS and rate-limit settings |
| `frontend/.env` | non-secret app settings only (it is bundled into the app, so anything in it can be read) |
| `.env` (root) | only the PostgreSQL password for `docker-compose.yml` |

`APP_ENV=production` makes both sides refuse unsafe settings at start-up (short or placeholder JWT secret, non-HTTPS API
address, simulated vision turned on, and so on).

## Quality checks

```bash
cd backend  && make check        # ruff, mypy --strict, pytest (SQLite; set TEST_DATABASE_URL for PostgreSQL)
cd frontend && make check        # flutter analyze, flutter test
```

## What to know before relying on it

* The umpire assistant is **not** backed by trained models yet. Development builds can show a clearly labelled simulation;
  all other builds are score-only and never invent a call. Details and limits: [`docs/SPEC_ADAPTATIONS.md`](docs/SPEC_ADAPTATIONS.md).
* The backend's rate limiter is in-process, so a multi-instance deployment needs a shared limiter in front.
* See [`docs/SPEC_ADAPTATIONS.md`](docs/SPEC_ADAPTATIONS.md) §6 for the full list of known limitations.
