"""Consistent error envelope: {code, message, details, request_id}.

Every error response — including Pydantic validation errors — uses this shape.
request_id is taken from the incoming X-Request-ID header or generated.
"""
from __future__ import annotations

import logging
import uuid
from typing import Any

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware

log = logging.getLogger("quickbite.errors")

REQUEST_ID_HEADER = "X-Request-ID"


class AppError(Exception):
    """Domain error that maps to an HTTP status + machine-readable code."""

    def __init__(self, status: int, code: str, message: str, details: Any = None):
        super().__init__(message)
        self.status = status
        self.code = code
        self.message = message
        self.details = details


def envelope(code: str, message: str, details: Any, request_id: str) -> dict:
    return {"code": code, "message": message, "details": details, "request_id": request_id}


class RequestIdMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        request_id = request.headers.get(REQUEST_ID_HEADER) or uuid.uuid4().hex[:16]
        request.state.request_id = request_id
        response = await call_next(request)
        response.headers[REQUEST_ID_HEADER] = request_id
        return response


def _request_id(request: Request) -> str:
    return getattr(request.state, "request_id", uuid.uuid4().hex[:16])


def register_error_handlers(app: FastAPI) -> None:
    app.add_middleware(RequestIdMiddleware)

    @app.exception_handler(AppError)
    async def app_error_handler(request: Request, exc: AppError):
        return JSONResponse(
            status_code=exc.status,
            content=envelope(exc.code, exc.message, exc.details, _request_id(request)),
        )

    @app.exception_handler(RequestValidationError)
    async def validation_handler(request: Request, exc: RequestValidationError):
        details = [
            {"loc": list(e.get("loc", [])), "msg": e.get("msg"), "type": e.get("type")}
            for e in exc.errors()
        ]
        return JSONResponse(
            status_code=422,
            content=envelope(
                "VALIDATION_ERROR", "Request validation failed.", details, _request_id(request)
            ),
        )

    @app.exception_handler(Exception)
    async def unhandled_handler(request: Request, exc: Exception):
        log.exception("unhandled error request_id=%s", _request_id(request))
        return JSONResponse(
            status_code=500,
            content=envelope(
                "INTERNAL_ERROR", "An unexpected error occurred.", None, _request_id(request)
            ),
        )
