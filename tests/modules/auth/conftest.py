"""
ConnectHub — Auth Module Test Fixtures.

Shared fixtures for auth module tests — provides async SQLite database,
pre-built services, and sample data (org, super admin, admin).
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
from connecthub.core.permissions.constants import ADMIN_ROLE, SUPER_ADMIN_ROLE
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
from connecthub.core.permissions.service import PermissionService
from connecthub.core.security.hashing import hash_password
from connecthub.modules.auth.models import Organization, User  # noqa: F401 — register
from connecthub.modules.auth.repository import AuthRepository
from connecthub.modules.auth.service import AdminService, AuthService


@pytest.fixture
async def async_engine():
    """Create an async SQLite engine for testing."""
    engine = create_async_engine(
        "sqlite+aiosqlite:///:memory:",
        echo=False,
    )
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield engine
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
    await engine.dispose()


@pytest.fixture
async def db_session(async_engine) -> AsyncGenerator[AsyncSession, None]:
    """Provide an async session scoped to each test."""
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
def auth_service(db_session: AsyncSession) -> AuthService:
    return AuthService(db_session)


@pytest.fixture
def admin_service(db_session: AsyncSession) -> AdminService:
    return AdminService(db_session)


@pytest.fixture
def policy(db_session: AsyncSession) -> PolicyService:
    return PolicyService(db_session)


@pytest.fixture
def registry(db_session: AsyncSession) -> PermissionRegistry:
    return PermissionRegistry(db_session)


@pytest.fixture
def audit_service(db_session: AsyncSession) -> AuditService:
    return AuditService(db_session)


@pytest.fixture
async def super_admin_role(db_session: AsyncSession) -> Role:
    """Create the Super Admin system role."""
    role = Role(
        code=SUPER_ADMIN_ROLE,
        name="Super Admin",
        description="Unrestricted system access.",
        is_system=True,
    )
    db_session.add(role)
    await db_session.flush()
    return role


@pytest.fixture
async def admin_role(db_session: AsyncSession) -> Role:
    """Create the Admin role."""
    role = Role(
        code=ADMIN_ROLE,
        name="Admin",
        description="Organization administrator.",
    )
    db_session.add(role)
    await db_session.flush()
    return role


@pytest.fixture
async def test_org(auth_repo: AuthRepository, db_session: AsyncSession) -> Organization:
    """Create a test organization."""
    org = await auth_repo.create_organization(
        name="Test Organization",
        slug="test-org",
    )
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
    """Create a Super Admin user with role assigned."""
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
async def sample_domain(
    registry: PermissionRegistry, db_session: AsyncSession,
):
    """Register a sample permission domain with CRUD actions."""
    domain = await registry.register_domain(
        DomainRegistration(
            code="department_management",
            name="Department Management",
            actions=[
                ActionDefinition(code="create", name="Create Department"),
                ActionDefinition(code="read", name="View Departments"),
                ActionDefinition(code="update", name="Update Department"),
                ActionDefinition(code="delete", name="Delete Department"),
            ],
        )
    )
    await db_session.commit()
    return domain
