"""Pydantic request/response schemas for the /api/v1 contract."""
from __future__ import annotations

from datetime import datetime
from typing import Any, Generic, TypeVar

from pydantic import BaseModel, Field

T = TypeVar("T")


# --- pagination ------------------------------------------------------------
class Page(BaseModel, Generic[T]):
    items: list[T]
    page: int
    page_size: int
    total: int


def paginate(items: list[T], total: int, page: int, page_size: int) -> dict:
    return {"items": items, "page": page, "page_size": page_size, "total": total}


# --- auth -------------------------------------------------------------------
class LoginRequest(BaseModel):
    email: str = Field(min_length=3, max_length=255)
    password: str = Field(min_length=1, max_length=128)


class UserSummary(BaseModel):
    id: str
    email: str
    name: str
    role: str


class LoginResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_at: datetime
    role: str
    user: UserSummary


class MeResponse(UserSummary):
    created_at: datetime


# --- catalog -----------------------------------------------------------------
class RestaurantOut(BaseModel):
    id: str
    name: str
    address: str
    is_active: bool
    image_url: str | None = None
    cuisine: str | None = None
    description: str | None = None
    rating: float | None = None
    delivery_time_minutes: int | None = None


class MenuItemOut(BaseModel):
    id: str
    restaurant_id: str
    name: str
    price_minor: int
    currency: str
    is_available: bool


# --- checkout -----------------------------------------------------------------
class CheckoutItem(BaseModel):
    menu_item_id: str = Field(min_length=1, max_length=64)
    quantity: int = Field(ge=1, le=20)


class CheckoutRequest(BaseModel):
    restaurant_id: str = Field(min_length=1, max_length=64)
    delivery_address: str = Field(min_length=8, max_length=500)
    items: list[CheckoutItem] = Field(min_length=1, max_length=20)


class CheckoutAccepted(BaseModel):
    order_id: str
    status: str
    currency: str
    total_amount_minor: int
    version: int
    message: str


# --- orders --------------------------------------------------------------------
class OrderItemOut(BaseModel):
    menu_item_id: str
    item_name: str
    quantity: int
    unit_price_minor: int


class OrderOut(BaseModel):
    id: str
    customer_id: str
    restaurant_id: str
    delivery_address: str
    currency: str
    total_minor: int
    status: str
    version: int
    failure_code: str | None
    driver_id: str | None
    driver_name: str | None = None
    created_at: datetime
    updated_at: datetime
    items: list[OrderItemOut] = []


class OrderListItem(BaseModel):
    id: str
    restaurant_id: str
    currency: str
    total_minor: int
    status: str
    version: int
    created_at: datetime
    updated_at: datetime


class HistoryEntry(BaseModel):
    from_status: str | None
    to_status: str
    version: int
    note: str | None
    created_at: datetime


class NotificationOut(BaseModel):
    id: int
    event_id: str
    event_type: str
    order_id: str
    title: str
    body: str
    created_at: datetime


# --- admin ----------------------------------------------------------------------
class AdminSummary(BaseModel):
    orders_by_status: dict[str, int]
    outbox_pending: int
    outbox_scheduled: int
    retries_scheduled: int
    quarantine_total: int


class ErrorEnvelope(BaseModel):
    code: str
    message: str
    details: Any | None = None
    request_id: str


# --- health ----------------------------------------------------------------------
class HealthOut(BaseModel):
    status: str
    details: dict[str, Any] = {}
