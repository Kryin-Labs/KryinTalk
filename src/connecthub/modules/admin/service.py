"""
ConnectHub Admin Module — Business Logic.

Admin operations for user management, audit log querying, system dashboard statistics,
and privileged actions. All actions are audited.
"""

from __future__ import annotations

import logging
import uuid
from datetime import datetime

from sqlalchemy import select, func as sqlfunc
from sqlalchemy.ext.asyncio import AsyncSession

from connecthub.core.audit.models import AuditLog
from connecthub.core.audit.schemas import AuditLogResponse
from connecthub.core.audit.service import AuditService
from connecthub.core.exceptions import ConflictError, ForbiddenError, NotFoundError, ValidationError
from connecthub.core.permissions.constants import (
    ACTION_MANAGE,
    ACTION_READ,
    ADMIN_ROLE,
    DOMAIN_AUDIT,
    DOMAIN_SYSTEM,
    MEMBER_ROLE,
    SUPER_ADMIN_ROLE,
)
from connecthub.core.permissions.policy import PolicyService
from connecthub.core.permissions.repository import PermissionRepository
from connecthub.core.security.hashing import hash_password
from connecthub.modules.admin.schemas import (
    AdminPasswordResetRequest,
    AuditLogListResponse,
    SystemStatsResponse,
    UserAdminResponse,
    UserCreateAdminRequest,
    UserListResponse,
    UserUpdateRequest,
)
from connecthub.modules.auth.models import Organization, User
from connecthub.modules.auth.repository import AuthRepository
from connecthub.modules.files.models import FileAttachment
from connecthub.modules.messaging.models import Conversation, Message

logger = logging.getLogger(__name__)


class AdminService:
    """Admin service — manages users, audit logs, system stats."""

    def __init__(self, session: AsyncSession) -> None:
        self._session = session
        self._auth_repo = AuthRepository(session)
        self._perm_repo = PermissionRepository(session)
        self._policy = PolicyService(session)
        self._audit = AuditService(session)

    async def _require_admin(self, user_id: uuid.UUID, domain: str = "user_management", action: str = ACTION_MANAGE) -> None:
        """Verify user is Super Admin or has required domain permission."""
        result = await self._policy.check_permission(user_id, domain, action)
        if not result.allowed:
            raise ForbiddenError("Admin permission required.")

    async def _resolve_user_role(self, user_id: uuid.UUID) -> tuple[str, bool]:
        """Determine primary role code and super admin status for a user."""
        is_sa = await self._policy.is_super_admin(user_id)
        if is_sa:
            return "super_admin", True
        roles = await self._perm_repo.get_user_roles(user_id)
        for ur in roles:
            if ur.role:
                code = ur.role.code.lower()
                if code in ("super_admin", "admin", "manager"):
                    return code, False
        return "member", False

    # ── User Management ──────────────────────────

    async def list_users(
        self,
        admin_user_id: uuid.UUID,
        limit: int = 50,
        offset: int = 0,
        is_active: bool | None = None,
    ) -> UserListResponse:
        """List organization users for admin console."""
        await self._require_admin(admin_user_id, "user_management", ACTION_READ)

        stmt = select(User).where(User.deleted_at.is_(None))
        if is_active is not None:
            stmt = stmt.where(User.is_active == is_active)

        count_stmt = select(sqlfunc.count(User.id)).where(User.deleted_at.is_(None))
        if is_active is not None:
            count_stmt = count_stmt.where(User.is_active == is_active)

        total_res = await self._session.execute(count_stmt)
        total = total_res.scalar_one()

        stmt = stmt.order_by(User.created_at.desc()).limit(limit).offset(offset)
        result = await self._session.execute(stmt)
        users = list(result.scalars().all())

        items: list[UserAdminResponse] = []
        for u in users:
            role_code, is_sa = await self._resolve_user_role(u.id)
            res = UserAdminResponse.model_validate(u)
            res.role = role_code
            res.is_super_admin = is_sa
            items.append(res)

        return UserListResponse(items=items, total=total)

    async def get_user_detail(
        self, admin_user_id: uuid.UUID, target_user_id: uuid.UUID,
    ) -> UserAdminResponse:
        """Get full user details."""
        await self._require_admin(admin_user_id, "user_management", ACTION_READ)

        user = await self._auth_repo.get_user_by_id(target_user_id)
        if user is None:
            raise NotFoundError("User not found.")
        role_code, is_sa = await self._resolve_user_role(user.id)
        res = UserAdminResponse.model_validate(user)
        res.role = role_code
        res.is_super_admin = is_sa
        return res

    async def create_user(
        self, admin_user_id: uuid.UUID, data: UserCreateAdminRequest,
    ) -> UserAdminResponse:
        """Create a new user in the organization."""
        await self._require_admin(admin_user_id, "user_management", ACTION_MANAGE)

        acting_user = await self._auth_repo.get_user_by_id(admin_user_id)
        if acting_user is None:
            raise NotFoundError("Acting user not found.")

        # Duplicate check
        if await self._auth_repo.get_user_by_email(data.email):
            raise ConflictError("Email already registered.")
        if await self._auth_repo.get_user_by_username(data.username):
            raise ConflictError("Username already taken.")

        # Create user
        user = await self._auth_repo.create_user(
            organization_id=acting_user.organization_id,
            email=data.email,
            username=data.username,
            display_name=data.display_name,
            password_hash=hash_password(data.password),
        )
        user.is_active = data.is_active
        await self._session.flush()

        # Assign Role
        target_role = (data.role or "member").lower()
        if data.is_super_admin:
            target_role = "super_admin"

        role_obj = await self._perm_repo.get_role_by_code(target_role)
        if role_obj is None:
            role_obj = await self._perm_repo.create_role(
                code=target_role,
                name=target_role.replace("_", " ").title(),
                is_system=target_role in ("super_admin", "admin", "member"),
            )
        await self._perm_repo.assign_role_to_user(
            user_id=user.id,
            role_id=role_obj.id,
            granted_by=admin_user_id,
        )

        await self._audit.log(
            user_id=admin_user_id,
            action="admin.user.created",
            resource_type="user",
            resource_id=str(user.id),
            details={"email": data.email, "role": target_role},
        )

        role_code, is_sa = await self._resolve_user_role(user.id)
        res = UserAdminResponse.model_validate(user)
        res.role = role_code
        res.is_super_admin = is_sa
        return res

    async def reset_user_password(
        self, admin_user_id: uuid.UUID, target_user_id: uuid.UUID, new_password: str,
    ) -> None:
        """Reset a user's password directly."""
        await self._require_admin(admin_user_id, "user_management", ACTION_MANAGE)

        user = await self._auth_repo.get_user_by_id(target_user_id)
        if user is None:
            raise NotFoundError("User not found.")

        user.password_hash = hash_password(new_password)
        await self._session.flush()

        await self._audit.log(
            user_id=admin_user_id,
            action="admin.user.password_reset",
            resource_type="user",
            resource_id=str(target_user_id),
            details={"message": "Password reset by administrator"},
        )

    async def update_user(
        self,
        admin_user_id: uuid.UUID,
        target_user_id: uuid.UUID,
        data: UserUpdateRequest,
    ) -> UserAdminResponse:
        """Update user status, role, or display name."""
        await self._require_admin(admin_user_id, "user_management", ACTION_MANAGE)

        user = await self._auth_repo.get_user_by_id(target_user_id)
        if user is None:
            raise NotFoundError("User not found.")

        changes = {}
        if data.display_name is not None and data.display_name != user.display_name:
            changes["display_name"] = {"old": user.display_name, "new": data.display_name}
            user.display_name = data.display_name

        if data.is_active is not None and data.is_active != user.is_active:
            changes["is_active"] = {"old": user.is_active, "new": data.is_active}
            user.is_active = data.is_active

        # Role change
        if data.role is not None:
            target_role = data.role.lower()
            if data.is_super_admin:
                target_role = "super_admin"

            role_obj = await self._perm_repo.get_role_by_code(target_role)
            if role_obj is None:
                role_obj = await self._perm_repo.create_role(
                    code=target_role,
                    name=target_role.replace("_", " ").title(),
                    is_system=target_role in ("super_admin", "admin", "member"),
                )

            # Remove existing roles and assign new role
            current_roles = await self._perm_repo.get_user_roles(target_user_id)
            for ur in current_roles:
                await self._perm_repo.remove_role_from_user(target_user_id, ur.role_id)

            await self._perm_repo.assign_role_to_user(
                user_id=target_user_id,
                role_id=role_obj.id,
                granted_by=admin_user_id,
            )
            changes["role"] = {"new": target_role}

        if changes:
            await self._audit.log(
                user_id=admin_user_id,
                action="admin.user.updated",
                resource_type="user",
                resource_id=str(target_user_id),
                changes=changes,
            )

        await self._session.flush()
        user = await self._auth_repo.get_user_by_id(target_user_id)
        role_code, is_sa = await self._resolve_user_role(target_user_id)
        res = UserAdminResponse.model_validate(user)
        res.role = role_code
        res.is_super_admin = is_sa
        return res

    async def deactivate_user(
        self, admin_user_id: uuid.UUID, target_user_id: uuid.UUID,
    ) -> UserAdminResponse:
        """Deactivate a user account."""
        return await self.update_user(
            admin_user_id, target_user_id, UserUpdateRequest(is_active=False),
        )

    # ── Audit Log Viewer ─────────────────────────

    async def list_audit_logs(
        self,
        admin_user_id: uuid.UUID,
        user_id_filter: uuid.UUID | None = None,
        action_filter: str | None = None,
        resource_type_filter: str | None = None,
        resource_id_filter: str | None = None,
        from_date: datetime | None = None,
        to_date: datetime | None = None,
        limit: int = 50,
        offset: int = 0,
    ) -> AuditLogListResponse:
        """List audit logs with filtering and pagination."""
        await self._require_admin(admin_user_id, DOMAIN_AUDIT, ACTION_READ)

        entries = await self._audit.query(
            user_id=user_id_filter,
            action=action_filter,
            resource_type=resource_type_filter,
            resource_id=resource_id_filter,
            from_date=from_date,
            to_date=to_date,
            limit=limit,
            offset=offset,
        )
        total = await self._audit.count(
            user_id=user_id_filter,
            action=action_filter,
            resource_type=resource_type_filter,
        )

        return AuditLogListResponse(
            items=entries,
            total=total,
        )

    # ── System Statistics Dashboard ──────────────

    async def get_system_stats(self, admin_user_id: uuid.UUID) -> SystemStatsResponse:
        """Get high-level dashboard statistics."""
        await self._require_admin(admin_user_id, DOMAIN_SYSTEM, ACTION_READ)

        user_count_res = await self._session.execute(
            select(sqlfunc.count(User.id)).where(User.deleted_at.is_(None))
        )
        total_users = user_count_res.scalar_one()

        active_user_res = await self._session.execute(
            select(sqlfunc.count(User.id)).where(
                User.deleted_at.is_(None), User.is_active.is_(True)
            )
        )
        active_users = active_user_res.scalar_one()

        org_count_res = await self._session.execute(
            select(sqlfunc.count(Organization.id)).where(Organization.deleted_at.is_(None))
        )
        total_orgs = org_count_res.scalar_one()

        conv_count_res = await self._session.execute(
            select(sqlfunc.count(Conversation.id))
        )
        total_convs = conv_count_res.scalar_one()

        msg_count_res = await self._session.execute(
            select(sqlfunc.count(Message.id)).where(Message.deleted_at.is_(None))
        )
        total_messages = msg_count_res.scalar_one()

        file_count_res = await self._session.execute(
            select(sqlfunc.count(FileAttachment.id)).where(FileAttachment.deleted_at.is_(None))
        )
        total_files = file_count_res.scalar_one()

        file_bytes_res = await self._session.execute(
            select(sqlfunc.coalesce(sqlfunc.sum(FileAttachment.size_bytes), 0)).where(
                FileAttachment.deleted_at.is_(None)
            )
        )
        total_file_bytes = file_bytes_res.scalar_one()

        audit_count_res = await self._session.execute(
            select(sqlfunc.count(AuditLog.id))
        )
        total_audit_logs = audit_count_res.scalar_one()

        return SystemStatsResponse(
            total_users=total_users,
            active_users=active_users,
            total_organizations=total_orgs,
            total_conversations=total_convs,
            total_messages=total_messages,
            total_files=total_files,
            total_file_bytes=total_file_bytes,
            total_audit_logs=total_audit_logs,
        )
