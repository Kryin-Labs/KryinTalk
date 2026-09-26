"""
ConnectHub File Module — ORM Models.

File metadata stored in PostgreSQL. File content stored on local filesystem.
Access control tied to conversation participation (same as messages).
"""

from __future__ import annotations

import uuid

from sqlalchemy import BigInteger, Boolean, DateTime, ForeignKey, String, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from connecthub.core.database.base import Base, IDMixin, SoftDeleteMixin, TimestampMixin


class FileAttachment(Base, IDMixin, TimestampMixin, SoftDeleteMixin):
    """A file uploaded to a conversation.

    Metadata lives in PostgreSQL. Content lives on local filesystem.
    Access is gated by conversation participation (Section 5).
    """

    __tablename__ = "file_attachments"

    organization_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("organizations.id"),
        nullable=False,
        index=True,
    )
    conversation_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("conversations.id"),
        nullable=False,
        index=True,
    )
    uploaded_by: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        nullable=False,
        index=True,
    )
    original_filename: Mapped[str] = mapped_column(
        String(500), nullable=False,
    )
    stored_filename: Mapped[str] = mapped_column(
        String(255), nullable=False, unique=True,
    )
    content_type: Mapped[str] = mapped_column(
        String(255), nullable=False,
    )
    size_bytes: Mapped[int] = mapped_column(
        BigInteger, nullable=False,
    )
    storage_path: Mapped[str] = mapped_column(
        String(1000), nullable=False,
    )
    has_preview: Mapped[bool] = mapped_column(
        Boolean, default=False, nullable=False,
    )
