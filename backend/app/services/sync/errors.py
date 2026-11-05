"""Per-event sync error codes (API_CONTRACT §5.4)."""

from __future__ import annotations

INVALID_PAYLOAD = "INVALID_PAYLOAD"
UNSUPPORTED_EVENT = "UNSUPPORTED_EVENT"
FORBIDDEN = "FORBIDDEN"
PARENT_NOT_FOUND = "PARENT_NOT_FOUND"
INVALID_REFERENCE = "INVALID_REFERENCE"
INVALID_STATE = "INVALID_STATE"
INVALID_DELIVERY = "INVALID_DELIVERY"
INNINGS_CLOSED = "INNINGS_CLOSED"
OVER_LIMIT_EXCEEDED = "OVER_LIMIT_EXCEEDED"
NOT_LAST_DELIVERY = "NOT_LAST_DELIVERY"
ENTITY_NOT_FOUND = "ENTITY_NOT_FOUND"
INTERNAL_ERROR = "INTERNAL_ERROR"


class SyncRejection(Exception):  # noqa: N818 - a domain signal, not an error class
    """Raised by a handler to reject one event. The event's savepoint is rolled back."""

    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message
