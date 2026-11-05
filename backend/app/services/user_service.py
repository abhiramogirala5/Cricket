"""Current-user operations (API_CONTRACT §3.3)."""

from __future__ import annotations

import logging

from sqlalchemy import delete
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import password_incorrect
from app.core.security import PasswordService
from app.models.match import Match
from app.models.player import Player
from app.models.team import Team
from app.models.user import User
from app.schemas.auth import UserUpdate
from app.services import replay_service
from app.services.storage import ObjectStorage, StorageError

logger = logging.getLogger(__name__)


async def update_profile(session: AsyncSession, user: User, update: UserUpdate) -> User:
    fields = update.model_fields_set
    if "display_name" in fields and update.display_name is not None:
        user.display_name = update.display_name
    if "phone" in fields:
        user.phone = update.phone  # None clears the number
    await session.commit()
    return user


async def delete_account(
    session: AsyncSession,
    passwords: PasswordService,
    user: User,
    password: str,
    storage: ObjectStorage | None = None,
) -> None:
    """Delete the user and everything they own, in one transaction.

    Matches go first (their innings, deliveries, decisions, scans and so on follow by cascade),
    then the roster, and finally the user (which cascades to refresh tokens and the sync ledger).
    The order is explicit on purpose: players and teams are referenced by match data with plain
    ``NO ACTION`` foreign keys, and PostgreSQL would otherwise be free to try deleting a player
    before the match rows that mention it are gone.

    The replay rows go with the user (cascade). The replay files in the bucket are removed
    afterwards, one by one; a file that cannot be removed is logged and left behind rather than
    failing an account deletion that has already happened.
    """
    if not await passwords.verify(user.password_hash, password):
        raise password_incorrect()
    owner_id = user.id
    replay_paths = await replay_service.storage_paths_of(session, owner_id) if storage else []
    await session.execute(delete(Match).where(Match.owner_id == owner_id))
    await session.execute(delete(Player).where(Player.owner_id == owner_id))
    await session.execute(delete(Team).where(Team.owner_id == owner_id))
    await session.execute(delete(User).where(User.id == owner_id))
    await session.commit()
    if storage is None:
        return
    for path in replay_paths:
        try:
            await storage.delete(path)
        except StorageError:
            logger.warning("a replay file of a deleted account could not be removed: %s", path)
