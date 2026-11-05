"""GET /matches and /matches/{match_id}/snapshot (API_CONTRACT §4)."""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, Query

from app.api.deps import CurrentUser, Limit, Offset, SessionDep
from app.models.enums import MatchStatus
from app.schemas.common import Page
from app.schemas.read import MatchSnapshot, MatchSummary
from app.services import read_service

router = APIRouter(prefix="/matches", tags=["matches"])


@router.get("", response_model=Page[MatchSummary])
async def list_matches(
    user: CurrentUser,
    session: SessionDep,
    status: Annotated[MatchStatus | None, Query(description="Filter by match status")] = None,
    limit: Limit = 50,
    offset: Offset = 0,
) -> Page[MatchSummary]:
    return await read_service.list_matches(
        session, user.id, status=status, limit=limit, offset=offset
    )


@router.get("/{match_id}/snapshot", response_model=MatchSnapshot)
async def match_snapshot(
    match_id: uuid.UUID, user: CurrentUser, session: SessionDep
) -> MatchSnapshot:
    return await read_service.get_match_snapshot(session, user.id, match_id)
