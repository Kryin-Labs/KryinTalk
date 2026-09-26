"""
ConnectHub Notification Module — ORM Models.

Per-user notifications stored in PostgreSQL. Each notification
is scoped to a single user and optionally linked to a conversation
for participant verification.
"""

from __future__ import annotations

import enum
import uuid

from sqlalchemy import Boolean, DateTime, Enum, ForeignKey, String, Text, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from connecthub.core.database.base import Base, IDMixin, SoftDeleteMixin, TimestampMixin


class NotificationType(str, enum.Enum):
    """Notification category."""

    MESSAGE = "message"
    FILE = "file"
    MENTION = "mention"
    INVITATION = "invitation"
    SYSTEM = "system"


class NotificationItem(Base, IDMixin, TimestampMixin, SoftDeleteMixin):
    """A per-user notification.

    Notifications are strictly per-user — no cross-user access.
    The conversation_id link allows participant verification
    to ensure notifications are only created for actual participants.
    """

    __tablename__ = "notification_items"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        nullable=False,
        index=True,
    )
    notification_type: Mapped[NotificationType] = mapped_column(
        Enum(NotificationType, name="notification_type_enum", create_constraint=False),
        nullable=False,
    )
    title: Mapped[str] = mapped_column(String(500), nullable=False)
    body: Mapped[str] = mapped_column(Text, nullable=False, default="")
    resource_type: Mapped[str | None] = mapped_column(
        String(100), nullable=True,
    )
    resource_id: Mapped[str | None] = mapped_column(
        String(100), nullable=True,
    )
    conversation_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), nullable=True, index=True,
    )
    is_read: Mapped[bool] = mapped_column(
        Boolean, default=False, nullable=False, index=True,
    )
