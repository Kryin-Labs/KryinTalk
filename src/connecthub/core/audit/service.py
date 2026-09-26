"""
ConnectHub — Audit Logging Service.

Logs privileged actions to the database and emits audit events
to the event bus for real-time monitoring.

Implements the AuditLogger protocol expected by PermissionService.

See: ConnectHub_Blueprint_v1.md Section 9
"""

from __future__ import annotations

import logging
import uuid
from datetime import datetime
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession

from connecthub.core.audit.repository import AuditRepository
from connecthub.core.audit.schemas import AuditLogResponse
from connecthub.core.permissions.service import AuditLogger

logger = logging.getLogger(__name__)


class AuditService(AuditLogger):
    """Audit logging service — logs actions to the database.

    Every privileged action (Admin/Super Admin actions especially)
    is recorded with: who, what, when, from where, and on what resource.
    """

    def __init__(self, session: AsyncSession) -> None:
        self._repo = AuditRepository(session)

    async def log(
        self,
        user_id: uuid.UUID | None = None,
        action: str = "",
        resource_type: str = "",
        resource_id: str | None = None,
        details: dict[str, Any] | None = None,
        changes: dict[str, Any] | None = None,
        ip_address: str | None = None,
        user_agent: str | None = None,
    ) -> AuditLogResponse:
        """Log an auditable action.

        Args:
            user_id: The user who performed the action (None for system actions).
            action: The action performed (e.g., "role.created", "permission.granted").
            resource_type: The type of resource affected (e.g., "role", "user").
            resource_id: The ID of the affected resource.
            details: Action-specific context (JSONB).
            changes: Before/after snapshot for mutations (JSONB).
            ip_address: Client IP address.
            user_agent: Client user agent string.

        Returns:
            The created audit log entry.
        """
        entry = await self._repo.create(
            user_id=user_id,
            action=action,
            resource_type=resource_type,
            resource_id=resource_id,
            ip_address=ip_address,
            user_agent=user_agent,
            details=details,
            changes=changes,
        )

        logger.info(
            "Audit: user=%s action=%s resource=%s/%s",
            user_id, action, resource_type, resource_id,
        )

        return AuditLogResponse.model_validate(entry)

    async def query(
        self,
        user_id: uuid.UUID | None = None,
        action: str | None = None,
        resource_type: str | None = None,
        resource_id: str | None = None,
        from_date: datetime | None = None,
        to_date: datetime | None = None,
        limit: int = 50,
        offset: int = 0,
    ) -> list[AuditLogResponse]:
        """Query audit logs with optional filters."""
        entries = await self._repo.query(
            user_id=user_id,
            action=action,
            resource_type=resource_type,
            resource_id=resource_id,
            from_date=from_date,
            to_date=to_date,
            limit=limit,
            offset=offset,
        )
        return [AuditLogResponse.model_validate(e) for e in entries]

    async def count(
        self,
        user_id: uuid.UUID | None = None,
        action: str | None = None,
        resource_type: str | None = None,
    ) -> int:
        """Count audit log entries matching filters."""
        return await self._repo.count(
            user_id=user_id,
            action=action,
            resource_type=resource_type,
        )

