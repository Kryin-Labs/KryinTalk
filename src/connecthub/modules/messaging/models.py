"""
ConnectHub Messaging Module — ORM Models.

Conversation is the unified abstraction over DMs and group chats.
Messages are stored in PostgreSQL as the system
of record (Section 3.1).
"""

from __future__ import annotations

import enum
import threading
import time
import uuid
from datetime import datetime

from sqlalchemy import BigInteger, Boolean, DateTime, Enum, ForeignKey, String, Text, UniqueConstraint, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.types import JSON
from sqlalchemy.orm import Mapped, mapped_column, relationship

from connecthub.core.database.base import Base, IDMixin, SoftDeleteMixin, TimestampMixin


# Thread-safe monotonic sequence counter for message ordering.
# Combines time_ns with an atomic increment to guarantee uniqueness
# even when multiple messages are created in rapid succession.
_seq_lock = threading.Lock()
_seq_last = 0


def _next_sequence() -> int:
    """Generate a monotonically increasing sequence number."""
    global _seq_last
    with _seq_lock:
        now = time.time_ns()
        _seq_last = max(now, _seq_last + 1)
        return _seq_last


class ConversationType(str, enum.Enum):
    """Conversation type."""

    DIRECT = "direct"
    # Retained only while existing channel rows await the production data drop.
    CHANNEL = "channel"
    GROUP = "group"


class MessageType(str, enum.Enum):
    """Message content type."""

    TEXT = "text"
    SYSTEM = "system"
    FILE = "file"


class Conversation(Base, IDMixin, TimestampMixin):
    """A unified conversation — DM or group chat.

    For DIRECT: target_id is None (participants define the pair).
    For GROUP: target_id references the group.
    """

    __tablename__ = "conversations"

    organization_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("organizations.id"),
        nullable=False,
        index=True,
    )
    conversation_type: Mapped[ConversationType] = mapped_column(
        Enum(ConversationType, name="conversation_type_enum", create_constraint=False),
        nullable=False,
    )
    target_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), nullable=True, index=True,
    )

    # Relationships
    participants: Mapped[list[ConversationParticipant]] = relationship(
        "ConversationParticipant",
        back_populates="conversation",
        cascade="all, delete-orphan",
    )
    messages: Mapped[list[Message]] = relationship(
        "Message",
        back_populates="conversation",
        cascade="all, delete-orphan",
    )


class ConversationParticipant(Base, IDMixin, TimestampMixin):
    """A user's membership in a conversation.

    Tracks last_read_at for read receipt support.
    """

    __tablename__ = "conversation_participants"
    __table_args__ = (
        UniqueConstraint("conversation_id", "user_id", name="uq_conv_participants_conv_user"),
    )

    conversation_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("conversations.id"),
        nullable=False,
        index=True,
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        nullable=False,
        index=True,
    )
    last_read_at: Mapped[uuid.UUID | None] = mapped_column(
        DateTime(timezone=True), nullable=True,
    )

    # Relationships
    conversation: Mapped[Conversation] = relationship(
        "Conversation", back_populates="participants",
    )


class Message(Base, IDMixin, TimestampMixin, SoftDeleteMixin):
    """A message in a conversation.

    PostgreSQL is the system of record (Section 3.1).
    The broker (NATS) handles real-time fan-out only.
    """

    __tablename__ = "messages"

    sequence_num: Mapped[int] = mapped_column(
        BigInteger, default=_next_sequence, unique=True, nullable=False, index=True,
    )

    conversation_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("conversations.id"),
        nullable=False,
        index=True,
    )
    sender_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        nullable=False,
        index=True,
    )
    content: Mapped[str] = mapped_column(Text, nullable=False)
    message_type: Mapped[MessageType] = mapped_column(
        Enum(MessageType, name="message_type_enum", create_constraint=False),
        nullable=False,
        default=MessageType.TEXT,
    )
    parent_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("messages.id"),
        nullable=True,
        index=True,
    )
    metadata_json: Mapped[dict | None] = mapped_column(
        JSON, nullable=True,
    )
    is_pinned: Mapped[bool] = mapped_column(
        Boolean, default=False, nullable=False, index=True,
    )
    pinned_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True,
    )
    pinned_by: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), nullable=True,
    )

    # Relationships
    conversation: Mapped[Conversation] = relationship(
        "Conversation", back_populates="messages",
    )


class MessageReaction(Base, IDMixin, TimestampMixin):
    """One user's emoji reaction to one message."""

    __tablename__ = "message_reactions"
    __table_args__ = (
        UniqueConstraint("message_id", "user_id", "emoji", name="uq_message_reaction"),
    )

    message_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("messages.id"),
        nullable=False,
        index=True,
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        nullable=False,
        index=True,
    )
    emoji: Mapped[str] = mapped_column(String(64), nullable=False)
