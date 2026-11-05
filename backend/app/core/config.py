"""Typed application settings. This is the ONLY module that reads the environment."""

from __future__ import annotations

from functools import lru_cache
from pathlib import Path
from typing import Annotated, Literal, Self
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

from pydantic import Field, SecretStr, field_validator, model_validator
from pydantic_settings import BaseSettings, NoDecode, SettingsConfigDict

PLACEHOLDER_JWT_SECRET = "change-me-to-a-long-random-string"  # noqa: S105 - documented placeholder
MIN_PRODUCTION_SECRET_LENGTH = 32
_ENV_FILE = Path(__file__).resolve().parents[2] / ".env"

AppEnv = Literal["development", "staging", "production", "test"]


SUPABASE_HOST_SUFFIXES = (".supabase.co", ".supabase.com")
SUPABASE_TRANSACTION_POOLER_PORT = 6543


def normalize_database_url(url: str) -> str:
    """Make a PostgreSQL URL usable with the asyncpg driver.

    * ``postgres://`` / ``postgresql://`` become ``postgresql+asyncpg://``;
    * asyncpg does not know libpq's ``sslmode``: ``sslmode=require`` becomes ``ssl=require``;
    * a Supabase host without any SSL setting gets ``ssl=require`` (Supabase only accepts TLS).
    """
    value = url.strip()
    for prefix in ("postgres://", "postgresql://"):
        if value.startswith(prefix):
            value = "postgresql+asyncpg://" + value[len(prefix) :]
            break
    if not value.startswith("postgresql+asyncpg://"):
        return value
    parts = urlsplit(value)
    query = [(k, v) for k, v in parse_qsl(parts.query, keep_blank_values=True)]
    names = {k for k, _ in query}
    if "sslmode" in names:
        query = [("ssl" if k == "sslmode" else k, v) for k, v in query]
        names = {k for k, _ in query}
    host = (parts.hostname or "").lower()
    if "ssl" not in names and host.endswith(SUPABASE_HOST_SUFFIXES):
        query.append(("ssl", "require"))
    return urlunsplit(parts._replace(query=urlencode(query)))


def database_port(url: str) -> int | None:
    """The port in a database URL, or ``None`` when it has none (or cannot be read)."""
    try:
        return urlsplit(url).port
    except ValueError:
        return None


class Settings(BaseSettings):
    """Configuration loaded from environment variables and ``backend/.env``."""

    model_config = SettingsConfigDict(
        env_file=_ENV_FILE,
        env_file_encoding="utf-8",
        extra="ignore",
        case_sensitive=False,
    )

    app_name: str = "Gully Umpire API"
    app_env: AppEnv = "development"

    database_url: str = Field(min_length=1)
    db_pool_size: int = Field(default=10, ge=1, le=100)
    db_max_overflow: int = Field(default=10, ge=0, le=100)
    db_pool_timeout_seconds: int = Field(default=30, ge=1, le=300)
    db_echo: bool = False

    jwt_secret_key: str = Field(min_length=1)
    jwt_algorithm: Literal["HS256"] = "HS256"
    access_token_expire_minutes: int = Field(default=15, ge=1, le=1440)
    refresh_token_expire_days: int = Field(default=30, ge=1, le=365)
    refresh_reuse_grace_seconds: int = Field(default=10, ge=0, le=300)

    cors_allowed_origins: Annotated[list[str], NoDecode] = Field(default_factory=list)

    rate_limit_auth_requests: int = Field(default=10, ge=1, le=10_000)
    rate_limit_auth_window_seconds: int = Field(default=60, ge=1, le=3600)
    trusted_proxy: bool = False

    max_request_body_bytes: int = Field(default=2 * 1024 * 1024, ge=1024)

    # Supabase Storage keeps the replay files of deliveries. The database itself is the Supabase
    # PostgreSQL database (DATABASE_URL). Leave both unset to run without replay storage.
    supabase_url: str | None = None
    supabase_service_role_key: SecretStr | None = None
    supabase_replay_bucket: str = Field(default="replays", min_length=3, max_length=63)
    replay_max_bytes: int = Field(default=8 * 1024 * 1024, ge=1024, le=50 * 1024 * 1024)
    replay_download_ttl_seconds: int = Field(default=600, ge=60, le=3600)

    log_level: Literal["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"] = "INFO"

    sentry_dsn: str | None = None
    sentry_traces_sample_rate: float = Field(default=0.0, ge=0.0, le=1.0)

    # Argon2id cost parameters. The defaults follow the argon2-cffi / RFC 9106 low-memory profile;
    # tests lower them for speed.
    argon2_time_cost: int = Field(default=3, ge=1, le=10)
    argon2_memory_cost_kib: int = Field(default=65_536, ge=8, le=1_048_576)
    argon2_parallelism: int = Field(default=4, ge=1, le=16)

    @field_validator("database_url", mode="before")
    @classmethod
    def _normalize_database_url(cls, value: object) -> object:
        return normalize_database_url(value) if isinstance(value, str) else value

    @field_validator("cors_allowed_origins", mode="before")
    @classmethod
    def _split_origins(cls, value: object) -> object:
        if value is None:
            return []
        if isinstance(value, str):
            return [item.strip() for item in value.split(",") if item.strip()]
        return value

    @field_validator("supabase_url", "supabase_service_role_key", mode="before")
    @classmethod
    def _empty_supabase_is_none(cls, value: object) -> object:
        if isinstance(value, str) and not value.strip():
            return None
        return value.strip() if isinstance(value, str) else value

    @field_validator("supabase_url")
    @classmethod
    def _supabase_url_shape(cls, value: str | None) -> str | None:
        if value is None:
            return None
        value = value.rstrip("/")
        if not value.startswith(("https://", "http://")):
            raise ValueError(
                "SUPABASE_URL must start with https:// (for example https://abc.supabase.co)"
            )
        return value

    @field_validator("sentry_dsn", mode="before")
    @classmethod
    def _empty_dsn_is_none(cls, value: object) -> object:
        if isinstance(value, str) and not value.strip():
            return None
        return value

    @model_validator(mode="after")
    def _database_and_storage_guards(self) -> Self:
        if database_port(self.database_url) == SUPABASE_TRANSACTION_POOLER_PORT:
            raise ValueError(
                "DATABASE_URL points to port 6543 (Supabase's transaction pooler), which does not "
                "support the prepared statements this API uses. Use the direct connection or the "
                "session pooler instead: both listen on port 5432."
            )
        if (self.supabase_url is None) != (self.supabase_service_role_key is None):
            raise ValueError(
                "SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set together "
                "(or both left empty to run without replay storage)"
            )
        return self

    @model_validator(mode="after")
    def _production_guards(self) -> Self:
        if self.app_env != "production":
            return self
        problems: list[str] = []
        if self.supabase_url is not None and not self.supabase_url.startswith("https://"):
            problems.append("SUPABASE_URL must use https:// in production")
        if (
            len(self.jwt_secret_key) < MIN_PRODUCTION_SECRET_LENGTH
            or self.jwt_secret_key == PLACEHOLDER_JWT_SECRET
        ):
            problems.append(
                "JWT_SECRET_KEY must be a random secret of at least "
                f"{MIN_PRODUCTION_SECRET_LENGTH} "
                "characters (not the documented placeholder)"
            )
        if "*" in self.cors_allowed_origins:
            problems.append("CORS_ALLOWED_ORIGINS must not contain '*' in production")
        if not self.database_url.startswith("postgresql"):
            problems.append("DATABASE_URL must point to PostgreSQL in production")
        if problems:
            raise ValueError("Invalid production configuration: " + "; ".join(problems))
        return self

    @property
    def replays_enabled(self) -> bool:
        """Replay files can be stored (Supabase Storage is configured)."""
        return self.supabase_url is not None and self.supabase_service_role_key is not None

    @property
    def is_production(self) -> bool:
        return self.app_env == "production"

    @property
    def is_sqlite(self) -> bool:
        return self.database_url.startswith("sqlite")


@lru_cache
def get_settings() -> Settings:
    """Process-wide settings (cached). Tests build their own ``Settings`` instead."""
    return Settings()  # required fields come from the environment
