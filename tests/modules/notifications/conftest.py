"""
ConnectHub — Notification Module Test Fixtures.
"""

from __future__ import annotations

from collections.abc import AsyncGenerator

import pytest
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import sessionmaker

from connecthub.core.audit.models import AuditLog  # noqa: F401
from connecthub.core.database.base import Base
from connecthub.core.permissions.constants import SUPER_ADMIN_ROLE
from connecthub.core.permissions.models import (  # noqa: F401
    DirectPermission, PermissionAction, PermissionDomain,
    Role, RolePermission, UserRole,
)
from connecthub.core.permissions.repository import PermissionRepository
from connecthub.core.security.hashing import hash_password
from connecthub.modules.auth.models import Organization, User  # noqa: F401
from connecthub.modules.auth.repository import AuthRepository
from connecthub.modules.group.models import Group, GroupMember  # noqa: F401
from connecthub.modules.messaging.models import (  # noqa: F401
    Conversation, ConversationParticipant, Message,
)
from connecthub.modules.files.models import FileAttachment  # noqa: F401
from connecthub.modules.notifications.models import NotificationItem  # noqa: F401
from connecthub.modules.notifications.service import NotificationService


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
def notification_service(db_session): return NotificationService(db_session)


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
async def user_alice(auth_repo, perm_repo, super_admin_role, test_org, db_session) -> User:
    user = await auth_repo.create_user(
        organization_id=test_org.id, email="alice@test.com", username="alice",
        display_name="Alice", password_hash=hash_password("Pass123!"),
    )
    await db_session.flush()
    return user


@pytest.fixture
async def user_bob(auth_repo, perm_repo, super_admin_role, test_org, db_session) -> User:
    user = await auth_repo.create_user(
        organization_id=test_org.id, email="bob@test.com", username="bob",
        display_name="Bob", password_hash=hash_password("Pass123!"),
    )
    await db_session.flush()
    return user
