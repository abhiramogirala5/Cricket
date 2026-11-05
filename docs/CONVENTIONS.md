# Naming and structure conventions

## Repository layout

```
gully-umpire/
├── backend/        Python 3.12+ · FastAPI · SQLAlchemy 2 (async) · Alembic · PostgreSQL
├── frontend/       Flutter (Dart 3) · Riverpod · go_router · sqflite · dio
├── docs/           API contract, scoring rules, shared test vectors, conventions, reference specs
├── docker-compose.yml   local PostgreSQL + backend
└── README.md
```

`backend/` and `frontend/` never import from each other. Their only shared artefacts are the documents in `docs/`
(`API_CONTRACT.md`, `SCORING_RULES.md`, `scoring_test_vectors.json`).

## Secrets and configuration

| File | Committed | Contents |
|---|---|---|
| `backend/.env.example` | yes | every variable with a safe placeholder and a comment |
| `backend/.env` | **no** (git-ignored) | real values: `DATABASE_URL`, `JWT_SECRET_KEY`, `SENTRY_DSN`, … |
| `frontend/.env.example` | yes | `APP_ENV`, `API_BASE_URL`, feature flags |
| `frontend/.env` | **no** (git-ignored) | local values. Bundled as an asset → **never put secrets here** |
| `.env` at repo root | — | only used by `docker-compose.yml` for the Postgres password |

Code reads configuration through exactly one typed object: `app.core.config.Settings` (backend) and
`lib/core/config/app_config.dart` (frontend). No other file touches `os.environ` / `dotenv` directly.

## Python (backend)

| Thing | Convention | Example |
|---|---|---|
| Packages/modules | `snake_case`, singular nouns for models, plural for routers | `models/delivery.py`, `api/v1/endpoints/matches.py` |
| Classes | `PascalCase`; ORM models are singular nouns | `Delivery`, `RefreshToken` |
| Pydantic schemas | `<Thing>Read`, `<Thing>Create`, `<Thing>Update`, `<Thing>Payload` (sync) | `MatchRead`, `DeliveryPayload` |
| Services | `<domain>_service.py`, functions or small classes, no HTTP types | `auth_service.py`, `sync_service.py` |
| Pure logic | no I/O, no SQLAlchemy | `services/scoring.py` |
| Tables / columns | plural `snake_case` tables, singular columns | `deliveries.runs_bat` |
| Constraint names | via `MetaData(naming_convention=…)`: `ix_`, `uq_`, `ck_`, `fk_`, `pk_` | `uq_deliveries_innings_id_delivery_sequence` |
| Tests | mirror the package tree, `test_<module>.py` | `tests/services/test_scoring.py` |
| Tooling | `ruff` (lint + format), `mypy`, `pytest` | `make check` |

Layering (imports only point downward): `api` → `services` → `models` / `db`; `schemas` are used by `api` and `services`; `core` is used by everyone.

## Dart / Flutter (frontend)

| Thing | Convention | Example |
|---|---|---|
| Files and folders | `snake_case` | `live_scoring_screen.dart` |
| Types | `PascalCase` | `LiveScoringController` |
| Members/variables | `lowerCamelCase`; constants `lowerCamelCase` (Dart style) | `maxBatchSize` |
| Screens | `<name>_screen.dart` → `<Name>Screen` | `scorecard_screen.dart` |
| Reusable widgets | descriptive noun, `<name>.dart` | `score_summary_card.dart` |
| Riverpod | `<thing>Provider`; notifiers `<Thing>Controller`. Wiring lives in `core/di/` (no code generation) | `matchListProvider` |
| Repositories | concrete `<Thing>Repository` classes in `data/repositories/`; they depend on `LocalStore`, so tests use an in-memory SQLite | `match_repository.dart` |
| Local DB | `data/local/` — one place for SQL; records are stored as JSON documents with a few indexed columns | `local_store.dart` |
| Remote | `data/remote/` — `api_client.dart`, DTO mappers | |
| Pure logic next to a screen | a plain `.dart` file beside the `presentation/` folder, so it can be unit-tested without widgets | `features/scorecard/scorecard_text.dart` |
| Tests | mirror `lib/` under `test/`, suffix `_test.dart` | `test/domain/scoring/score_engine_test.dart` |

Folder structure (feature-first, layered inside the app core):

```
frontend/lib/
├── main.dart                     bootstrap only
├── app/                          App widget, router (routes.dart, app_router.dart), shell, theme
├── core/                         config (app_config.dart), DI wiring (di/), errors, utils, shared widgets
├── domain/                       PURE DART — models, scoring engine, scorecard, decisions, setup rules (no Flutter imports)
├── cv/                           PURE DART — computer-vision contracts, geometry, tracking, scene scan, pipelines, mock adapters
├── data/                         local (sqflite), remote (dio), repositories, session, sync outbox
└── features/<feature>/           screens in presentation/, plus pure helpers beside it (match flow, text, draft builders)
```

Dependency rule: `features` → `data`/`domain`/`cv`/`core`; `data` → `domain`; `cv` → `domain/decisions`; `domain` imports nothing from the other layers.
`core/di/` is the one place that may import from every layer, because it connects them.
`domain/` and `cv/` must not import `package:flutter/*` so they can be unit-tested with `flutter test` quickly (and with plain Dart).

## API naming

- Resource paths are plural lower-case nouns (`/matches`, `/players`), actions are verbs under a resource (`/auth/login`, `/sync/push`).
- JSON keys `snake_case`; enum values `UPPER_SNAKE_CASE`; error codes `UPPER_SNAKE_CASE`.

## Git

- Conventional-commit style messages (`feat(backend): …`, `fix(frontend): …`, `docs: …`).
- A change to `docs/API_CONTRACT.md` or `docs/SCORING_RULES.md` must update both sides and the shared vectors in the same pull request.
