"""Admin endpoints: cross-customer order overview + aggregate summary."""
from __future__ import annotations

from fastapi import APIRouter, Depends, Query
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ...database import get_session
from ...models import Order, OutboxEvent, QuarantineRecord, RetryJob, User
from ..deps import pagination_params, require_admin
from ..schemas import AdminSummary, OrderListItem, paginate

router = APIRouter()


@router.get("/admin/orders")
def admin_orders(
    status: str | None = Query(default=None),
    page: int = Query(1),
    page_size: int = Query(20),
    _admin: User = Depends(require_admin),
    session: Session = Depends(get_session),
):
    page, page_size = pagination_params(page, page_size)
    q = select(Order)
    if status:
        q = q.where(Order.status == status)
    total = session.execute(select(func.count()).select_from(q.subquery())).scalar() or 0
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


@router.get("/admin/summary", response_model=AdminSummary)
def admin_summary(
    _admin: User = Depends(require_admin),
    session: Session = Depends(get_session),
):
    by_status = {
        row[0]: row[1]
        for row in session.execute(
            select(Order.status, func.count()).group_by(Order.status)
        ).all()
    }
    outbox_pending = session.execute(
        select(func.count()).select_from(OutboxEvent).where(OutboxEvent.state == "pending")
    ).scalar() or 0
    outbox_scheduled = session.execute(
        select(func.count()).select_from(OutboxEvent).where(OutboxEvent.state == "scheduled")
    ).scalar() or 0
    retries_scheduled = session.execute(
        select(func.count()).select_from(RetryJob).where(RetryJob.state == "scheduled")
    ).scalar() or 0
    quarantine_total = session.execute(
        select(func.count()).select_from(QuarantineRecord)
    ).scalar() or 0
    return AdminSummary(
        orders_by_status=by_status,
        outbox_pending=outbox_pending,
        outbox_scheduled=outbox_scheduled,
        retries_scheduled=retries_scheduled,
        quarantine_total=quarantine_total,
    )
