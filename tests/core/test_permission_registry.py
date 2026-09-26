"""
ConnectHub — Permission Registry Tests.

Tests for module registration: register domains, actions,
idempotent re-registration, and deactivation.
"""

from __future__ import annotations

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from connecthub.core.permissions.registry import PermissionRegistry
from connecthub.core.permissions.schemas import ActionDefinition, DomainRegistration


@pytest.mark.asyncio
async def test_register_new_domain(
    registry: PermissionRegistry, db_session: AsyncSession,
) -> None:
    """Registering a new domain creates it with all actions."""
    domain = await registry.register_domain(
        DomainRegistration(
            code="user_management",
            name="User Management",
            description="Manage users",
            actions=[
                ActionDefinition(code="create", name="Create User"),
                ActionDefinition(code="read", name="View Users"),
                ActionDefinition(code="delete", name="Delete User"),
            ],
        )
    )
    await db_session.commit()

    assert domain.code == "user_management"
    assert domain.name == "User Management"
    assert domain.is_active is True
    assert len(domain.actions) == 3

    action_codes = {a.code for a in domain.actions}
    assert action_codes == {"create", "read", "delete"}


@pytest.mark.asyncio
async def test_idempotent_registration(
    registry: PermissionRegistry, db_session: AsyncSession,
) -> None:
    """Re-registering the same domain is idempotent — no duplicates."""
    reg = DomainRegistration(
        code="file_management",
        name="File Management",
        actions=[
            ActionDefinition(code="upload", name="Upload File"),
            ActionDefinition(code="download", name="Download File"),
        ],
    )

    domain1 = await registry.register_domain(reg)
    await db_session.commit()

    domain2 = await registry.register_domain(reg)
    await db_session.commit()

    # Same domain ID — not duplicated
    assert domain1.id == domain2.id
    assert len(domain2.actions) == 2


@pytest.mark.asyncio
async def test_registration_adds_new_actions(
    registry: PermissionRegistry, db_session: AsyncSession,
) -> None:
    """Re-registering with additional actions adds them (additive)."""
    # First registration
    await registry.register_domain(
        DomainRegistration(
            code="report_management",
            name="Reports",
            actions=[
                ActionDefinition(code="read", name="View Reports"),
            ],
        )
    )
    await db_session.commit()

    # Second registration with additional action
    domain = await registry.register_domain(
        DomainRegistration(
            code="report_management",
            name="Reports",
            actions=[
                ActionDefinition(code="read", name="View Reports"),
                ActionDefinition(code="export", name="Export Reports"),
            ],
        )
    )
    await db_session.commit()

    assert len(domain.actions) == 2
    action_codes = {a.code for a in domain.actions}
    assert action_codes == {"read", "export"}


@pytest.mark.asyncio
async def test_deactivate_domain(
    registry: PermissionRegistry, db_session: AsyncSession,
) -> None:
    """Deactivating a domain marks it inactive."""
    await registry.register_domain(
        DomainRegistration(
            code="temp_domain",
            name="Temporary",
            actions=[
                ActionDefinition(code="read", name="Read"),
            ],
        )
    )
    await db_session.commit()

    result = await registry.deactivate_domain("temp_domain")
    await db_session.commit()
    assert result is True

    # Active-only listing should exclude it
    domains = await registry.list_domains(active_only=True)
    assert not any(d.code == "temp_domain" for d in domains)


@pytest.mark.asyncio
async def test_deactivate_nonexistent_domain(
    registry: PermissionRegistry,
) -> None:
    """Deactivating a non-existent domain returns False."""
    result = await registry.deactivate_domain("nonexistent")
    assert result is False


@pytest.mark.asyncio
async def test_list_domains(
    registry: PermissionRegistry, db_session: AsyncSession,
) -> None:
    """List all active domains."""
    await registry.register_domain(
        DomainRegistration(
            code="domain_a",
            name="Domain A",
            actions=[ActionDefinition(code="read", name="Read")],
        )
    )
    await registry.register_domain(
        DomainRegistration(
            code="domain_b",
            name="Domain B",
            actions=[ActionDefinition(code="write", name="Write")],
        )
    )
    await db_session.commit()

    domains = await registry.list_domains()
    codes = {d.code for d in domains}
    assert "domain_a" in codes
    assert "domain_b" in codes
