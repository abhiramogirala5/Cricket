"""Password hashing (Argon2id), JWT access tokens and opaque refresh tokens."""

from __future__ import annotations

import asyncio
import hashlib
import secrets
import uuid
from datetime import datetime, timedelta

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError

from app.core.config import Settings
from app.core.errors import ApiError, invalid_token, token_expired

ACCESS_TOKEN_TYPE = "access"  # noqa: S105 - claim value, not a secret
_JWT_LEEWAY_SECONDS = 5


class PasswordService:
    """Argon2id hashing off the event loop. Never logs or returns the password."""

    def __init__(self, settings: Settings) -> None:
        self._hasher = PasswordHasher(
            time_cost=settings.argon2_time_cost,
            memory_cost=settings.argon2_memory_cost_kib,
            parallelism=settings.argon2_parallelism,
        )
        # Verified against when the account does not exist so both paths cost about the same.
        self._dummy_hash = self._hasher.hash(secrets.token_urlsafe(16))

    async def hash(self, password: str) -> str:
        return await asyncio.to_thread(self._hasher.hash, password)

    async def verify(self, password_hash: str, password: str) -> bool:
        try:
            return await asyncio.to_thread(self._hasher.verify, password_hash, password)
        except (VerificationError, InvalidHashError):
            return False

    async def burn_time(self, password: str) -> None:
        """Spend roughly the cost of one verification (unknown-email path)."""
        await self.verify(self._dummy_hash, password)

    def needs_rehash(self, password_hash: str) -> bool:
        return self._hasher.check_needs_rehash(password_hash)


def create_access_token(settings: Settings, user_id: uuid.UUID, now: datetime) -> str:
    expires = now + timedelta(minutes=settings.access_token_expire_minutes)
    claims = {
        "sub": str(user_id),
        "type": ACCESS_TOKEN_TYPE,
        "iat": int(now.timestamp()),
        "exp": int(expires.timestamp()),
        "jti": uuid.uuid4().hex,
    }
    return jwt.encode(claims, settings.jwt_secret_key, algorithm=settings.jwt_algorithm)


def decode_access_token(settings: Settings, token: str) -> uuid.UUID:
    """Return the user id or raise ``TOKEN_EXPIRED`` / ``INVALID_TOKEN``."""
    try:
        claims = jwt.decode(
            token,
            settings.jwt_secret_key,
            algorithms=[settings.jwt_algorithm],
            options={"require": ["exp", "iat", "sub", "type"]},
            leeway=_JWT_LEEWAY_SECONDS,
        )
    except jwt.ExpiredSignatureError as exc:
        raise token_expired() from exc
    except jwt.PyJWTError as exc:
        raise invalid_token() from exc
    if claims.get("type") != ACCESS_TOKEN_TYPE:
        raise invalid_token()
    try:
        return uuid.UUID(str(claims["sub"]))
    except ValueError as exc:
        raise invalid_token() from exc


def generate_refresh_token() -> str:
    """256+ bits of randomness, URL-safe."""
    return secrets.token_urlsafe(48)


def hash_refresh_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


__all__ = [
    "ACCESS_TOKEN_TYPE",
    "ApiError",
    "PasswordService",
    "create_access_token",
    "decode_access_token",
    "generate_refresh_token",
    "hash_refresh_token",
]
