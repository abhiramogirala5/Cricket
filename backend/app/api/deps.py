"""Shared FastAPI dependencies."""

from __future__ import annotations

from typing import Annotated

from fastapi import Depends, Query, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings
from app.core.errors import (
    account_disabled,
    invalid_token,
    not_authenticated,
    service_unavailable,
)
from app.core.security import PasswordService, decode_access_token
from app.db.session import get_session
from app.models.user import User
from app.services.storage import ObjectStorage

bearer_scheme = HTTPBearer(auto_error=False, description="Access token from /auth/login")


def get_app_settings(request: Request) -> Settings:
    settings: Settings = request.app.state.settings
    return settings


def get_password_service(request: Request) -> PasswordService:
    service: PasswordService = request.app.state.password_service
    return service


def get_storage(request: Request) -> ObjectStorage:
    """The replay file storage; 503 when the server was started without Supabase Storage."""
    storage: ObjectStorage | None = request.app.state.storage
    if storage is None:
        raise service_unavailable("Replay storage is not set up on this server.")
    return storage


def get_optional_storage(request: Request) -> ObjectStorage | None:
    """The replay file storage, or ``None`` when the server runs without it."""
    storage: ObjectStorage | None = request.app.state.storage
    return storage


SessionDep = Annotated[AsyncSession, Depends(get_session)]
SettingsDep = Annotated[Settings, Depends(get_app_settings)]
PasswordServiceDep = Annotated[PasswordService, Depends(get_password_service)]
StorageDep = Annotated[ObjectStorage, Depends(get_storage)]
OptionalStorageDep = Annotated[ObjectStorage | None, Depends(get_optional_storage)]


async def get_current_user(
    session: SessionDep,
    settings: SettingsDep,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer_scheme)],
) -> User:
    if credentials is None:
        raise not_authenticated()
    user_id = decode_access_token(settings, credentials.credentials)
    user = await session.get(User, user_id)
    if user is None:
        raise invalid_token()
    if not user.is_active:
        raise account_disabled()
    return user


CurrentUser = Annotated[User, Depends(get_current_user)]

Limit = Annotated[int, Query(ge=1, le=100, description="Page size (1-100)")]
Offset = Annotated[int, Query(ge=0, description="Items to skip")]
