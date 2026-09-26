"""
ConnectHub — Permission FastAPI Dependencies.

Provides a dependency factory for checking permissions at the router level.
Usage:

    @router.get(
        "/groups",
        dependencies=[Depends(require_permission("group_management", "read"))],
    )
    async def list_groups(...):
        ...

The dependency extracts the current user from the request (Phase 3+),
calls PolicyService.require_permission(), and raises NotFoundError if denied.
"""

from __future__ import annotations

import uuid
from collections.abc import Callable, Coroutine
from typing import Any

from fastapi import Depends, Request
from sqlalchemy.ext.asyncio import AsyncSession

from connecthub.core.database.session import get_db_session
from connecthub.core.permissions.policy import PolicyService


def require_permission(
    domain_code: str,
    action_code: str,
) -> Callable[..., Coroutine[Any, Any, None]]:
    """FastAPI dependency factory for permission checking.

    Returns a dependency function that:
    1. Extracts the current user ID from the request state
    2. Evaluates the permission via PolicyService
    3. Raises NotFoundError (404) if access is denied

    Args:
        domain_code: The permission domain (e.g., "group_management").
        action_code: The action within the domain (e.g., "read").

    Returns:
        A FastAPI dependency function.
    """

    async def _check_permission(
        request: Request,
        db: AsyncSession = Depends(get_db_session),
    ) -> None:
        # Extract current user ID from request state
        # Phase 3 will set this via authentication middleware.
        # For now, allow passing via header for testing.
        user_id_str = getattr(request.state, "user_id", None)
        if user_id_str is None:
            # Fallback: check X-User-ID header (development/testing only)
            user_id_str = request.headers.get("X-User-ID")

        if user_id_str is None:
            from connecthub.core.exceptions import UnauthorizedError
            raise UnauthorizedError("Authentication required.")

        user_id = uuid.UUID(str(user_id_str))

        policy = PolicyService(db)
        await policy.require_permission(user_id, domain_code, action_code)

    return _check_permission
