"""POST /auth/register | login | refresh | logout (API_CONTRACT §3.2)."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Response, status

from app.api.deps import PasswordServiceDep, SessionDep, SettingsDep
from app.core.rate_limit import enforce_auth_rate_limit
from app.schemas.auth import (
    AuthResponse,
    LoginRequest,
    LogoutRequest,
    RefreshRequest,
    RegisterRequest,
    TokenPair,
    UserRead,
)
from app.services import auth_service
from app.services.auth_service import IssuedTokens

router = APIRouter(prefix="/auth", tags=["auth"], dependencies=[Depends(enforce_auth_rate_limit)])


def _token_pair(tokens: IssuedTokens) -> TokenPair:
    return TokenPair(
        access_token=tokens.access_token,
        refresh_token=tokens.refresh_token,
        expires_in=tokens.expires_in,
    )


@router.post("/register", response_model=AuthResponse, status_code=status.HTTP_201_CREATED)
async def register(
    body: RegisterRequest,
    session: SessionDep,
    settings: SettingsDep,
    passwords: PasswordServiceDep,
) -> AuthResponse:
    user, tokens = await auth_service.register(
        session,
        settings,
        passwords,
        email=body.email,
        password=body.password,
        display_name=body.display_name,
    )
    return AuthResponse(user=UserRead.model_validate(user), tokens=_token_pair(tokens))


@router.post("/login", response_model=AuthResponse)
async def login(
    body: LoginRequest,
    session: SessionDep,
    settings: SettingsDep,
    passwords: PasswordServiceDep,
) -> AuthResponse:
    user, tokens = await auth_service.login(
        session, settings, passwords, email=body.email, password=body.password
    )
    return AuthResponse(user=UserRead.model_validate(user), tokens=_token_pair(tokens))


@router.post("/refresh", response_model=TokenPair)
async def refresh(body: RefreshRequest, session: SessionDep, settings: SettingsDep) -> TokenPair:
    tokens = await auth_service.refresh(session, settings, refresh_token=body.refresh_token)
    return _token_pair(tokens)


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
async def logout(body: LogoutRequest, session: SessionDep) -> Response:
    await auth_service.logout(session, refresh_token=body.refresh_token)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
