"""
ConnectHub Auth Module — HTTP Endpoints.

Routes:
    POST /auth/login          — Authenticate → token pair
    POST /auth/register       — Create a member account → token pair
    POST /auth/refresh        — Refresh access token
    GET  /auth/me             — Current user profile
    POST /auth/admins         — Create admin (Super Admin only)
    GET  /auth/admins         — List admins (Super Admin only)
    PUT  /auth/admins/{id}/suspend    — Suspend admin
    PUT  /auth/admins/{id}/reactivate — Reactivate admin
    POST /auth/admins/{id}/permissions   — Grant permissions
    DELETE /auth/admins/{id}/permissions — Revoke permissions
"""

from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, Request
from sqlalchemy.ext.asyncio import AsyncSession

from connecthub.core.database.session import get_db_session
from connecthub.modules.auth.schemas import (
    AdminCreateRequest,
    AdminSuspendRequest,
    ChangePasswordRequest,
    LoginRequest,
    PermissionUpdateRequest,
    RegisterRequest,
    RefreshRequest,
    TokenResponse,
    UserProfileUpdateRequest,
    UserResponse,
)
from connecthub.modules.auth.service import AdminService, AuthService

router = APIRouter()


def _get_user_id(request: Request) -> uuid.UUID:
    """Extract user_id from request state (set by auth middleware)."""
    return request.state.user_id


# ── Authentication ───────────────────────────

@router.post("/login", response_model=TokenResponse)
async def login(
    data: LoginRequest,
    request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> TokenResponse:
    """Authenticate and return a token pair."""
    service = AuthService(db)
    token_pair = await service.login(
        email=data.email,
        password=data.password,
        ip_address=request.client.host if request.client else None,
        user_agent=request.headers.get("User-Agent"),
    )
    return TokenResponse(
        access_token=token_pair.access_token,
        refresh_token=token_pair.refresh_token,
        token_type=token_pair.token_type,
        expires_in=token_pair.expires_in,
    )


@router.post("/register", response_model=TokenResponse, status_code=201)
async def register(
    data: RegisterRequest,
    request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> TokenResponse:
    """Create a workspace member account and sign them in immediately."""
    token_pair = await AuthService(db).register(data)
    return TokenResponse(
        access_token=token_pair.access_token,
        refresh_token=token_pair.refresh_token,
        token_type=token_pair.token_type,
        expires_in=token_pair.expires_in,
    )


@router.post("/refresh", response_model=TokenResponse)
async def refresh_token(
    data: RefreshRequest,
    db: AsyncSession = Depends(get_db_session),
) -> TokenResponse:
    """Refresh the access token."""
    service = AuthService(db)
    token_pair = await service.refresh_token(data.refresh_token)
    return TokenResponse(
        access_token=token_pair.access_token,
        refresh_token=token_pair.refresh_token,
        token_type=token_pair.token_type,
        expires_in=token_pair.expires_in,
    )


@router.post("/change-password", status_code=204)
async def change_password(
    data: ChangePasswordRequest,
    request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> None:
    """Change the authenticated user's password."""
    service = AuthService(db)
    await service.change_password(
        user_id=_get_user_id(request),
        current_password=data.current_password,
        new_password=data.new_password,
        ip_address=request.client.host if request.client else None,
        user_agent=request.headers.get("User-Agent"),
    )


@router.get("/me", response_model=UserResponse)
async def get_current_user(
    request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> UserResponse:
    """Get the current authenticated user's profile."""
    service = AuthService(db)
    return await service.get_current_user(_get_user_id(request))


@router.put("/me", response_model=UserResponse)
@router.patch("/me", response_model=UserResponse)
async def update_current_user_profile(
    data: UserProfileUpdateRequest,
    request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> UserResponse:
    """Update the current authenticated user's profile and privacy settings."""
    service = AuthService(db)
    return await service.update_profile(_get_user_id(request), data)


@router.get("/directory", response_model=list[UserResponse])
async def get_user_directory(
    request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> list[UserResponse]:
    """Get all active users in the user's organization (for DMs and invitations)."""
    service = AuthService(db)
    return await service.get_directory(_get_user_id(request))


@router.get("/users/{user_id}", response_model=UserResponse)
async def get_user_by_id(
    user_id: uuid.UUID,
    request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> UserResponse:
    """Get public profile of a user by ID."""
    service = AuthService(db)
    return await service.get_user_by_id(user_id)


# ── Admin Management (Super Admin Only) ──────

@router.post("/admins", response_model=UserResponse, status_code=201)
async def create_admin(
    data: AdminCreateRequest,
    request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> UserResponse:
    """Create a new Admin user (Super Admin only)."""
    service = AdminService(db)
    return await service.create_admin(
        acting_user_id=_get_user_id(request),
        email=data.email,
        username=data.username,
        display_name=data.display_name,
        password=data.password,
        permission_action_ids=data.permission_action_ids,
    )


@router.get("/admins", response_model=list[UserResponse])
async def list_admins(
    request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> list[UserResponse]:
    """List all admin users (Super Admin only)."""
    service = AdminService(db)
    return await service.list_admins(acting_user_id=_get_user_id(request))


@router.put("/admins/{user_id}/suspend", response_model=UserResponse)
async def suspend_admin(
    user_id: uuid.UUID,
    request: Request,
    data: AdminSuspendRequest | None = None,
    db: AsyncSession = Depends(get_db_session),
) -> UserResponse:
    """Suspend an Admin user (Super Admin only)."""
    service = AdminService(db)
    return await service.suspend_admin(
        acting_user_id=_get_user_id(request),
        target_user_id=user_id,
        reason=data.reason if data else None,
    )


@router.put("/admins/{user_id}/reactivate", response_model=UserResponse)
async def reactivate_admin(
    user_id: uuid.UUID,
    request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> UserResponse:
    """Reactivate a suspended Admin user (Super Admin only)."""
    service = AdminService(db)
    return await service.reactivate_admin(
        acting_user_id=_get_user_id(request),
        target_user_id=user_id,
    )


@router.post("/admins/{user_id}/permissions", status_code=204)
async def grant_admin_permissions(
    user_id: uuid.UUID,
    data: PermissionUpdateRequest,
    request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> None:
    """Grant permissions to an Admin (Super Admin only)."""
    service = AdminService(db)
    await service.grant_admin_permissions(
        acting_user_id=_get_user_id(request),
        target_user_id=user_id,
        action_ids=data.action_ids,
    )


@router.delete("/admins/{user_id}/permissions", status_code=204)
async def revoke_admin_permissions(
    user_id: uuid.UUID,
    data: PermissionUpdateRequest,
    request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> None:
    """Revoke permissions from an Admin (Super Admin only)."""
    service = AdminService(db)
    await service.revoke_admin_permissions(
        acting_user_id=_get_user_id(request),
        target_user_id=user_id,
        action_ids=data.action_ids,
    )
