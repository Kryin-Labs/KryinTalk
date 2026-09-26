"""
ConnectHub Org Settings Module — Business Logic.

Permission-gated organization settings management.
"""

from __future__ import annotations

import logging
import uuid

from sqlalchemy.ext.asyncio import AsyncSession

from connecthub.core.audit.service import AuditService
from connecthub.core.exceptions import NotFoundError
from connecthub.core.permissions.policy import PolicyService
from connecthub.modules.auth.repository import AuthRepository
from connecthub.modules.org_settings.schemas import OrgSettingsResponse, OrgSettingsUpdate

logger = logging.getLogger(__name__)

DOMAIN = "organization_settings"
ACTION_READ = "read"
ACTION_UPDATE = "update"


class OrgSettingsService:
    """Organization settings service — permission-gated."""

    def __init__(self, session: AsyncSession) -> None:
        self._auth_repo = AuthRepository(session)
        self._policy = PolicyService(session)
        self._audit = AuditService(session)

    async def get_organization(
        self, user_id: uuid.UUID,
    ) -> OrgSettingsResponse:
        """Get the current user's organization settings.

        Requires `organization_settings.read` permission.
        """
        await self._policy.require_permission(user_id, DOMAIN, ACTION_READ)

        user = await self._auth_repo.get_user_by_id(user_id)
        if user is None:
            raise NotFoundError("Resource not found.")

        org = await self._auth_repo.get_organization_by_id(user.organization_id)
        if org is None:
            raise NotFoundError("Resource not found.")

        return OrgSettingsResponse.model_validate(org)

    async def update_organization(
        self,
        user_id: uuid.UUID,
        data: OrgSettingsUpdate,
    ) -> OrgSettingsResponse:
        """Update organization settings.

        Requires `organization_settings.update` permission.
        """
        await self._policy.require_permission(user_id, DOMAIN, ACTION_UPDATE)

        user = await self._auth_repo.get_user_by_id(user_id)
        if user is None:
            raise NotFoundError("Resource not found.")

        org = await self._auth_repo.get_organization_by_id(user.organization_id)
        if org is None:
            raise NotFoundError("Resource not found.")

        changes_before = {}
        changes_after = {}

        if data.name is not None:
            changes_before["name"] = org.name
            org.name = data.name
            changes_after["name"] = data.name

        if data.settings is not None:
            changes_before["settings"] = org.settings
            org.settings = data.settings
            changes_after["settings"] = data.settings

        await self._audit.log(
            user_id=user_id,
            action="organization.updated",
            resource_type="organization",
            resource_id=str(org.id),
            changes={"before": changes_before, "after": changes_after},
        )

        logger.info("Organization %s updated by user %s", org.id, user_id)
        return OrgSettingsResponse.model_validate(org)
