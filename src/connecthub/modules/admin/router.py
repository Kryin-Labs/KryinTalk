"""
ConnectHub Admin Module — REST Endpoints.

Routes:
    GET    /admin/users                     — List users (paginated)
    GET    /admin/users/{user_id}           — Get user details
    PUT    /admin/users/{user_id}           — Update user status / display name
    PUT    /admin/users/{user_id}/deactivate — Deactivate user
    GET    /admin/audit-logs                — List & filter audit logs
    GET    /admin/stats                     — System dashboard stats
    POST   /admin/backup                    — Create JSON backup
    GET    /admin/backup                    — List backups
    POST   /admin/backup/{backup_id}/restore — Restore from backup
    DELETE /admin/backup/{backup_id}        — Delete backup file
"""

from __future__ import annotations

import uuid
from datetime import datetime

from fastapi import APIRouter, Depends, Query, Request
from sqlalchemy.ext.asyncio import AsyncSession

from connecthub.core.database.session import get_db_session
from connecthub.modules.admin.backup_service import BackupService
from connecthub.modules.admin.schemas import (
    AdminPasswordResetRequest,
    AuditLogListResponse,
    BackupListResponse,
    BackupResponse,
    RestoreResponse,
    SystemStatsResponse,
    UserAdminResponse,
    UserCreateAdminRequest,
    UserListResponse,
    UserUpdateRequest,
)
from connecthub.modules.admin.service import AdminService

router = APIRouter()


def _uid(request: Request) -> uuid.UUID:
    return request.state.user_id


# ── User Management ──────────────────────────

@router.post("/users", response_model=UserAdminResponse, status_code=201)
async def create_user(
    data: UserCreateAdminRequest,
    request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> UserAdminResponse:
    """Create a new user with role assignment (Admin & Super Admin)."""
    return await AdminService(db).create_user(
        admin_user_id=_uid(request),
        data=data,
    )


@router.get("/users", response_model=UserListResponse)
async def list_users(
    request: Request,
    limit: int = Query(default=50, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    is_active: bool | None = Query(default=None),
    db: AsyncSession = Depends(get_db_session),
) -> UserListResponse:
    return await AdminService(db).list_users(
        admin_user_id=_uid(request),
        limit=limit,
        offset=offset,
        is_active=is_active,
    )


@router.post("/users/{user_id}/reset-password", status_code=204)
async def reset_user_password(
    user_id: uuid.UUID,
    data: AdminPasswordResetRequest,
    request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> None:
    """Reset a user's password (Admin & Super Admin)."""
    await AdminService(db).reset_user_password(
        admin_user_id=_uid(request),
        target_user_id=user_id,
        new_password=data.new_password,
    )


@router.get("/users/{user_id}", response_model=UserAdminResponse)
async def get_user_detail(
    user_id: uuid.UUID,
    request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> UserAdminResponse:
    return await AdminService(db).get_user_detail(
        admin_user_id=_uid(request),
        target_user_id=user_id,
    )


@router.put("/users/{user_id}", response_model=UserAdminResponse)
async def update_user(
    user_id: uuid.UUID,
    request: Request,
    data: UserUpdateRequest,
    db: AsyncSession = Depends(get_db_session),
) -> UserAdminResponse:
    return await AdminService(db).update_user(
        admin_user_id=_uid(request),
        target_user_id=user_id,
        data=data,
    )


@router.put("/users/{user_id}/deactivate", response_model=UserAdminResponse)
async def deactivate_user(
    user_id: uuid.UUID,
    request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> UserAdminResponse:
    return await AdminService(db).deactivate_user(
        admin_user_id=_uid(request),
        target_user_id=user_id,
    )


# ── Audit Log Viewer ─────────────────────────

@router.get("/audit-logs", response_model=AuditLogListResponse)
async def list_audit_logs(
    request: Request,
    user_id: uuid.UUID | None = Query(default=None),
    action: str | None = Query(default=None),
    resource_type: str | None = Query(default=None),
    resource_id: str | None = Query(default=None),
    from_date: datetime | None = Query(default=None),
    to_date: datetime | None = Query(default=None),
    limit: int = Query(default=50, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    db: AsyncSession = Depends(get_db_session),
) -> AuditLogListResponse:
    return await AdminService(db).list_audit_logs(
        admin_user_id=_uid(request),
        user_id_filter=user_id,
        action_filter=action,
        resource_type_filter=resource_type,
        resource_id_filter=resource_id,
        from_date=from_date,
        to_date=to_date,
        limit=limit,
        offset=offset,
    )


# ── System Statistics Dashboard ──────────────

@router.get("/stats", response_model=SystemStatsResponse)
async def get_system_stats(
    request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> SystemStatsResponse:
    return await AdminService(db).get_system_stats(admin_user_id=_uid(request))


# ── Backup & Restore ─────────────────────────

@router.post("/backup", response_model=BackupResponse, status_code=201)
async def create_backup(
    request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> BackupResponse:
    admin_id = _uid(request)
    await AdminService(db)._require_admin(admin_id)
    return await BackupService(db).create_backup(user_id=admin_id)


@router.get("/backup", response_model=BackupListResponse)
async def list_backups(
    request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> BackupListResponse:
    admin_id = _uid(request)
    await AdminService(db)._require_admin(admin_id)
    return await BackupService(db).list_backups()


@router.post("/backup/{backup_id}/restore", response_model=RestoreResponse)
async def restore_backup(
    backup_id: str,
    request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> RestoreResponse:
    admin_id = _uid(request)
    await AdminService(db)._require_admin(admin_id)
    return await BackupService(db).restore_backup(user_id=admin_id, backup_id=backup_id)


@router.delete("/backup/{backup_id}", status_code=204)
async def delete_backup(
    backup_id: str,
    request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> None:
    admin_id = _uid(request)
    await AdminService(db)._require_admin(admin_id)
    await BackupService(db).delete_backup(user_id=admin_id, backup_id=backup_id)
