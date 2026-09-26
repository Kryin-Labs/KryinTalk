"""
ConnectHub — Admin Service Tests.

User management, system dashboard stats, admin permission checks.
"""

from __future__ import annotations

import pytest

from connecthub.core.exceptions import ForbiddenError, NotFoundError
from connecthub.modules.admin.schemas import UserUpdateRequest


@pytest.mark.asyncio
async def test_list_users_as_admin(
    admin_service, super_admin_user, regular_user, db_session,
):
    """Super admin can list all users."""
    await db_session.commit()
    result = await admin_service.list_users(super_admin_user.id)
    assert result.total >= 2
    emails = [u.email for u in result.items]
    assert "admin@test.com" in emails
    assert "regular@test.com" in emails


@pytest.mark.asyncio
async def test_list_users_as_regular_user_denied(
    admin_service, regular_user, db_session,
):
    """Regular user without permissions is denied listing users."""
    await db_session.commit()
    with pytest.raises(ForbiddenError):
        await admin_service.list_users(regular_user.id)


@pytest.mark.asyncio
async def test_get_user_detail(
    admin_service, super_admin_user, regular_user, db_session,
):
    """Super admin can get user details."""
    await db_session.commit()
    detail = await admin_service.get_user_detail(super_admin_user.id, regular_user.id)
    assert detail.id == regular_user.id
    assert detail.email == "regular@test.com"


@pytest.mark.asyncio
async def test_update_user(
    admin_service, super_admin_user, regular_user, db_session,
):
    """Admin can update user display name and status."""
    await db_session.commit()
    updated = await admin_service.update_user(
        super_admin_user.id,
        regular_user.id,
        UserUpdateRequest(display_name="Updated Display Name", is_active=False),
    )
    await db_session.commit()
    assert updated.display_name == "Updated Display Name"
    assert updated.is_active is False


@pytest.mark.asyncio
async def test_deactivate_user(
    admin_service, super_admin_user, regular_user, db_session,
):
    """Admin can deactivate user."""
    await db_session.commit()
    deactivated = await admin_service.deactivate_user(super_admin_user.id, regular_user.id)
    await db_session.commit()
    assert deactivated.is_active is False


@pytest.mark.asyncio
async def test_get_system_stats(
    admin_service, super_admin_user, db_session,
):
    """Admin can view dashboard stats."""
    await db_session.commit()
    stats = await admin_service.get_system_stats(super_admin_user.id)
    assert stats.total_users >= 1
    assert stats.active_users >= 1
    assert stats.total_organizations >= 1
