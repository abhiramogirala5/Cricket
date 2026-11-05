from __future__ import annotations

from fastapi import APIRouter

from app.api.v1.endpoints import auth, matches, players, replays, sync, teams, users

api_router = APIRouter()
api_router.include_router(auth.router)
api_router.include_router(users.router)
api_router.include_router(players.router)
api_router.include_router(teams.router)
api_router.include_router(matches.router)
api_router.include_router(replays.router)
api_router.include_router(sync.router)
