"""Object storage for replay files: a small interface and its Supabase Storage implementation.

The phone never receives a Supabase key. It asks this API for a short-lived signed URL (to upload a
replay, or to download one) and talks to Supabase Storage directly with it, so replay files do not
pass through the API (and its small request-size limit) at all. The service-role key stays on the
server, in ``backend/.env``.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from typing import Protocol
from urllib.parse import quote, urlsplit

import httpx

logger = logging.getLogger(__name__)

_TIMEOUT = httpx.Timeout(10.0, connect=5.0)


class StorageError(Exception):
    """The storage service could not do what was asked (it is down, refused, or answered oddly)."""


@dataclass(frozen=True)
class SignedUpload:
    """Where and how to upload one object."""

    url: str
    method: str = "PUT"
    headers: dict[str, str] | None = None
    expires_in_seconds: int = 7200


class ObjectStorage(Protocol):
    """What the replay endpoints need from a storage service."""

    async def ensure_bucket(self) -> None:
        """Create the (private) bucket when it does not exist yet."""

    async def create_upload(self, path: str) -> SignedUpload:
        """A signed URL to which the object ``path`` can be uploaded."""

    async def object_size(self, path: str) -> int | None:
        """The size in bytes of the stored object, or ``None`` when there is none."""

    async def create_download_url(self, path: str, ttl_seconds: int) -> str:
        """A signed URL from which the object can be downloaded for ``ttl_seconds``."""

    async def delete(self, path: str) -> None:
        """Delete the object. A missing object is not an error."""

    async def aclose(self) -> None:
        """Release connections."""


def _looks_like_jwt(key: str) -> bool:
    return key.count(".") == 2


class SupabaseStorage:
    """``ObjectStorage`` on top of the Supabase Storage REST API (``/storage/v1``)."""

    def __init__(
        self,
        *,
        base_url: str,
        service_key: str,
        bucket: str,
        max_object_bytes: int,
        client: httpx.AsyncClient | None = None,
    ) -> None:
        self._base = base_url.rstrip("/") + "/storage/v1"
        self._bucket = bucket
        self._max_object_bytes = max_object_bytes
        self._client = client or httpx.AsyncClient(timeout=_TIMEOUT)
        # Legacy keys are JWTs and go in both headers. The newer "secret" keys are not JWTs and must
        # only be sent as ``apikey``; the Supabase gateway then adds the matching Authorization.
        self._headers = {"apikey": service_key}
        if _looks_like_jwt(service_key):
            self._headers["Authorization"] = f"Bearer {service_key}"

    # ---- helpers ---------------------------------------------------------------------------

    def _object_url(self, kind: str, path: str) -> str:
        return f"{self._base}/{kind}/{quote(self._bucket, safe='')}/{quote(path, safe='/')}"

    async def _send(
        self,
        method: str,
        url: str,
        *,
        expected: tuple[int, ...] = (200,),
        extra_headers: dict[str, str] | None = None,
        json: object | None = None,
    ) -> httpx.Response:
        headers = {**self._headers, **(extra_headers or {})}
        try:
            response = await self._client.request(method, url, headers=headers, json=json)
        except httpx.HTTPError as error:
            logger.warning("storage request failed: %s %s (%s)", method, urlsplit(url).path, error)
            raise StorageError("The storage service could not be reached.") from error
        if response.status_code not in expected:
            logger.warning(
                "storage request refused: %s %s -> %s",
                method,
                urlsplit(url).path,
                response.status_code,
            )
            raise StorageError(f"The storage service answered {response.status_code}.")
        return response

    def _absolute(self, location: str) -> str:
        """The API answers with a path relative to ``/storage/v1`` (older docs show full URLs)."""
        if location.startswith(("https://", "http://")):
            return location
        return f"{self._base}{location if location.startswith('/') else '/' + location}"

    # ---- ObjectStorage ---------------------------------------------------------------------

    async def ensure_bucket(self) -> None:
        body = {
            "id": self._bucket,
            "name": self._bucket,
            "public": False,
            "file_size_limit": self._max_object_bytes,
        }
        headers = {**self._headers}
        try:
            response = await self._client.post(f"{self._base}/bucket", headers=headers, json=body)
        except httpx.HTTPError as error:
            raise StorageError("The storage service could not be reached.") from error
        if response.status_code in (200, 201):
            logger.info("created the private storage bucket %s", self._bucket)
            return
        if response.status_code in (400, 409) and "exist" in response.text.lower():
            return
        raise StorageError(f"The bucket could not be created ({response.status_code}).")

    async def create_upload(self, path: str) -> SignedUpload:
        response = await self._send(
            "POST",
            self._object_url("object/upload/sign", path),
            extra_headers={"x-upsert": "true"},
        )
        try:
            data = response.json()
            location = str(data["url"])
        except (ValueError, KeyError, TypeError) as error:
            raise StorageError("The storage service sent an unreadable upload link.") from error
        return SignedUpload(
            url=self._absolute(location),
            method="PUT",
            headers={"Content-Type": "application/octet-stream"},
        )

    async def object_size(self, path: str) -> int | None:
        try:
            response = await self._client.request(
                "HEAD", self._object_url("object/authenticated", path), headers=self._headers
            )
        except httpx.HTTPError as error:
            raise StorageError("The storage service could not be reached.") from error
        if response.status_code in (400, 404):
            return None
        if response.status_code != 200:
            raise StorageError(f"The storage service answered {response.status_code}.")
        try:
            return int(response.headers["content-length"])
        except (KeyError, ValueError) as error:
            raise StorageError("The storage service did not report the size.") from error

    async def create_download_url(self, path: str, ttl_seconds: int) -> str:
        response = await self._send(
            "POST", self._object_url("object/sign", path), json={"expiresIn": ttl_seconds}
        )
        try:
            location = str(response.json()["signedURL"])
        except (ValueError, KeyError, TypeError) as error:
            raise StorageError("The storage service sent an unreadable download link.") from error
        return self._absolute(location)

    async def delete(self, path: str) -> None:
        await self._send("DELETE", self._object_url("object", path), expected=(200, 204, 400, 404))

    async def aclose(self) -> None:
        await self._client.aclose()
