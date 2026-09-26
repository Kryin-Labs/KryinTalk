"""
ConnectHub — Permission Engine Pydantic Schemas.

Request/response schemas for the permission system.
Used by the permission services and (in Phase 8) the Admin Console API.
"""

from __future__ import annotations

import uuid
from datetime import datetime

from pydantic import BaseModel, Field


# ──────────────────────────────────────────────
# Permission Domain Schemas
# ──────────────────────────────────────────────
class ActionDefinition(BaseModel):
    """Defines an action to register within a permission domain."""

    code: str = Field(..., min_length=1, max_length=100)
    name: str = Field(..., min_length=1, max_length=255)
    description: str | None = None


class DomainRegistration(BaseModel):
    """Request to register a module's permission domain and its actions."""

    code: str = Field(..., min_length=1, max_length=100)
    name: str = Field(..., min_length=1, max_length=255)
    description: str | None = None
    actions: list[ActionDefinition] = Field(..., min_length=1)


class ActionResponse(BaseModel):
    """Response schema for a permission action."""

    id: uuid.UUID
    code: str
    name: str
    description: str | None
    is_active: bool
    created_at: datetime

    model_config = {"from_attributes": True}


class DomainResponse(BaseModel):
    """Response schema for a permission domain."""

    id: uuid.UUID
    code: str
    name: str
    description: str | None
    is_active: bool
    actions: list[ActionResponse]
    created_at: datetime

    model_config = {"from_attributes": True}


# ──────────────────────────────────────────────
# Role Schemas
# ──────────────────────────────────────────────
class RoleCreate(BaseModel):
    """Request to create a new role."""

    code: str = Field(..., min_length=1, max_length=100)
    name: str = Field(..., min_length=1, max_length=255)
    description: str | None = None
    organization_id: uuid.UUID | None = None


class RoleResponse(BaseModel):
    """Response schema for a role."""

    id: uuid.UUID
    code: str
    name: str
    description: str | None
    organization_id: uuid.UUID | None
    is_system: bool
    is_active: bool
    created_at: datetime

    model_config = {"from_attributes": True}


# ──────────────────────────────────────────────
# Permission Grant/Revoke Schemas
# ──────────────────────────────────────────────
class RolePermissionGrant(BaseModel):
    """Request to grant a permission action to a role."""

    role_id: uuid.UUID
    action_id: uuid.UUID


class UserRoleAssign(BaseModel):
    """Request to assign a role to a user."""

    user_id: uuid.UUID
    role_id: uuid.UUID


class DirectPermissionGrant(BaseModel):
    """Request to grant or deny a permission directly to a user."""

    user_id: uuid.UUID
    action_id: uuid.UUID
    is_grant: bool = True  # True = grant, False = deny


# ──────────────────────────────────────────────
# Access Check Schemas
# ──────────────────────────────────────────────
class AccessCheckRequest(BaseModel):
    """Request to check if a user has a specific permission."""

    user_id: uuid.UUID
    domain_code: str
    action_code: str


class AccessCheckResult(BaseModel):
    """Result of an access check."""

    allowed: bool
    reason: str  # e.g., "super_admin_bypass", "role_grant", "direct_grant", "denied"
    domain_code: str
    action_code: str
