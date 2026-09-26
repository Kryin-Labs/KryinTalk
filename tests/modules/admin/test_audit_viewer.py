"""
ConnectHub — Audit Viewer Tests.

Query audit logs with filtering (user, action, resource, date range) and pagination.
Verify privileged actions are logged.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

import pytest

from connecthub.core.exceptions import ForbiddenError


@pytest.mark.asyncio
async def test_list_audit_logs_as_admin(
    admin_service, audit_service, super_admin_user, db_session,
):
    """Admin can query audit logs."""
    await db_session.commit()
    # Log an action
    await audit_service.log(
        user_id=super_admin_user.id,
        action="test.action",
        resource_type="test",
        resource_id="123",
    )
    await db_session.commit()

    result = await admin_service.list_audit_logs(super_admin_user.id)
    assert result.total >= 1
    actions = [item.action for item in result.items]
    assert "test.action" in actions


@pytest.mark.asyncio
async def test_list_audit_logs_filtered_by_action(
    admin_service, audit_service, super_admin_user, db_session,
):
    """Filter audit logs by action."""
    await db_session.commit()
    await audit_service.log(
        user_id=super_admin_user.id,
        action="action.alpha",
        resource_type="res_a",
    )
    await audit_service.log(
        user_id=super_admin_user.id,
        action="action.beta",
        resource_type="res_b",
    )
    await db_session.commit()

    result = await admin_service.list_audit_logs(
        super_admin_user.id, action_filter="action.alpha"
    )
    assert len(result.items) >= 1
    for item in result.items:
        assert item.action == "action.alpha"


@pytest.mark.asyncio
async def test_list_audit_logs_filtered_by_date_range(
    admin_service, audit_service, super_admin_user, db_session,
):
    """Filter audit logs by date range."""
    await db_session.commit()
    await audit_service.log(
        user_id=super_admin_user.id,
        action="recent.action",
        resource_type="test",
    )
    await db_session.commit()

    now = datetime.now(timezone.utc)
    from_date = now - timedelta(hours=1)
    to_date = now + timedelta(hours=1)

    result = await admin_service.list_audit_logs(
        super_admin_user.id, from_date=from_date, to_date=to_date,
    )
    assert result.total >= 1


@pytest.mark.asyncio
async def test_list_audit_logs_regular_user_denied(
    admin_service, regular_user, db_session,
):
    """Regular user denied reading audit logs."""
    await db_session.commit()
    with pytest.raises(ForbiddenError):
        await admin_service.list_audit_logs(regular_user.id)
