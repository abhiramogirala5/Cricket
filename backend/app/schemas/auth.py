"""Auth and current-user schemas (API_CONTRACT §3)."""

from __future__ import annotations

import re
import uuid
from datetime import datetime
from typing import Annotated, Self

from pydantic import (
    EmailStr,
    Field,
    StringConstraints,
    field_validator,
    model_validator,
)

from app.schemas.common import ApiModel, RequestModel

_PHONE_PATTERN = re.compile(r"^[0-9+\-() ]{5,25}$")

DisplayName = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=100)]
Password = Annotated[str, Field(min_length=8, max_length=128)]
RefreshTokenValue = Annotated[str, Field(min_length=1, max_length=512)]


class _EmailMixin(RequestModel):
    email: EmailStr

    @field_validator("email", mode="before")
    @classmethod
    def _strip_email(cls, value: object) -> object:
        return value.strip() if isinstance(value, str) else value

    @field_validator("email", mode="after")
    @classmethod
    def _normalize_email(cls, value: str) -> str:
        if len(value) > 255:
            raise ValueError("email is too long (max 255 characters)")
        return value.lower()


class RegisterRequest(_EmailMixin):
    password: Password
    display_name: DisplayName


class LoginRequest(_EmailMixin):
    # No length rules on login: wrong-length passwords simply fail as INVALID_CREDENTIALS.
    password: str = Field(min_length=1, max_length=1024)


class RefreshRequest(RequestModel):
    refresh_token: RefreshTokenValue


class LogoutRequest(RequestModel):
    refresh_token: RefreshTokenValue


class UserRead(ApiModel):
    id: uuid.UUID
    email: str
    display_name: str
    phone: str | None = None
    avatar_url: str | None = None
    created_at: datetime


class TokenPair(ApiModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"  # noqa: S105 - OAuth token type, not a secret
    expires_in: int


class AuthResponse(ApiModel):
    user: UserRead
    tokens: TokenPair


class UserUpdate(RequestModel):
    display_name: DisplayName | None = None
    phone: str | None = None

    @field_validator("display_name", mode="after")
    @classmethod
    def _display_name_not_null(cls, value: str | None) -> str | None:
        if value is None:
            raise ValueError("display_name cannot be null")
        return value

    @field_validator("phone", mode="after")
    @classmethod
    def _phone_format(cls, value: str | None) -> str | None:
        if value is None:
            return None
        cleaned = value.strip()
        if not _PHONE_PATTERN.match(cleaned):
            raise ValueError("phone must be 5-25 characters: digits and + - ( ) space only")
        return cleaned

    @model_validator(mode="after")
    def _at_least_one_field(self) -> Self:
        if not self.model_fields_set:
            raise ValueError("provide at least one of: display_name, phone")
        return self


class DeleteAccountRequest(RequestModel):
    password: str = Field(min_length=1, max_length=1024)
