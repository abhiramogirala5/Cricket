"""Settings parsing and the production guards."""

from __future__ import annotations

import pytest
from pydantic import ValidationError

from app.core.config import (
    PLACEHOLDER_JWT_SECRET,
    Settings,
    database_port,
    get_settings,
    normalize_database_url,
)

GOOD_SECRET = "s" * 48
PG_URL = "postgresql+asyncpg://user:pass@db.internal:5432/gully"

_ENV_NAMES = (
    "APP_ENV",
    "DATABASE_URL",
    "JWT_SECRET_KEY",
    "CORS_ALLOWED_ORIGINS",
    "ACCESS_TOKEN_EXPIRE_MINUTES",
    "REFRESH_TOKEN_EXPIRE_DAYS",
    "SENTRY_DSN",
    "TRUSTED_PROXY",
    "LOG_LEVEL",
    "SUPABASE_URL",
    "SUPABASE_SERVICE_ROLE_KEY",
    "SUPABASE_REPLAY_BUCKET",
    "REPLAY_MAX_BYTES",
    "REPLAY_DOWNLOAD_TTL_SECONDS",
)


@pytest.fixture(autouse=True)
def clean_env(monkeypatch: pytest.MonkeyPatch) -> None:
    for name in _ENV_NAMES:
        monkeypatch.delenv(name, raising=False)


def build(**values: object) -> Settings:
    base: dict[str, object] = {"database_url": PG_URL, "jwt_secret_key": GOOD_SECRET}
    base.update(values)
    return Settings(_env_file=None, **base)  # type: ignore[arg-type]


# ---------------------------------------------------------------------------- database url


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("postgres://u:p@h:5432/d", "postgresql+asyncpg://u:p@h:5432/d"),
        ("postgresql://u:p@h/d", "postgresql+asyncpg://u:p@h/d"),
        ("  postgres://u:p@h/d  ", "postgresql+asyncpg://u:p@h/d"),
        ("postgresql+asyncpg://u:p@h/d", "postgresql+asyncpg://u:p@h/d"),
        ("sqlite+aiosqlite:///./dev.db", "sqlite+aiosqlite:///./dev.db"),
    ],
)
def test_normalize_database_url(raw: str, expected: str) -> None:
    assert normalize_database_url(raw) == expected


def test_database_url_is_normalised_on_load() -> None:
    assert build(database_url="postgres://u:p@h/d").database_url == "postgresql+asyncpg://u:p@h/d"


def test_is_sqlite_flag() -> None:
    assert build(database_url="sqlite+aiosqlite://", app_env="test").is_sqlite
    assert not build().is_sqlite


# ---------------------------------------------------------------------------- required values


def test_database_url_and_secret_are_required() -> None:
    with pytest.raises(ValidationError) as excinfo:
        Settings(_env_file=None)  # type: ignore[call-arg]
    missing = {str(e["loc"][0]) for e in excinfo.value.errors()}
    assert missing == {"database_url", "jwt_secret_key"}


def test_values_are_read_from_the_environment(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("DATABASE_URL", "postgres://u:p@h/d")
    monkeypatch.setenv("JWT_SECRET_KEY", GOOD_SECRET)
    monkeypatch.setenv("ACCESS_TOKEN_EXPIRE_MINUTES", "5")
    monkeypatch.setenv("TRUSTED_PROXY", "true")
    settings = Settings(_env_file=None)  # type: ignore[call-arg]
    assert settings.database_url.startswith("postgresql+asyncpg://")
    assert settings.access_token_expire_minutes == 5
    assert settings.trusted_proxy is True


def test_get_settings_is_cached(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("DATABASE_URL", PG_URL)
    monkeypatch.setenv("JWT_SECRET_KEY", GOOD_SECRET)
    get_settings.cache_clear()
    try:
        assert get_settings() is get_settings()
    finally:
        get_settings.cache_clear()


# ---------------------------------------------------------------------------- defaults & bounds


def test_defaults() -> None:
    s = build()
    assert s.app_env == "development"
    assert s.jwt_algorithm == "HS256"
    assert s.access_token_expire_minutes == 15
    assert s.refresh_token_expire_days == 30
    assert s.refresh_reuse_grace_seconds == 10
    assert s.cors_allowed_origins == []
    assert s.trusted_proxy is False
    assert s.sentry_dsn is None
    assert s.max_request_body_bytes == 2 * 1024 * 1024
    assert not s.is_production


@pytest.mark.parametrize(
    "override",
    [
        {"access_token_expire_minutes": 0},
        {"access_token_expire_minutes": 1441},
        {"refresh_token_expire_days": 0},
        {"db_pool_size": 0},
        {"max_request_body_bytes": 10},
        {"argon2_time_cost": 0},
        {"log_level": "CHATTY"},
        {"jwt_algorithm": "none"},
        {"app_env": "prod"},
        {"jwt_secret_key": ""},
        {"database_url": ""},
    ],
)
def test_invalid_values_are_rejected(override: dict[str, object]) -> None:
    with pytest.raises(ValidationError):
        build(**override)


# ---------------------------------------------------------------------------- cors & sentry


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("", []),
        ("   ", []),
        ("https://a.example", ["https://a.example"]),
        ("https://a.example, https://b.example ,,", ["https://a.example", "https://b.example"]),
        (["https://a.example"], ["https://a.example"]),
        (None, []),
    ],
)
def test_cors_origins_parsing(raw: object, expected: list[str]) -> None:
    assert build(cors_allowed_origins=raw).cors_allowed_origins == expected


def test_cors_origins_from_environment(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("CORS_ALLOWED_ORIGINS", "https://a.example,https://b.example")
    assert build().cors_allowed_origins == ["https://a.example", "https://b.example"]


def test_blank_sentry_dsn_means_disabled(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("SENTRY_DSN", "   ")
    assert build().sentry_dsn is None
    assert build(sentry_dsn="https://key@o1.ingest.sentry.io/1").sentry_dsn is not None


# ---------------------------------------------------------------------------- production guards


def test_a_valid_production_configuration_is_accepted() -> None:
    settings = build(app_env="production", cors_allowed_origins="https://app.example.com")
    assert settings.is_production


@pytest.mark.parametrize(
    ("override", "fragment"),
    [
        ({"jwt_secret_key": PLACEHOLDER_JWT_SECRET}, "JWT_SECRET_KEY"),
        ({"jwt_secret_key": "too-short"}, "JWT_SECRET_KEY"),
        ({"cors_allowed_origins": "*"}, "CORS_ALLOWED_ORIGINS"),
        ({"cors_allowed_origins": "https://a.example,*"}, "CORS_ALLOWED_ORIGINS"),
        ({"database_url": "sqlite+aiosqlite:///./prod.db"}, "DATABASE_URL"),
    ],
)
def test_production_refuses_unsafe_settings(override: dict[str, object], fragment: str) -> None:
    with pytest.raises(ValidationError) as excinfo:
        build(app_env="production", **override)
    assert fragment in str(excinfo.value)


def test_production_reports_every_problem_at_once() -> None:
    with pytest.raises(ValidationError) as excinfo:
        build(
            app_env="production",
            jwt_secret_key="short",
            cors_allowed_origins="*",
            database_url="sqlite+aiosqlite://",
        )
    message = str(excinfo.value)
    assert all(
        name in message for name in ("JWT_SECRET_KEY", "CORS_ALLOWED_ORIGINS", "DATABASE_URL")
    )


@pytest.mark.parametrize("env", ["development", "staging", "test"])
def test_the_same_weak_values_are_allowed_outside_production(env: str) -> None:
    settings = build(
        app_env=env,
        jwt_secret_key="dev",
        cors_allowed_origins="*",
        database_url="sqlite+aiosqlite://",
    )
    assert not settings.is_production


# ---------------------------------------------------------------------------- Supabase database


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        # libpq's sslmode is translated to asyncpg's ssl.
        (
            "postgresql://u:p@h.example.com:5432/d?sslmode=require",
            "postgresql+asyncpg://u:p@h.example.com:5432/d?ssl=require",
        ),
        # Supabase hosts only accept TLS, so it is switched on when the URL says nothing.
        (
            "postgresql://postgres:p@db.abcdef.supabase.co:5432/postgres",
            "postgresql+asyncpg://postgres:p@db.abcdef.supabase.co:5432/postgres?ssl=require",
        ),
        (
            "postgres://postgres.abcdef:p@aws-0-eu.pooler.supabase.com:5432/postgres",
            "postgresql+asyncpg://postgres.abcdef:p@aws-0-eu.pooler.supabase.com:5432/postgres"
            "?ssl=require",
        ),
        # An explicit choice is respected.
        (
            "postgresql://postgres:p@db.abcdef.supabase.co:5432/postgres?ssl=disable",
            "postgresql+asyncpg://postgres:p@db.abcdef.supabase.co:5432/postgres?ssl=disable",
        ),
        # Other hosts are left alone.
        ("postgresql://u:p@localhost:5432/d", "postgresql+asyncpg://u:p@localhost:5432/d"),
    ],
)
def test_supabase_urls_get_tls(raw: str, expected: str) -> None:
    assert normalize_database_url(raw) == expected


def test_database_port() -> None:
    assert database_port("postgresql+asyncpg://u:p@h:6543/d") == 6543
    assert database_port("postgresql+asyncpg://u:p@h/d") is None
    assert database_port("not a url") is None


def test_the_transaction_pooler_port_is_refused_with_advice() -> None:
    with pytest.raises(ValidationError, match="5432"):
        build(database_url="postgresql://postgres.abc:p@aws-0-eu.pooler.supabase.com:6543/postgres")


# ---------------------------------------------------------------------------- Supabase storage


def test_replay_storage_is_off_by_default() -> None:
    settings = build()
    assert settings.supabase_url is None
    assert settings.supabase_service_role_key is None
    assert settings.replays_enabled is False
    assert settings.supabase_replay_bucket == "replays"
    assert settings.replay_max_bytes == 8 * 1024 * 1024
    assert settings.replay_download_ttl_seconds == 600


def test_replay_storage_is_on_when_url_and_key_are_set() -> None:
    settings = build(
        supabase_url="https://abc.supabase.co/", supabase_service_role_key=" sb_secret_Zq81 "
    )
    assert settings.replays_enabled is True
    assert settings.supabase_url == "https://abc.supabase.co"
    assert settings.supabase_service_role_key is not None
    assert settings.supabase_service_role_key.get_secret_value() == "sb_secret_Zq81"
    assert "sb_secret_Zq81" not in repr(settings)


def test_blank_supabase_values_mean_not_configured(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("SUPABASE_URL", "")
    monkeypatch.setenv("SUPABASE_SERVICE_ROLE_KEY", "  ")
    monkeypatch.setenv("DATABASE_URL", PG_URL)
    monkeypatch.setenv("JWT_SECRET_KEY", GOOD_SECRET)
    settings = Settings(_env_file=None)
    assert settings.replays_enabled is False


@pytest.mark.parametrize(
    "override",
    [
        {"supabase_url": "https://abc.supabase.co"},
        {"supabase_service_role_key": "key"},
    ],
)
def test_supabase_url_and_key_come_as_a_pair(override: dict[str, object]) -> None:
    with pytest.raises(ValidationError, match="SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY"):
        build(**override)


def test_supabase_url_must_be_a_web_address() -> None:
    with pytest.raises(ValidationError, match="https://"):
        build(supabase_url="abc.supabase.co", supabase_service_role_key="key")


def test_production_requires_https_for_supabase() -> None:
    values: dict[str, object] = {
        "app_env": "production",
        "supabase_url": "http://abc.supabase.co",
        "supabase_service_role_key": "key",
    }
    with pytest.raises(ValidationError, match="SUPABASE_URL must use https"):
        build(**values)
    build(**{**values, "supabase_url": "https://abc.supabase.co"})


@pytest.mark.parametrize(
    "override",
    [
        {"replay_max_bytes": 10},
        {"replay_max_bytes": 51 * 1024 * 1024},
        {"replay_download_ttl_seconds": 5},
        {"replay_download_ttl_seconds": 7200},
        {"supabase_replay_bucket": "ab"},
    ],
)
def test_replay_limits_are_range_checked(override: dict[str, object]) -> None:
    with pytest.raises(ValidationError):
        build(**override)
