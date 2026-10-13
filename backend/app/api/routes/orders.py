"""Order endpoints: checkout, listing, detail, history, notifications."""
from __future__ import annotations

from fastapi import APIRouter, Depends, Query, Response
from sqlalchemy import func, select
from sqlalchemy.orm import Session, selectinload

from ...database import get_session
from ...domain.checkout import checkout
from ...models import Driver, Notification, Order, OrderStatusHistory, User
from ..deps import (
    get_current_user,
    get_visible_order,
    idempotency_key_header,
    pagination_params,
    require_customer,
    request_id_header,
)
from ..schemas import (
    CheckoutAccepted,
    CheckoutRequest,
    HistoryEntry,
    NotificationOut,
    OrderItemOut,
    OrderListItem,
    OrderOut,
    paginate,
)

router = APIRouter()


def _order_to_out(order: Order, driver_name: str | None = None) -> dict:
    return OrderOut(
        id=order.id,
        customer_id=order.customer_id,
        restaurant_id=order.restaurant_id,
        delivery_address=order.delivery_address,
        currency=order.currency,
        total_minor=order.total_minor,
        status=order.status,
        version=order.version,
        failure_code=order.failure_code,
        driver_id=order.driver_id,
        driver_name=driver_name,
        created_at=order.created_at,
        updated_at=order.updated_at,
        items=[
            OrderItemOut(
                menu_item_id=i.menu_item_id, item_name=i.item_name,
                quantity=i.quantity, unit_price_minor=i.unit_price_minor,
            )
            for i in order.items
        ],
    ).model_dump()


@router.post("/orders", status_code=202)
def create_order(
    body: CheckoutRequest,
    response: Response,
    user: User = Depends(require_customer),
    idem_key: str = Depends(idempotency_key_header),
    request_id: str | None = Depends(request_id_header),
    session: Session = Depends(get_session),
):
    accepted, location, _created = checkout(
        session,
        customer_id=user.id,
        idem_key=idem_key,
        restaurant_id=body.restaurant_id,
        delivery_address=body.delivery_address,
        items=[i.model_dump() for i in body.items],
        correlation_id=request_id,
    )
    response.headers["Location"] = location
    return CheckoutAccepted(**accepted).model_dump()


@router.get("/orders")
def list_orders(
    status: str | None = Query(default=None),
    page: int = Query(1),
    page_size: int = Query(20),
    user: User = Depends(require_customer),
    session: Session = Depends(get_session),
):
    page, page_size = pagination_params(page, page_size)
    q = select(Order).where(Order.customer_id == user.id)
    if status:
        q = q.where(Order.status == status)
    total = session.execute(
        select(func.count()).select_from(q.subquery())
    ).scalar() or 0
    rows = session.execute(
        q.order_by(Order.created_at.desc()).offset((page - 1) * page_size).limit(page_size)
    ).scalars().all()
    items = [
        OrderListItem(
            id=o.id, restaurant_id=o.restaurant_id, currency=o.currency,
            total_minor=o.total_minor, status=o.status, version=o.version,
            created_at=o.created_at, updated_at=o.updated_at,
        ).model_dump()
        for o in rows
    ]
    return paginate(items, total, page, page_size)


@router.get("/orders/{order_id}")
def get_order(
    order_id: str,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    order = get_visible_order(order_id, user, session)
    order = session.execute(
        select(Order).options(selectinload(Order.items)).where(Order.id == order.id)
    ).scalar_one()
    driver_name = None
    if order.driver_id:
        driver = session.get(Driver, order.driver_id)
        driver_name = driver.name if driver else None
    return _order_to_out(order, driver_name)


@router.get("/orders/{order_id}/history")
def order_history(
    order_id: str,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    order = get_visible_order(order_id, user, session)
    rows = session.execute(
        select(OrderStatusHistory)
        .where(OrderStatusHistory.order_id == order.id)
        .order_by(OrderStatusHistory.version.asc(), OrderStatusHistory.id.asc())
    ).scalars().all()
    return [
        HistoryEntry(
            from_status=h.from_status, to_status=h.to_status, version=h.version,
            note=h.note, created_at=h.created_at,
        ).model_dump()
        for h in rows
    ]


@router.get("/orders/{order_id}/notifications")
def order_notifications(
    order_id: str,
    page: int = Query(1),
    page_size: int = Query(20),
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    page, page_size = pagination_params(page, page_size)
    order = get_visible_order(order_id, user, session)
    base = select(Notification).where(Notification.order_id == order.id)
    total = session.execute(select(func.count()).select_from(base.subquery())).scalar() or 0
    rows = session.execute(
        base.order_by(Notification.created_at.desc(), Notification.id.desc())
        .offset((page - 1) * page_size).limit(page_size)
    ).scalars().all()
    items = [
        NotificationOut(
            id=n.id, event_id=n.event_id, event_type=n.event_type, order_id=n.order_id,
            title=n.title, body=n.body, created_at=n.created_at,
        ).model_dump()
        for n in rows
    ]
    return paginate(items, total, page, page_size)
