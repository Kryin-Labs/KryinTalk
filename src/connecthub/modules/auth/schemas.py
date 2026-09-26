"""
ConnectHub Auth Module — Pydantic Schemas.

Request/response schemas for authentication and admin management.
"""

from __future__ import annotations

import re
import uuid
from datetime import datetime

from pydantic import BaseModel, Field, field_validator


# ──────────────────────────────────────────────
# Authentication
# ──────────────────────────────────────────────
class LoginRequest(BaseModel):
    """Login request — email + password."""

    email: str = Field(..., max_length=320)
    password: str = Field(..., min_length=1)


class RegisterRequest(BaseModel):
    """Self-service account registration for a workspace."""

    email: str = Field(..., max_length=320)
    username: str = Field(..., min_length=3, max_length=100)
    display_name: str = Field(..., min_length=1, max_length=255)
    password: str = Field(..., min_length=8, max_length=128)
    organization_slug: str | None = Field(default=None, max_length=100)

    @field_validator("email")
    @classmethod
    def normalize_email(cls, value: str) -> str:
        value = value.strip().lower()
        if not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", value):
            raise ValueError("Enter a valid email address.")
        return value

    @field_validator("username")
    @classmethod
    def normalize_username(cls, value: str) -> str:
        value = value.strip().lstrip("@").lower()
        if len(value) < 3:
            raise ValueError("Username must contain at least 3 characters.")
        return value

    @field_validator("display_name")
    @classmethod
    def normalize_display_name(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("Display name cannot be empty.")
        return value


class TokenResponse(BaseModel):
    """Token pair returned on login/refresh."""

    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int


class RefreshRequest(BaseModel):
    """Refresh token request."""

    refresh_token: str


class ChangePasswordRequest(BaseModel):
    """Self password change request."""

    current_password: str = Field(..., min_length=1)
    new_password: str = Field(..., min_length=6)


# ──────────────────────────────────────────────
# User / Admin
# ──────────────────────────────────────────────
class UserResponse(BaseModel):
    """Public user profile response."""

    id: uuid.UUID
    organization_id: uuid.UUID
    email: str
    username: str
    display_name: str
    is_active: bool
    is_suspended: bool
    is_super_admin: bool = False
    hide_from_dm: bool = False
    last_login_at: datetime | None
    created_at: datetime

    model_config = {"from_attributes": True}


class UserProfileUpdateRequest(BaseModel):
    """Request to update current user's profile and privacy settings."""

    display_name: str | None = None
    hide_from_dm: bool | None = None


class AdminCreateRequest(BaseModel):
    """Request to create a new Admin user (Super Admin only)."""

    email: str = Field(..., max_length=320)
    username: str = Field(..., min_length=3, max_length=100)
    display_name: str = Field(..., min_length=1, max_length=255)
    password: str = Field(..., min_length=8)
    permission_action_ids: list[uuid.UUID] = Field(
        default_factory=list,
        description="Permission action IDs to grant directly to this Admin.",
    )


class AdminSuspendRequest(BaseModel):
    """Request to suspend an Admin user."""

    reason: str | None = None


class PermissionUpdateRequest(BaseModel):
    """Request to grant or revoke permissions for an Admin."""

    action_ids: list[uuid.UUID] = Field(..., min_length=1)


# ──────────────────────────────────────────────
# Organization
# ──────────────────────────────────────────────
class OrganizationResponse(BaseModel):
    """Organization response."""

    id: uuid.UUID
    name: str
    slug: str
    is_active: bool
    created_at: datetime

    model_config = {"from_attributes": True}


# ──────────────────────────────────────────────
# Bootstrap
# ──────────────────────────────────────────────
class BootstrapRequest(BaseModel):
    """Request to bootstrap the Super Admin."""

    org_name: str = Field(..., min_length=1, max_length=255)
    org_slug: str = Field(..., min_length=1, max_length=100)
    email: str = Field(..., max_length=320)
    username: str = Field(..., min_length=3, max_length=100)
    display_name: str = Field(..., min_length=1, max_length=255)
    password: str = Field(..., min_length=8)
