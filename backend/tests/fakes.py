"""Test doubles."""

from __future__ import annotations

from app.services.storage import SignedUpload, StorageError


class FakeStorage:
    """An in-memory ``ObjectStorage``. ``put`` plays the part of the phone's upload."""

    def __init__(self) -> None:
        self.objects: dict[str, bytes] = {}
        self.deleted: list[str] = []
        self.bucket_checks = 0
        self.closed = False
        self.fail_with: StorageError | None = None

    def put(self, path: str, data: bytes) -> None:
        self.objects[path] = data

    def _check(self) -> None:
        if self.fail_with is not None:
            raise self.fail_with

    async def ensure_bucket(self) -> None:
        self.bucket_checks += 1
        self._check()

    async def create_upload(self, path: str) -> SignedUpload:
        self._check()
        return SignedUpload(
            url=f"https://storage.test/upload/{path}?token=t",
            headers={"Content-Type": "application/octet-stream"},
            expires_in_seconds=7200,
        )

    async def object_size(self, path: str) -> int | None:
        self._check()
        data = self.objects.get(path)
        return None if data is None else len(data)

    async def create_download_url(self, path: str, ttl_seconds: int) -> str:
        self._check()
        return f"https://storage.test/download/{path}?ttl={ttl_seconds}"

    async def delete(self, path: str) -> None:
        self._check()
        self.deleted.append(path)
        self.objects.pop(path, None)

    async def aclose(self) -> None:
        self.closed = True
