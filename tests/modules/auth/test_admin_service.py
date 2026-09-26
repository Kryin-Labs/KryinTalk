"""
ConnectHub — Admin Service Tests.

Tests for admin management: create/suspend/reactivate admins,
grant/revoke differentiated permissions, and audit logging.
Verifies that only Super Admins can perform these operations.
"""

from __future__ import annotations

import uuid

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from connecthub.core.audit.service import AuditService
from connecthub.core.exceptions import ConflictError, NotFoundError
from connecthub.core.permissions.constants import SUPER_ADMIN_ROLE
from connecthub.core.permissions.models import Role
from connecthub.core.permissions.policy import PolicyService
from connecthub.core.permissions.registry import PermissionRegistry
from connecthub.core.permissions.repository import PermissionRepository
from connecthub.modules.auth.models import Organization, User
from connecthub.modules.auth.service import AdminService


@pytest.mark.asyncio
async def test_create_admin(
    admin_service: AdminService,
    super_admin_user: User,
    db_session: AsyncSession,
) -> None:
    """Super Admin can create an admin user."""
    await db_session.commit()

    admin = await admin_service.create_admin(
        acting_user_id=super_admin_user.id,
        email="admin1@test.com",
        username="admin1",
        display_name="Admin One",
        password="AdminPass123!",
    )
    await db_session.commit()

    assert admin.email == "admin1@test.com"
    assert admin.username == "admin1"
    assert admin.is_active is True
    assert admin.is_suspended is False


@pytest.mark.asyncio
async def test_create_admin_with_permissions(
    admin_service: AdminService,
    super_admin_user: User,
    sample_domain,
    policy: PolicyService,
    db_session: AsyncSession,
) -> None:
    """Super Admin can create an admin with specific permissions."""
    await db_session.commit()

    # Get some action IDs from the sample domain
    read_action = next(a for a in sample_domain.actions if a.code == "read")
    create_action = next(a for a in sample_domain.actions if a.code == "create")

    admin = await admin_service.create_admin(
        acting_user_id=super_admin_user.id,
        email="admin_perms@test.com",
        username="admin_perms",
        display_name="Admin With Perms",
        password="AdminPass123!",
        permission_action_ids=[read_action.id, create_action.id],
    )
    await db_session.commit()

    # Verify permissions via PolicyService
    result_read = await policy.check_permission(
        admin.id, "department_management", "read",
    )
    assert result_read.allowed is True
    assert result_read.reason == "direct_grant"

    result_create = await policy.check_permission(
        admin.id, "department_management", "create",
    )
    assert result_create.allowed is True

    # "delete" was NOT granted — should be denied
    result_delete = await policy.check_permission(
        admin.id, "department_management", "delete",
    )
    assert result_delete.allowed is False


@pytest.mark.asyncio
async def test_non_super_admin_cannot_create_admin(
    admin_service: AdminService,
    test_org: Organization,
    auth_repo,
    db_session: AsyncSession,
) -> None:
    """Non-Super-Admin users cannot create admins (returns 404, not 403)."""
    from connecthub.core.security.hashing import hash_password

    regular_user = await auth_repo.create_user(
        organization_id=test_org.id,
        email="regular@test.com",
        username="regular",
        display_name="Regular User",
        password_hash=hash_password("RegularPass123!"),
    )
    await db_session.commit()

    with pytest.raises(NotFoundError):
        await admin_service.create_admin(
            acting_user_id=regular_user.id,
            email="newadmin@test.com",
            username="newadmin",
            display_name="New Admin",
            password="AdminPass123!",
        )


@pytest.mark.asyncio
async def test_create_admin_duplicate_email(
    admin_service: AdminService,
    super_admin_user: User,
    db_session: AsyncSession,
) -> None:
    """Creating an admin with a duplicate email raises ConflictError."""
    await db_session.commit()

    await admin_service.create_admin(
        acting_user_id=super_admin_user.id,
        email="dup@test.com",
        username="admin_dup1",
        display_name="Admin Dup",
        password="AdminPass123!",
    )
    await db_session.commit()

    with pytest.raises(ConflictError, match="Email already registered"):
        await admin_service.create_admin(
            acting_user_id=super_admin_user.id,
            email="dup@test.com",
            username="admin_dup2",
            display_name="Admin Dup 2",
            password="AdminPass123!",
        )


@pytest.mark.asyncio
async def test_suspend_admin(
    admin_service: AdminService,
    super_admin_user: User,
    db_session: AsyncSession,
) -> None:
    """Super Admin can suspend an admin."""
    await db_session.commit()

    admin = await admin_service.create_admin(
        acting_user_id=super_admin_user.id,
        email="suspend_me@test.com",
        username="suspend_me",
        display_name="To Be Suspended",
        password="AdminPass123!",
    )
    await db_session.commit()

    suspended = await admin_service.suspend_admin(
        acting_user_id=super_admin_user.id,
        target_user_id=admin.id,
        reason="Policy violation",
    )
    await db_session.commit()

    assert suspended.is_suspended is True


@pytest.mark.asyncio
async def test_cannot_suspend_yourself(
    admin_service: AdminService,
    super_admin_user: User,
    db_session: AsyncSession,
) -> None:
    """Super Admin cannot suspend themselves."""
    await db_session.commit()

    with pytest.raises(ConflictError, match="Cannot suspend yourself"):
        await admin_service.suspend_admin(
            acting_user_id=super_admin_user.id,
            target_user_id=super_admin_user.id,
        )


@pytest.mark.asyncio
async def test_reactivate_admin(
    admin_service: AdminService,
    super_admin_user: User,
    db_session: AsyncSession,
) -> None:
    """Super Admin can reactivate a suspended admin."""
    await db_session.commit()

    admin = await admin_service.create_admin(
        acting_user_id=super_admin_user.id,
        email="reactivate_me@test.com",
        username="reactivate_me",
        display_name="To Be Reactivated",
        password="AdminPass123!",
    )
    await db_session.commit()

    await admin_service.suspend_admin(
        acting_user_id=super_admin_user.id,
        target_user_id=admin.id,
    )
    await db_session.commit()

    reactivated = await admin_service.reactivate_admin(
        acting_user_id=super_admin_user.id,
        target_user_id=admin.id,
    )
    await db_session.commit()

    assert reactivated.is_suspended is False


@pytest.mark.asyncio
async def test_grant_differentiated_permissions(
    admin_service: AdminService,
    super_admin_user: User,
    sample_domain,
    policy: PolicyService,
    db_session: AsyncSession,
) -> None:
    """Super Admin can grant different permissions to different admins (Section 6.2)."""
    await db_session.commit()

    # Create two admins
    admin_a = await admin_service.create_admin(
        acting_user_id=super_admin_user.id,
        email="admin_a@test.com",
        username="admin_a",
        display_name="Admin A",
        password="AdminPass123!",
    )
    admin_b = await admin_service.create_admin(
        acting_user_id=super_admin_user.id,
        email="admin_b@test.com",
        username="admin_b",
        display_name="Admin B",
        password="AdminPass123!",
    )
    await db_session.commit()

    read_action = next(a for a in sample_domain.actions if a.code == "read")
    delete_action = next(a for a in sample_domain.actions if a.code == "delete")

    # Grant Admin A: read only
    await admin_service.grant_admin_permissions(
        acting_user_id=super_admin_user.id,
        target_user_id=admin_a.id,
        action_ids=[read_action.id],
    )
    # Grant Admin B: delete only
    await admin_service.grant_admin_permissions(
        acting_user_id=super_admin_user.id,
        target_user_id=admin_b.id,
        action_ids=[delete_action.id],
    )
    await db_session.commit()

    # Admin A can read, cannot delete
    assert (await policy.check_permission(admin_a.id, "department_management", "read")).allowed is True
    assert (await policy.check_permission(admin_a.id, "department_management", "delete")).allowed is False

    # Admin B can delete, cannot read
    assert (await policy.check_permission(admin_b.id, "department_management", "delete")).allowed is True
    assert (await policy.check_permission(admin_b.id, "department_management", "read")).allowed is False


@pytest.mark.asyncio
async def test_revoke_admin_permissions(
    admin_service: AdminService,
    super_admin_user: User,
    sample_domain,
    policy: PolicyService,
    db_session: AsyncSession,
) -> None:
    """Super Admin can revoke permissions from an admin."""
    await db_session.commit()

    read_action = next(a for a in sample_domain.actions if a.code == "read")

    admin = await admin_service.create_admin(
        acting_user_id=super_admin_user.id,
        email="revoke_me@test.com",
        username="revoke_me",
        display_name="Revoke Me",
        password="AdminPass123!",
        permission_action_ids=[read_action.id],
    )
    await db_session.commit()

    # Verify granted
    assert (await policy.check_permission(admin.id, "department_management", "read")).allowed is True

    # Revoke
    await admin_service.revoke_admin_permissions(
        acting_user_id=super_admin_user.id,
        target_user_id=admin.id,
        action_ids=[read_action.id],
    )
    await db_session.commit()

    # Now denied
    assert (await policy.check_permission(admin.id, "department_management", "read")).allowed is False


@pytest.mark.asyncio
async def test_list_admins(
    admin_service: AdminService,
    super_admin_user: User,
    db_session: AsyncSession,
) -> None:
    """Super Admin can list all admins in the organization."""
    await db_session.commit()

    await admin_service.create_admin(
        acting_user_id=super_admin_user.id,
        email="list_a@test.com",
        username="list_a",
        display_name="List A",
        password="AdminPass123!",
    )
    await admin_service.create_admin(
        acting_user_id=super_admin_user.id,
        email="list_b@test.com",
        username="list_b",
        display_name="List B",
        password="AdminPass123!",
    )
    await db_session.commit()

    admins = await admin_service.list_admins(acting_user_id=super_admin_user.id)
    # Should include the super admin + 2 new admins
    assert len(admins) >= 3


@pytest.mark.asyncio
async def test_admin_operations_create_audit_logs(
    admin_service: AdminService,
    audit_service: AuditService,
    super_admin_user: User,
    db_session: AsyncSession,
) -> None:
    """Admin operations produce audit log entries."""
    await db_session.commit()

    admin = await admin_service.create_admin(
        acting_user_id=super_admin_user.id,
        email="audited_admin@test.com",
        username="audited_admin",
        display_name="Audited Admin",
        password="AdminPass123!",
    )
    await db_session.commit()

    # Check audit logs
    logs = await audit_service.query(user_id=super_admin_user.id)
    assert any(log.action == "admin.created" for log in logs)

    # Suspend and check audit
    await admin_service.suspend_admin(
        acting_user_id=super_admin_user.id,
        target_user_id=admin.id,
        reason="Test suspension",
    )
    await db_session.commit()

    logs = await audit_service.query(user_id=super_admin_user.id)
    assert any(log.action == "admin.suspended" for log in logs)
