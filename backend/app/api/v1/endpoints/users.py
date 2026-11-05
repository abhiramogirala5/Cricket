"""GET / PATCH / DELETE /users/me (API_CONTRACT §3.3)."""

from __future__ import annotations

from fastapi import APIRouter, Response, status

from app.api.deps import CurrentUser, OptionalStorageDep, PasswordServiceDep, SessionDep
from app.schemas.auth import DeleteAccountRequest, UserRead, UserUpdate
from app.services import user_service

router = APIRouter(prefix="/users", tags=["users"])


@router.get("/me", response_model=UserRead)
async def read_me(user: CurrentUser) -> UserRead:
    return UserRead.model_validate(user)


@router.patch("/me", response_model=UserRead)
async def update_me(body: UserUpdate, user: CurrentUser, session: SessionDep) -> UserRead:
    updated = await user_service.update_profile(session, user, body)
    return UserRead.model_validate(updated)


@router.delete("/me", status_code=status.HTTP_204_NO_CONTENT)
async def delete_me(
    body: DeleteAccountRequest,
    user: CurrentUser,
    session: SessionDep,
    passwords: PasswordServiceDep,
    storage: OptionalStorageDep,
) -> Response:
    await user_service.delete_account(session, passwords, user, body.password, storage)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
