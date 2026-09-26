"""
ConnectHub Notification Module — Data Access Layer.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone

from sqlalchemy import and_, select, update, func as sqlfunc
from sqlalchemy.ext.asyncio import AsyncSession

from connecthub.modules.notifications.models import NotificationItem, NotificationType


class NotificationRepository:
    """Data access for notification items."""

    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def create(
        self,
        user_id: uuid.UUID,
        notification_type: NotificationType,
        title: str,
        body: str = "",
        resource_type: str | None = None,
        resource_id: str | None = None,
        conversation_id: uuid.UUID | None = None,
    ) -> NotificationItem:
        item = NotificationItem(
            user_id=user_id,
            notification_type=notification_type,
            title=title,
            body=body,
            resource_type=resource_type,
            resource_id=resource_id,
            conversation_id=conversation_id,
        )
        self._session.add(item)
        await self._session.flush()
        return item

    async def get_by_id(self, notification_id: uuid.UUID) -> NotificationItem | None:
        stmt = select(NotificationItem).where(
            and_(
                NotificationItem.id == notification_id,
                NotificationItem.deleted_at.is_(None),
            ),
        )
        result = await self._session.execute(stmt)
        return result.scalar_one_or_none()

    async def list_for_user(
        self,
        user_id: uuid.UUID,
        limit: int = 50,
        offset: int = 0,
        notification_type: NotificationType | None = None,
        unread_only: bool = False,
    ) -> list[NotificationItem]:
        filters = [
            NotificationItem.user_id == user_id,
            NotificationItem.deleted_at.is_(None),
        ]
        if notification_type is not None:
            filters.append(NotificationItem.notification_type == notification_type)
        if unread_only:
            filters.append(NotificationItem.is_read.is_(False))

        stmt = (
            select(NotificationItem)
            .where(and_(*filters))
            .order_by(NotificationItem.created_at.desc())
            .limit(limit)
            .offset(offset)
        )
        result = await self._session.execute(stmt)
        return list(result.scalars().all())

    async def count_for_user(
        self,
        user_id: uuid.UUID,
        notification_type: NotificationType | None = None,
        unread_only: bool = False,
    ) -> int:
        filters = [
            NotificationItem.user_id == user_id,
            NotificationItem.deleted_at.is_(None),
        ]
        if notification_type is not None:
            filters.append(NotificationItem.notification_type == notification_type)
        if unread_only:
            filters.append(NotificationItem.is_read.is_(False))

        stmt = select(sqlfunc.count(NotificationItem.id)).where(and_(*filters))
        result = await self._session.execute(stmt)
        return result.scalar_one()

    async def count_unread(self, user_id: uuid.UUID) -> int:
        stmt = select(sqlfunc.count(NotificationItem.id)).where(
            and_(
                NotificationItem.user_id == user_id,
                NotificationItem.is_read.is_(False),
                NotificationItem.deleted_at.is_(None),
            ),
        )
        result = await self._session.execute(stmt)
        return result.scalar_one()

    async def mark_read(self, notification_id: uuid.UUID) -> None:
        item = await self.get_by_id(notification_id)
        if item:
            item.is_read = True

    async def mark_all_read(self, user_id: uuid.UUID) -> int:
        stmt = (
            update(NotificationItem)
            .where(
                and_(
                    NotificationItem.user_id == user_id,
                    NotificationItem.is_read.is_(False),
                    NotificationItem.deleted_at.is_(None),
                ),
            )
            .values(is_read=True)
        )
        result = await self._session.execute(stmt)
        return result.rowcount

    async def mark_conversation_read(self, user_id: uuid.UUID, conversation_id: uuid.UUID) -> int:
        """Mark all notifications for a specific conversation as read."""
        stmt = (
            update(NotificationItem)
            .where(
                and_(
                    NotificationItem.user_id == user_id,
                    NotificationItem.conversation_id == conversation_id,
                    NotificationItem.is_read.is_(False),
                    NotificationItem.deleted_at.is_(None),
                ),
            )
            .values(is_read=True)
        )
        result = await self._session.execute(stmt)
        return result.rowcount

