"""Pure-ASGI middleware: request id, body-size limit, access log and last-resort 500 envelope."""

from __future__ import annotations

import logging
import re
import time
import uuid
from typing import Any

import sentry_sdk
from starlette.datastructures import Headers, MutableHeaders
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from app.core.errors import REQUEST_ID_HEADER, error_response, payload_too_large
from app.core.logging import request_id_ctx

_VALID_REQUEST_ID = re.compile(r"^[A-Za-z0-9._-]{1,64}$")
_access_log = logging.getLogger("app.access")
_error_log = logging.getLogger("app.error")


class RequestContextMiddleware:
    def __init__(self, app: ASGIApp, *, max_body_bytes: int) -> None:
        self.app = app
        self.max_body_bytes = max_body_bytes

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        headers = Headers(scope=scope)
        supplied = headers.get(REQUEST_ID_HEADER)
        request_id = (
            supplied if supplied and _VALID_REQUEST_ID.match(supplied) else uuid.uuid4().hex
        )
        scope.setdefault("state", {})["request_id"] = request_id
        token = request_id_ctx.set(request_id)

        started = time.perf_counter()
        status_code = 500
        response_started = False

        async def send_wrapper(message: Message) -> None:
            nonlocal status_code, response_started
            if message["type"] == "http.response.start":
                response_started = True
                status_code = int(message["status"])
                MutableHeaders(scope=message)[REQUEST_ID_HEADER] = request_id
            await send(message)

        try:
            declared = headers.get("content-length")
            if declared is not None and declared.isdigit() and int(declared) > self.max_body_bytes:
                response = error_response(
                    status_code=413,
                    code="PAYLOAD_TOO_LARGE",
                    message=f"The request body exceeds {self.max_body_bytes} bytes.",
                    request_id=request_id,
                )
                await response(scope, receive, send_wrapper)
            else:
                await self.app(scope, self._limited(receive), send_wrapper)
        except Exception as exc:
            _error_log.exception("Unhandled error while processing request")
            sentry_sdk.capture_exception(exc)
            if not response_started:
                response = error_response(
                    status_code=500,
                    code="INTERNAL_ERROR",
                    message="An unexpected error occurred.",
                    request_id=request_id,
                )
                await response(scope, receive, send_wrapper)
        finally:
            _access_log.info(
                "request",
                extra={
                    "method": scope.get("method"),
                    "path": scope.get("path"),
                    "status": status_code,
                    "duration_ms": round((time.perf_counter() - started) * 1000, 1),
                },
            )
            request_id_ctx.reset(token)

    def _limited(self, receive: Receive) -> Receive:
        """Count streamed body bytes; the resulting ApiError is rendered as a 413 envelope."""
        received = 0

        async def limited_receive() -> Message:
            nonlocal received
            message: dict[str, Any] = dict(await receive())
            if message["type"] == "http.request":
                received += len(message.get("body", b""))
                if received > self.max_body_bytes:
                    raise payload_too_large(self.max_body_bytes)
            return message

        return limited_receive
