"""Replay endpoints (API_CONTRACT §8) with an in-memory storage in place of Supabase."""

from __future__ import annotations

import hashlib
import uuid
from typing import Any

import httpx
import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncEngine, async_sessionmaker

from app.models.replay_clip import ReplayClip
from app.services.replay_service import storage_path_for
from app.services.storage import StorageError
from tests.fakes import FakeStorage
from tests.helpers import API, Account, register, uid

FILE = b"GUR1" + bytes(range(200))


def announcement(**overrides: Any) -> dict[str, Any]:
    body: dict[str, Any] = {
        "id": uid(),
        "match_id": uid(),
        "delivery_id": uid(),
        "size_bytes": len(FILE),
        "sha256": hashlib.sha256(FILE).hexdigest(),
        "width": 640,
        "height": 360,
        "frame_count": 42,
        "duration_ms": 1400,
    }
    body.update(overrides)
    return body


async def announce(
    client: httpx.AsyncClient, account: Account, body: dict[str, Any]
) -> httpx.Response:
    return await client.post(f"{API}/replays", json=body, headers=account.headers)


async def stored(
    client: httpx.AsyncClient, account: Account, storage: FakeStorage, **overrides: Any
) -> dict[str, Any]:
    """Announce, 'upload' and complete one replay; returns the finished replay."""
    body = announcement(**overrides)
    created = await announce(client, account, body)
    assert created.status_code == 201, created.text
    storage.put(
        storage_path_for(
            uuid.UUID(account.user_id), uuid.UUID(body["match_id"]), uuid.UUID(body["id"])
        ),
        FILE,
    )
    done = await client.post(f"{API}/replays/{body['id']}/complete", headers=account.headers)
    assert done.status_code == 200, done.text
    result: dict[str, Any] = done.json()
    return result


async def test_announce_returns_an_upload_target(
    replay_client: httpx.AsyncClient, storage: FakeStorage
) -> None:
    account = await register(replay_client)
    body = announcement()
    response = await announce(replay_client, account, body)
    assert response.status_code == 201
    data = response.json()
    assert data["replay"]["id"] == body["id"]
    assert data["replay"]["status"] == "PENDING"
    assert data["replay"]["uploaded_at"] is None
    upload = data["upload"]
    assert upload["method"] == "PUT"
    assert upload["headers"] == {"Content-Type": "application/octet-stream"}
    expected_path = storage_path_for(
        uuid.UUID(account.user_id), uuid.UUID(body["match_id"]), uuid.UUID(body["id"])
    )
    assert expected_path in upload["url"]
    assert upload["expires_in_seconds"] == 7200


async def test_announce_twice_is_harmless_and_refreshes_the_details(
    replay_client: httpx.AsyncClient,
) -> None:
    account = await register(replay_client)
    body = announcement()
    first = await announce(replay_client, account, body)
    second = await announce(replay_client, account, {**body, "frame_count": 50})
    assert first.status_code == second.status_code == 201
    assert second.json()["replay"]["frame_count"] == 50
    listing = await replay_client.get(f"{API}/replays", headers=account.headers)
    assert listing.json()["total"] == 0  # still pending: not listed


async def test_complete_requires_the_uploaded_file(
    replay_client: httpx.AsyncClient, storage: FakeStorage
) -> None:
    account = await register(replay_client)
    body = announcement()
    await announce(replay_client, account, body)
    missing = await replay_client.post(
        f"{API}/replays/{body['id']}/complete", headers=account.headers
    )
    assert missing.status_code == 409
    assert missing.json()["error"]["code"] == "UPLOAD_MISSING"

    path = storage_path_for(
        uuid.UUID(account.user_id), uuid.UUID(body["match_id"]), uuid.UUID(body["id"])
    )
    storage.put(path, FILE[:-1])
    short = await replay_client.post(
        f"{API}/replays/{body['id']}/complete", headers=account.headers
    )
    assert short.status_code == 409
    assert short.json()["error"]["code"] == "UPLOAD_SIZE_MISMATCH"

    storage.put(path, FILE)
    ok = await replay_client.post(f"{API}/replays/{body['id']}/complete", headers=account.headers)
    assert ok.status_code == 200
    assert ok.json()["status"] == "READY"
    assert ok.json()["uploaded_at"] is not None

    again = await replay_client.post(
        f"{API}/replays/{body['id']}/complete", headers=account.headers
    )
    assert again.status_code == 200
    assert again.json()["uploaded_at"] == ok.json()["uploaded_at"]


async def test_announcing_a_stored_replay_gives_no_upload_and_adopts_a_late_delivery_id(
    replay_client: httpx.AsyncClient, storage: FakeStorage
) -> None:
    account = await register(replay_client)
    first = await stored(replay_client, account, storage, delivery_id=None)
    assert first["delivery_id"] is None
    delivery_id = uid()
    again = await announce(
        replay_client,
        account,
        announcement(id=first["id"], match_id=first["match_id"], delivery_id=delivery_id),
    )
    assert again.status_code == 200
    assert again.json()["upload"] is None
    assert again.json()["replay"]["delivery_id"] == delivery_id
    # A second, different delivery id does not overwrite the first one.
    other = await announce(
        replay_client,
        account,
        announcement(id=first["id"], match_id=first["match_id"], delivery_id=uid()),
    )
    assert other.json()["replay"]["delivery_id"] == delivery_id


async def test_announce_rejects_oversized_files_and_bad_numbers(
    replay_client: httpx.AsyncClient,
) -> None:
    account = await register(replay_client)
    too_big = await announce(replay_client, account, announcement(size_bytes=8 * 1024 * 1024 + 1))
    assert too_big.status_code == 413
    assert too_big.json()["error"]["code"] == "PAYLOAD_TOO_LARGE"
    for bad in (
        {"size_bytes": 0},
        {"sha256": "ABC"},
        {"frame_count": 601},
        {"duration_ms": -1},
        {"width": 0},
        {"id": "not-a-uuid"},
    ):
        response = await announce(replay_client, account, announcement(**bad))
        assert response.status_code == 422, bad


async def test_replay_ids_cannot_be_taken_over_by_another_account(
    replay_client: httpx.AsyncClient, storage: FakeStorage
) -> None:
    owner = await register(replay_client)
    intruder = await register(replay_client)
    clip = await stored(replay_client, owner, storage)

    taken = await announce(
        replay_client, intruder, announcement(id=clip["id"], match_id=clip["match_id"])
    )
    assert taken.status_code == 409
    for method, url in (
        ("POST", f"{API}/replays/{clip['id']}/complete"),
        ("GET", f"{API}/replays/{clip['id']}/download"),
        ("DELETE", f"{API}/replays/{clip['id']}"),
    ):
        response = await replay_client.request(method, url, headers=intruder.headers)
        assert response.status_code == 404, (method, url)
        assert response.json()["error"]["code"] == "NOT_FOUND"
    assert storage.deleted == []
    listing = await replay_client.get(f"{API}/replays", headers=intruder.headers)
    assert listing.json()["total"] == 0


async def test_list_filters_and_orders_newest_first(
    replay_client: httpx.AsyncClient, storage: FakeStorage
) -> None:
    account = await register(replay_client)
    match = uid()
    delivery = uid()
    first = await stored(replay_client, account, storage, match_id=match, delivery_id=delivery)
    second = await stored(replay_client, account, storage, match_id=match)
    third = await stored(replay_client, account, storage)

    everything = await replay_client.get(f"{API}/replays", headers=account.headers)
    assert everything.json()["total"] == 3
    ids = [item["id"] for item in everything.json()["items"]]
    assert set(ids) == {first["id"], second["id"], third["id"]}

    of_match = await replay_client.get(
        f"{API}/replays", params={"match_id": match}, headers=account.headers
    )
    assert {item["id"] for item in of_match.json()["items"]} == {first["id"], second["id"]}

    of_delivery = await replay_client.get(
        f"{API}/replays", params={"delivery_id": delivery}, headers=account.headers
    )
    assert [item["id"] for item in of_delivery.json()["items"]] == [first["id"]]

    paged = await replay_client.get(
        f"{API}/replays", params={"limit": 2, "offset": 2}, headers=account.headers
    )
    assert paged.json()["total"] == 3
    assert len(paged.json()["items"]) == 1


async def test_download_returns_a_signed_link_for_stored_replays_only(
    replay_client: httpx.AsyncClient, storage: FakeStorage
) -> None:
    account = await register(replay_client)
    pending = announcement()
    await announce(replay_client, account, pending)
    not_ready = await replay_client.get(
        f"{API}/replays/{pending['id']}/download", headers=account.headers
    )
    assert not_ready.status_code == 404

    clip = await stored(replay_client, account, storage)
    response = await replay_client.get(
        f"{API}/replays/{clip['id']}/download", headers=account.headers
    )
    assert response.status_code == 200
    assert response.json()["expires_in_seconds"] == 600
    assert response.json()["url"].startswith("https://storage.test/download/")
    assert "ttl=600" in response.json()["url"]


async def test_delete_removes_the_file_and_the_row(
    replay_client: httpx.AsyncClient, storage: FakeStorage, engine: AsyncEngine
) -> None:
    account = await register(replay_client)
    clip = await stored(replay_client, account, storage)
    path = storage_path_for(
        uuid.UUID(account.user_id), uuid.UUID(clip["match_id"]), uuid.UUID(clip["id"])
    )
    assert path in storage.objects

    response = await replay_client.delete(f"{API}/replays/{clip['id']}", headers=account.headers)
    assert response.status_code == 204
    assert path not in storage.objects
    assert storage.deleted == [path]
    again = await replay_client.delete(f"{API}/replays/{clip['id']}", headers=account.headers)
    assert again.status_code == 404
    async with async_sessionmaker(engine)() as session:
        assert (await session.scalars(select(ReplayClip))).all() == []


async def test_storage_outage_is_a_503_and_changes_nothing_that_matters(
    replay_client: httpx.AsyncClient, storage: FakeStorage
) -> None:
    account = await register(replay_client)
    clip = await stored(replay_client, account, storage)
    pending = announcement()
    storage.fail_with = StorageError("down")

    announced = await announce(replay_client, account, pending)
    assert announced.status_code == 503
    assert announced.json()["error"]["code"] == "SERVICE_UNAVAILABLE"
    download = await replay_client.get(
        f"{API}/replays/{clip['id']}/download", headers=account.headers
    )
    assert download.status_code == 503
    delete = await replay_client.delete(f"{API}/replays/{clip['id']}", headers=account.headers)
    assert delete.status_code == 503
    complete = await replay_client.post(
        f"{API}/replays/{pending['id']}/complete", headers=account.headers
    )
    assert complete.status_code == 503

    # The replay that was stored is still there once the storage is back.
    storage.fail_with = None
    listing = await replay_client.get(f"{API}/replays", headers=account.headers)
    assert [item["id"] for item in listing.json()["items"]] == [clip["id"]]


async def test_replays_need_a_login(replay_client: httpx.AsyncClient) -> None:
    for method, url in (
        ("POST", f"{API}/replays"),
        ("GET", f"{API}/replays"),
        ("POST", f"{API}/replays/{uid()}/complete"),
        ("GET", f"{API}/replays/{uid()}/download"),
        ("DELETE", f"{API}/replays/{uid()}"),
    ):
        response = await replay_client.request(method, url)
        assert response.status_code == 401, (method, url)


async def test_without_storage_the_replay_endpoints_say_so(client: httpx.AsyncClient) -> None:
    account = await register(client)
    response = await announce(client, account, announcement())
    assert response.status_code == 503
    assert response.json()["error"]["code"] == "SERVICE_UNAVAILABLE"
    # Everything else keeps working.
    me = await client.get(f"{API}/users/me", headers=account.headers)
    assert me.status_code == 200


@pytest.mark.parametrize("path_kind", ["owner", "match", "clip"])
def test_storage_path_is_made_of_the_three_ids(path_kind: str) -> None:
    owner, match, clip = uuid.uuid4(), uuid.uuid4(), uuid.uuid4()
    path = storage_path_for(owner, match, clip)
    assert path == f"{owner}/{match}/{clip}.gur"
    assert {"owner": str(owner), "match": str(match), "clip": str(clip)}[path_kind] in path
    assert len(path) <= 200


async def test_deleting_the_account_removes_replay_rows_and_files(
    replay_client: httpx.AsyncClient, storage: FakeStorage, engine: AsyncEngine
) -> None:
    account = await register(replay_client)
    other = await register(replay_client)
    clip = await stored(replay_client, account, storage)
    pending = announcement()
    await announce(replay_client, account, pending)
    pending_path = storage_path_for(
        uuid.UUID(account.user_id), uuid.UUID(pending["match_id"]), uuid.UUID(pending["id"])
    )
    storage.put(pending_path, FILE)  # uploaded, but never completed
    kept = await stored(replay_client, other, storage)
    clip_path = storage_path_for(
        uuid.UUID(account.user_id), uuid.UUID(clip["match_id"]), uuid.UUID(clip["id"])
    )

    response = await replay_client.request(
        "DELETE", f"{API}/users/me", json={"password": account.password}, headers=account.headers
    )
    assert response.status_code == 204
    assert sorted(storage.deleted) == sorted([clip_path, pending_path])
    async with async_sessionmaker(engine)() as session:
        remaining = (await session.scalars(select(ReplayClip))).all()
    assert [row.id for row in remaining] == [uuid.UUID(kept["id"])]


async def test_a_file_that_cannot_be_removed_does_not_fail_the_account_deletion(
    replay_client: httpx.AsyncClient, storage: FakeStorage
) -> None:
    account = await register(replay_client)
    await stored(replay_client, account, storage)
    storage.fail_with = StorageError("down")
    response = await replay_client.request(
        "DELETE", f"{API}/users/me", json={"password": account.password}, headers=account.headers
    )
    assert response.status_code == 204
    storage.fail_with = None
    login = await replay_client.post(
        f"{API}/auth/login", json={"email": account.email, "password": account.password}
    )
    assert login.status_code == 401


async def test_deleting_the_account_works_without_storage(client: httpx.AsyncClient) -> None:
    account = await register(client)
    response = await client.request(
        "DELETE", f"{API}/users/me", json={"password": account.password}, headers=account.headers
    )
    assert response.status_code == 204
