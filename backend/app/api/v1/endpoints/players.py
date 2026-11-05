"""GET /players (API_CONTRACT §4)."""

from __future__ import annotations

from fastapi import APIRouter

from app.api.deps import CurrentUser, Limit, Offset, SessionDep
from app.schemas.common import Page
from app.schemas.read import PlayerRead
from app.services import read_service

router = APIRouter(prefix="/players", tags=["players"])


@router.get("", response_model=Page[PlayerRead])
async def list_players(
    user: CurrentUser, session: SessionDep, limit: Limit = 50, offset: Offset = 0
) -> Page[PlayerRead]:
    return await read_service.list_players(session, user.id, limit=limit, offset=offset)
