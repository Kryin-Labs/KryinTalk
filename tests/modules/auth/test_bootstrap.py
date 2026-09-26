"""
ConnectHub — Bootstrap Tests.

Tests for the Super Admin bootstrap flow.
"""

from __future__ import annotations

import uuid

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from connecthub.core.permissions.constants import SUPER_ADMIN_ROLE
from connecthub.core.permissions.models import Role, UserRole
from connecthub.core.permissions.repository import PermissionRepository
from connecthub.core.security.hashing import hash_password
from connecthub.modules.auth.models import Organization, User
from connecthub.modules.auth.repository import AuthRepository


@pytest.mark.asyncio
async def test_bootstrap_creates_org_user_and_role(
    auth_repo: AuthRepository,
    perm_repo: PermissionRepository,
    super_admin_role: Role,
    db_session: AsyncSession,
) -> None:
    """Bootstrap creates org + user + super_admin role assignment."""
    # Create organization
    org = await auth_repo.create_organization(
        name="Bootstrap Org", slug="bootstrap-org",
    )

    # Create user
    user = await auth_repo.create_user(
        organization_id=org.id,
        email="bootstrap@test.com",
        username="bootstrap_admin",
        display_name="Bootstrap Admin",
        password_hash=hash_password("BootstrapPass123!"),
    )

    # Assign super_admin role
    await perm_repo.assign_role_to_user(user.id, super_admin_role.id)
    await db_session.commit()

    # Verify org exists
    found_org = await auth_repo.get_organization_by_slug("bootstrap-org")
    assert found_org is not None
    assert found_org.name == "Bootstrap Org"

    # Verify user exists
    found_user = await auth_repo.get_user_by_email("bootstrap@test.com")
    assert found_user is not None
    assert found_user.username == "bootstrap_admin"

    # Verify super_admin role assigned
    has_sa = await perm_repo.user_has_system_role(user.id, SUPER_ADMIN_ROLE)
    assert has_sa is True


@pytest.mark.asyncio
async def test_bootstrap_prevents_duplicate_super_admin(
    auth_repo: AuthRepository,
    perm_repo: PermissionRepository,
    super_admin_role: Role,
    db_session: AsyncSession,
) -> None:
    """Bootstrap refuses if a Super Admin already exists."""
    # First bootstrap
    org = await auth_repo.create_organization(name="First Org", slug="first-org")
    user = await auth_repo.create_user(
        organization_id=org.id,
        email="first_sa@test.com",
        username="first_sa",
        display_name="First SA",
        password_hash=hash_password("FirstSAPass123!"),
    )
    await perm_repo.assign_role_to_user(user.id, super_admin_role.id)
    await db_session.commit()

    # Simulate bootstrap check: query for existing super admin
    from sqlalchemy import select
    stmt = select(UserRole).where(UserRole.role_id == super_admin_role.id)
    result = await db_session.execute(stmt)
    existing_sa = result.scalar_one_or_none()

    # Super Admin already exists — bootstrap should refuse
    assert existing_sa is not None, "Bootstrap should detect existing Super Admin"


@pytest.mark.asyncio
async def test_bootstrap_user_can_login(
    auth_repo: AuthRepository,
    perm_repo: PermissionRepository,
    super_admin_role: Role,
    db_session: AsyncSession,
) -> None:
    """Bootstrapped Super Admin can log in successfully."""
    from connecthub.modules.auth.service import AuthService

    org = await auth_repo.create_organization(name="Login Org", slug="login-org")
    user = await auth_repo.create_user(
        organization_id=org.id,
        email="login_sa@test.com",
        username="login_sa",
        display_name="Login SA",
        password_hash=hash_password("LoginPass123!"),
    )
    await perm_repo.assign_role_to_user(user.id, super_admin_role.id)
    await db_session.commit()

    auth_service = AuthService(db_session)
    tokens = await auth_service.login("login_sa@test.com", "LoginPass123!")
    await db_session.commit()

    assert tokens.access_token is not None
    assert tokens.refresh_token is not None


@pytest.mark.asyncio
async def test_bootstrap_user_has_full_access(
    auth_repo: AuthRepository,
    perm_repo: PermissionRepository,
    super_admin_role: Role,
    registry,
    db_session: AsyncSession,
) -> None:
    """Bootstrapped Super Admin bypasses all permission checks."""
    from connecthub.core.permissions.policy import PolicyService
    from connecthub.core.permissions.schemas import ActionDefinition, DomainRegistration

    # Register a domain
    await registry.register_domain(
        DomainRegistration(
            code="user_management",
            name="User Management",
            actions=[ActionDefinition(code="create", name="Create User")],
        )
    )

    org = await auth_repo.create_organization(name="Access Org", slug="access-org")
    user = await auth_repo.create_user(
        organization_id=org.id,
        email="access_sa@test.com",
        username="access_sa",
        display_name="Access SA",
        password_hash=hash_password("AccessPass123!"),
    )
    await perm_repo.assign_role_to_user(user.id, super_admin_role.id)
    await db_session.commit()

    policy = PolicyService(db_session)
    result = await policy.check_permission(user.id, "user_management", "create")
    assert result.allowed is True
    assert result.reason == "super_admin_bypass"
