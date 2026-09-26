"""
ConnectHub Org Settings Module — Pydantic Schemas.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any

from pydantic import BaseModel, Field


class OrgSettingsUpdate(BaseModel):
    """Update organization settings."""

    name: str | None = Field(default=None, min_length=1, max_length=255)
    settings: dict[str, Any] | None = None


class OrgSettingsResponse(BaseModel):
    """Organization settings response."""

    id: uuid.UUID
    name: str
    slug: str
    is_active: bool
    settings: dict[str, Any] | None
    created_at: datetime

    model_config = {"from_attributes": True}
