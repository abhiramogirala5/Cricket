"""GET /teams (API_CONTRACT §4)."""

from __future__ import annotations

from fastapi import APIRouter

from app.api.deps import CurrentUser, Limit, Offset, SessionDep
from app.schemas.common import Page
from app.schemas.read import TeamRead
from app.services import read_service

router = APIRouter(prefix="/teams", tags=["teams"])


@router.get("", response_model=Page[TeamRead])
async def list_teams(
    user: CurrentUser, session: SessionDep, limit: Limit = 50, offset: Offset = 0
) -> Page[TeamRead]:
    return await read_service.list_teams(session, user.id, limit=limit, offset=offset)
