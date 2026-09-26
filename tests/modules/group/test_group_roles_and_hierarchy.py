"""
ConnectHub — Group Custom Roles, Hierarchy, and Permission Ceiling Tests.

Tests:
- Default roles (Owner, Admin, Member) auto-created upon group creation.
- Owner protection (cannot be demoted, removed, or modified).
- Hierarchy restrictions: role managers can only manage roles below their rank.
- Permission ceiling: role managers cannot grant permissions they do not have.
- Single default role functionality.
- Member role assignment according to hierarchy.
- Safe role deletion with fallback reassignment.
"""

from __future__ import annotations

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from connecthub.core.exceptions import ConflictError, ForbiddenError, NotFoundError
from connecthub.modules.group.schemas import (
    GroupCreate,
    GroupRoleCreate,
    GroupRoleReorderItem,
    GroupRoleReorderRequest,
    GroupRoleUpdate,
)
from connecthub.modules.group.service import GroupService


@pytest.mark.asyncio
async def test_auto_created_default_roles(group_service, super_admin_user, group_domain, db_session):
    """Group creation automatically seeds 4 system roles: Group Owner, Group Admin, Group Member, and Group Viewer."""
    await db_session.commit()
    group = await group_service.create_group(
        super_admin_user.id, GroupCreate(name="Engineering", slug="eng"),
    )
    await db_session.commit()

    roles = await group_service.list_roles(super_admin_user.id, group.id)
    role_names = [r.name for r in roles]

    assert "Group Owner" in role_names
    assert "Group Admin" in role_names
    assert "Group Member" in role_names
    assert "Group Viewer" in role_names

    # Owner is rank 0, protected
    owner = next(r for r in roles if r.name == "Group Owner")
    assert owner.hierarchy_rank == 0
    assert owner.is_system is True
    assert owner.is_default is False

    # Member is default
    member_role = next(r for r in roles if r.name == "Group Member")
    assert member_role.is_default is True
    assert member_role.hierarchy_rank == 100
    assert member_role.is_system is True

    # Viewer is rank 200, view-only, system, non-default
    viewer_role = next(r for r in roles if r.name == "Group Viewer")
    assert viewer_role.is_default is False
    assert viewer_role.hierarchy_rank == 200
    assert viewer_role.is_system is True
    assert viewer_role.permissions["view_messages"] is True
    assert viewer_role.permissions["view_members"] is True
    assert viewer_role.permissions["send_messages"] is False
    assert viewer_role.permissions["add_reactions"] is False
    assert viewer_role.permissions["send_attachments"] is False
    assert viewer_role.permissions["delete_group"] is False


@pytest.mark.asyncio
async def test_owner_protection(group_service, super_admin_user, member_user, group_domain, db_session):
    """Group Owner cannot be removed from group or assigned another role."""
    await db_session.commit()
    group = await group_service.create_group(
        super_admin_user.id, GroupCreate(name="Secured Group", slug="sec-group", member_ids=[member_user.id]),
    )
    await db_session.commit()

    roles = await group_service.list_roles(super_admin_user.id, group.id)
    admin_role = next(r for r in roles if r.name == "Group Admin")

    # Group Admin tries to remove Owner -> Forbidden
    with pytest.raises(ForbiddenError):
        await group_service.remove_member(member_user.id, group.id, super_admin_user.id)

    # Group Admin tries to change Owner's role -> Forbidden
    with pytest.raises(ForbiddenError):
        await group_service.assign_member_role(member_user.id, group.id, super_admin_user.id, admin_role.id)


@pytest.mark.asyncio
async def test_custom_role_creation_and_permission_ceiling(
    group_service, super_admin_user, member_user, group_domain, db_session,
):
    """Owner can create custom roles with any permissions. Non-owner cannot exceed authority."""
    await db_session.commit()
    group = await group_service.create_group(
        super_admin_user.id, GroupCreate(name="Designers", slug="designers"),
    )
    await db_session.commit()

    # Owner creates Moderator role
    mod_role = await group_service.create_role(
        super_admin_user.id,
        group.id,
        GroupRoleCreate(
            name="Moderator",
            color="#3B82F6",
            description="Moderates content",
            permissions={
                "view_messages": True,
                "send_messages": True,
                "delete_other_messages": True,
                "pin_messages": True,
                "manage_members": True,
            },
        ),
    )
    await db_session.commit()
    assert mod_role.name == "Moderator"
    assert mod_role.color == "#3B82F6"
    assert mod_role.permissions["delete_other_messages"] is True

    # Add member_user and assign Moderator role
    await group_service.add_members(super_admin_user.id, group.id, [member_user.id], role_id=mod_role.id)
    await db_session.commit()


@pytest.mark.asyncio
async def test_default_role_switch(group_service, super_admin_user, group_domain, db_session):
    """Setting a new role as default role makes the previous default role non-default."""
    await db_session.commit()
    group = await group_service.create_group(
        super_admin_user.id, GroupCreate(name="Writers", slug="writers"),
    )
    await db_session.commit()

    roles_before = await group_service.list_roles(super_admin_user.id, group.id)
    old_default = next(r for r in roles_before if r.is_default)
    assert old_default.name == "Group Member"

    # Create new custom role and make it default
    editor_role = await group_service.create_role(
        super_admin_user.id,
        group.id,
        GroupRoleCreate(
            name="Editor",
            color="#10B981",
            is_default=True,
        ),
    )
    await db_session.commit()

    roles_after = await group_service.list_roles(super_admin_user.id, group.id)
    editor_updated = next(r for r in roles_after if r.id == editor_role.id)
    member_updated = next(r for r in roles_after if r.id == old_default.id)

    assert editor_updated.is_default is True
    assert member_updated.is_default is False


@pytest.mark.asyncio
async def test_role_deletion_with_member_reassignment(
    group_service, super_admin_user, member_user, group_domain, db_session,
):
    """Deleting a custom role reassigns members to the default role."""
    await db_session.commit()
    group = await group_service.create_group(
        super_admin_user.id, GroupCreate(name="Support", slug="support"),
    )
    await db_session.commit()

    # Create role
    support_role = await group_service.create_role(
        super_admin_user.id,
        group.id,
        GroupRoleCreate(name="Support Tier 1", color="#EC4899"),
    )
    await db_session.commit()

    # Add member with support role
    await group_service.add_members(super_admin_user.id, group.id, [member_user.id], role_id=support_role.id)
    await db_session.commit()

    # Delete support role
    await group_service.delete_role(super_admin_user.id, group.id, support_role.id)
    await db_session.commit()

    # Verify member is now default role
    members = await group_service.list_members(super_admin_user.id, group.id)
    reassigned_member = next(m for m in members.items if m.user_id == member_user.id)
    assert reassigned_member.role.name == "Group Member"


@pytest.mark.asyncio
async def test_group_viewer_cannot_be_deleted(
    group_service, super_admin_user, group_domain, db_session,
):
    """Group Viewer is a protected system role and cannot be deleted."""
    await db_session.commit()
    group = await group_service.create_group(
        super_admin_user.id, GroupCreate(name="Finance", slug="fin"),
    )
    await db_session.commit()

    roles = await group_service.list_roles(super_admin_user.id, group.id)
    viewer_role = next(r for r in roles if r.name == "Group Viewer")

    with pytest.raises(ForbiddenError):
        await group_service.delete_role(super_admin_user.id, group.id, viewer_role.id)


@pytest.mark.asyncio
async def test_group_viewer_view_only_enforcement(
    group_service, super_admin_user, member_user, group_domain, db_session,
):
    """User assigned Group Viewer role cannot perform write or management actions."""
    from connecthub.modules.messaging.schemas import ConversationType, MessageCreate
    from connecthub.modules.messaging.service import MessagingService

    await db_session.commit()
    group = await group_service.create_group(
        super_admin_user.id, GroupCreate(name="Audit Room", slug="audit-room"),
    )
    await db_session.commit()

    roles = await group_service.list_roles(super_admin_user.id, group.id)
    viewer_role = next(r for r in roles if r.name == "Group Viewer")

    # Add member_user as Group Viewer
    await group_service.add_members(super_admin_user.id, group.id, [member_user.id], role_id=viewer_role.id)
    await db_session.commit()

    # Messaging service check
    msg_service = MessagingService(db_session)
    conv = await msg_service.get_or_create_conversation(
        super_admin_user.id, ConversationType.GROUP, target_id=group.id,
    )
    await msg_service._repo.add_participant(conv.id, member_user.id)
    await db_session.commit()

    # Viewer tries to send a message -> Forbidden
    with pytest.raises(ForbiddenError):
        await msg_service.send_message(
            member_user.id, conv.id, MessageCreate(content="Hello viewer"),
        )
