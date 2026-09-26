"""
ConnectHub — Permission Engine ORM Models.

Database models for the dynamic, data-driven permission system.
No hardcoded roles or permissions — everything is stored as data
and evaluated by the PolicyService at runtime.

Tables:
    - permission_domains: Registered modules/feature areas
    - permission_actions: Available actions per domain
    - roles: Dynamic role definitions
    - role_permissions: Role → action grants
    - user_roles: User → role assignments
    - direct_permissions: Per-user grants/denies (Admin granularity)

See: ConnectHub_Blueprint_v1.md Sections 5, 6.3
"""

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import (
    Boolean,
    DateTime,
    ForeignKey,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from connecthub.core.database.base import Base, IDMixin, TimestampMixin


# ──────────────────────────────────────────────
# Permission Domains (Module Registration)
# ──────────────────────────────────────────────
class PermissionDomain(Base, IDMixin, TimestampMixin):
    """A registered module or feature area in the permission system.

    Examples: "user_management", "department_management", "file_management"
    Modules register their domain at startup via PermissionRegistry.
    """

    __tablename__ = "permission_domains"

    code: Mapped[str] = mapped_column(
        String(100), unique=True, nullable=False, index=True,
    )
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)

    # Relationships
    actions: Mapped[list[PermissionAction]] = relationship(
        "PermissionAction", back_populates="domain", lazy="selectin",
    )


# ──────────────────────────────────────────────
# Permission Actions (Available Operations)
# ──────────────────────────────────────────────
class PermissionAction(Base, IDMixin, TimestampMixin):
    """An available action within a permission domain.

    Examples: "create", "read", "update", "delete", "manage"
    Each domain can have its own set of actions.
    """

    __tablename__ = "permission_actions"
    __table_args__ = (
        UniqueConstraint("domain_id", "code", name="uq_permission_actions_domain_code"),
    )

    domain_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("permission_domains.id"), nullable=False, index=True,
    )
    code: Mapped[str] = mapped_column(String(100), nullable=False)
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)

    # Relationships
    domain: Mapped[PermissionDomain] = relationship(
        "PermissionDomain", back_populates="actions",
    )


# ──────────────────────────────────────────────
# Roles (Dynamic Role Definitions)
# ──────────────────────────────────────────────
class Role(Base, IDMixin, TimestampMixin):
    """A dynamically created role.

    Roles are data — not hardcoded enums. The Super Admin role is seeded
    at migration time with is_system=True (immutable, cannot be deleted
    or have its permissions modified through the normal permission service).
    """

    __tablename__ = "roles"

    organization_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), nullable=True, index=True,
    )
    code: Mapped[str] = mapped_column(
        String(100), unique=True, nullable=False, index=True,
    )
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    is_system: Mapped[bool] = mapped_column(
        Boolean, default=False, nullable=False,
    )
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)

    # Relationships
    permissions: Mapped[list[RolePermission]] = relationship(
        "RolePermission", back_populates="role", lazy="selectin",
    )
    user_roles: Mapped[list[UserRole]] = relationship(
        "UserRole", back_populates="role", lazy="selectin",
    )


# ──────────────────────────────────────────────
# Role Permissions (Role → Action Grants)
# ──────────────────────────────────────────────
class RolePermission(Base, IDMixin):
    """Links a role to a permission action (grant).

    Granting a role permission means any user with that role
    can perform the specified action in the specified domain.
    """

    __tablename__ = "role_permissions"
    __table_args__ = (
        UniqueConstraint("role_id", "action_id", name="uq_role_permissions_role_action"),
    )

    role_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("roles.id"), nullable=False, index=True,
    )
    action_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("permission_actions.id"), nullable=False, index=True,
    )
    granted_by: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), nullable=True,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False,
    )

    # Relationships
    role: Mapped[Role] = relationship("Role", back_populates="permissions")
    action: Mapped[PermissionAction] = relationship("PermissionAction")


# ──────────────────────────────────────────────
# User Roles (User → Role Assignments)
# ──────────────────────────────────────────────
class UserRole(Base, IDMixin):
    """Assigns a role to a user.

    user_id references the users table (created in Phase 3).
    For Phase 2 testing, user_id is a plain UUID without FK constraint.
    """

    __tablename__ = "user_roles"
    __table_args__ = (
        UniqueConstraint("user_id", "role_id", name="uq_user_roles_user_role"),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), nullable=False, index=True,
    )
    role_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("roles.id"), nullable=False, index=True,
    )
    granted_by: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), nullable=True,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False,
    )

    # Relationships
    role: Mapped[Role] = relationship("Role", back_populates="user_roles")


# ──────────────────────────────────────────────
# Direct Permissions (Per-User Grants/Denies)
# ──────────────────────────────────────────────
class DirectPermission(Base, IDMixin):
    """Per-user permission grant or deny.

    Supports Section 6.2: Super Admin can grant/revoke permissions
    individually, per Admin. No two Admins are required to have
    identical privileges.

    is_grant=True → explicit grant (allow this action)
    is_grant=False → explicit deny (block this action, overrides role grants)
    """

    __tablename__ = "direct_permissions"
    __table_args__ = (
        UniqueConstraint("user_id", "action_id", name="uq_direct_permissions_user_action"),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), nullable=False, index=True,
    )
    action_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("permission_actions.id"), nullable=False, index=True,
    )
    is_grant: Mapped[bool] = mapped_column(
        Boolean, nullable=False,
    )
    granted_by: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), nullable=True,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False,
    )

    # Relationships
    action: Mapped[PermissionAction] = relationship("PermissionAction")
