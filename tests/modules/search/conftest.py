"""
ConnectHub — Search Module Test Fixtures.
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
from connecthub.modules.messaging.service import MessagingService
from connecthub.modules.files.service import FileService
from connecthub.modules.files.storage import LocalStorageBackend
from connecthub.modules.search.service import SearchService


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
def messaging_service(db_session): return MessagingService(db_session)

@pytest.fixture
def search_service(db_session): return SearchService(db_session)

@pytest.fixture
def storage_backend(tmp_path):
    d = tmp_path / "uploads"
    d.mkdir()
    return LocalStorageBackend(base_dir=str(d))

@pytest.fixture
def file_service(db_session, storage_backend):
    return FileService(db_session, storage=storage_backend)


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
    await perm_repo.assign_role_to_user(user.id, super_admin_role.id)
    await db_session.flush()
    return user


@pytest.fixture
async def user_bob(auth_repo, perm_repo, super_admin_role, test_org, db_session) -> User:
    user = await auth_repo.create_user(
        organization_id=test_org.id, email="bob@test.com", username="bob",
        display_name="Bob", password_hash=hash_password("Pass123!"),
    )
    await perm_repo.assign_role_to_user(user.id, super_admin_role.id)
    await db_session.flush()
    return user


@pytest.fixture
async def user_charlie(auth_repo, test_org, super_admin_role, db_session) -> User:
    """Third user — NOT added to conversations by default."""
    user = await auth_repo.create_user(
        organization_id=test_org.id, email="charlie@test.com", username="charlie",
        display_name="Charlie", password_hash=hash_password("Pass123!"),
    )
    await db_session.flush()
    return user


@pytest.fixture
async def dm_alice_bob(messaging_service, user_alice, user_bob, db_session):
    """DM between Alice and Bob with messages."""
    await db_session.commit()
    conv = await messaging_service.start_direct_message(user_alice.id, user_bob.id)
    await db_session.commit()
    return conv
