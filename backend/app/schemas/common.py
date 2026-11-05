from __future__ import annotations

from pydantic import BaseModel, ConfigDict, Field


class ApiModel(BaseModel):
    """Base of every response model: built from ORM rows."""

    model_config = ConfigDict(from_attributes=True)


class RequestModel(BaseModel):
    """Base of every request model: unknown fields are rejected (VALIDATION_ERROR)."""

    model_config = ConfigDict(extra="forbid")


class Page[T](ApiModel):
    """List envelope (API_CONTRACT §4)."""

    items: list[T]
    total: int = Field(ge=0)
    limit: int = Field(ge=1)
    offset: int = Field(ge=0)


class StatusOk(ApiModel):
    status: str


class HealthReady(ApiModel):
    status: str
    database: str
