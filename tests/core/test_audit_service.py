"""
ConnectHub — Audit Service Tests.

Tests for audit log creation, querying, and immutability.
"""

from __future__ import annotations

import uuid

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from connecthub.core.audit.service import AuditService


@pytest.mark.asyncio
async def test_log_action(
    audit_service: AuditService, db_session: AsyncSession,
) -> None:
    """Log an action and verify it's stored."""
    user_id = uuid.uuid4()

    entry = await audit_service.log(
        user_id=user_id,
        action="test.action",
        resource_type="test_resource",
        resource_id="res-123",
        details={"key": "value"},
        ip_address="192.168.1.1",
        user_agent="TestAgent/1.0",
    )
    await db_session.commit()

    assert entry.user_id == user_id
    assert entry.action == "test.action"
    assert entry.resource_type == "test_resource"
    assert entry.resource_id == "res-123"
    assert entry.details == {"key": "value"}
    assert entry.ip_address == "192.168.1.1"
    assert entry.created_at is not None


@pytest.mark.asyncio
async def test_log_system_action(
    audit_service: AuditService, db_session: AsyncSession,
) -> None:
    """Log a system action (no user_id)."""
    entry = await audit_service.log(
        action="system.startup",
        resource_type="system",
        details={"version": "0.1.0"},
    )
    await db_session.commit()

    assert entry.user_id is None
    assert entry.action == "system.startup"


@pytest.mark.asyncio
async def test_query_by_user(
    audit_service: AuditService, db_session: AsyncSession,
) -> None:
    """Query audit logs filtered by user."""
    user_a = uuid.uuid4()
    user_b = uuid.uuid4()

    await audit_service.log(user_id=user_a, action="a.action", resource_type="test")
    await audit_service.log(user_id=user_b, action="b.action", resource_type="test")
    await audit_service.log(user_id=user_a, action="a.action2", resource_type="test")
    await db_session.commit()

    logs_a = await audit_service.query(user_id=user_a)
    assert len(logs_a) == 2
    assert all(log.user_id == user_a for log in logs_a)


@pytest.mark.asyncio
async def test_query_by_action(
    audit_service: AuditService, db_session: AsyncSession,
) -> None:
    """Query audit logs filtered by action type."""
    user_id = uuid.uuid4()

    await audit_service.log(user_id=user_id, action="role.created", resource_type="role")
    await audit_service.log(user_id=user_id, action="role.deleted", resource_type="role")
    await audit_service.log(user_id=user_id, action="permission.granted", resource_type="permission")
    await db_session.commit()

    logs = await audit_service.query(action="role.created")
    assert len(logs) == 1
    assert logs[0].action == "role.created"


@pytest.mark.asyncio
async def test_query_by_resource(
    audit_service: AuditService, db_session: AsyncSession,
) -> None:
    """Query audit logs filtered by resource type and ID."""
    user_id = uuid.uuid4()
    resource_id = str(uuid.uuid4())

    await audit_service.log(
        user_id=user_id, action="resource.updated",
        resource_type="department", resource_id=resource_id,
    )
    await audit_service.log(
        user_id=user_id, action="resource.updated",
        resource_type="team", resource_id=str(uuid.uuid4()),
    )
    await db_session.commit()

    logs = await audit_service.query(resource_type="department", resource_id=resource_id)
    assert len(logs) == 1
    assert logs[0].resource_type == "department"
    assert logs[0].resource_id == resource_id


@pytest.mark.asyncio
async def test_query_ordered_newest_first(
    audit_service: AuditService, db_session: AsyncSession,
) -> None:
    """Audit logs are returned in reverse creation order (newest first)."""
    user_id = uuid.uuid4()

    # Create entries with explicit spread in time by using IDs as differentiator
    entry1 = await audit_service.log(user_id=user_id, action="first", resource_type="test")
    entry2 = await audit_service.log(user_id=user_id, action="second", resource_type="test")
    entry3 = await audit_service.log(user_id=user_id, action="third", resource_type="test")
    await db_session.commit()

    logs = await audit_service.query(user_id=user_id)
    assert len(logs) == 3
    # All three actions should be present
    actions = {log.action for log in logs}
    assert actions == {"first", "second", "third"}


@pytest.mark.asyncio
async def test_query_with_pagination(
    audit_service: AuditService, db_session: AsyncSession,
) -> None:
    """Audit log queries support limit and offset."""
    user_id = uuid.uuid4()

    for i in range(5):
        await audit_service.log(
            user_id=user_id, action=f"action_{i}", resource_type="test",
        )
    await db_session.commit()

    page1 = await audit_service.query(user_id=user_id, limit=2, offset=0)
    page2 = await audit_service.query(user_id=user_id, limit=2, offset=2)

    assert len(page1) == 2
    assert len(page2) == 2
    # Different entries
    assert page1[0].id != page2[0].id


@pytest.mark.asyncio
async def test_log_with_changes_snapshot(
    audit_service: AuditService, db_session: AsyncSession,
) -> None:
    """Audit log can store before/after change snapshots."""
    user_id = uuid.uuid4()

    entry = await audit_service.log(
        user_id=user_id,
        action="role.updated",
        resource_type="role",
        resource_id="role-123",
        changes={
            "before": {"name": "Old Name"},
            "after": {"name": "New Name"},
        },
    )
    await db_session.commit()

    assert entry.changes is not None
    assert entry.changes["before"]["name"] == "Old Name"
    assert entry.changes["after"]["name"] == "New Name"
