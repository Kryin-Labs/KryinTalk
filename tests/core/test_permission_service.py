"""
ConnectHub — Permission Service Tests.

Tests for permission management operations: role CRUD,
role permission grants/revokes, user role assignment, and
direct permission management. Verifies audit logging.
"""

from __future__ import annotations

import uuid

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from connecthub.core.audit.service import AuditService
from connecthub.core.exceptions import ConflictError, NotFoundError
from connecthub.core.permissions.models import Role
from connecthub.core.permissions.repository import PermissionRepository
from connecthub.core.permissions.schemas import RoleCreate
from connecthub.core.permissions.service import PermissionService


@pytest.mark.asyncio
async def test_create_role(
    perm_service: PermissionService, db_session: AsyncSession,
) -> None:
    """Create a new role successfully."""
    acting_user = uuid.uuid4()
    role = await perm_service.create_role(
        RoleCreate(code="editor", name="Editor", description="Can edit content"),
        acting_user_id=acting_user,
    )
    await db_session.commit()

    assert role.code == "editor"
    assert role.name == "Editor"
    assert role.is_system is False
    assert role.is_active is True


@pytest.mark.asyncio
async def test_create_duplicate_role_fails(
    perm_service: PermissionService, db_session: AsyncSession,
) -> None:
    """Creating a role with a duplicate code raises ConflictError."""
    acting_user = uuid.uuid4()
    await perm_service.create_role(
        RoleCreate(code="unique_role", name="Unique Role"),
        acting_user_id=acting_user,
    )
    await db_session.commit()

    with pytest.raises(ConflictError):
        await perm_service.create_role(
            RoleCreate(code="unique_role", name="Duplicate"),
            acting_user_id=acting_user,
        )


@pytest.mark.asyncio
async def test_grant_role_permission(
    perm_service: PermissionService,
    sample_domain,
    db_session: AsyncSession,
    perm_repo: PermissionRepository,
) -> None:
    """Grant a permission action to a role."""
    acting_user = uuid.uuid4()
    role = await perm_service.create_role(
        RoleCreate(code="dept_editor", name="Department Editor"),
        acting_user_id=acting_user,
    )
    await db_session.commit()

    action = await perm_repo.resolve_action("department_management", "update")
    assert action is not None

    await perm_service.grant_role_permission(
        role_id=role.id, action_id=action.id, acting_user_id=acting_user,
    )
    await db_session.commit()

    # Verify the permission was granted
    rp = await perm_repo.get_role_permission(role.id, action.id)
    assert rp is not None


@pytest.mark.asyncio
async def test_grant_duplicate_role_permission_fails(
    perm_service: PermissionService,
    sample_domain,
    db_session: AsyncSession,
    perm_repo: PermissionRepository,
) -> None:
    """Granting the same permission twice raises ConflictError."""
    acting_user = uuid.uuid4()
    role = await perm_service.create_role(
        RoleCreate(code="dup_perm_role", name="Dup Test"),
        acting_user_id=acting_user,
    )
    action = await perm_repo.resolve_action("department_management", "read")
    assert action is not None
    await perm_service.grant_role_permission(role.id, action.id, acting_user)
    await db_session.commit()

    with pytest.raises(ConflictError):
        await perm_service.grant_role_permission(role.id, action.id, acting_user)


@pytest.mark.asyncio
async def test_cannot_modify_system_role_permissions(
    perm_service: PermissionService,
    super_admin_role: Role,
    sample_domain,
    db_session: AsyncSession,
    perm_repo: PermissionRepository,
) -> None:
    """System roles (Super Admin) cannot have their permissions modified."""
    acting_user = uuid.uuid4()
    action = await perm_repo.resolve_action("department_management", "read")
    assert action is not None
    await db_session.commit()

    with pytest.raises(ConflictError, match="system roles"):
        await perm_service.grant_role_permission(
            super_admin_role.id, action.id, acting_user,
        )


@pytest.mark.asyncio
async def test_revoke_role_permission(
    perm_service: PermissionService,
    sample_domain,
    db_session: AsyncSession,
    perm_repo: PermissionRepository,
) -> None:
    """Revoke a permission action from a role."""
    acting_user = uuid.uuid4()
    role = await perm_service.create_role(
        RoleCreate(code="revoke_test", name="Revoke Test"),
        acting_user_id=acting_user,
    )
    action = await perm_repo.resolve_action("department_management", "delete")
    assert action is not None
    await perm_service.grant_role_permission(role.id, action.id, acting_user)
    await db_session.commit()

    await perm_service.revoke_role_permission(role.id, action.id, acting_user)
    await db_session.commit()

    rp = await perm_repo.get_role_permission(role.id, action.id)
    assert rp is None


@pytest.mark.asyncio
async def test_assign_role_to_user(
    perm_service: PermissionService, db_session: AsyncSession,
    perm_repo: PermissionRepository,
) -> None:
    """Assign a role to a user."""
    acting_user = uuid.uuid4()
    target_user = uuid.uuid4()

    role = await perm_service.create_role(
        RoleCreate(code="assign_test", name="Assign Test"),
        acting_user_id=acting_user,
    )
    await db_session.commit()

    await perm_service.assign_role_to_user(target_user, role.id, acting_user)
    await db_session.commit()

    user_roles = await perm_repo.get_user_roles(target_user)
    assert len(user_roles) == 1
    assert user_roles[0].role_id == role.id


@pytest.mark.asyncio
async def test_assign_duplicate_role_fails(
    perm_service: PermissionService, db_session: AsyncSession,
) -> None:
    """Assigning the same role twice raises ConflictError."""
    acting_user = uuid.uuid4()
    target_user = uuid.uuid4()

    role = await perm_service.create_role(
        RoleCreate(code="dup_assign", name="Dup Assign"),
        acting_user_id=acting_user,
    )
    await perm_service.assign_role_to_user(target_user, role.id, acting_user)
    await db_session.commit()

    with pytest.raises(ConflictError):
        await perm_service.assign_role_to_user(target_user, role.id, acting_user)


@pytest.mark.asyncio
async def test_remove_role_from_user(
    perm_service: PermissionService, db_session: AsyncSession,
    perm_repo: PermissionRepository,
) -> None:
    """Remove a role from a user."""
    acting_user = uuid.uuid4()
    target_user = uuid.uuid4()

    role = await perm_service.create_role(
        RoleCreate(code="remove_test", name="Remove Test"),
        acting_user_id=acting_user,
    )
    await perm_service.assign_role_to_user(target_user, role.id, acting_user)
    await db_session.commit()

    await perm_service.remove_role_from_user(target_user, role.id, acting_user)
    await db_session.commit()

    user_roles = await perm_repo.get_user_roles(target_user)
    assert len(user_roles) == 0


@pytest.mark.asyncio
async def test_direct_permission_grant(
    perm_service: PermissionService,
    sample_domain,
    db_session: AsyncSession,
    perm_repo: PermissionRepository,
) -> None:
    """Grant a direct permission to a user."""
    acting_user = uuid.uuid4()
    target_user = uuid.uuid4()

    action = await perm_repo.resolve_action("department_management", "create")
    assert action is not None

    await perm_service.grant_direct_permission(
        target_user, action.id, is_grant=True, acting_user_id=acting_user,
    )
    await db_session.commit()

    dp = await perm_repo.get_direct_permission(target_user, action.id)
    assert dp is not None
    assert dp.is_grant is True


@pytest.mark.asyncio
async def test_direct_permission_deny(
    perm_service: PermissionService,
    sample_domain,
    db_session: AsyncSession,
    perm_repo: PermissionRepository,
) -> None:
    """Grant a direct deny to a user."""
    acting_user = uuid.uuid4()
    target_user = uuid.uuid4()

    action = await perm_repo.resolve_action("department_management", "delete")
    assert action is not None

    await perm_service.grant_direct_permission(
        target_user, action.id, is_grant=False, acting_user_id=acting_user,
    )
    await db_session.commit()

    dp = await perm_repo.get_direct_permission(target_user, action.id)
    assert dp is not None
    assert dp.is_grant is False


@pytest.mark.asyncio
async def test_operations_create_audit_logs(
    perm_service: PermissionService,
    audit_service: AuditService,
    db_session: AsyncSession,
) -> None:
    """Permission operations produce audit log entries."""
    acting_user = uuid.uuid4()

    # Create a role (should be audited)
    await perm_service.create_role(
        RoleCreate(code="audited_role", name="Audited Role"),
        acting_user_id=acting_user,
    )
    await db_session.commit()

    # Check audit logs
    logs = await audit_service.query(user_id=acting_user)
    assert len(logs) >= 1
    assert any(log.action == "role.created" for log in logs)
