"""
ConnectHub — SuperAdmin Force Message Override Tests.
"""

from __future__ import annotations

import asyncio
from datetime import datetime, timedelta, timezone
import pytest

from connecthub.core.exceptions import ForbiddenError, NotFoundError
from connecthub.modules.group.schemas import GroupCreate
from connecthub.modules.group.service import _force_message_overrides


@pytest.mark.asyncio
async def test_superadmin_view_permissions_without_membership(
    group_service, super_admin_user, member_user, group_domain, db_session,
):
    """Super Admin not added to group can still view group, messages, members and settings."""
    await db_session.commit()
    # Member user creates private group
    group = await group_service.create_group(
        member_user.id, GroupCreate(name="Private Group", slug="priv-grp", is_private=True),
    )
    await db_session.commit()

    # Super Admin can view
    assert await group_service.check_group_permission(group.id, super_admin_user.id, "view_group") is True
    assert await group_service.check_group_permission(group.id, super_admin_user.id, "view_messages") is True
    assert await group_service.check_group_permission(group.id, super_admin_user.id, "view_members") is True
    assert await group_service.check_group_permission(group.id, super_admin_user.id, "manage_group_settings") is True


@pytest.mark.asyncio
async def test_superadmin_cannot_send_messages_without_override(
    group_service, super_admin_user, member_user, group_domain, db_session,
):
    """Super Admin not added to group cannot send messages by default without active override."""
    await db_session.commit()
    # Clear any residual override state
    _force_message_overrides.clear()

    group = await group_service.create_group(
        member_user.id, GroupCreate(name="Restricted Group", slug="restr-grp", is_private=True),
    )
    await db_session.commit()

    # Messaging permissions must return False
    assert await group_service.check_group_permission(group.id, super_admin_user.id, "send_messages") is False
    assert await group_service.check_group_permission(group.id, super_admin_user.id, "reply_messages") is False
    assert await group_service.check_group_permission(group.id, super_admin_user.id, "send_links") is False

    # Status check indicates inactive
    status = await group_service.get_force_message_override_status(super_admin_user.id, group.id)
    assert status["active"] is False
    assert status["remaining_seconds"] == 0


@pytest.mark.asyncio
async def test_superadmin_activate_force_message_override(
    group_service, super_admin_user, member_user, group_domain, audit_service, db_session,
):
    """Super Admin activates 2-minute override and gains message sending permissions."""
    await db_session.commit()
    _force_message_overrides.clear()

    group = await group_service.create_group(
        member_user.id, GroupCreate(name="Override Group", slug="over-grp", is_private=True),
    )
    await db_session.commit()

    # Activate override
    res = await group_service.activate_force_message_override(super_admin_user.id, group.id, duration_seconds=120)
    await db_session.commit()

    assert res["active"] is True
    assert res["remaining_seconds"] == 120
    assert res["group_id"] == str(group.id)

    # Now messaging permission checks succeed
    assert await group_service.check_group_permission(group.id, super_admin_user.id, "send_messages") is True
    assert await group_service.check_group_permission(group.id, super_admin_user.id, "reply_messages") is True

    # Status check reflects active state
    status = await group_service.get_force_message_override_status(super_admin_user.id, group.id)
    assert status["active"] is True
    assert status["remaining_seconds"] > 0

    # Audit log was generated
    logs = await audit_service.query(user_id=super_admin_user.id, action="group.force_message_override.activated")
    assert len(logs) >= 1


@pytest.mark.asyncio
async def test_regular_user_cannot_activate_override(
    group_service, regular_user, member_user, group_domain, db_session,
):
    """Non-Super Admin users cannot activate Force Message override."""
    await db_session.commit()
    group = await group_service.create_group(
        member_user.id, GroupCreate(name="Sec Group", slug="sec-grp", is_private=True),
    )
    await db_session.commit()

    with pytest.raises(ForbiddenError):
        await group_service.activate_force_message_override(regular_user.id, group.id)


@pytest.mark.asyncio
async def test_force_override_expiration(
    group_service, super_admin_user, member_user, group_domain, db_session,
):
    """Force message override expires after its duration."""
    await db_session.commit()
    _force_message_overrides.clear()

    group = await group_service.create_group(
        member_user.id, GroupCreate(name="Expire Group", slug="exp-grp", is_private=True),
    )
    await db_session.commit()

    # Manually insert an expired override
    expired_time = datetime.now(timezone.utc) - timedelta(seconds=5)
    _force_message_overrides[(group.id, super_admin_user.id)] = expired_time

    # check_group_permission should detect expiration, pop the key, and return False
    assert await group_service.check_group_permission(group.id, super_admin_user.id, "send_messages") is False

    # Status should return inactive
    status = await group_service.get_force_message_override_status(super_admin_user.id, group.id)
    assert status["active"] is False
    assert status["remaining_seconds"] == 0
