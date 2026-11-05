"""API error type and the JSON error envelope (docs/API_CONTRACT.md §1.1)."""

from __future__ import annotations

from typing import Any

from fastapi import FastAPI, Request
from fastapi.encoders import jsonable_encoder
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

REQUEST_ID_HEADER = "X-Request-ID"

_STATUS_TO_CODE: dict[int, str] = {
    400: "BAD_REQUEST",
    401: "NOT_AUTHENTICATED",
    403: "FORBIDDEN",
    404: "NOT_FOUND",
    405: "METHOD_NOT_ALLOWED",
    409: "CONFLICT",
    413: "PAYLOAD_TOO_LARGE",
    422: "VALIDATION_ERROR",
    429: "RATE_LIMITED",
    503: "SERVICE_UNAVAILABLE",
}


class ApiError(StarletteHTTPException):
    """An error that is rendered as the standard envelope.

    Inheriting from Starlette's ``HTTPException`` lets it travel through FastAPI's request parsing
    untouched (FastAPI re-raises ``HTTPException`` subclasses as is).
    """

    def __init__(
        self,
        status_code: int,
        code: str,
        message: str,
        *,
        details: list[dict[str, Any]] | None = None,
        headers: dict[str, str] | None = None,
    ) -> None:
        super().__init__(status_code=status_code, detail=message, headers=headers)
        self.code = code
        self.message = message
        self.details = details


# ---- shortcuts -------------------------------------------------------------------------------


def not_authenticated(message: str = "Authentication required.") -> ApiError:
    return ApiError(401, "NOT_AUTHENTICATED", message, headers={"WWW-Authenticate": "Bearer"})


def token_expired() -> ApiError:
    return ApiError(
        401,
        "TOKEN_EXPIRED",
        "The access token has expired.",
        headers={"WWW-Authenticate": "Bearer"},
    )


def invalid_token() -> ApiError:
    return ApiError(
        401, "INVALID_TOKEN", "The access token is invalid.", headers={"WWW-Authenticate": "Bearer"}
    )


def invalid_credentials() -> ApiError:
    return ApiError(401, "INVALID_CREDENTIALS", "Incorrect email or password.")


def invalid_refresh_token() -> ApiError:
    return ApiError(401, "INVALID_REFRESH_TOKEN", "The refresh token is invalid or has expired.")


def account_disabled() -> ApiError:
    return ApiError(403, "ACCOUNT_DISABLED", "This account has been disabled.")


def password_incorrect() -> ApiError:
    return ApiError(403, "PASSWORD_INCORRECT", "The password is not correct.")


def not_found(message: str = "Resource not found.") -> ApiError:
    return ApiError(404, "NOT_FOUND", message)


def email_already_registered() -> ApiError:
    return ApiError(
        409, "EMAIL_ALREADY_REGISTERED", "An account with this email address already exists."
    )


def payload_too_large(limit: int) -> ApiError:
    return ApiError(413, "PAYLOAD_TOO_LARGE", f"The request body exceeds {limit} bytes.")


def rate_limited(retry_after_seconds: int) -> ApiError:
    return ApiError(
        429,
        "RATE_LIMITED",
        "Too many requests. Please try again later.",
        headers={"Retry-After": str(max(1, retry_after_seconds))},
    )


def service_unavailable(message: str = "The service is temporarily unavailable.") -> ApiError:
    return ApiError(503, "SERVICE_UNAVAILABLE", message)


# ---- rendering -------------------------------------------------------------------------------


def request_id_of(request: Request) -> str | None:
    value = getattr(request.state, "request_id", None)
    return value if isinstance(value, str) else None


def build_error_body(
    *,
    code: str,
    message: str,
    request_id: str | None,
    details: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    error: dict[str, Any] = {"code": code, "message": message}
    if details is not None:
        error["details"] = details
    error["request_id"] = request_id
    return {"error": error}


def error_response(
    *,
    status_code: int,
    code: str,
    message: str,
    request_id: str | None,
    details: list[dict[str, Any]] | None = None,
    headers: dict[str, str] | None = None,
) -> JSONResponse:
    out_headers = dict(headers or {})
    if request_id:
        out_headers[REQUEST_ID_HEADER] = request_id
    return JSONResponse(
        status_code=status_code,
        content=build_error_body(
            code=code, message=message, request_id=request_id, details=details
        ),
        headers=out_headers,
    )


async def _handle_http_exception(request: Request, exc: Exception) -> JSONResponse:
    assert isinstance(exc, StarletteHTTPException)  # noqa: S101 - registered for this type only
    request_id = request_id_of(request)
    if isinstance(exc, ApiError):
        return error_response(
            status_code=exc.status_code,
            code=exc.code,
            message=exc.message,
            request_id=request_id,
            details=exc.details,
            headers=dict(exc.headers) if exc.headers else None,
        )
    code = _STATUS_TO_CODE.get(
        exc.status_code, "INTERNAL_ERROR" if exc.status_code >= 500 else "BAD_REQUEST"
    )
    message = exc.detail if isinstance(exc.detail, str) and exc.detail else "Request failed."
    if exc.status_code == 404:
        message = "Resource not found."
    return error_response(
        status_code=exc.status_code,
        code=code,
        message=message,
        request_id=request_id,
        headers=dict(exc.headers) if exc.headers else None,
    )


def validation_details(exc: RequestValidationError) -> list[dict[str, Any]]:
    """Only location, message and type: never the submitted value (it may be a password)."""
    details: list[dict[str, Any]] = []
    for item in exc.errors():
        details.append(
            {
                "loc": jsonable_encoder(list(item.get("loc", ()))),
                "msg": str(item.get("msg", "Invalid value")),
                "type": str(item.get("type", "value_error")),
            }
        )
    return details


async def _handle_validation_error(request: Request, exc: Exception) -> JSONResponse:
    assert isinstance(exc, RequestValidationError)  # noqa: S101 - registered for this type only
    return error_response(
        status_code=422,
        code="VALIDATION_ERROR",
        message="The request is not valid.",
        request_id=request_id_of(request),
        details=validation_details(exc),
    )


def register_exception_handlers(app: FastAPI) -> None:
    app.add_exception_handler(StarletteHTTPException, _handle_http_exception)
    app.add_exception_handler(RequestValidationError, _handle_validation_error)
