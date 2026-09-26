"""
ConnectHub Notification Module — Business Logic.

Notifications are strictly per-user. No user can access
another user's notifications (Section 5).
"""

from __future__ import annotations

import logging
import uuid

from sqlalchemy.ext.asyncio import AsyncSession

from connecthub.core.exceptions import NotFoundError
from connecthub.modules.notifications.models import NotificationType
from connecthub.modules.notifications.repository import NotificationRepository
from connecthub.modules.notifications.schemas import (
    NotificationListResponse,
    NotificationResponse,
    UnreadCountResponse,
)

logger = logging.getLogger(__name__)


class NotificationService:
    """Notification service — per-user, Section 5 compliant.

    Every operation verifies the requesting user owns the notification.
    """

    def __init__(self, session: AsyncSession) -> None:
        self._repo = NotificationRepository(session)

    # ── Create ───────────────────────────────

    async def create_notification(
        self,
        user_id: uuid.UUID,
        notification_type: NotificationType,
        title: str,
        body: str = "",
        resource_type: str | None = None,
        resource_id: str | None = None,
        conversation_id: uuid.UUID | None = None,
    ) -> NotificationResponse:
        """Create a notification for a user."""
        item = await self._repo.create(
            user_id=user_id,
            notification_type=notification_type,
            title=title,
            body=body,
            resource_type=resource_type,
            resource_id=resource_id,
            conversation_id=conversation_id,
        )
        logger.info("Notification created for user %s: %s", user_id, title)
        return NotificationResponse.model_validate(item)

    # ── List ─────────────────────────────────

    async def list_notifications(
        self,
        user_id: uuid.UUID,
        limit: int = 50,
        offset: int = 0,
        notification_type: NotificationType | None = None,
        unread_only: bool = False,
    ) -> NotificationListResponse:
        """List user's own notifications (paginated and filterable)."""
        items = await self._repo.list_for_user(
            user_id, limit, offset, notification_type=notification_type, unread_only=unread_only,
        )
        total = await self._repo.count_for_user(
            user_id, notification_type=notification_type, unread_only=unread_only,
        )
        return NotificationListResponse(
            items=[NotificationResponse.model_validate(i) for i in items],
            total=total,
        )

    # ── Read State ───────────────────────────

    async def mark_read(
        self,
        user_id: uuid.UUID,
        notification_id: uuid.UUID,
    ) -> None:
        """Mark a single notification as read. Verifies ownership."""
        item = await self._repo.get_by_id(notification_id)
        if item is None or item.user_id != user_id:
            raise NotFoundError("Resource not found.")
        await self._repo.mark_read(notification_id)

    async def mark_all_read(self, user_id: uuid.UUID) -> int:
        """Mark all unread notifications as read. Returns count marked."""
        return await self._repo.mark_all_read(user_id)

    async def mark_conversation_read(self, user_id: uuid.UUID, conversation_id: uuid.UUID) -> int:
        """Mark all notifications for a specific conversation as read."""
        return await self._repo.mark_conversation_read(user_id, conversation_id)

    # ── Unread Count ─────────────────────────

    async def get_unread_count(self, user_id: uuid.UUID) -> UnreadCountResponse:
        """Get unread notification count for badge display."""
        count = await self._repo.count_unread(user_id)
        return UnreadCountResponse(count=count)

