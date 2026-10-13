"""POST /api/v1/auth/login, GET /api/v1/me."""
from __future__ import annotations

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from ...database import get_session
from ...errors import AppError
from ...models import User
from ...security import create_access_token, verify_password
from ..deps import get_current_user
from ..schemas import LoginRequest, LoginResponse, MeResponse, UserSummary

router = APIRouter()


@router.post("/auth/login", response_model=LoginResponse)
def login(body: LoginRequest, session: Session = Depends(get_session)):
    user = session.execute(
        select(User).where(User.email == body.email.strip().lower())
    ).scalar_one_or_none()
    if user is None or not verify_password(body.password, user.password_hash):
        raise AppError(401, "INVALID_CREDENTIALS", "Invalid email or password.")
    token, expires = create_access_token(user_id=user.id, role=user.role)
    return LoginResponse(
        access_token=token,
        expires_at=expires,
        role=user.role,
        user=UserSummary(id=user.id, email=user.email, name=user.name, role=user.role),
    )


@router.get("/me", response_model=MeResponse)
def me(user: User = Depends(get_current_user)):
    return MeResponse(
        id=user.id, email=user.email, name=user.name, role=user.role,
        created_at=user.created_at,
    )
