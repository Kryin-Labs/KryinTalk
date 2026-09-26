"""
ConnectHub — Central Policy / Authorization Service.

The single point of authorization for all access decisions.
Every module's service layer calls PolicyService before returning data.
No hardcoded role checks anywhere — purely data-driven evaluation.

Policy Evaluation Order:
    1. Super Admin bypass → ALLOW (Section 6.1)
    2. Direct deny on action → DENY
    3. Direct grant on action → ALLOW
    4. Role grant on action → ALLOW
    5. Default → DENY

See: ConnectHub_Blueprint_v1.md Sections 5, 6.1, 6.3
"""

from __future__ import annotations

import logging
import uuid

from sqlalchemy.ext.asyncio import AsyncSession

from connecthub.core.exceptions import NotFoundError
from connecthub.core.permissions.constants import SUPER_ADMIN_ROLE
from connecthub.core.permissions.repository import PermissionRepository
from connecthub.core.permissions.schemas import AccessCheckResult

logger = logging.getLogger(__name__)


class PolicyService:
    """Central authorization service — evaluates all access decisions.

    IMPORTANT: This is the ONLY place where permission logic is evaluated.
    Module code must NEVER contain `if role == "admin"` or similar checks.
    """

    def __init__(self, session: AsyncSession) -> None:
        self._repo = PermissionRepository(session)

    async def check_permission(
        self,
        user_id: uuid.UUID,
        domain_code: str,
        action_code: str,
    ) -> AccessCheckResult:
        """Evaluate whether a user has a specific permission.

        Follows the 5-step evaluation order documented above.

        Args:
            user_id: The user requesting access.
            domain_code: The permission domain (e.g., "department_management").
            action_code: The action within the domain (e.g., "create").

        Returns:
            AccessCheckResult with allowed=True/False and a reason string.
        """
        base_result = {"domain_code": domain_code, "action_code": action_code}

        # ── Step 1: Super Admin Bypass ───────
        is_super_admin = await self._repo.user_has_system_role(
            user_id, SUPER_ADMIN_ROLE,
        )
        if is_super_admin:
            logger.debug(
                "Access ALLOWED (super_admin_bypass): user=%s domain=%s action=%s",
                user_id, domain_code, action_code,
            )
            return AccessCheckResult(
                allowed=True, reason="super_admin_bypass", **base_result,
            )

        # ── Step 2-4: Resolve the action ─────
        action = await self._repo.resolve_action(domain_code, action_code)
        if action is None:
            # Domain or action doesn't exist or is inactive → deny
            logger.debug(
                "Access DENIED (action_not_found): user=%s domain=%s action=%s",
                user_id, domain_code, action_code,
            )
            return AccessCheckResult(
                allowed=False, reason="action_not_found", **base_result,
            )

        # ── Step 2: Check Direct Deny ────────
        direct = await self._repo.get_direct_permission(user_id, action.id)
        if direct is not None and not direct.is_grant:
            logger.debug(
                "Access DENIED (direct_deny): user=%s domain=%s action=%s",
                user_id, domain_code, action_code,
            )
            return AccessCheckResult(
                allowed=False, reason="direct_deny", **base_result,
            )

        # ── Step 3: Check Direct Grant ───────
        if direct is not None and direct.is_grant:
            logger.debug(
                "Access ALLOWED (direct_grant): user=%s domain=%s action=%s",
                user_id, domain_code, action_code,
            )
            return AccessCheckResult(
                allowed=True, reason="direct_grant", **base_result,
            )

        # ── Step 4: Check Role Grants ────────
        has_role_grant = await self._repo.check_role_permission(user_id, action.id)
        if has_role_grant:
            logger.debug(
                "Access ALLOWED (role_grant): user=%s domain=%s action=%s",
                user_id, domain_code, action_code,
            )
            return AccessCheckResult(
                allowed=True, reason="role_grant", **base_result,
            )

        # ── Step 5: Default Deny ─────────────
        logger.debug(
            "Access DENIED (no_permission): user=%s domain=%s action=%s",
            user_id, domain_code, action_code,
        )
        return AccessCheckResult(
            allowed=False, reason="no_permission", **base_result,
        )

    async def require_permission(
        self,
        user_id: uuid.UUID,
        domain_code: str,
        action_code: str,
    ) -> None:
        """Check permission and raise NotFoundError if denied.

        Uses NotFoundError (404) instead of ForbiddenError (403)
        to prevent metadata leakage — Section 5 requires that
        unauthorized resources are completely invisible, including
        not confirming their existence via a 403 response.

        Args:
            user_id: The user requesting access.
            domain_code: The permission domain.
            action_code: The action within the domain.

        Raises:
            NotFoundError: If the user does not have the required permission.
        """
        result = await self.check_permission(user_id, domain_code, action_code)
        if not result.allowed:
            raise NotFoundError("Resource not found.")

    async def is_super_admin(self, user_id: uuid.UUID) -> bool:
        """Check if a user has the Super Admin role.

        This is a convenience method — modules should still use
        check_permission/require_permission for access decisions.
        This method exists for workflows that need to know if the
        acting user is a Super Admin (e.g., admin management flows).

        Args:
            user_id: The user to check.

        Returns:
            True if the user has the Super Admin system role.
        """
        return await self._repo.user_has_system_role(user_id, SUPER_ADMIN_ROLE)
