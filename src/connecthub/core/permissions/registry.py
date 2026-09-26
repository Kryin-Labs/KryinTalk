"""
ConnectHub — Permission Registry.

Modules call the registry at startup to register their permission domains
and available actions. Registration is idempotent (safe on every boot).

Example usage in a module's __init__.py:

    async def register_permissions(session: AsyncSession) -> None:
        registry = PermissionRegistry(session)
        await registry.register_domain(
            DomainRegistration(
            code="group_management",
            name="Group Management",
            description="Manage workspace groups",
            actions=[
                    ActionDefinition(code="create", name="Create Group"),
                    ActionDefinition(code="read", name="View Groups"),
                    ActionDefinition(code="update", name="Update Group"),
                    ActionDefinition(code="delete", name="Delete Group"),
                ],
            )
        )
"""

from __future__ import annotations

import logging

from sqlalchemy.ext.asyncio import AsyncSession

from connecthub.core.permissions.repository import PermissionRepository
from connecthub.core.permissions.schemas import DomainRegistration, DomainResponse

logger = logging.getLogger(__name__)


class PermissionRegistry:
    """Service for registering module permission domains and actions.

    Registration is idempotent — calling register_domain multiple times
    with the same code will update the existing domain and add any
    new actions, but will not remove existing ones.
    """

    def __init__(self, session: AsyncSession) -> None:
        self._repo = PermissionRepository(session)

    async def register_domain(self, registration: DomainRegistration) -> DomainResponse:
        """Register a permission domain and its actions.

        If the domain already exists, updates its metadata and adds any
        new actions that don't yet exist. Existing actions are not removed
        (to prevent breaking existing role grants).

        Args:
            registration: The domain registration request.

        Returns:
            The registered domain with all its actions.
        """
        # Get or create domain
        domain = await self._repo.get_domain_by_code(registration.code)

        if domain is None:
            domain = await self._repo.create_domain(
                code=registration.code,
                name=registration.name,
                description=registration.description,
            )
            logger.info("Registered new permission domain: '%s'", registration.code)
        else:
            # Update metadata if changed
            domain.name = registration.name
            if registration.description is not None:
                domain.description = registration.description
            domain.is_active = True
            logger.info("Updated existing permission domain: '%s'", registration.code)

        # Register actions (additive — never removes existing actions)
        for action_def in registration.actions:
            existing_action = await self._repo.get_action_by_domain_and_code(
                domain.id, action_def.code,
            )
            if existing_action is None:
                await self._repo.create_action(
                    domain_id=domain.id,
                    code=action_def.code,
                    name=action_def.name,
                    description=action_def.description,
                )
                logger.info(
                    "Registered action '%s.%s'", registration.code, action_def.code,
                )
            else:
                # Update metadata
                existing_action.name = action_def.name
                if action_def.description is not None:
                    existing_action.description = action_def.description
                existing_action.is_active = True

        # Refresh to load all actions
        domain = await self._repo.get_domain_by_code(registration.code)
        assert domain is not None  # We just created/updated it
        return DomainResponse.model_validate(domain)

    async def list_domains(self, active_only: bool = True) -> list[DomainResponse]:
        """List all registered permission domains with their actions.

        Args:
            active_only: If True, only return active domains.

        Returns:
            List of domains with their actions.
        """
        domains = await self._repo.list_domains(active_only=active_only)
        return [DomainResponse.model_validate(d) for d in domains]

    async def deactivate_domain(self, code: str) -> bool:
        """Deactivate a permission domain (soft-disable).

        Does not delete — existing role grants remain but policy evaluation
        will treat the domain as inactive (deny all checks).

        Args:
            code: The domain code to deactivate.

        Returns:
            True if the domain was found and deactivated.
        """
        domain = await self._repo.get_domain_by_code(code)
        if domain is None:
            return False
        domain.is_active = False
        logger.info("Deactivated permission domain: '%s'", code)
        return True
