"""Registration, login, refresh-token rotation and logout (API_CONTRACT §3)."""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Any, cast

from sqlalchemy import select, update
from sqlalchemy.engine import CursorResult
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings
from app.core.errors import (
    account_disabled,
    email_already_registered,
    invalid_credentials,
    invalid_refresh_token,
)
from app.core.security import (
    PasswordService,
    create_access_token,
    generate_refresh_token,
    hash_refresh_token,
)
from app.db.base import utcnow
from app.models.refresh_token import RefreshToken
from app.models.user import User


@dataclass(frozen=True, slots=True)
class IssuedTokens:
    access_token: str
    refresh_token: str
    expires_in: int


async def _issue_tokens(
    session: AsyncSession,
    settings: Settings,
    user: User,
    *,
    family_id: uuid.UUID | None,
    now: datetime,
) -> IssuedTokens:
    raw_refresh = generate_refresh_token()
    session.add(
        RefreshToken(
            user_id=user.id,
            family_id=family_id or uuid.uuid4(),
            token_hash=hash_refresh_token(raw_refresh),
            issued_at=now,
            expires_at=now + timedelta(days=settings.refresh_token_expire_days),
        )
    )
    return IssuedTokens(
        access_token=create_access_token(settings, user.id, now),
        refresh_token=raw_refresh,
        expires_in=settings.access_token_expire_minutes * 60,
    )


async def _revoke_family(session: AsyncSession, family_id: uuid.UUID, now: datetime) -> None:
    await session.execute(
        update(RefreshToken)
        .where(RefreshToken.family_id == family_id, RefreshToken.revoked_at.is_(None))
        .values(revoked_at=now)
    )


async def get_user_by_email(session: AsyncSession, email: str) -> User | None:
    return await session.scalar(select(User).where(User.email == email))


async def register(
    session: AsyncSession,
    settings: Settings,
    passwords: PasswordService,
    *,
    email: str,
    password: str,
    display_name: str,
) -> tuple[User, IssuedTokens]:
    if await get_user_by_email(session, email) is not None:
        raise email_already_registered()
    now = utcnow()
    user = User(
        email=email,
        password_hash=await passwords.hash(password),
        display_name=display_name,
        created_at=now,
        updated_at=now,
    )
    session.add(user)
    try:
        await session.flush()
    except IntegrityError as exc:  # concurrent registration of the same address
        await session.rollback()
        raise email_already_registered() from exc
    tokens = await _issue_tokens(session, settings, user, family_id=None, now=now)
    await session.commit()
    return user, tokens


async def login(
    session: AsyncSession,
    settings: Settings,
    passwords: PasswordService,
    *,
    email: str,
    password: str,
) -> tuple[User, IssuedTokens]:
    user = await get_user_by_email(session, email)
    if user is None:
        await passwords.burn_time(password)
        raise invalid_credentials()
    if not await passwords.verify(user.password_hash, password):
        raise invalid_credentials()
    if not user.is_active:
        raise account_disabled()
    if passwords.needs_rehash(user.password_hash):
        user.password_hash = await passwords.hash(password)
    now = utcnow()
    tokens = await _issue_tokens(session, settings, user, family_id=None, now=now)
    await session.commit()
    return user, tokens


async def refresh(
    session: AsyncSession,
    settings: Settings,
    *,
    refresh_token: str,
) -> IssuedTokens:
    """Rotate a refresh token; reusing a rotated one revokes its family (after a grace window)."""
    now = utcnow()
    row = await session.scalar(
        select(RefreshToken).where(RefreshToken.token_hash == hash_refresh_token(refresh_token))
    )
    if row is None or row.revoked_at is not None or row.expires_at <= now:
        raise invalid_refresh_token()

    if row.rotated_at is not None:
        age = (now - row.rotated_at).total_seconds()
        if age > settings.refresh_reuse_grace_seconds:
            # A token that was already exchanged is being replayed: assume theft, end the session.
            await _revoke_family(session, row.family_id, now)
            await session.commit()
        raise invalid_refresh_token()

    user = await session.get(User, row.user_id)
    if user is None:
        raise invalid_refresh_token()
    if not user.is_active:
        raise account_disabled()

    # Atomic rotation: only one of two concurrent requests with the same token can win.
    result = await session.execute(
        update(RefreshToken)
        .where(
            RefreshToken.id == row.id,
            RefreshToken.rotated_at.is_(None),
            RefreshToken.revoked_at.is_(None),
        )
        .values(rotated_at=now)
    )
    if cast("CursorResult[Any]", result).rowcount != 1:
        await session.rollback()
        raise invalid_refresh_token()
    tokens = await _issue_tokens(session, settings, user, family_id=row.family_id, now=now)
    await session.commit()
    return tokens


async def logout(session: AsyncSession, *, refresh_token: str) -> None:
    """Revoke the token's whole family. Idempotent: unknown tokens are ignored."""
    row = await session.scalar(
        select(RefreshToken).where(RefreshToken.token_hash == hash_refresh_token(refresh_token))
    )
    if row is None:
        return
    await _revoke_family(session, row.family_id, utcnow())
    await session.commit()
