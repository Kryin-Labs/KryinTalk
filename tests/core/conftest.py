"""
ConnectHub — Permission Engine Test Fixtures.

Provides an async SQLite in-memory database for testing the permission
engine without requiring a real PostgreSQL instance.
"""

from __future__ import annotations

import uuid
from collections.abc import AsyncGenerator

import pytest
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import sessionmaker

from connecthub.core.audit.service import AuditService
from connecthub.core.database.base import Base
from connecthub.core.permissions.constants import SUPER_ADMIN_ROLE
from connecthub.core.permissions.models import (
    DirectPermission,
    PermissionAction,
    PermissionDomain,
    Role,
    RolePermission,
    UserRole,
)
from connecthub.core.audit.models import AuditLog  # noqa: F401 — import to register model
from connecthub.core.permissions.policy import PolicyService
from connecthub.core.permissions.registry import PermissionRegistry
from connecthub.core.permissions.repository import PermissionRepository
from connecthub.core.permissions.schemas import ActionDefinition, DomainRegistration
from connecthub.core.permissions.service import PermissionService


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
def perm_repo(db_session: AsyncSession) -> PermissionRepository:
    """Provide a PermissionRepository instance."""
    return PermissionRepository(db_session)


@pytest.fixture
def registry(db_session: AsyncSession) -> PermissionRegistry:
    """Provide a PermissionRegistry instance."""
    return PermissionRegistry(db_session)


@pytest.fixture
def policy(db_session: AsyncSession) -> PolicyService:
    """Provide a PolicyService instance."""
    return PolicyService(db_session)


@pytest.fixture
def audit_service(db_session: AsyncSession) -> AuditService:
    """Provide an AuditService instance."""
    return AuditService(db_session)


@pytest.fixture
def perm_service(db_session: AsyncSession, audit_service: AuditService) -> PermissionService:
    """Provide a PermissionService instance with audit logging."""
    return PermissionService(db_session, audit_logger=audit_service)


@pytest.fixture
async def super_admin_role(db_session: AsyncSession) -> Role:
    """Create and return the Super Admin system role."""
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
async def sample_domain(registry: PermissionRegistry, db_session: AsyncSession):
    """Register a sample permission domain with standard CRUD actions."""
    domain = await registry.register_domain(
        DomainRegistration(
            code="group_management",
            name="Group Management",
            description="Manage workspace groups",
            actions=[
                ActionDefinition(code="create", name="Create Group"),
                ActionDefinition(code="read", name="View Groups"),
                ActionDefinition(code="update", name="Update Group"),
                ActionDefinition(code="delete", name="Delete Group"),
                ActionDefinition(code="manage", name="Full Group Management"),
            ],
        )
    )
    await db_session.commit()
    return domain
