"""
ConnectHub Admin Module — Pydantic Schemas.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any

from pydantic import BaseModel, Field

from connecthub.core.audit.schemas import AuditLogResponse


# ── User Management ──────────────────────────

class UserAdminResponse(BaseModel):
    """Full user detail for admin console view."""

    id: uuid.UUID
    organization_id: uuid.UUID
    email: str
    username: str
    display_name: str
    is_active: bool
    is_suspended: bool = False
    role: str = "member"
    is_super_admin: bool = False
    created_at: datetime | None = None
    updated_at: datetime | None = None

    model_config = {"from_attributes": True}


class UserListResponse(BaseModel):
    """Paginated user list response."""

    items: list[UserAdminResponse]
    total: int


class UserCreateAdminRequest(BaseModel):
    """Admin user creation request."""

    email: str = Field(..., max_length=320)
    username: str = Field(..., min_length=3, max_length=100)
    display_name: str = Field(..., min_length=1, max_length=255)
    password: str = Field(..., min_length=6)
    role: str = Field(default="member")
    is_super_admin: bool = False
    is_active: bool = True


class AdminPasswordResetRequest(BaseModel):
    """Admin resetting user password."""

    new_password: str = Field(..., min_length=6)


class UserUpdateRequest(BaseModel):
    """Admin user update request."""

    display_name: str | None = None
    is_active: bool | None = None
    role: str | None = None
    is_super_admin: bool | None = None


# ── Audit Log Viewer ─────────────────────────

class AuditLogListResponse(BaseModel):
    """Paginated audit log response with filters."""

    items: list[AuditLogResponse]
    total: int


# ── System Statistics ────────────────────────

class SystemStatsResponse(BaseModel):
    """System statistics for admin dashboard."""

    total_users: int
    active_users: int
    total_organizations: int
    total_conversations: int
    total_messages: int
    total_files: int
    total_file_bytes: int
    total_audit_logs: int


# ── Backup & Restore ─────────────────────────

class BackupResponse(BaseModel):
    """Backup metadata."""

    id: str
    filename: str
    size_bytes: int
    created_at: str
    tables_backed_up: list[str] = []
    formatted_title: str | None = None
    has_website: bool = True
    has_database: bool = True
    is_secure_encrypted: bool = True
    checksum_sha256: str | None = None


class BackupListResponse(BaseModel):
    """List of available backups."""

    items: list[BackupResponse]
    total: int


class RestoreResponse(BaseModel):
    """Restore operation summary."""

    backup_id: str
    restored_tables: list[str]
    total_records_restored: int
    timestamp: datetime
