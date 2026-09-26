"""
ConnectHub — Org Settings Module Test Fixtures.

Reuses the same fixture pattern as department tests.
"""

from __future__ import annotations

import uuid
from collections.abc import AsyncGenerator

import pytest
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import sessionmaker

from connecthub.core.audit.models import AuditLog  # noqa: F401
from connecthub.core.audit.service import AuditService
from connecthub.core.database.base import Base
from connecthub.core.permissions.constants import SUPER_ADMIN_ROLE
from connecthub.core.permissions.models import (  # noqa: F401
    DirectPermission,
    PermissionAction,
    PermissionDomain,
    Role,
    RolePermission,
    UserRole,
)
from connecthub.core.permissions.policy import PolicyService
from connecthub.core.permissions.registry import PermissionRegistry
from connecthub.core.permissions.repository import PermissionRepository
from connecthub.core.permissions.schemas import ActionDefinition, DomainRegistration
from connecthub.core.security.hashing import hash_password
from connecthub.modules.auth.models import Organization, User  # noqa: F401
from connecthub.modules.auth.repository import AuthRepository


@pytest.fixture
async def async_engine():
    engine = create_async_engine("sqlite+aiosqlite:///:memory:", echo=False)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield engine
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
    await engine.dispose()


@pytest.fixture
async def db_session(async_engine) -> AsyncGenerator[AsyncSession, None]:
    session_factory = sessionmaker(
        bind=async_engine, class_=AsyncSession, expire_on_commit=False,
    )
    async with session_factory() as session:
        yield session
        await session.rollback()


@pytest.fixture
def auth_repo(db_session: AsyncSession) -> AuthRepository:
    return AuthRepository(db_session)


@pytest.fixture
def perm_repo(db_session: AsyncSession) -> PermissionRepository:
    return PermissionRepository(db_session)


@pytest.fixture
def registry(db_session: AsyncSession) -> PermissionRegistry:
    return PermissionRegistry(db_session)


@pytest.fixture
def audit_service(db_session: AsyncSession) -> AuditService:
    return AuditService(db_session)


@pytest.fixture
async def super_admin_role(db_session: AsyncSession) -> Role:
    role = Role(
        code=SUPER_ADMIN_ROLE, name="Super Admin",
        description="Unrestricted system access.", is_system=True,
    )
    db_session.add(role)
    await db_session.flush()
    return role


@pytest.fixture
async def test_org(auth_repo: AuthRepository, db_session: AsyncSession) -> Organization:
    org = await auth_repo.create_organization(name="Test Org", slug="test-org")
    await db_session.flush()
    return org


@pytest.fixture
async def super_admin_user(
    auth_repo: AuthRepository,
    perm_repo: PermissionRepository,
    super_admin_role: Role,
    test_org: Organization,
    db_session: AsyncSession,
) -> User:
    user = await auth_repo.create_user(
        organization_id=test_org.id,
        email="superadmin@test.com",
        username="superadmin",
        display_name="Super Admin",
        password_hash=hash_password("SuperAdminPass123!"),
    )
    await perm_repo.assign_role_to_user(user.id, super_admin_role.id)
    await db_session.flush()
    return user


@pytest.fixture
async def regular_user(
    auth_repo: AuthRepository,
    test_org: Organization,
    super_admin_role: Role,
    db_session: AsyncSession,
) -> User:
    user = await auth_repo.create_user(
        organization_id=test_org.id,
        email="regular@test.com",
        username="regular",
        display_name="Regular User",
        password_hash=hash_password("RegularPass123!"),
    )
    await db_session.flush()
    return user


@pytest.fixture
async def org_domain(
    registry: PermissionRegistry, db_session: AsyncSession,
) -> PermissionDomain:
    domain = await registry.register_domain(
        DomainRegistration(
            code="organization_settings",
            name="Organization Settings",
            actions=[
                ActionDefinition(code="read", name="View Organization"),
                ActionDefinition(code="update", name="Update Organization"),
            ],
        )
    )
    await db_session.flush()
    return domain
