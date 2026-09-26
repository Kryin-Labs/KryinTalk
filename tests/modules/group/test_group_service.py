"""
ConnectHub — Group Service Tests.

CRUD, membership, Section 5 visibility, permission gating, audit logging.
"""

from __future__ import annotations

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from connecthub.core.audit.service import AuditService
from connecthub.core.exceptions import ConflictError, NotFoundError
from connecthub.core.permissions.models import PermissionDomain
from connecthub.modules.auth.models import User
from connecthub.modules.group.schemas import GroupCreate, GroupUpdate
from connecthub.modules.group.service import GroupService


@pytest.mark.asyncio
async def test_create_group(group_service, super_admin_user, group_domain, db_session):
    await db_session.commit()
    group = await group_service.create_group(
        super_admin_user.id, GroupCreate(name="Dev Chat", slug="dev-chat"),
    )
    await db_session.commit()
    assert group.name == "Dev Chat"
    assert group.is_private is True
    assert group.member_count == 1  # creator auto-added


@pytest.mark.asyncio
async def test_create_group_with_initial_members(
    group_service, super_admin_user, member_user, group_domain, db_session,
):
    """Group creation can include initial members."""
    await db_session.commit()
    group = await group_service.create_group(
        super_admin_user.id,
        GroupCreate(name="Team Chat", slug="team-chat", member_ids=[member_user.id]),
    )
    await db_session.commit()
    assert group.member_count == 2  # creator + member


@pytest.mark.asyncio
async def test_create_group_duplicate_slug(group_service, super_admin_user, group_domain, db_session):
    await db_session.commit()
    await group_service.create_group(
        super_admin_user.id, GroupCreate(name="G1", slug="g1"),
    )
    await db_session.commit()
    with pytest.raises(ConflictError):
        await group_service.create_group(
            super_admin_user.id, GroupCreate(name="G2", slug="g1"),
        )


@pytest.mark.asyncio
async def test_update_group(group_service, super_admin_user, group_domain, db_session):
    await db_session.commit()
    group = await group_service.create_group(
        super_admin_user.id, GroupCreate(name="Old", slug="old"),
    )
    await db_session.commit()
    updated = await group_service.update_group(
        super_admin_user.id, group.id, GroupUpdate(name="New Name"),
    )
    await db_session.commit()
    assert updated.name == "New Name"


@pytest.mark.asyncio
async def test_delete_group_soft(group_service, super_admin_user, group_domain, db_session):
    await db_session.commit()
    group = await group_service.create_group(
        super_admin_user.id, GroupCreate(name="Temp", slug="temp"),
    )
    await db_session.commit()
    await group_service.delete_group(super_admin_user.id, group.id)
    await db_session.commit()
    with pytest.raises(NotFoundError):
        await group_service.get_group(super_admin_user.id, group.id)


# ── Membership ───────────────────────────────

@pytest.mark.asyncio
async def test_add_members(
    group_service, super_admin_user, member_user, group_domain, db_session,
):
    await db_session.commit()
    group = await group_service.create_group(
        super_admin_user.id, GroupCreate(name="G", slug="g"),
    )
    await db_session.commit()
    assert group.member_count == 1

    updated = await group_service.add_members(
        super_admin_user.id, group.id, [member_user.id],
    )
    await db_session.commit()
    assert updated.member_count == 2


@pytest.mark.asyncio
async def test_remove_members(
    group_service, super_admin_user, member_user, group_domain, db_session,
):
    await db_session.commit()
    group = await group_service.create_group(
        super_admin_user.id,
        GroupCreate(name="G", slug="g", member_ids=[member_user.id]),
    )
    await db_session.commit()
    assert group.member_count == 2

    updated = await group_service.remove_members(
        super_admin_user.id, group.id, [member_user.id],
    )
    await db_session.commit()
    assert updated.member_count == 1


# ── Section 5 Visibility ────────────────────

@pytest.mark.asyncio
async def test_visibility_no_read_gets_empty_list(
    group_service, super_admin_user, regular_user, group_domain, db_session,
):
    """User WITHOUT read → empty list (Section 5)."""
    await db_session.commit()
    await group_service.create_group(
        super_admin_user.id, GroupCreate(name="Secret", slug="secret"),
    )
    await db_session.commit()
    result = await group_service.list_groups(regular_user.id)
    assert result.items == []
    assert result.total == 0


@pytest.mark.asyncio
async def test_visibility_no_read_gets_404(
    group_service, super_admin_user, regular_user, group_domain, db_session,
):
    """User WITHOUT read → 404 (not 403, Section 5)."""
    await db_session.commit()
    group = await group_service.create_group(
        super_admin_user.id, GroupCreate(name="Hidden", slug="hidden"),
    )
    await db_session.commit()
    with pytest.raises(NotFoundError):
        await group_service.get_group(regular_user.id, group.id)


@pytest.mark.asyncio
async def test_visibility_with_read_sees_groups(
    group_service, super_admin_user, user_with_group_read, group_domain, db_session,
):
    """User WITH read → sees groups."""
    await db_session.commit()
    await group_service.create_group(
        super_admin_user.id, GroupCreate(name="G1", slug="g1"),
    )
    await group_service.create_group(
        super_admin_user.id, GroupCreate(name="G2", slug="g2"),
    )
    await db_session.commit()
    result = await group_service.list_groups(user_with_group_read.id)
    assert len(result.items) == 2


@pytest.mark.asyncio
async def test_visibility_super_admin_sees_all(
    group_service, super_admin_user, group_domain, db_session,
):
    await db_session.commit()
    for i in range(3):
        await group_service.create_group(
            super_admin_user.id, GroupCreate(name=f"G{i}", slug=f"g{i}"),
        )
    await db_session.commit()
    result = await group_service.list_groups(super_admin_user.id)
    assert len(result.items) == 3


@pytest.mark.asyncio
async def test_no_create_permission_denied(
    group_service, user_with_group_read, group_domain, db_session,
):
    await db_session.commit()
    with pytest.raises(NotFoundError):
        await group_service.create_group(
            user_with_group_read.id, GroupCreate(name="Blocked", slug="blocked"),
        )


@pytest.mark.asyncio
async def test_group_operations_audited(
    group_service, audit_service, super_admin_user, member_user, group_domain, db_session,
):
    await db_session.commit()
    group = await group_service.create_group(
        super_admin_user.id, GroupCreate(name="Audited", slug="audited"),
    )
    await db_session.commit()
    await group_service.add_members(super_admin_user.id, group.id, [member_user.id])
    await db_session.commit()
    await group_service.delete_group(super_admin_user.id, group.id)
    await db_session.commit()

    logs = await audit_service.query(user_id=super_admin_user.id)
    actions = [l.action for l in logs]
    assert "group.created" in actions
    assert "group.members.added" in actions
    assert "group.deleted" in actions
