"""
ConnectHub — Audit Log Data Access Layer.

Repository for audit log database operations.
Audit logs are append-only — no update or delete operations.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from connecthub.core.audit.models import AuditLog


class AuditRepository:
    """Data access for audit logs — append-only."""

    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def create(
        self,
        user_id: uuid.UUID | None,
        action: str,
        resource_type: str,
        resource_id: str | None = None,
        ip_address: str | None = None,
        user_agent: str | None = None,
        details: dict[str, Any] | None = None,
        changes: dict[str, Any] | None = None,
    ) -> AuditLog:
        """Create a new audit log entry."""
        entry = AuditLog(
            user_id=user_id,
            action=action,
            resource_type=resource_type,
            resource_id=resource_id,
            ip_address=ip_address,
            user_agent=user_agent,
            details=details,
            changes=changes,
        )
        self._session.add(entry)
        await self._session.flush()
        return entry

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
    ) -> list[AuditLog]:
        """Query audit logs with optional filters.

        Results are ordered by created_at descending (newest first).
        """
        stmt = select(AuditLog)

        if user_id is not None:
            stmt = stmt.where(AuditLog.user_id == user_id)
        if action is not None:
            stmt = stmt.where(AuditLog.action == action)
        if resource_type is not None:
            stmt = stmt.where(AuditLog.resource_type == resource_type)
        if resource_id is not None:
            stmt = stmt.where(AuditLog.resource_id == resource_id)
        if from_date is not None:
            stmt = stmt.where(AuditLog.created_at >= from_date)
        if to_date is not None:
            stmt = stmt.where(AuditLog.created_at <= to_date)

        stmt = stmt.order_by(AuditLog.created_at.desc())
        stmt = stmt.limit(limit).offset(offset)

        result = await self._session.execute(stmt)
        return list(result.scalars().all())

    async def count(
        self,
        user_id: uuid.UUID | None = None,
        action: str | None = None,
        resource_type: str | None = None,
    ) -> int:
        """Count audit log entries matching the given filters."""
        from sqlalchemy import func as sqlfunc

        stmt = select(sqlfunc.count(AuditLog.id))

        if user_id is not None:
            stmt = stmt.where(AuditLog.user_id == user_id)
        if action is not None:
            stmt = stmt.where(AuditLog.action == action)
        if resource_type is not None:
            stmt = stmt.where(AuditLog.resource_type == resource_type)

        result = await self._session.execute(stmt)
        return result.scalar_one()
