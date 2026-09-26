"""
ConnectHub — Group Module Test Fixtures.
"""

from __future__ import annotations

from collections.abc import AsyncGenerator

import pytest
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import sessionmaker

from connecthub.core.audit.models import AuditLog  # noqa: F401
from connecthub.core.audit.service import AuditService
from connecthub.core.database.base import Base
from connecthub.core.permissions.constants import SUPER_ADMIN_ROLE
from connecthub.core.permissions.models import (  # noqa: F401
    DirectPermission, PermissionAction, PermissionDomain,
    Role, RolePermission, UserRole,
)
from connecthub.core.permissions.policy import PolicyService
from connecthub.core.permissions.registry import PermissionRegistry
from connecthub.core.permissions.repository import PermissionRepository
from connecthub.core.permissions.schemas import ActionDefinition, DomainRegistration
from connecthub.core.security.hashing import hash_password
from connecthub.modules.auth.models import Organization, User  # noqa: F401
from connecthub.modules.auth.repository import AuthRepository
from connecthub.modules.group.models import Group, GroupMember, GroupRole  # noqa: F401
from connecthub.modules.messaging.models import Conversation, ConversationParticipant, Message, MessageReaction  # noqa: F401
from connecthub.modules.group.service import GroupService


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
    sf = sessionmaker(bind=async_engine, class_=AsyncSession, expire_on_commit=False)
    async with sf() as session:
        yield session
        await session.rollback()


@pytest.fixture
def auth_repo(db_session): return AuthRepository(db_session)

@pytest.fixture
def perm_repo(db_session): return PermissionRepository(db_session)

@pytest.fixture
def registry(db_session): return PermissionRegistry(db_session)

@pytest.fixture
def audit_service(db_session): return AuditService(db_session)

@pytest.fixture
def group_service(db_session): return GroupService(db_session)

@pytest.fixture
def policy(db_session): return PolicyService(db_session)


@pytest.fixture
async def super_admin_role(db_session) -> Role:
    role = Role(code=SUPER_ADMIN_ROLE, name="Super Admin",
                description="Unrestricted.", is_system=True)
    db_session.add(role)
    await db_session.flush()
    return role


@pytest.fixture
async def test_org(auth_repo, db_session) -> Organization:
    org = await auth_repo.create_organization(name="Test Org", slug="test-org")
    await db_session.flush()
    return org


@pytest.fixture
async def super_admin_user(auth_repo, perm_repo, super_admin_role, test_org, db_session) -> User:
    user = await auth_repo.create_user(
        organization_id=test_org.id, email="sa@test.com", username="sa",
        display_name="Super Admin", password_hash=hash_password("Pass123!"),
    )
    await perm_repo.assign_role_to_user(user.id, super_admin_role.id)
    await db_session.flush()
    return user


@pytest.fixture
async def regular_user(auth_repo, test_org, super_admin_role, db_session) -> User:
    user = await auth_repo.create_user(
        organization_id=test_org.id, email="reg@test.com", username="reg",
        display_name="Regular", password_hash=hash_password("Pass123!"),
    )
    await db_session.flush()
    return user


@pytest.fixture
async def member_user(auth_repo, test_org, super_admin_role, db_session) -> User:
    """An extra user to add as a group member."""
    user = await auth_repo.create_user(
        organization_id=test_org.id, email="member@test.com", username="member",
        display_name="Member User", password_hash=hash_password("Pass123!"),
    )
    await db_session.flush()
    return user


@pytest.fixture
async def group_domain(registry, db_session) -> PermissionDomain:
    domain = await registry.register_domain(
        DomainRegistration(
            code="group_management", name="Group Management",
            actions=[
                ActionDefinition(code="create", name="Create Group"),
                ActionDefinition(code="read", name="View Groups"),
                ActionDefinition(code="update", name="Update Group"),
                ActionDefinition(code="delete", name="Delete Group"),
            ],
        )
    )
    await db_session.flush()
    return domain


@pytest.fixture
async def user_with_group_read(auth_repo, test_org, group_domain, super_admin_role, db_session) -> User:
    user = await auth_repo.create_user(
        organization_id=test_org.id, email="greader@test.com", username="greader",
        display_name="Group Reader", password_hash=hash_password("Pass123!"),
    )
    read_action = next(a for a in group_domain.actions if a.code == "read")
    db_session.add(DirectPermission(user_id=user.id, action_id=read_action.id, is_grant=True))
    await db_session.flush()
    return user
