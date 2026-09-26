"""
ConnectHub Notification Module — Pydantic Schemas.
"""

from __future__ import annotations

import uuid
from datetime import datetime

from pydantic import BaseModel

from connecthub.modules.notifications.models import NotificationType


class NotificationCreate(BaseModel):
    """Create notification schema."""

    user_id: uuid.UUID | None = None
    notification_type: NotificationType = NotificationType.SYSTEM
    title: str
    body: str = ""
    resource_type: str | None = None
    resource_id: str | None = None
    conversation_id: uuid.UUID | None = None


class NotificationResponse(BaseModel):
    """Single notification."""

    id: uuid.UUID
    user_id: uuid.UUID
    notification_type: NotificationType
    title: str
    body: str
    resource_type: str | None
    resource_id: str | None
    conversation_id: uuid.UUID | None
    is_read: bool
    created_at: datetime

    model_config = {"from_attributes": True}


class NotificationListResponse(BaseModel):
    """Paginated notification list."""

    items: list[NotificationResponse]
    total: int


class UnreadCountResponse(BaseModel):
    """Unread notification count for badge."""

    count: int
