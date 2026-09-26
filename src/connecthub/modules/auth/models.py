"""
ConnectHub Auth Module — ORM Models.

Organization and User entities. These are the foundational identity
models that all other modules reference.

See: ConnectHub_Blueprint_v1.md Sections 6.1, 6.2
"""

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, JSON, String, Text, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from connecthub.core.database.base import Base, IDMixin, SoftDeleteMixin, TimestampMixin
from typing import Any


# ──────────────────────────────────────────────
# Organization
# ──────────────────────────────────────────────
class Organization(Base, IDMixin, TimestampMixin, SoftDeleteMixin):
    """An organization — the top-level tenant entity.

    Every user belongs to exactly one organization.
    Every organization has exactly one Super Admin (Section 6.1).
    """

    __tablename__ = "organizations"

    name: Mapped[str] = mapped_column(String(255), nullable=False)
    slug: Mapped[str] = mapped_column(
        String(100), unique=True, nullable=False, index=True,
    )
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    settings: Mapped[dict[str, Any] | None] = mapped_column(
        JSON, nullable=True, default=None,
    )

    # Relationships
    users: Mapped[list[User]] = relationship("User", back_populates="organization")


# ──────────────────────────────────────────────
# User
# ──────────────────────────────────────────────
class User(Base, IDMixin, TimestampMixin, SoftDeleteMixin):
    """A user account.

    Users are members of an organization. Authentication is via
    email + password (bcrypt hashed). Suspension prevents login
    without deleting the account (recoverable by Super Admin).
    """

    __tablename__ = "users"

    organization_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("organizations.id"),
        nullable=False,
        index=True,
    )
    email: Mapped[str] = mapped_column(
        String(320), unique=True, nullable=False, index=True,
    )
    username: Mapped[str] = mapped_column(
        String(100), unique=True, nullable=False, index=True,
    )
    display_name: Mapped[str] = mapped_column(String(255), nullable=False)
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)

    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    is_suspended: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    hide_from_dm: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)

    last_login_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True,
    )

    # Relationships
    organization: Mapped[Organization] = relationship(
        "Organization", back_populates="users",
    )
