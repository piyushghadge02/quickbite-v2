"""Auth / RBAC dependencies and shared API helpers."""
from __future__ import annotations

import jwt as pyjwt
from fastapi import Depends, Header, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..database import get_session
from ..errors import AppError
from ..models import Order, User
from ..security import decode_access_token

_bearer = HTTPBearer(auto_error=False)

MAX_PAGE_SIZE = 100


def get_current_user(
    creds: HTTPAuthorizationCredentials | None = Depends(_bearer),
    session: Session = Depends(get_session),
) -> User:
    if creds is None or not creds.credentials:
        raise AppError(401, "UNAUTHENTICATED", "Missing bearer token.")
    try:
        claims = decode_access_token(creds.credentials)
    except pyjwt.ExpiredSignatureError:
        raise AppError(401, "TOKEN_EXPIRED", "Access token has expired; sign in again.")
    except pyjwt.PyJWTError:
        raise AppError(401, "INVALID_TOKEN", "Access token is invalid.")
    user = session.get(User, claims["sub"])
    if user is None:
        raise AppError(401, "INVALID_TOKEN", "Access token is invalid.")
    return user


def require_admin(user: User = Depends(get_current_user)) -> User:
    if user.role != "admin":
        raise AppError(403, "FORBIDDEN", "Admin role required.")
    return user


def require_customer(user: User = Depends(get_current_user)) -> User:
    if user.role != "customer":
        raise AppError(403, "FORBIDDEN", "Customer role required.")
    return user


def get_visible_order(order_id: str, user: User, session: Session) -> Order:
    """Owner-or-admin visibility. Other customers' orders are 404 (no leak)."""
    order = session.get(Order, order_id)
    if order is None:
        raise AppError(404, "ORDER_NOT_FOUND", "Order not found.", {"order_id": order_id})
    if user.role != "admin" and order.customer_id != user.id:
        raise AppError(404, "ORDER_NOT_FOUND", "Order not found.", {"order_id": order_id})
    return order


def pagination_params(page: int = 1, page_size: int = 20) -> tuple[int, int]:
    if page < 1:
        raise AppError(422, "INVALID_PAGE", "page must be >= 1.", {"page": page})
    if page_size < 1 or page_size > MAX_PAGE_SIZE:
        raise AppError(
            422, "INVALID_PAGE_SIZE",
            f"page_size must be 1..{MAX_PAGE_SIZE}.", {"page_size": page_size},
        )
    return page, page_size


def idempotency_key_header(
    idempotency_key: str | None = Header(default=None, alias="Idempotency-Key"),
) -> str:
    if not idempotency_key:
        raise AppError(
            422, "MISSING_IDEMPOTENCY_KEY", "Idempotency-Key header is required.",
            {"header": "Idempotency-Key"},
        )
    return idempotency_key


def request_id_header(
    request_id: str | None = Header(default=None, alias="X-Request-ID"),
) -> str | None:
    return request_id
