"""
ConnectHub Group Module — ORM Models.

Private and Organization-wide Groups with custom roles, hierarchy, and permission tracking.
Groups are multi-user collaboration spaces scoped to an organization.

See: channels.md & ConnectHub_Blueprint_v1.md Section 7
"""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, JSON, String, Text, UniqueConstraint, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from connecthub.core.database.base import Base, IDMixin, SoftDeleteMixin, TimestampMixin


class Group(Base, IDMixin, TimestampMixin, SoftDeleteMixin):
    """A group — a collaboration space for selected or organization-wide users.

    Groups are org-scoped. Membership and custom roles control access and permissions.
    """

    __tablename__ = "groups"
    __table_args__ = (
        UniqueConstraint("organization_id", "slug", name="uq_groups_org_slug"),
    )

    organization_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("organizations.id"),
        nullable=False,
        index=True,
    )
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    slug: Mapped[str] = mapped_column(String(100), nullable=False, index=True)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    icon: Mapped[str | None] = mapped_column(String(255), nullable=True)
    color: Mapped[str | None] = mapped_column(String(50), nullable=True)
    visibility: Mapped[str] = mapped_column(String(50), default="private", nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    is_private: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    only_admin_invites: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    created_by: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), nullable=True,
    )

    # Relationships
    roles: Mapped[list[GroupRole]] = relationship(
        "GroupRole", back_populates="group", cascade="all, delete-orphan", order_by="GroupRole.hierarchy_rank",
    )
    members: Mapped[list[GroupMember]] = relationship(
        "GroupMember", back_populates="group", cascade="all, delete-orphan",
    )
    invites: Mapped[list[GroupInvite]] = relationship(
        "GroupInvite", back_populates="group", cascade="all, delete-orphan",
    )


class GroupRole(Base, IDMixin, TimestampMixin):
    """A custom role within a group.

    Controls permissions, hierarchy rank, and styling for assigned members.
    Group Owner has rank 0 (protected, system).
    Group Admin has rank 10.
    Group Member (default) has rank 100.
    """

    __tablename__ = "group_roles"
    __table_args__ = (
        UniqueConstraint("group_id", "name", name="uq_group_roles_group_name"),
    )

    group_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("groups.id"),
        nullable=False,
        index=True,
    )
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    color: Mapped[str | None] = mapped_column(String(50), nullable=True, default="#64748B")
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    hierarchy_rank: Mapped[int] = mapped_column(Integer, nullable=False, default=100)
    is_system: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    is_default: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    permissions: Mapped[dict[str, Any]] = mapped_column(JSON, default=dict, nullable=False)

    # Relationships
    group: Mapped[Group] = relationship("Group", back_populates="roles")
    members: Mapped[list[GroupMember]] = relationship(
        "GroupMember", back_populates="role",
    )


class GroupMember(Base, IDMixin, TimestampMixin):
    """A user's membership in a group with an assigned group role."""

    __tablename__ = "group_members"
    __table_args__ = (
        UniqueConstraint("group_id", "user_id", name="uq_group_members_group_user"),
    )

    group_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("groups.id"),
        nullable=False,
        index=True,
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        nullable=False,
        index=True,
    )
    role_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("group_roles.id"),
        nullable=True,
        index=True,
    )
    added_by: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), nullable=True,
    )

    # Relationships
    group: Mapped[Group] = relationship("Group", back_populates="members")
    role: Mapped[GroupRole | None] = relationship("GroupRole", back_populates="members")


class GroupInvite(Base, IDMixin, TimestampMixin):
    """A single-use expiring invite link token for a group."""

    __tablename__ = "group_invites"

    group_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("groups.id"),
        nullable=False,
        index=True,
    )
    token: Mapped[str] = mapped_column(
        String(64), unique=True, nullable=False, index=True,
    )
    created_by: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), nullable=False,
    )
    max_uses: Mapped[int] = mapped_column(Integer, default=1, nullable=False)
    uses_count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    is_revoked: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)

    # Relationships
    group: Mapped[Group] = relationship("Group", back_populates="invites")
