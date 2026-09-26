"""
ConnectHub — Audit Log ORM Model.

Immutable record of every privileged action in the system.
Captures: who, what, when, from where, and on what resource.

See: ConnectHub_Blueprint_v1.md Section 9
"""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import DateTime, JSON, String, Text, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from connecthub.core.database.base import Base, IDMixin


class AuditLog(Base, IDMixin):
    """Immutable audit log entry.

    Once created, audit log entries are never updated or deleted.
    They provide a complete, tamper-evident trail of all privileged
    actions in the system.
    """

    __tablename__ = "audit_logs"

    # WHO performed the action
    user_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), nullable=True, index=True,
    )

    # WHAT action was performed
    action: Mapped[str] = mapped_column(
        String(255), nullable=False, index=True,
    )

    # ON WHAT resource
    resource_type: Mapped[str] = mapped_column(
        String(100), nullable=False, index=True,
    )
    resource_id: Mapped[str | None] = mapped_column(
        String(255), nullable=True, index=True,
    )

    # FROM WHERE
    ip_address: Mapped[str | None] = mapped_column(
        String(45), nullable=True,  # IPv6 max length
    )
    user_agent: Mapped[str | None] = mapped_column(
        Text, nullable=True,
    )

    # DETAILS — action-specific context
    details: Mapped[dict[str, Any] | None] = mapped_column(
        JSON, nullable=True,
    )

    # CHANGES — before/after snapshot for mutations
    changes: Mapped[dict[str, Any] | None] = mapped_column(
        JSON, nullable=True,
    )

    # WHEN — immutable timestamp
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
        index=True,
    )
