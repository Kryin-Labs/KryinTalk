"""
ConnectHub — Authentication Service Tests.

Tests for login, token generation/validation, token refresh,
and suspended user denial.
"""

from __future__ import annotations

import uuid

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from connecthub.core.exceptions import UnauthorizedError
from connecthub.core.security.hashing import hash_password
from connecthub.core.security.jwt import decode_token
from connecthub.modules.auth.models import Organization, User
from connecthub.modules.auth.repository import AuthRepository
from connecthub.modules.auth.service import AuthService


@pytest.mark.asyncio
async def test_login_success(
    auth_service: AuthService,
    super_admin_user: User,
    db_session: AsyncSession,
) -> None:
    """Valid credentials return a token pair."""
    await db_session.commit()

    tokens = await auth_service.login("superadmin@test.com", "SuperAdminPass123!")
    await db_session.commit()

    assert tokens.access_token
    assert tokens.refresh_token
    assert tokens.token_type == "bearer"
    assert tokens.expires_in > 0

    # Verify the access token contains correct claims
    payload = decode_token(tokens.access_token)
    assert payload.sub == str(super_admin_user.id)
    assert payload.type == "access"


@pytest.mark.asyncio
async def test_login_invalid_email(
    auth_service: AuthService,
    super_admin_user: User,
    db_session: AsyncSession,
) -> None:
    """Wrong email raises UnauthorizedError."""
    await db_session.commit()

    with pytest.raises(UnauthorizedError, match="Invalid credentials"):
        await auth_service.login("wrong@test.com", "SuperAdminPass123!")


@pytest.mark.asyncio
async def test_login_invalid_password(
    auth_service: AuthService,
    super_admin_user: User,
    db_session: AsyncSession,
) -> None:
    """Wrong password raises UnauthorizedError."""
    await db_session.commit()

    with pytest.raises(UnauthorizedError, match="Invalid credentials"):
        await auth_service.login("superadmin@test.com", "WrongPassword!")


@pytest.mark.asyncio
async def test_login_suspended_user(
    auth_service: AuthService,
    auth_repo: AuthRepository,
    super_admin_user: User,
    db_session: AsyncSession,
) -> None:
    """Suspended user cannot login."""
    await auth_repo.suspend_user(super_admin_user.id)
    await db_session.commit()

    with pytest.raises(UnauthorizedError, match="Account suspended"):
        await auth_service.login("superadmin@test.com", "SuperAdminPass123!")


@pytest.mark.asyncio
async def test_refresh_token_success(
    auth_service: AuthService,
    super_admin_user: User,
    db_session: AsyncSession,
) -> None:
    """Valid refresh token returns a new token pair."""
    await db_session.commit()

    tokens = await auth_service.login("superadmin@test.com", "SuperAdminPass123!")
    await db_session.commit()

    new_tokens = await auth_service.refresh_token(tokens.refresh_token)
    assert new_tokens.access_token
    assert new_tokens.access_token != tokens.access_token  # New token


@pytest.mark.asyncio
async def test_refresh_token_invalid(
    auth_service: AuthService,
    db_session: AsyncSession,
) -> None:
    """Invalid refresh token raises UnauthorizedError."""
    with pytest.raises(UnauthorizedError):
        await auth_service.refresh_token("invalid.jwt.token")


@pytest.mark.asyncio
async def test_refresh_token_rejects_access_token(
    auth_service: AuthService,
    super_admin_user: User,
    db_session: AsyncSession,
) -> None:
    """Using an access token as a refresh token fails."""
    await db_session.commit()

    tokens = await auth_service.login("superadmin@test.com", "SuperAdminPass123!")
    await db_session.commit()

    # Try to use the access token as a refresh token
    with pytest.raises(UnauthorizedError, match="Invalid token type"):
        await auth_service.refresh_token(tokens.access_token)


@pytest.mark.asyncio
async def test_refresh_suspended_user_denied(
    auth_service: AuthService,
    auth_repo: AuthRepository,
    super_admin_user: User,
    db_session: AsyncSession,
) -> None:
    """Suspended user cannot refresh tokens."""
    await db_session.commit()

    tokens = await auth_service.login("superadmin@test.com", "SuperAdminPass123!")
    await db_session.commit()

    # Suspend the user after login
    await auth_repo.suspend_user(super_admin_user.id)
    await db_session.commit()

    with pytest.raises(UnauthorizedError, match="Account unavailable"):
        await auth_service.refresh_token(tokens.refresh_token)


@pytest.mark.asyncio
async def test_get_current_user(
    auth_service: AuthService,
    super_admin_user: User,
    db_session: AsyncSession,
) -> None:
    """Get current user profile."""
    await db_session.commit()

    user = await auth_service.get_current_user(super_admin_user.id)
    assert user.email == "superadmin@test.com"
    assert user.username == "superadmin"
    assert user.display_name == "Super Admin"


@pytest.mark.asyncio
async def test_login_creates_audit_log(
    auth_service: AuthService,
    audit_service,
    super_admin_user: User,
    db_session: AsyncSession,
) -> None:
    """Login creates an audit log entry."""
    await db_session.commit()

    await auth_service.login("superadmin@test.com", "SuperAdminPass123!")
    await db_session.commit()

    logs = await audit_service.query(user_id=super_admin_user.id, action="auth.login_success")
    assert len(logs) >= 1
