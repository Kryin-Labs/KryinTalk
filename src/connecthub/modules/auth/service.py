"""
ConnectHub Auth Module — Business Logic.

AuthService: Authentication flows (login, token refresh).
AdminService: Admin management (create, suspend, grant permissions).

All operations use PolicyService for authorization and AuditService for logging.
"""

from __future__ import annotations

import logging
import uuid

from sqlalchemy import and_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from connecthub.core.audit.service import AuditService
from connecthub.core.exceptions import ConflictError, NotFoundError, UnauthorizedError
from connecthub.core.permissions.constants import ADMIN_ROLE, SUPER_ADMIN_ROLE
from connecthub.core.permissions.policy import PolicyService
from connecthub.core.permissions.repository import PermissionRepository
from connecthub.core.permissions.schemas import RoleCreate
from connecthub.core.permissions.service import PermissionService
from connecthub.core.security.hashing import hash_password, verify_password
from connecthub.core.security.jwt import (
    InvalidTokenError,
    TokenPair,
    create_token_pair,
    decode_token,
)
from connecthub.modules.auth.models import Organization, User
from connecthub.modules.auth.repository import AuthRepository
from connecthub.modules.auth.schemas import (
    RegisterRequest,
    UserProfileUpdateRequest,
    UserResponse,
)

logger = logging.getLogger(__name__)


class AuthService:
    """Authentication service — login and token refresh."""

    def __init__(self, session: AsyncSession) -> None:
        self._session = session
        self._repo = AuthRepository(session)
        self._audit = AuditService(session)

    async def login(
        self,
        email: str,
        password: str,
        ip_address: str | None = None,
        user_agent: str | None = None,
    ) -> TokenPair:
        """Authenticate a user and return a token pair.

        Args:
            email: User's email address.
            password: User's plaintext password.
            ip_address: Client IP address (for audit).
            user_agent: Client user agent (for audit).

        Returns:
            TokenPair with access and refresh tokens.

        Raises:
            UnauthorizedError: If credentials are invalid or user is suspended.
        """
        user = await self._repo.get_user_by_email(email)
        if user is None:
            raise UnauthorizedError("Invalid credentials.")

        if not verify_password(password, user.password_hash):
            await self._audit.log(
                user_id=user.id,
                action="auth.login_failed",
                resource_type="user",
                resource_id=str(user.id),
                details={"reason": "invalid_password"},
                ip_address=ip_address,
                user_agent=user_agent,
            )
            raise UnauthorizedError("Invalid credentials.")

        if user.is_suspended:
            await self._audit.log(
                user_id=user.id,
                action="auth.login_suspended",
                resource_type="user",
                resource_id=str(user.id),
                ip_address=ip_address,
                user_agent=user_agent,
            )
            raise UnauthorizedError("Account suspended.")

        if not user.is_active:
            raise UnauthorizedError("Account deactivated.")

        # Update last login
        await self._repo.update_last_login(user.id)

        # Audit successful login
        await self._audit.log(
            user_id=user.id,
            action="auth.login_success",
            resource_type="user",
            resource_id=str(user.id),
            ip_address=ip_address,
            user_agent=user_agent,
        )

        logger.info("User '%s' logged in successfully", user.email)
        return create_token_pair(user.id, user.organization_id)

    async def register(self, data: RegisterRequest) -> TokenPair:
        """Create an active member account and return a ready-to-use session."""
        email = str(data.email).strip().lower()
        username = data.username.strip().lstrip("@").lower()
        display_name = data.display_name.strip()
        if await self._repo.get_user_by_email(email) is not None:
            raise ConflictError("Email already registered.")
        if await self._repo.get_user_by_username(username) is not None:
            raise ConflictError("Username already registered.")

        organization = None
        if data.organization_slug:
            organization = await self._repo.get_organization_by_slug(
                data.organization_slug.strip().lower()
            )
            if organization is None:
                raise NotFoundError("Organization not found.")
        if organization is None:
            result = await self._session.execute(
                select(Organization)
                .where(
                    and_(
                        Organization.is_active.is_(True),
                        Organization.deleted_at.is_(None),
                    )
                )
                .order_by(Organization.created_at)
                .limit(1)
            )
            organization = result.scalar_one_or_none()
        if organization is None:
            raise NotFoundError("No active organization is available.")

        try:
            user = await self._repo.create_user(
                organization_id=organization.id,
                email=email,
                username=username,
                display_name=display_name,
                password_hash=hash_password(data.password),
            )
        except IntegrityError as exc:
            # The preflight checks provide a friendly response in the normal
            # case; this also closes the race where two registrations arrive
            # at the same time and the database unique constraint wins.
            await self._session.rollback()
            raise ConflictError("Email or username already registered.") from exc
        await self._audit.log(
            user_id=user.id,
            action="auth.register",
            resource_type="user",
            resource_id=str(user.id),
            details={"organization_id": str(organization.id)},
        )
        return create_token_pair(user.id, organization.id)

    async def refresh_token(self, refresh_token_str: str) -> TokenPair:
        """Rotate an access token using a valid refresh token.

        Args:
            refresh_token_str: The refresh token to validate.

        Returns:
            A new TokenPair.

        Raises:
            UnauthorizedError: If the refresh token is invalid or user is suspended.
        """
        try:
            payload = decode_token(refresh_token_str)
        except InvalidTokenError:
            raise UnauthorizedError("Invalid refresh token.")

        if payload.type != "refresh":
            raise UnauthorizedError("Invalid token type.")

        user_id = uuid.UUID(payload.sub)
        user = await self._repo.get_user_by_id(user_id)
        if user is None or user.is_suspended or not user.is_active:
            raise UnauthorizedError("Account unavailable.")

        return create_token_pair(user.id, user.organization_id)

    async def get_current_user(self, user_id: uuid.UUID) -> UserResponse:
        """Get the current user's profile.

        Args:
            user_id: The authenticated user's ID.

        Returns:
            User profile response.

        Raises:
            NotFoundError: If user not found.
        """
        user = await self._repo.get_user_by_id(user_id)
        if user is None:
            raise NotFoundError("Resource not found.")
        is_sa = await PolicyService(self._session).is_super_admin(user_id)
        response = UserResponse.model_validate(user)
        response.is_super_admin = is_sa
        return response

    async def get_user_by_id(self, user_id: uuid.UUID) -> UserResponse:
        """Get a specific user's public profile by user ID."""
        user = await self._repo.get_user_by_id(user_id)
        if user is None:
            raise NotFoundError("Resource not found.")
        is_sa = await PolicyService(self._session).is_super_admin(user_id)
        response = UserResponse.model_validate(user)
        response.is_super_admin = is_sa
        return response

    async def get_directory(self, user_id: uuid.UUID) -> list[UserResponse]:
        """Get the user directory for the current user's organization.
        
        Users with hide_from_dm=True are excluded from general directory listings
        (Direct Messages and Contacts) unless viewed by Super Admin or the user themselves.
        """
        user = await self._repo.get_user_by_id(user_id)
        if user is None:
            raise NotFoundError("Resource not found.")
        users = await self._repo.list_org_users(user.organization_id)
        is_sa = await PolicyService(self._session).is_super_admin(user_id)

        result: list[UserResponse] = []
        for u in users:
            if getattr(u, "hide_from_dm", False) and u.id != user_id and not is_sa:
                continue
            resp = UserResponse.model_validate(u)
            resp.is_super_admin = await PolicyService(self._session).is_super_admin(u.id)
            result.append(resp)
        return result

    async def update_profile(
        self,
        user_id: uuid.UUID,
        data: UserProfileUpdateRequest,
    ) -> UserResponse:
        """Update current user profile and privacy settings."""
        user = await self._repo.get_user_by_id(user_id)
        if user is None:
            raise NotFoundError("Resource not found.")

        if data.display_name is not None and data.display_name.strip():
            user.display_name = data.display_name.strip()
        if data.hide_from_dm is not None:
            user.hide_from_dm = data.hide_from_dm

        await self._session.flush()
        is_sa = await PolicyService(self._session).is_super_admin(user_id)
        resp = UserResponse.model_validate(user)
        resp.is_super_admin = is_sa
        return resp

    async def change_password(
        self,
        user_id: uuid.UUID,
        current_password: str,
        new_password: str,
        ip_address: str | None = None,
        user_agent: str | None = None,
    ) -> None:
        """Change current user password after verifying current password."""
        user = await self._repo.get_user_by_id(user_id)
        if user is None:
            raise NotFoundError("User not found.")

        if not verify_password(current_password, user.password_hash):
            await self._audit.log(
                user_id=user.id,
                action="auth.password_change_failed",
                resource_type="user",
                resource_id=str(user.id),
                details={"reason": "invalid_current_password"},
                ip_address=ip_address,
                user_agent=user_agent,
            )
            raise UnauthorizedError("Current password is incorrect.")

        user.password_hash = hash_password(new_password)
        await self._session.flush()

        await self._audit.log(
            user_id=user.id,
            action="auth.password_changed",
            resource_type="user",
            resource_id=str(user.id),
            details={"message": "Password updated successfully"},
            ip_address=ip_address,
            user_agent=user_agent,
        )


class AdminService:
    """Admin management service — Super Admin only operations.

    All operations require the acting user to be a Super Admin.
    Permissions are granted through the Phase 2 permission engine.
    """

    def __init__(self, session: AsyncSession) -> None:
        self._session = session
        self._repo = AuthRepository(session)
        self._perm_repo = PermissionRepository(session)
        self._perm_service = PermissionService(session, audit_logger=AuditService(session))
        self._policy = PolicyService(session)
        self._audit = AuditService(session)

    async def _require_super_admin(self, acting_user_id: uuid.UUID) -> None:
        """Verify the acting user is a Super Admin.

        Raises NotFoundError (not 403) to prevent info leakage.
        """
        is_sa = await self._policy.is_super_admin(acting_user_id)
        if not is_sa:
            raise NotFoundError("Resource not found.")

    async def create_admin(
        self,
        acting_user_id: uuid.UUID,
        email: str,
        username: str,
        display_name: str,
        password: str,
        permission_action_ids: list[uuid.UUID] | None = None,
    ) -> UserResponse:
        """Create a new Admin user.

        Only Super Admin can create admins (Section 6.1).

        Args:
            acting_user_id: The Super Admin performing the operation.
            email: New admin's email.
            username: New admin's username.
            display_name: New admin's display name.
            password: New admin's password (will be hashed).
            permission_action_ids: Permission actions to grant directly.

        Returns:
            The created admin user.
        """
        await self._require_super_admin(acting_user_id)

        # Get the acting user's org
        acting_user = await self._repo.get_user_by_id(acting_user_id)
        if acting_user is None:
            raise NotFoundError("Resource not found.")

        # Check for duplicate email/username
        if await self._repo.get_user_by_email(email):
            raise ConflictError("Email already registered.")
        if await self._repo.get_user_by_username(username):
            raise ConflictError("Username already taken.")

        # Create the user
        user = await self._repo.create_user(
            organization_id=acting_user.organization_id,
            email=email,
            username=username,
            display_name=display_name,
            password_hash=hash_password(password),
        )

        # Assign the admin role (create if doesn't exist)
        admin_role = await self._perm_repo.get_role_by_code(ADMIN_ROLE)
        if admin_role is None:
            admin_role = await self._perm_repo.create_role(
                code=ADMIN_ROLE,
                name="Admin",
                description="Organization administrator with delegated permissions.",
            )
        await self._perm_repo.assign_role_to_user(
            user.id, admin_role.id, granted_by=acting_user_id,
        )

        # Grant direct permissions if specified (Section 6.2 — per-admin granularity)
        if permission_action_ids:
            for action_id in permission_action_ids:
                await self._perm_service.grant_direct_permission(
                    user_id=user.id,
                    action_id=action_id,
                    is_grant=True,
                    acting_user_id=acting_user_id,
                )

        # Audit
        await self._audit.log(
            user_id=acting_user_id,
            action="admin.created",
            resource_type="user",
            resource_id=str(user.id),
            details={
                "email": email,
                "username": username,
                "permission_count": len(permission_action_ids or []),
            },
        )

        logger.info(
            "Admin '%s' created by Super Admin %s", username, acting_user_id,
        )
        return UserResponse.model_validate(user)

    async def suspend_admin(
        self,
        acting_user_id: uuid.UUID,
        target_user_id: uuid.UUID,
        reason: str | None = None,
    ) -> UserResponse:
        """Suspend an Admin user (prevent login).

        Args:
            acting_user_id: The Super Admin performing the operation.
            target_user_id: The admin to suspend.
            reason: Optional reason for suspension.

        Returns:
            The suspended user.
        """
        await self._require_super_admin(acting_user_id)

        # Cannot suspend yourself
        if acting_user_id == target_user_id:
            raise ConflictError("Cannot suspend yourself.")

        user = await self._repo.suspend_user(target_user_id)
        if user is None:
            raise NotFoundError("Resource not found.")

        await self._audit.log(
            user_id=acting_user_id,
            action="admin.suspended",
            resource_type="user",
            resource_id=str(target_user_id),
            details={"reason": reason},
        )

        logger.info(
            "Admin %s suspended by Super Admin %s", target_user_id, acting_user_id,
        )
        return UserResponse.model_validate(user)

    async def reactivate_admin(
        self,
        acting_user_id: uuid.UUID,
        target_user_id: uuid.UUID,
    ) -> UserResponse:
        """Reactivate a suspended Admin user.

        Args:
            acting_user_id: The Super Admin performing the operation.
            target_user_id: The admin to reactivate.

        Returns:
            The reactivated user.
        """
        await self._require_super_admin(acting_user_id)

        user = await self._repo.reactivate_user(target_user_id)
        if user is None:
            raise NotFoundError("Resource not found.")

        await self._audit.log(
            user_id=acting_user_id,
            action="admin.reactivated",
            resource_type="user",
            resource_id=str(target_user_id),
        )

        logger.info(
            "Admin %s reactivated by Super Admin %s", target_user_id, acting_user_id,
        )
        return UserResponse.model_validate(user)

    async def grant_admin_permissions(
        self,
        acting_user_id: uuid.UUID,
        target_user_id: uuid.UUID,
        action_ids: list[uuid.UUID],
    ) -> None:
        """Grant permissions directly to an Admin (Section 6.2).

        Args:
            acting_user_id: The Super Admin performing the operation.
            target_user_id: The admin to grant permissions to.
            action_ids: Permission action IDs to grant.
        """
        await self._require_super_admin(acting_user_id)

        user = await self._repo.get_user_by_id(target_user_id)
        if user is None:
            raise NotFoundError("Resource not found.")

        for action_id in action_ids:
            await self._perm_service.grant_direct_permission(
                user_id=target_user_id,
                action_id=action_id,
                is_grant=True,
                acting_user_id=acting_user_id,
            )

        await self._audit.log(
            user_id=acting_user_id,
            action="admin.permissions.granted",
            resource_type="user",
            resource_id=str(target_user_id),
            details={"action_ids": [str(a) for a in action_ids]},
        )

    async def revoke_admin_permissions(
        self,
        acting_user_id: uuid.UUID,
        target_user_id: uuid.UUID,
        action_ids: list[uuid.UUID],
    ) -> None:
        """Revoke permissions from an Admin.

        Args:
            acting_user_id: The Super Admin performing the operation.
            target_user_id: The admin to revoke permissions from.
            action_ids: Permission action IDs to revoke.
        """
        await self._require_super_admin(acting_user_id)

        user = await self._repo.get_user_by_id(target_user_id)
        if user is None:
            raise NotFoundError("Resource not found.")

        for action_id in action_ids:
            try:
                await self._perm_service.revoke_direct_permission(
                    user_id=target_user_id,
                    action_id=action_id,
                    acting_user_id=acting_user_id,
                )
            except NotFoundError:
                pass  # Already revoked — idempotent

        await self._audit.log(
            user_id=acting_user_id,
            action="admin.permissions.revoked",
            resource_type="user",
            resource_id=str(target_user_id),
            details={"action_ids": [str(a) for a in action_ids]},
        )

    async def list_admins(
        self,
        acting_user_id: uuid.UUID,
    ) -> list[UserResponse]:
        """List all admin users in the acting user's organization.

        Args:
            acting_user_id: The Super Admin performing the operation.

        Returns:
            List of admin users.
        """
        await self._require_super_admin(acting_user_id)

        acting_user = await self._repo.get_user_by_id(acting_user_id)
        if acting_user is None:
            raise NotFoundError("Resource not found.")

        users = await self._repo.list_users_by_org(
            acting_user.organization_id, include_suspended=True,
        )
        return [UserResponse.model_validate(u) for u in users]
