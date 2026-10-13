"""Restaurant / menu browsing (signed-in users)."""
from __future__ import annotations

from fastapi import APIRouter, Depends, Query
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ...database import get_session
from ...errors import AppError
from ...models import MenuItem, Restaurant, User
from ..deps import get_current_user, pagination_params
from ..schemas import MenuItemOut, RestaurantOut, paginate

router = APIRouter()


@router.get("/restaurants")
def list_restaurants(
    page: int = Query(1),
    page_size: int = Query(20),
    _user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    page, page_size = pagination_params(page, page_size)
    total = session.execute(select(func.count()).select_from(Restaurant)).scalar() or 0
    rows = session.execute(
        select(Restaurant).order_by(Restaurant.name).offset((page - 1) * page_size).limit(page_size)
    ).scalars().all()
    items = [
        RestaurantOut(
            id=r.id,
            name=r.name,
            address=r.address,
            is_active=r.is_active,
            image_url=r.image_url,
            cuisine=r.cuisine,
            description=r.description,
            rating=r.rating,
            delivery_time_minutes=r.delivery_time_minutes,
        )
        for r in rows
    ]
    return paginate([i.model_dump() for i in items], total, page, page_size)


@router.get("/restaurants/{restaurant_id}/menu")
def restaurant_menu(
    restaurant_id: str,
    page: int = Query(1),
    page_size: int = Query(20),
    _user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    page, page_size = pagination_params(page, page_size)
    restaurant = session.get(Restaurant, restaurant_id)
    if restaurant is None:
        raise AppError(404, "RESTAURANT_NOT_FOUND", "Restaurant not found.",
                       {"restaurant_id": restaurant_id})
    total = session.execute(
        select(func.count()).select_from(MenuItem).where(MenuItem.restaurant_id == restaurant_id)
    ).scalar() or 0
    rows = session.execute(
        select(MenuItem)
        .where(MenuItem.restaurant_id == restaurant_id)
        .order_by(MenuItem.name)
        .offset((page - 1) * page_size).limit(page_size)
    ).scalars().all()
    items = [
        MenuItemOut(
            id=m.id, restaurant_id=m.restaurant_id, name=m.name,
            price_minor=m.price_minor, currency=m.currency, is_available=m.is_available,
        ).model_dump()
        for m in rows
    ]
    return paginate(items, total, page, page_size)
