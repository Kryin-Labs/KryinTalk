"""
ConnectHub — Audit Log Pydantic Schemas.

Schemas for audit log creation and querying.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any

from pydantic import BaseModel, Field


class AuditLogCreate(BaseModel):
    """Schema for creating an audit log entry."""

    user_id: uuid.UUID | None = None
    action: str = Field(..., min_length=1, max_length=255)
    resource_type: str = Field(..., min_length=1, max_length=100)
    resource_id: str | None = None
    ip_address: str | None = None
    user_agent: str | None = None
    details: dict[str, Any] | None = None
    changes: dict[str, Any] | None = None


class AuditLogResponse(BaseModel):
    """Response schema for an audit log entry."""

    id: uuid.UUID
    user_id: uuid.UUID | None
    action: str
    resource_type: str
    resource_id: str | None
    ip_address: str | None
    user_agent: str | None
    details: dict[str, Any] | None
    changes: dict[str, Any] | None
    created_at: datetime

    model_config = {"from_attributes": True}


class AuditLogQuery(BaseModel):
    """Query parameters for filtering audit logs."""

    user_id: uuid.UUID | None = None
    action: str | None = None
    resource_type: str | None = None
    resource_id: str | None = None
    from_date: datetime | None = None
    to_date: datetime | None = None
    limit: int = Field(default=50, ge=1, le=500)
    offset: int = Field(default=0, ge=0)
