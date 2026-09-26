"""
ConnectHub — Permission Management Service.

Management operations for the permission system (used by Super Admin Console).
All operations emit audit events and are fully logged.
"""

from __future__ import annotations

import logging
import uuid

from sqlalchemy.ext.asyncio import AsyncSession

from connecthub.core.exceptions import ConflictError, NotFoundError
from connecthub.core.permissions.repository import PermissionRepository
from connecthub.core.permissions.schemas import RoleCreate, RoleResponse

logger = logging.getLogger(__name__)


class PermissionService:
    """Management service for roles, role permissions, user roles, and direct permissions.

    All write operations require an `acting_user_id` for audit trail.
    """

    def __init__(
        self,
        session: AsyncSession,
        audit_logger: AuditLogger | None = None,
    ) -> None:
        self._repo = PermissionRepository(session)
        self._audit = audit_logger

    # ── Role Management ──────────────────────

    async def create_role(
        self,
        data: RoleCreate,
        acting_user_id: uuid.UUID,
    ) -> RoleResponse:
        """Create a new role.

        Args:
            data: Role creation data.
            acting_user_id: The user performing the operation (for audit).

        Returns:
            The created role.

        Raises:
            ConflictError: If a role with the same code already exists.
        """
        existing = await self._repo.get_role_by_code(data.code)
        if existing is not None:
            raise ConflictError(f"Role with code '{data.code}' already exists.")

        role = await self._repo.create_role(
            code=data.code,
            name=data.name,
            description=data.description,
            organization_id=data.organization_id,
        )
        logger.info("Role '%s' created by user %s", data.code, acting_user_id)

        if self._audit:
            await self._audit.log(
                user_id=acting_user_id,
                action="role.created",
                resource_type="role",
                resource_id=str(role.id),
                details={"code": data.code, "name": data.name},
            )

        return RoleResponse.model_validate(role)

    async def list_roles(self, active_only: bool = True) -> list[RoleResponse]:
        """List all roles."""
        roles = await self._repo.list_roles(active_only=active_only)
        return [RoleResponse.model_validate(r) for r in roles]

    # ── Role Permission Management ───────────

    async def grant_role_permission(
        self,
        role_id: uuid.UUID,
        action_id: uuid.UUID,
        acting_user_id: uuid.UUID,
    ) -> None:
        """Grant a permission action to a role.

        Args:
            role_id: The role to grant the permission to.
            action_id: The permission action to grant.
            acting_user_id: The user performing the operation.

        Raises:
            NotFoundError: If the role or action does not exist.
            ConflictError: If the permission is already granted.
        """
        role = await self._repo.get_role_by_id(role_id)
        if role is None:
            raise NotFoundError("Resource not found.")
        if role.is_system:
            raise ConflictError("Cannot modify permissions of system roles.")

        action = await self._repo.get_action_by_id(action_id)
        if action is None:
            raise NotFoundError("Resource not found.")

        existing = await self._repo.get_role_permission(role_id, action_id)
        if existing is not None:
            raise ConflictError("Permission already granted to this role.")

        await self._repo.grant_role_permission(
            role_id=role_id, action_id=action_id, granted_by=acting_user_id,
        )
        logger.info(
            "Permission '%s' granted to role '%s' by user %s",
            action_id, role.code, acting_user_id,
        )

        if self._audit:
            await self._audit.log(
                user_id=acting_user_id,
                action="role_permission.granted",
                resource_type="role_permission",
                resource_id=f"{role_id}:{action_id}",
                details={"role_code": role.code, "action_id": str(action_id)},
            )

    async def revoke_role_permission(
        self,
        role_id: uuid.UUID,
        action_id: uuid.UUID,
        acting_user_id: uuid.UUID,
    ) -> None:
        """Revoke a permission action from a role."""
        role = await self._repo.get_role_by_id(role_id)
        if role is None:
            raise NotFoundError("Resource not found.")
        if role.is_system:
            raise ConflictError("Cannot modify permissions of system roles.")

        deleted = await self._repo.revoke_role_permission(role_id, action_id)
        if not deleted:
            raise NotFoundError("Resource not found.")

        logger.info(
            "Permission '%s' revoked from role '%s' by user %s",
            action_id, role.code, acting_user_id,
        )

        if self._audit:
            await self._audit.log(
                user_id=acting_user_id,
                action="role_permission.revoked",
                resource_type="role_permission",
                resource_id=f"{role_id}:{action_id}",
                details={"role_code": role.code, "action_id": str(action_id)},
            )

    # ── User Role Management ────────────────

    async def assign_role_to_user(
        self,
        user_id: uuid.UUID,
        role_id: uuid.UUID,
        acting_user_id: uuid.UUID,
    ) -> None:
        """Assign a role to a user.

        Args:
            user_id: The user to assign the role to.
            role_id: The role to assign.
            acting_user_id: The user performing the operation.

        Raises:
            NotFoundError: If the role does not exist.
        """
        role = await self._repo.get_role_by_id(role_id)
        if role is None:
            raise NotFoundError("Resource not found.")

        # Check if already assigned
        existing_roles = await self._repo.get_user_roles(user_id)
        if any(ur.role_id == role_id for ur in existing_roles):
            raise ConflictError("Role already assigned to this user.")

        await self._repo.assign_role_to_user(
            user_id=user_id, role_id=role_id, granted_by=acting_user_id,
        )
        logger.info(
            "Role '%s' assigned to user %s by user %s",
            role.code, user_id, acting_user_id,
        )

        if self._audit:
            await self._audit.log(
                user_id=acting_user_id,
                action="user_role.assigned",
                resource_type="user_role",
                resource_id=f"{user_id}:{role_id}",
                details={"target_user_id": str(user_id), "role_code": role.code},
            )

    async def remove_role_from_user(
        self,
        user_id: uuid.UUID,
        role_id: uuid.UUID,
        acting_user_id: uuid.UUID,
    ) -> None:
        """Remove a role from a user."""
        deleted = await self._repo.remove_role_from_user(user_id, role_id)
        if not deleted:
            raise NotFoundError("Resource not found.")

        logger.info(
            "Role '%s' removed from user %s by user %s",
            role_id, user_id, acting_user_id,
        )

        if self._audit:
            await self._audit.log(
                user_id=acting_user_id,
                action="user_role.removed",
                resource_type="user_role",
                resource_id=f"{user_id}:{role_id}",
                details={"target_user_id": str(user_id), "role_id": str(role_id)},
            )

    # ── Direct Permission Management ─────────

    async def grant_direct_permission(
        self,
        user_id: uuid.UUID,
        action_id: uuid.UUID,
        is_grant: bool,
        acting_user_id: uuid.UUID,
    ) -> None:
        """Grant or deny a permission directly to a user.

        Args:
            user_id: The target user.
            action_id: The permission action.
            is_grant: True = explicit grant, False = explicit deny.
            acting_user_id: The user performing the operation.
        """
        action = await self._repo.get_action_by_id(action_id)
        if action is None:
            raise NotFoundError("Resource not found.")

        # Remove existing direct permission if any, then create new one
        await self._repo.revoke_direct_permission(user_id, action_id)
        await self._repo.grant_direct_permission(
            user_id=user_id,
            action_id=action_id,
            is_grant=is_grant,
            granted_by=acting_user_id,
        )

        action_type = "grant" if is_grant else "deny"
        logger.info(
            "Direct %s of permission '%s' to user %s by user %s",
            action_type, action_id, user_id, acting_user_id,
        )

        if self._audit:
            await self._audit.log(
                user_id=acting_user_id,
                action=f"direct_permission.{action_type}",
                resource_type="direct_permission",
                resource_id=f"{user_id}:{action_id}",
                details={
                    "target_user_id": str(user_id),
                    "action_id": str(action_id),
                    "is_grant": is_grant,
                },
            )

    async def revoke_direct_permission(
        self,
        user_id: uuid.UUID,
        action_id: uuid.UUID,
        acting_user_id: uuid.UUID,
    ) -> None:
        """Revoke a direct permission from a user."""
        deleted = await self._repo.revoke_direct_permission(user_id, action_id)
        if not deleted:
            raise NotFoundError("Resource not found.")

        logger.info(
            "Direct permission '%s' revoked from user %s by user %s",
            action_id, user_id, acting_user_id,
        )

        if self._audit:
            await self._audit.log(
                user_id=acting_user_id,
                action="direct_permission.revoked",
                resource_type="direct_permission",
                resource_id=f"{user_id}:{action_id}",
                details={
                    "target_user_id": str(user_id),
                    "action_id": str(action_id),
                },
            )


class AuditLogger:
    """Protocol for audit logging — injected into PermissionService.

    Decouples the permission service from the audit implementation.
    """

    async def log(
        self,
        user_id: uuid.UUID,
        action: str,
        resource_type: str,
        resource_id: str,
        details: dict | None = None,
        ip_address: str | None = None,
        user_agent: str | None = None,
    ) -> None:
        """Log an auditable action."""
        ...
