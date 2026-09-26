"""
ConnectHub — Permission Engine Data Access Layer.

Repository for all permission-related database operations.
Provides optimized queries for policy evaluation and management.
"""

from __future__ import annotations

import uuid

from sqlalchemy import and_, delete, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from connecthub.core.permissions.models import (
    DirectPermission,
    PermissionAction,
    PermissionDomain,
    Role,
    RolePermission,
    UserRole,
)


class PermissionRepository:
    """Data access for all permission tables."""

    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    # ── Permission Domains ───────────────────

    async def get_domain_by_code(self, code: str) -> PermissionDomain | None:
        """Get a permission domain by its code, with actions eagerly loaded."""
        stmt = (
            select(PermissionDomain)
            .options(selectinload(PermissionDomain.actions))
            .where(PermissionDomain.code == code)
            .execution_options(populate_existing=True)
        )
        result = await self._session.execute(stmt)
        return result.scalar_one_or_none()

    async def create_domain(
        self,
        code: str,
        name: str,
        description: str | None = None,
    ) -> PermissionDomain:
        """Create a new permission domain."""
        domain = PermissionDomain(code=code, name=name, description=description)
        self._session.add(domain)
        await self._session.flush()
        return domain

    async def list_domains(self, active_only: bool = True) -> list[PermissionDomain]:
        """List all permission domains."""
        stmt = select(PermissionDomain).options(
            selectinload(PermissionDomain.actions)
        )
        if active_only:
            stmt = stmt.where(PermissionDomain.is_active.is_(True))
        stmt = stmt.order_by(PermissionDomain.name)
        result = await self._session.execute(stmt)
        return list(result.scalars().all())

    # ── Permission Actions ───────────────────

    async def get_action_by_domain_and_code(
        self, domain_id: uuid.UUID, code: str,
    ) -> PermissionAction | None:
        """Get an action by domain ID and action code."""
        stmt = select(PermissionAction).where(
            and_(PermissionAction.domain_id == domain_id, PermissionAction.code == code),
        )
        result = await self._session.execute(stmt)
        return result.scalar_one_or_none()

    async def get_action_by_id(self, action_id: uuid.UUID) -> PermissionAction | None:
        """Get a permission action by ID."""
        stmt = select(PermissionAction).where(PermissionAction.id == action_id)
        result = await self._session.execute(stmt)
        return result.scalar_one_or_none()

    async def create_action(
        self,
        domain_id: uuid.UUID,
        code: str,
        name: str,
        description: str | None = None,
    ) -> PermissionAction:
        """Create a new permission action."""
        action = PermissionAction(
            domain_id=domain_id, code=code, name=name, description=description,
        )
        self._session.add(action)
        await self._session.flush()
        return action

    async def resolve_action(
        self, domain_code: str, action_code: str,
    ) -> PermissionAction | None:
        """Resolve a permission action by domain code and action code.

        Returns the action if both domain and action exist and are active.
        Used by PolicyService for permission evaluation.
        """
        stmt = (
            select(PermissionAction)
            .join(PermissionDomain)
            .where(
                and_(
                    PermissionDomain.code == domain_code,
                    PermissionDomain.is_active.is_(True),
                    PermissionAction.code == action_code,
                    PermissionAction.is_active.is_(True),
                ),
            )
        )
        result = await self._session.execute(stmt)
        return result.scalar_one_or_none()

    # ── Roles ────────────────────────────────

    async def get_role_by_id(self, role_id: uuid.UUID) -> Role | None:
        """Get a role by ID."""
        stmt = select(Role).where(Role.id == role_id)
        result = await self._session.execute(stmt)
        return result.scalar_one_or_none()

    async def get_role_by_code(self, code: str) -> Role | None:
        """Get a role by code."""
        stmt = select(Role).where(Role.code == code)
        result = await self._session.execute(stmt)
        return result.scalar_one_or_none()

    async def create_role(
        self,
        code: str,
        name: str,
        description: str | None = None,
        organization_id: uuid.UUID | None = None,
        is_system: bool = False,
    ) -> Role:
        """Create a new role."""
        role = Role(
            code=code,
            name=name,
            description=description,
            organization_id=organization_id,
            is_system=is_system,
        )
        self._session.add(role)
        await self._session.flush()
        return role

    async def list_roles(self, active_only: bool = True) -> list[Role]:
        """List all roles."""
        stmt = select(Role)
        if active_only:
            stmt = stmt.where(Role.is_active.is_(True))
        stmt = stmt.order_by(Role.name)
        result = await self._session.execute(stmt)
        return list(result.scalars().all())

    # ── Role Permissions ─────────────────────

    async def grant_role_permission(
        self,
        role_id: uuid.UUID,
        action_id: uuid.UUID,
        granted_by: uuid.UUID | None = None,
    ) -> RolePermission:
        """Grant a permission action to a role."""
        rp = RolePermission(
            role_id=role_id, action_id=action_id, granted_by=granted_by,
        )
        self._session.add(rp)
        await self._session.flush()
        return rp

    async def revoke_role_permission(
        self, role_id: uuid.UUID, action_id: uuid.UUID,
    ) -> bool:
        """Revoke a permission action from a role. Returns True if deleted."""
        stmt = delete(RolePermission).where(
            and_(RolePermission.role_id == role_id, RolePermission.action_id == action_id),
        )
        result = await self._session.execute(stmt)
        return result.rowcount > 0  # type: ignore[union-attr]

    async def get_role_permission(
        self, role_id: uuid.UUID, action_id: uuid.UUID,
    ) -> RolePermission | None:
        """Check if a role has a specific permission."""
        stmt = select(RolePermission).where(
            and_(RolePermission.role_id == role_id, RolePermission.action_id == action_id),
        )
        result = await self._session.execute(stmt)
        return result.scalar_one_or_none()

    # ── User Roles ───────────────────────────

    async def assign_role_to_user(
        self,
        user_id: uuid.UUID,
        role_id: uuid.UUID,
        granted_by: uuid.UUID | None = None,
    ) -> UserRole:
        """Assign a role to a user."""
        ur = UserRole(user_id=user_id, role_id=role_id, granted_by=granted_by)
        self._session.add(ur)
        await self._session.flush()
        return ur

    async def remove_role_from_user(
        self, user_id: uuid.UUID, role_id: uuid.UUID,
    ) -> bool:
        """Remove a role from a user. Returns True if deleted."""
        stmt = delete(UserRole).where(
            and_(UserRole.user_id == user_id, UserRole.role_id == role_id),
        )
        result = await self._session.execute(stmt)
        return result.rowcount > 0  # type: ignore[union-attr]

    async def get_user_roles(self, user_id: uuid.UUID) -> list[UserRole]:
        """Get all roles assigned to a user."""
        stmt = (
            select(UserRole)
            .options(selectinload(UserRole.role))
            .where(UserRole.user_id == user_id)
        )
        result = await self._session.execute(stmt)
        return list(result.scalars().all())

    async def user_has_system_role(self, user_id: uuid.UUID, role_code: str) -> bool:
        """Check if a user has a specific system role (e.g., super_admin)."""
        stmt = (
            select(UserRole)
            .join(Role)
            .where(
                and_(
                    UserRole.user_id == user_id,
                    Role.code == role_code,
                    Role.is_system.is_(True),
                    Role.is_active.is_(True),
                ),
            )
        )
        result = await self._session.execute(stmt)
        return result.scalar_one_or_none() is not None

    # ── Direct Permissions ───────────────────

    async def grant_direct_permission(
        self,
        user_id: uuid.UUID,
        action_id: uuid.UUID,
        is_grant: bool,
        granted_by: uuid.UUID | None = None,
    ) -> DirectPermission:
        """Grant or deny a permission directly to a user."""
        dp = DirectPermission(
            user_id=user_id,
            action_id=action_id,
            is_grant=is_grant,
            granted_by=granted_by,
        )
        self._session.add(dp)
        await self._session.flush()
        return dp

    async def revoke_direct_permission(
        self, user_id: uuid.UUID, action_id: uuid.UUID,
    ) -> bool:
        """Revoke a direct permission from a user. Returns True if deleted."""
        stmt = delete(DirectPermission).where(
            and_(
                DirectPermission.user_id == user_id,
                DirectPermission.action_id == action_id,
            ),
        )
        result = await self._session.execute(stmt)
        return result.rowcount > 0  # type: ignore[union-attr]

    async def get_direct_permission(
        self, user_id: uuid.UUID, action_id: uuid.UUID,
    ) -> DirectPermission | None:
        """Get a specific direct permission for a user."""
        stmt = select(DirectPermission).where(
            and_(
                DirectPermission.user_id == user_id,
                DirectPermission.action_id == action_id,
            ),
        )
        result = await self._session.execute(stmt)
        return result.scalar_one_or_none()

    # ── Policy Evaluation Queries ────────────

    async def check_role_permission(
        self, user_id: uuid.UUID, action_id: uuid.UUID,
    ) -> bool:
        """Check if any of the user's roles grant the specified action.

        Optimized single query with JOINs for performance.
        """
        stmt = (
            select(RolePermission.id)
            .join(Role, RolePermission.role_id == Role.id)
            .join(UserRole, UserRole.role_id == Role.id)
            .where(
                and_(
                    UserRole.user_id == user_id,
                    RolePermission.action_id == action_id,
                    Role.is_active.is_(True),
                ),
            )
            .limit(1)
        )
        result = await self._session.execute(stmt)
        return result.scalar_one_or_none() is not None
