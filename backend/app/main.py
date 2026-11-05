"""Application factory.

Run with ``uvicorn app.main:create_app --factory`` (see Makefile and scripts/entrypoint.sh).
"""

from __future__ import annotations

import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

import sentry_sdk
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.ext.asyncio import AsyncEngine

from app import __version__
from app.api.health import router as health_router
from app.api.v1.router import api_router
from app.core.config import Settings, get_settings
from app.core.errors import REQUEST_ID_HEADER, register_exception_handlers
from app.core.logging import configure_logging
from app.core.middleware import RequestContextMiddleware
from app.core.rate_limit import SlidingWindowRateLimiter
from app.core.security import PasswordService
from app.db.session import create_engine, create_session_factory
from app.services.storage import ObjectStorage, StorageError, SupabaseStorage

logger = logging.getLogger(__name__)


def _init_sentry(settings: Settings) -> None:
    if not settings.sentry_dsn:
        return
    sentry_sdk.init(
        dsn=settings.sentry_dsn,
        environment=settings.app_env,
        release=__version__,
        traces_sample_rate=settings.sentry_traces_sample_rate,
        send_default_pii=False,
    )


def _make_storage(settings: Settings) -> ObjectStorage | None:
    """Supabase Storage for replay files, or ``None`` when it is not configured."""
    if settings.supabase_url is None or settings.supabase_service_role_key is None:
        return None
    return SupabaseStorage(
        base_url=settings.supabase_url,
        service_key=settings.supabase_service_role_key.get_secret_value(),
        bucket=settings.supabase_replay_bucket,
        max_object_bytes=settings.replay_max_bytes,
    )


def create_app(
    settings: Settings | None = None,
    *,
    engine: AsyncEngine | None = None,
    storage: ObjectStorage | None = None,
) -> FastAPI:
    """Build the FastAPI app. Tests pass their own ``settings``, ``engine`` and ``storage``."""
    settings = settings or get_settings()
    configure_logging(settings.log_level)
    _init_sentry(settings)

    owns_engine = engine is None
    db_engine = engine if engine is not None else create_engine(settings)
    owns_storage = storage is None
    replay_storage = storage if storage is not None else _make_storage(settings)

    @asynccontextmanager
    async def lifespan(_app: FastAPI) -> AsyncIterator[None]:
        if replay_storage is not None and owns_storage:
            try:
                await replay_storage.ensure_bucket()
            except StorageError as error:
                # The API still works without the bucket: only replay uploads fail until it exists.
                logger.warning("could not check the replay bucket: %s", error)
        yield
        if replay_storage is not None and owns_storage:
            await replay_storage.aclose()
        if owns_engine:
            await db_engine.dispose()

    docs_enabled = not settings.is_production
    app = FastAPI(
        title=settings.app_name,
        version=__version__,
        description="Backend for Gully Umpire: accounts, offline-first sync and match storage.",
        lifespan=lifespan,
        docs_url="/docs" if docs_enabled else None,
        redoc_url="/redoc" if docs_enabled else None,
        openapi_url="/openapi.json" if docs_enabled else None,
    )

    app.state.settings = settings
    app.state.engine = db_engine
    app.state.storage = replay_storage
    app.state.session_factory = create_session_factory(db_engine)
    app.state.password_service = PasswordService(settings)
    app.state.auth_rate_limiter = SlidingWindowRateLimiter(
        settings.rate_limit_auth_requests, settings.rate_limit_auth_window_seconds
    )

    register_exception_handlers(app)

    if settings.cors_allowed_origins:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=settings.cors_allowed_origins,
            allow_methods=["GET", "POST", "PATCH", "DELETE", "OPTIONS"],
            allow_headers=["Authorization", "Content-Type", REQUEST_ID_HEADER],
            expose_headers=[REQUEST_ID_HEADER, "Retry-After"],
            max_age=600,
        )
    # Added last = outermost: every response (including CORS pre-flights) gets a request id.
    app.add_middleware(RequestContextMiddleware, max_body_bytes=settings.max_request_body_bytes)

    app.include_router(health_router)
    app.include_router(api_router, prefix="/api/v1")
    return app
