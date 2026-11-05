"""``SupabaseStorage`` against a mocked Supabase Storage REST API."""

from __future__ import annotations

import json
from collections.abc import Callable

import httpx
import pytest

from app.services.storage import StorageError, SupabaseStorage

BASE = "https://abc.supabase.co"
JWT_KEY = "eyJhbGciOi.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.c2lnbmF0dXJl"
SECRET_KEY = "sb_secret_abcdefghijklmnop"
PATH = "11111111-1111-1111-1111-111111111111/22222222-2222-2222-2222-222222222222/33333333.gur"


Handler = Callable[[httpx.Request], httpx.Response]


def storage_with(
    handler: Handler, *, key: str = JWT_KEY, bucket: str = "replays"
) -> tuple[SupabaseStorage, list[httpx.Request]]:
    """A ``SupabaseStorage`` whose HTTP calls go to ``handler``; also returns the requests seen."""
    seen: list[httpx.Request] = []

    def record(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return handler(request)

    client = httpx.AsyncClient(transport=httpx.MockTransport(record))
    storage = SupabaseStorage(
        base_url=BASE,
        service_key=key,
        bucket=bucket,
        max_object_bytes=8 * 1024 * 1024,
        client=client,
    )
    return storage, seen


async def test_upload_link_is_made_absolute_and_asks_for_upsert() -> None:
    def answer(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json={"url": f"/object/upload/sign/replays/{PATH}?token=abc"})

    storage, seen = storage_with(answer)
    upload = await storage.create_upload(PATH)
    assert upload.url == f"{BASE}/storage/v1/object/upload/sign/replays/{PATH}?token=abc"
    assert upload.method == "PUT"
    assert upload.headers == {"Content-Type": "application/octet-stream"}
    request = seen[0]
    assert request.method == "POST"
    assert str(request.url) == f"{BASE}/storage/v1/object/upload/sign/replays/{PATH}"
    assert request.headers["x-upsert"] == "true"
    await storage.aclose()


async def test_upload_link_may_already_be_absolute() -> None:
    def answer(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json={"url": "https://other.example/upload?token=1"})

    storage, _ = storage_with(answer)
    assert (await storage.create_upload(PATH)).url == "https://other.example/upload?token=1"


async def test_legacy_jwt_keys_are_sent_as_apikey_and_bearer() -> None:
    def answer(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json={"url": "/x"})

    storage, seen = storage_with(answer, key=JWT_KEY)
    await storage.create_upload(PATH)
    assert seen[0].headers["apikey"] == JWT_KEY
    assert seen[0].headers["authorization"] == f"Bearer {JWT_KEY}"


async def test_new_style_secret_keys_are_sent_only_as_apikey() -> None:
    def answer(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json={"url": "/x"})

    storage, seen = storage_with(answer, key=SECRET_KEY)
    await storage.create_upload(PATH)
    assert seen[0].headers["apikey"] == SECRET_KEY
    assert "authorization" not in seen[0].headers


async def test_object_names_and_bucket_are_url_encoded() -> None:
    def answer(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json={"url": "/x"})

    storage, seen = storage_with(answer, bucket="my replays")
    await storage.create_upload("a b/c#d.gur")
    assert seen[0].url.raw_path.decode() == (
        "/storage/v1/object/upload/sign/my%20replays/a%20b/c%23d.gur"
    )


async def test_object_size_comes_from_the_content_length() -> None:
    def answer(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, headers={"content-length": "1234"})

    storage, seen = storage_with(answer)
    assert await storage.object_size(PATH) == 1234
    assert seen[0].method == "HEAD"
    assert str(seen[0].url) == f"{BASE}/storage/v1/object/authenticated/replays/{PATH}"


@pytest.mark.parametrize("status", [400, 404])
async def test_object_size_of_a_missing_object_is_none(status: int) -> None:
    storage, _ = storage_with(lambda request: httpx.Response(status))
    assert await storage.object_size(PATH) is None


async def test_object_size_errors() -> None:
    server_error, _ = storage_with(lambda request: httpx.Response(500))
    with pytest.raises(StorageError):
        await server_error.object_size(PATH)

    no_size, _ = storage_with(lambda request: httpx.Response(200))
    with pytest.raises(StorageError):
        await no_size.object_size(PATH)


async def test_download_link_is_signed_for_the_given_time() -> None:
    def answer(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json={"signedURL": f"/object/sign/replays/{PATH}?token=t"})

    storage, seen = storage_with(answer)
    url = await storage.create_download_url(PATH, 600)
    assert url == f"{BASE}/storage/v1/object/sign/replays/{PATH}?token=t"
    assert json.loads(seen[0].content) == {"expiresIn": 600}
    assert str(seen[0].url) == f"{BASE}/storage/v1/object/sign/replays/{PATH}"


async def test_unreadable_answers_are_storage_errors() -> None:
    storage, _ = storage_with(lambda request: httpx.Response(200, json={"nope": 1}))
    with pytest.raises(StorageError):
        await storage.create_upload(PATH)
    with pytest.raises(StorageError):
        await storage.create_download_url(PATH, 60)

    html, _ = storage_with(lambda request: httpx.Response(200, text="<html>"))
    with pytest.raises(StorageError):
        await html.create_upload(PATH)


async def test_refusals_and_network_failures_are_storage_errors() -> None:
    refused, _ = storage_with(lambda request: httpx.Response(403, json={"error": "no"}))
    with pytest.raises(StorageError, match="403"):
        await refused.create_upload(PATH)

    def unreachable(request: httpx.Request) -> httpx.Response:
        raise httpx.ConnectError("no route", request=request)

    down, _ = storage_with(unreachable)
    with pytest.raises(StorageError):
        await down.create_upload(PATH)
    with pytest.raises(StorageError):
        await down.object_size(PATH)
    with pytest.raises(StorageError):
        await down.ensure_bucket()


@pytest.mark.parametrize("status", [200, 204, 400, 404])
async def test_delete_tolerates_missing_objects(status: int) -> None:
    storage, seen = storage_with(lambda request: httpx.Response(status))
    await storage.delete(PATH)
    assert seen[0].method == "DELETE"
    assert str(seen[0].url) == f"{BASE}/storage/v1/object/replays/{PATH}"


async def test_delete_reports_server_errors() -> None:
    storage, _ = storage_with(lambda request: httpx.Response(500))
    with pytest.raises(StorageError):
        await storage.delete(PATH)


async def test_ensure_bucket_creates_a_private_bucket() -> None:
    storage, seen = storage_with(lambda request: httpx.Response(200, json={"name": "replays"}))
    await storage.ensure_bucket()
    assert str(seen[0].url) == f"{BASE}/storage/v1/bucket"
    body = json.loads(seen[0].content)
    assert body == {
        "id": "replays",
        "name": "replays",
        "public": False,
        "file_size_limit": 8 * 1024 * 1024,
    }


@pytest.mark.parametrize("status", [400, 409])
async def test_ensure_bucket_accepts_an_existing_bucket(status: int) -> None:
    storage, _ = storage_with(
        lambda request: httpx.Response(
            status, json={"error": "Duplicate", "message": "The resource already exists"}
        )
    )
    await storage.ensure_bucket()


async def test_ensure_bucket_reports_other_failures() -> None:
    storage, _ = storage_with(lambda request: httpx.Response(401, json={"error": "bad key"}))
    with pytest.raises(StorageError, match="401"):
        await storage.ensure_bucket()
