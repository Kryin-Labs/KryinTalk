"""
ConnectHub — Policy Service Tests.

Tests the central authorization service with all 5 evaluation steps:
1. Super Admin bypass → ALLOW
2. Direct deny → DENY
3. Direct grant → ALLOW
4. Role grant → ALLOW
5. Default → DENY
"""

from __future__ import annotations

import uuid

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from connecthub.core.permissions.constants import SUPER_ADMIN_ROLE
from connecthub.core.permissions.models import Role
from connecthub.core.permissions.policy import PolicyService
from connecthub.core.permissions.registry import PermissionRegistry
from connecthub.core.permissions.repository import PermissionRepository
from connecthub.core.permissions.schemas import ActionDefinition, DomainRegistration
from connecthub.core.exceptions import NotFoundError


@pytest.mark.asyncio
async def test_super_admin_bypass(
    policy: PolicyService,
    super_admin_role: Role,
    sample_domain,
    db_session: AsyncSession,
    perm_repo: PermissionRepository,
) -> None:
    """Super Admin bypasses all permission checks (Section 6.1)."""
    user_id = uuid.uuid4()
    await perm_repo.assign_role_to_user(user_id, super_admin_role.id)
    await db_session.commit()

    result = await policy.check_permission(user_id, "department_management", "create")
    assert result.allowed is True
    assert result.reason == "super_admin_bypass"


@pytest.mark.asyncio
async def test_super_admin_bypass_unregistered_domain(
    policy: PolicyService,
    super_admin_role: Role,
    db_session: AsyncSession,
    perm_repo: PermissionRepository,
) -> None:
    """Super Admin can access even unregistered domains (bypass is unconditional)."""
    user_id = uuid.uuid4()
    await perm_repo.assign_role_to_user(user_id, super_admin_role.id)
    await db_session.commit()

    result = await policy.check_permission(user_id, "nonexistent_domain", "anything")
    assert result.allowed is True
    assert result.reason == "super_admin_bypass"


@pytest.mark.asyncio
async def test_role_grant_allows_access(
    policy: PolicyService,
    sample_domain,
    db_session: AsyncSession,
    perm_repo: PermissionRepository,
) -> None:
    """User with a role that grants the action → allowed."""
    user_id = uuid.uuid4()

    # Create a role and grant it the "read" permission
    role = await perm_repo.create_role(code="dept_viewer", name="Department Viewer")
    action = await perm_repo.resolve_action("department_management", "read")
    assert action is not None
    await perm_repo.grant_role_permission(role.id, action.id)
    await perm_repo.assign_role_to_user(user_id, role.id)
    await db_session.commit()

    result = await policy.check_permission(user_id, "department_management", "read")
    assert result.allowed is True
    assert result.reason == "role_grant"


@pytest.mark.asyncio
async def test_no_permission_denies_access(
    policy: PolicyService,
    sample_domain,
    db_session: AsyncSession,
) -> None:
    """User without any grants → denied (default deny)."""
    user_id = uuid.uuid4()

    result = await policy.check_permission(user_id, "department_management", "create")
    assert result.allowed is False
    assert result.reason == "no_permission"


@pytest.mark.asyncio
async def test_direct_grant_allows_access(
    policy: PolicyService,
    sample_domain,
    db_session: AsyncSession,
    perm_repo: PermissionRepository,
) -> None:
    """User with a direct grant → allowed."""
    user_id = uuid.uuid4()
    action = await perm_repo.resolve_action("department_management", "create")
    assert action is not None
    await perm_repo.grant_direct_permission(user_id, action.id, is_grant=True)
    await db_session.commit()

    result = await policy.check_permission(user_id, "department_management", "create")
    assert result.allowed is True
    assert result.reason == "direct_grant"


@pytest.mark.asyncio
async def test_direct_deny_overrides_role_grant(
    policy: PolicyService,
    sample_domain,
    db_session: AsyncSession,
    perm_repo: PermissionRepository,
) -> None:
    """Direct deny overrides role grant (deny takes precedence)."""
    user_id = uuid.uuid4()

    # Grant via role
    role = await perm_repo.create_role(code="dept_admin", name="Department Admin")
    action = await perm_repo.resolve_action("department_management", "delete")
    assert action is not None
    await perm_repo.grant_role_permission(role.id, action.id)
    await perm_repo.assign_role_to_user(user_id, role.id)

    # Add direct deny
    await perm_repo.grant_direct_permission(user_id, action.id, is_grant=False)
    await db_session.commit()

    result = await policy.check_permission(user_id, "department_management", "delete")
    assert result.allowed is False
    assert result.reason == "direct_deny"


@pytest.mark.asyncio
async def test_inactive_domain_denies_access(
    policy: PolicyService,
    registry: PermissionRegistry,
    sample_domain,
    db_session: AsyncSession,
    perm_repo: PermissionRepository,
) -> None:
    """Deactivated domain → deny all checks against it."""
    user_id = uuid.uuid4()

    # Grant via role
    role = await perm_repo.create_role(code="viewer", name="Viewer")
    action = await perm_repo.resolve_action("department_management", "read")
    assert action is not None
    await perm_repo.grant_role_permission(role.id, action.id)
    await perm_repo.assign_role_to_user(user_id, role.id)
    await db_session.commit()

    # Verify access works
    result = await policy.check_permission(user_id, "department_management", "read")
    assert result.allowed is True

    # Deactivate the domain
    await registry.deactivate_domain("department_management")
    await db_session.commit()

    # Now access should be denied
    result = await policy.check_permission(user_id, "department_management", "read")
    assert result.allowed is False
    assert result.reason == "action_not_found"


@pytest.mark.asyncio
async def test_nonexistent_action_denies_access(
    policy: PolicyService,
    sample_domain,
    db_session: AsyncSession,
) -> None:
    """Non-existent action within a valid domain → denied."""
    user_id = uuid.uuid4()

    result = await policy.check_permission(user_id, "department_management", "nonexistent")
    assert result.allowed is False
    assert result.reason == "action_not_found"


@pytest.mark.asyncio
async def test_require_permission_raises_not_found(
    policy: PolicyService,
    sample_domain,
    db_session: AsyncSession,
) -> None:
    """require_permission raises NotFoundError (404, not 403) when denied."""
    user_id = uuid.uuid4()

    with pytest.raises(NotFoundError):
        await policy.require_permission(user_id, "department_management", "create")


@pytest.mark.asyncio
async def test_require_permission_passes_when_allowed(
    policy: PolicyService,
    super_admin_role: Role,
    sample_domain,
    db_session: AsyncSession,
    perm_repo: PermissionRepository,
) -> None:
    """require_permission passes silently when access is allowed."""
    user_id = uuid.uuid4()
    await perm_repo.assign_role_to_user(user_id, super_admin_role.id)
    await db_session.commit()

    # Should not raise
    await policy.require_permission(user_id, "department_management", "create")


@pytest.mark.asyncio
async def test_is_super_admin_helper(
    policy: PolicyService,
    super_admin_role: Role,
    db_session: AsyncSession,
    perm_repo: PermissionRepository,
) -> None:
    """is_super_admin returns True for Super Admin users."""
    admin_user = uuid.uuid4()
    regular_user = uuid.uuid4()

    await perm_repo.assign_role_to_user(admin_user, super_admin_role.id)
    await db_session.commit()

    assert await policy.is_super_admin(admin_user) is True
    assert await policy.is_super_admin(regular_user) is False


@pytest.mark.asyncio
async def test_end_to_end_register_grant_check(
    registry: PermissionRegistry,
    policy: PolicyService,
    db_session: AsyncSession,
    perm_repo: PermissionRepository,
) -> None:
    """End-to-end: register module → create role → grant → assign → check → ALLOW."""
    # 1. Register a module
    domain = await registry.register_domain(
        DomainRegistration(
            code="group_management",
            name="Group Management",
            actions=[
                ActionDefinition(code="create", name="Create Group"),
                ActionDefinition(code="read", name="View Groups"),
            ],
        )
    )
    await db_session.commit()

    # 2. Create a role
    role = await perm_repo.create_role(code="group_mod", name="Group Moderator")

    # 3. Grant the "read" permission to the role
    read_action = next(a for a in domain.actions if a.code == "read")
    await perm_repo.grant_role_permission(role.id, read_action.id)

    # 4. Assign the role to a user
    user_id = uuid.uuid4()
    await perm_repo.assign_role_to_user(user_id, role.id)
    await db_session.commit()

    # 5. Check permission → should be allowed
    result = await policy.check_permission(user_id, "channel_management", "read")
    assert result.allowed is True
    assert result.reason == "role_grant"

    # 6. Action NOT granted → should be denied
    result = await policy.check_permission(user_id, "channel_management", "create")
    assert result.allowed is False
    assert result.reason == "no_permission"
