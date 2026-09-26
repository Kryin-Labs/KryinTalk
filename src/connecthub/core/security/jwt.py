"""
ConnectHub — JWT Token Management.

Creates and verifies JSON Web Tokens for authentication.
Uses HS256 symmetric signing — suitable for single-service deployments.
Upgrade to RS256 asymmetric if multi-service token verification is needed.

Token types:
    - access: Short-lived (30 min default), carries user context
    - refresh: Longer-lived (7 days default), used to rotate access tokens
"""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone
from typing import Any, Literal

from jose import JWTError, jwt
from pydantic import BaseModel

from connecthub.config import settings


class TokenPayload(BaseModel):
    """Decoded JWT payload."""

    sub: str  # user_id
    org: str | None = None  # organization_id
    type: Literal["access", "refresh"] = "access"
    exp: datetime
    iat: datetime


class TokenPair(BaseModel):
    """Access + refresh token pair returned on login."""

    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int  # seconds until access token expires


def create_access_token(
    user_id: uuid.UUID,
    organization_id: uuid.UUID | None = None,
    extra_claims: dict[str, Any] | None = None,
) -> str:
    """Create a short-lived access token.

    Args:
        user_id: The authenticated user's ID.
        organization_id: The user's organization ID.
        extra_claims: Additional claims to include in the token.

    Returns:
        Encoded JWT string.
    """
    now = datetime.now(timezone.utc)
    expire = now + timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)

    payload: dict[str, Any] = {
        "sub": str(user_id),
        "org": str(organization_id) if organization_id else None,
        "type": "access",
        "exp": expire,
        "iat": now,
        "jti": str(uuid.uuid4()),  # unique token ID
    }
    if extra_claims:
        payload.update(extra_claims)

    return jwt.encode(payload, settings.SECRET_KEY, algorithm="HS256")


def create_refresh_token(user_id: uuid.UUID) -> str:
    """Create a longer-lived refresh token.

    Args:
        user_id: The authenticated user's ID.

    Returns:
        Encoded JWT string.
    """
    now = datetime.now(timezone.utc)
    expire = now + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS)

    payload: dict[str, Any] = {
        "sub": str(user_id),
        "type": "refresh",
        "exp": expire,
        "iat": now,
        "jti": str(uuid.uuid4()),
    }

    return jwt.encode(payload, settings.SECRET_KEY, algorithm="HS256")


def decode_token(token: str) -> TokenPayload:
    """Decode and validate a JWT token.

    Args:
        token: The encoded JWT string.

    Returns:
        Decoded token payload.

    Raises:
        InvalidTokenError: If the token is invalid, expired, or malformed.
    """
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=["HS256"])
    except JWTError as e:
        raise InvalidTokenError(f"Invalid token: {e}") from e

    return TokenPayload(
        sub=payload["sub"],
        org=payload.get("org"),
        type=payload.get("type", "access"),
        exp=datetime.fromtimestamp(payload["exp"], tz=timezone.utc),
        iat=datetime.fromtimestamp(payload["iat"], tz=timezone.utc),
    )


def create_token_pair(
    user_id: uuid.UUID,
    organization_id: uuid.UUID | None = None,
) -> TokenPair:
    """Create both access and refresh tokens.

    Args:
        user_id: The authenticated user's ID.
        organization_id: The user's organization ID.

    Returns:
        A TokenPair with both tokens and expiry info.
    """
    return TokenPair(
        access_token=create_access_token(user_id, organization_id),
        refresh_token=create_refresh_token(user_id),
        expires_in=settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60,
    )


def verify_token(token: str) -> dict[str, Any] | None:
    """Verify a JWT token and return payload dictionary, or None if invalid."""
    try:
        payload = decode_token(token)
        return {"sub": payload.sub, "org": payload.org, "type": payload.type}
    except InvalidTokenError:
        return None


class InvalidTokenError(Exception):
    """Raised when a JWT token is invalid, expired, or malformed."""

    pass
