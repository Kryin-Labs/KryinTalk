"""
ConnectHub Group Module — Pydantic Schemas.

Schemas for Groups, Custom Roles, Permissions, and Member Management.
Compliant with channels.md specifications.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any

from pydantic import BaseModel, Field


# ── Permission Dict & Defaults ───────────────

ALL_PERMISSION_KEYS = [
    # Messages
    "view_messages",
    "send_messages",
    "edit_own_messages",
    "edit_other_messages",
    "delete_own_messages",
    "delete_other_messages",
    "reply_messages",
    "add_reactions",
    "remove_reactions",
    "pin_messages",
    "unpin_messages",
    "send_links",
    "send_attachments",
    "send_images",
    "send_files",
    # Members
    "view_members",
    "add_members",
    "remove_members",
    "manage_members",
    "view_member_profiles",
    # Roles
    "view_roles",
    "create_roles",
    "edit_roles",
    "delete_roles",
    "assign_roles",
    "manage_role_hierarchy",
    "manage_role_permissions",
    # Group
    "view_group",
    "edit_group_name",
    "edit_group_description",
    "change_group_icon",
    "change_group_visibility",
    "manage_group_settings",
    "delete_group",
    # Mentions
    "mention_users",
]


def default_owner_permissions() -> dict[str, bool]:
    """All permissions enabled for Group Owner."""
    return {k: True for k in ALL_PERMISSION_KEYS}


def default_admin_permissions() -> dict[str, bool]:
    """Group Admin permissions: everything except delete_group."""
    perms = {k: True for k in ALL_PERMISSION_KEYS}
    perms["delete_group"] = False
    return perms


def default_member_permissions() -> dict[str, bool]:
    """Standard Group Member permissions."""
    perms = {k: False for k in ALL_PERMISSION_KEYS}
    perms.update({
        "view_messages": True,
        "send_messages": True,
        "edit_own_messages": True,
        "delete_own_messages": True,
        "reply_messages": True,
        "add_reactions": True,
        "remove_reactions": True,
        "send_links": True,
        "send_attachments": True,
        "send_images": True,
        "send_files": True,
        "view_members": True,
        "view_member_profiles": True,
        "view_roles": True,
        "view_group": True,
        "mention_users": True,
    })
    return perms


def default_viewer_permissions() -> dict[str, bool]:
    """View-only Group Viewer permissions."""
    perms = {k: False for k in ALL_PERMISSION_KEYS}
    perms.update({
        "view_messages": True,
        "view_members": True,
        "view_member_profiles": True,
        "view_roles": True,
        "view_group": True,
    })
    return perms


# ── Roles ────────────────────────────────────

class GroupRoleCreate(BaseModel):
    """Create a new custom group role."""

    name: str = Field(..., min_length=1, max_length=100)
    color: str | None = "#64748B"
    description: str | None = None
    permissions: dict[str, bool] = Field(default_factory=default_member_permissions)
    is_default: bool = False


class GroupRoleUpdate(BaseModel):
    """Update a custom group role."""

    name: str | None = Field(default=None, min_length=1, max_length=100)
    color: str | None = None
    description: str | None = None
    permissions: dict[str, bool] | None = None
    is_default: bool | None = None


class GroupRoleResponse(BaseModel):
    """Group role response."""

    id: uuid.UUID
    group_id: uuid.UUID
    name: str
    color: str | None
    description: str | None
    hierarchy_rank: int
    is_system: bool
    is_default: bool
    permissions: dict[str, Any]
    member_count: int = 0
    created_at: datetime

    model_config = {"from_attributes": True}


class GroupRoleReorderItem(BaseModel):
    """Item for reordering roles."""

    role_id: uuid.UUID
    hierarchy_rank: int


class GroupRoleReorderRequest(BaseModel):
    """Reorder roles in hierarchy."""

    roles: list[GroupRoleReorderItem] = Field(..., min_length=1)


class GroupRoleDeleteRequest(BaseModel):
    """Delete a role and reassign members."""

    fallback_role_id: uuid.UUID | None = None


# ── Members ──────────────────────────────────

class MemberAddRequest(BaseModel):
    """Add members to a group."""

    user_ids: list[uuid.UUID] = Field(..., min_length=1)
    role_id: uuid.UUID | None = None


class MemberRemoveRequest(BaseModel):
    """Remove members from a group."""

    user_ids: list[uuid.UUID] = Field(..., min_length=1)


class MemberRoleUpdateRequest(BaseModel):
    """Assign or change a member's role in a group."""

    role_id: uuid.UUID


class GroupMemberDetailResponse(BaseModel):
    """Group member detail with user info and assigned role."""

    id: uuid.UUID
    group_id: uuid.UUID
    user_id: uuid.UUID
    username: str | None = None
    display_name: str | None = None
    email: str | None = None
    role_id: uuid.UUID | None = None
    role: GroupRoleResponse | None = None
    added_by: uuid.UUID | None = None
    created_at: datetime

    model_config = {"from_attributes": True}


class GroupMemberListResponse(BaseModel):
    """List of group members with full detail."""

    items: list[GroupMemberDetailResponse]
    total: int


# ── Group ────────────────────────────────────

class GroupCreate(BaseModel):
    """Create a new group."""

    name: str = Field(..., min_length=1, max_length=255)
    slug: str = Field(..., min_length=1, max_length=100)
    description: str | None = None
    icon: str | None = None
    color: str | None = None
    visibility: str = "private"  # "private" or "organization"
    is_private: bool = True
    is_view_only: bool = False
    only_admin_invites: bool = True
    member_ids: list[uuid.UUID] = Field(default_factory=list)


class GroupUpdate(BaseModel):
    """Update an existing group."""

    name: str | None = Field(default=None, min_length=1, max_length=255)
    description: str | None = None
    icon: str | None = None
    color: str | None = None
    visibility: str | None = None
    is_active: bool | None = None
    is_private: bool | None = None
    only_admin_invites: bool | None = None


class GroupResponse(BaseModel):
    """Group response."""

    id: uuid.UUID
    organization_id: uuid.UUID
    name: str
    slug: str
    description: str | None
    icon: str | None = None
    color: str | None = None
    visibility: str = "private"
    is_active: bool
    is_private: bool
    only_admin_invites: bool = True
    created_by: uuid.UUID | None
    member_count: int = 0
    current_user_role: GroupRoleResponse | None = None
    current_user_permissions: dict[str, bool] | None = None
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}


class GroupListResponse(BaseModel):
    """Paginated group list response."""

    items: list[GroupResponse]
    total: int
    limit: int
    offset: int


# ── Invites ──────────────────────────────────

class GroupInviteCreate(BaseModel):
    """Create a single-use expiring invite link token."""

    expires_hours: int = Field(default=24, ge=1, le=720)


class GroupInviteResponse(BaseModel):
    """Group invite link token response."""

    id: uuid.UUID
    group_id: uuid.UUID
    group_name: str
    token: str
    invite_url: str
    created_by: uuid.UUID
    created_by_name: str | None = None
    max_uses: int = 1
    uses_count: int = 0
    is_expired: bool = False
    is_used: bool = False
    expires_at: datetime
    created_at: datetime


class GroupInviteAcceptResponse(BaseModel):
    """Response when an invite link is accepted."""

    message: str
    group_id: uuid.UUID
    group_name: str
    conversation_id: uuid.UUID | None = None


class UserInviteRequest(BaseModel):
    """Invite a specific user by @username or user_id."""

    username: str | None = None
    user_id: uuid.UUID | None = None
    role_id: uuid.UUID | None = None


class UserInviteResponse(BaseModel):
    """Response after sending invitation notification."""

    message: str
    target_user_id: uuid.UUID
    target_username: str
    notification_id: uuid.UUID | None = None


class InviteRespondRequest(BaseModel):
    """Accept or reject a group invitation."""

    action: str = Field(..., pattern="^(accept|reject)$")
    notification_id: uuid.UUID | None = None
