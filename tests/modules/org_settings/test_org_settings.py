"""
ConnectHub — Organization Settings Tests.

Tests for reading/updating org settings with permission gating.
"""

from __future__ import annotations

import uuid

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from connecthub.core.audit.service import AuditService
from connecthub.core.exceptions import NotFoundError
from connecthub.core.permissions.models import DirectPermission, PermissionDomain, Role
from connecthub.modules.auth.models import Organization, User
from connecthub.modules.org_settings.schemas import OrgSettingsUpdate
from connecthub.modules.org_settings.service import OrgSettingsService


@pytest.fixture
def org_service(db_session: AsyncSession) -> OrgSettingsService:
    return OrgSettingsService(db_session)


@pytest.mark.asyncio
async def test_super_admin_can_read_org(
    org_service: OrgSettingsService,
    super_admin_user: User,
    org_domain: PermissionDomain,
    db_session: AsyncSession,
) -> None:
    """Super Admin can read organization settings."""
    await db_session.commit()

    org = await org_service.get_organization(super_admin_user.id)
    assert org.name == "Test Org"
    assert org.slug == "test-org"


@pytest.mark.asyncio
async def test_super_admin_can_update_org(
    org_service: OrgSettingsService,
    super_admin_user: User,
    org_domain: PermissionDomain,
    db_session: AsyncSession,
) -> None:
    """Super Admin can update organization settings."""
    await db_session.commit()

    updated = await org_service.update_organization(
        user_id=super_admin_user.id,
        data=OrgSettingsUpdate(name="Updated Org Name"),
    )
    await db_session.commit()

    assert updated.name == "Updated Org Name"


@pytest.mark.asyncio
async def test_super_admin_can_update_org_settings_json(
    org_service: OrgSettingsService,
    super_admin_user: User,
    org_domain: PermissionDomain,
    db_session: AsyncSession,
) -> None:
    """Super Admin can update org settings JSON payload."""
    await db_session.commit()

    updated = await org_service.update_organization(
        user_id=super_admin_user.id,
        data=OrgSettingsUpdate(settings={"max_admins": 5, "theme": "dark"}),
    )
    await db_session.commit()

    assert updated.settings == {"max_admins": 5, "theme": "dark"}


@pytest.mark.asyncio
async def test_regular_user_cannot_read_org(
    org_service: OrgSettingsService,
    regular_user: User,
    org_domain: PermissionDomain,
    db_session: AsyncSession,
) -> None:
    """User without read permission gets 404 on org settings."""
    await db_session.commit()

    with pytest.raises(NotFoundError):
        await org_service.get_organization(regular_user.id)


@pytest.mark.asyncio
async def test_regular_user_cannot_update_org(
    org_service: OrgSettingsService,
    regular_user: User,
    org_domain: PermissionDomain,
    db_session: AsyncSession,
) -> None:
    """User without update permission gets 404 on org update."""
    await db_session.commit()

    with pytest.raises(NotFoundError):
        await org_service.update_organization(
            user_id=regular_user.id,
            data=OrgSettingsUpdate(name="Hacked Name"),
        )


@pytest.mark.asyncio
async def test_org_update_creates_audit_log(
    org_service: OrgSettingsService,
    audit_service: AuditService,
    super_admin_user: User,
    org_domain: PermissionDomain,
    db_session: AsyncSession,
) -> None:
    """Org settings update produces an audit log entry."""
    await db_session.commit()

    await org_service.update_organization(
        user_id=super_admin_user.id,
        data=OrgSettingsUpdate(name="Audited Org"),
    )
    await db_session.commit()

    logs = await audit_service.query(
        user_id=super_admin_user.id, action="organization.updated",
    )
    assert len(logs) >= 1
