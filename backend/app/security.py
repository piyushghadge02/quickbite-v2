"""Password hashing (bcrypt) and JWT bearer tokens (PyJWT)."""
from __future__ import annotations

import secrets
import uuid
from datetime import datetime, timedelta, timezone

import bcrypt
import jwt

from .config import settings

_BCRYPT_MAX_BYTES = 72


def hash_password(password: str) -> str:
    raw = password.encode("utf-8")
    if len(raw) > _BCRYPT_MAX_BYTES:
        raise ValueError("password too long")
    return bcrypt.hashpw(raw, bcrypt.gensalt()).decode("utf-8")


def verify_password(password: str, password_hash: str) -> bool:
    try:
        return bcrypt.checkpw(password.encode("utf-8"), password_hash.encode("utf-8"))
    except (ValueError, TypeError):
        return False


def new_id(prefix: str) -> str:
    return f"{prefix}_{secrets.token_hex(8)}"


def new_idempotency_key() -> str:
    return str(uuid.uuid4())


def create_access_token(*, user_id: str, role: str) -> tuple[str, datetime]:
    now = datetime.now(timezone.utc)
    expires = now + timedelta(minutes=settings.jwt_expires_minutes)
    payload = {"sub": user_id, "role": role, "iat": now, "exp": expires}
    token = jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)
    return token, expires


def decode_access_token(token: str) -> dict:
    """Decode and validate claims; raises jwt.PyJWTError on any problem."""
    payload = jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
    if not payload.get("sub") or not payload.get("role"):
        raise jwt.InvalidTokenError("missing sub/role claims")
    return payload
