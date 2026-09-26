"""Add permission engine and audit log tables.

Revision ID: 0001
Revises: None
Create Date: 2026-08-09

Creates:
    - permission_domains: Registered modules/feature areas
    - permission_actions: Available actions per domain
    - roles: Dynamic role definitions
    - role_permissions: Role → action grants
    - user_roles: User → role assignments
    - direct_permissions: Per-user grants/denies
    - audit_logs: Immutable audit trail

Seeds:
    - super_admin system role
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import UUID

# revision identifiers
revision: str = "0001"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Create permission engine and audit log tables."""

    # ── Permission Domains ───────────────────
    op.create_table(
        "permission_domains",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("code", sa.String(100), unique=True, nullable=False, index=True),
        sa.Column("name", sa.String(255), nullable=False),
        sa.Column("description", sa.Text, nullable=True),
        sa.Column("is_active", sa.Boolean, nullable=False, server_default=sa.text("true")),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )

    # ── Permission Actions ───────────────────
    op.create_table(
        "permission_actions",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("domain_id", UUID(as_uuid=True), sa.ForeignKey("permission_domains.id"), nullable=False, index=True),
        sa.Column("code", sa.String(100), nullable=False),
        sa.Column("name", sa.String(255), nullable=False),
        sa.Column("description", sa.Text, nullable=True),
        sa.Column("is_active", sa.Boolean, nullable=False, server_default=sa.text("true")),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.UniqueConstraint("domain_id", "code", name="uq_permission_actions_domain_code"),
    )

    # ── Roles ────────────────────────────────
    op.create_table(
        "roles",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("organization_id", UUID(as_uuid=True), nullable=True, index=True),
        sa.Column("code", sa.String(100), unique=True, nullable=False, index=True),
        sa.Column("name", sa.String(255), nullable=False),
        sa.Column("description", sa.Text, nullable=True),
        sa.Column("is_system", sa.Boolean, nullable=False, server_default=sa.text("false")),
        sa.Column("is_active", sa.Boolean, nullable=False, server_default=sa.text("true")),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )

    # ── Role Permissions ─────────────────────
    op.create_table(
        "role_permissions",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("role_id", UUID(as_uuid=True), sa.ForeignKey("roles.id"), nullable=False, index=True),
        sa.Column("action_id", UUID(as_uuid=True), sa.ForeignKey("permission_actions.id"), nullable=False, index=True),
        sa.Column("granted_by", UUID(as_uuid=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.UniqueConstraint("role_id", "action_id", name="uq_role_permissions_role_action"),
    )

    # ── User Roles ───────────────────────────
    op.create_table(
        "user_roles",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", UUID(as_uuid=True), nullable=False, index=True),
        sa.Column("role_id", UUID(as_uuid=True), sa.ForeignKey("roles.id"), nullable=False, index=True),
        sa.Column("granted_by", UUID(as_uuid=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.UniqueConstraint("user_id", "role_id", name="uq_user_roles_user_role"),
    )

    # ── Direct Permissions ───────────────────
    op.create_table(
        "direct_permissions",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", UUID(as_uuid=True), nullable=False, index=True),
        sa.Column("action_id", UUID(as_uuid=True), sa.ForeignKey("permission_actions.id"), nullable=False, index=True),
        sa.Column("is_grant", sa.Boolean, nullable=False),
        sa.Column("granted_by", UUID(as_uuid=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.UniqueConstraint("user_id", "action_id", name="uq_direct_permissions_user_action"),
    )

    # ── Audit Logs ───────────────────────────
    op.create_table(
        "audit_logs",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", UUID(as_uuid=True), nullable=True, index=True),
        sa.Column("action", sa.String(255), nullable=False, index=True),
        sa.Column("resource_type", sa.String(100), nullable=False, index=True),
        sa.Column("resource_id", sa.String(255), nullable=True, index=True),
        sa.Column("ip_address", sa.String(45), nullable=True),
        sa.Column("user_agent", sa.Text, nullable=True),
        sa.Column("details", sa.JSON, nullable=True),
        sa.Column("changes", sa.JSON, nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False, index=True),
    )

    # ── Seed: Super Admin System Role ────────
    import uuid
    op.execute(
        sa.text(
            "INSERT INTO roles (id, code, name, description, is_system, is_active) "
            "VALUES (:id, :code, :name, :description, true, true)"
        ).bindparams(
            id=str(uuid.uuid4()),
            code="super_admin",
            name="Super Admin",
            description="Unrestricted system access. Bypasses the permission engine by design.",
        )
    )


def downgrade() -> None:
    """Drop all permission engine and audit log tables."""
    op.drop_table("audit_logs")
    op.drop_table("direct_permissions")
    op.drop_table("user_roles")
    op.drop_table("role_permissions")
    op.drop_table("roles")
    op.drop_table("permission_actions")
    op.drop_table("permission_domains")
