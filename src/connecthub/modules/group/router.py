"""
ConnectHub Group Module — HTTP Endpoints.

Routes for Groups, Custom Roles, Permissions, and Member Management.
"""

from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, Query, Request
from sqlalchemy.ext.asyncio import AsyncSession

from connecthub.core.database.session import get_db_session
from connecthub.modules.group.schemas import (
    GroupCreate,
    GroupInviteAcceptResponse,
    GroupInviteCreate,
    GroupInviteResponse,
    GroupListResponse,
    GroupMemberListResponse,
    GroupMemberDetailResponse,
    GroupResponse,
    GroupRoleCreate,
    GroupRoleDeleteRequest,
    GroupRoleReorderRequest,
    GroupRoleResponse,
    GroupRoleUpdate,
    GroupUpdate,
    InviteRespondRequest,
    MemberAddRequest,
    MemberRemoveRequest,
    MemberRoleUpdateRequest,
    UserInviteRequest,
    UserInviteResponse,
)
from connecthub.modules.group.service import GroupService

router = APIRouter()


def _uid(request: Request) -> uuid.UUID:
    return request.state.user_id


# ── Group Invite Links & Token Inspection (Global token paths) ──

@router.get("/invites/{token}", response_model=GroupInviteResponse)
async def get_invite_info(
    token: str,
    db: AsyncSession = Depends(get_db_session),
) -> GroupInviteResponse:
    return await GroupService(db).get_invite_info(token)


@router.post("/invites/{token}/accept", response_model=GroupInviteAcceptResponse)
async def accept_invite_link(
    token: str,
    request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> GroupInviteAcceptResponse:
    return await GroupService(db).accept_invite_link(token, _uid(request))


# ── Group Endpoints ──────────────────────────

@router.post("", response_model=GroupResponse, status_code=201)
async def create_group(
    data: GroupCreate, request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> GroupResponse:
    return await GroupService(db).create_group(_uid(request), data)


@router.get("", response_model=GroupListResponse)
async def list_groups(
    request: Request,
    limit: int = Query(default=100, ge=1, le=500),
    offset: int = Query(default=0, ge=0),
    db: AsyncSession = Depends(get_db_session),
) -> GroupListResponse:
    return await GroupService(db).list_groups(_uid(request), limit, offset)


@router.get("/{group_id}", response_model=GroupResponse)
async def get_group(
    group_id: uuid.UUID, request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> GroupResponse:
    return await GroupService(db).get_group(_uid(request), group_id)


@router.put("/{group_id}", response_model=GroupResponse)
async def update_group(
    group_id: uuid.UUID, data: GroupUpdate, request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> GroupResponse:
    return await GroupService(db).update_group(_uid(request), group_id, data)


@router.delete("/{group_id}", status_code=204)
async def delete_group(
    group_id: uuid.UUID, request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> None:
    await GroupService(db).delete_group(_uid(request), group_id)


# ── Member Endpoints ─────────────────────────

@router.get("/{group_id}/members", response_model=GroupMemberListResponse)
async def list_members(
    group_id: uuid.UUID, request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> GroupMemberListResponse:
    return await GroupService(db).list_members(_uid(request), group_id)


@router.post("/{group_id}/members", response_model=GroupResponse)
async def add_members(
    group_id: uuid.UUID, data: MemberAddRequest, request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> GroupResponse:
    return await GroupService(db).add_members(
        _uid(request), group_id, data.user_ids, role_id=data.role_id,
    )


@router.put("/{group_id}/members/{target_user_id}/role", response_model=GroupMemberDetailResponse)
async def assign_member_role(
    group_id: uuid.UUID, target_user_id: uuid.UUID, data: MemberRoleUpdateRequest, request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> GroupMemberDetailResponse:
    return await GroupService(db).assign_member_role(
        _uid(request), group_id, target_user_id, data.role_id,
    )


@router.delete("/{group_id}/members/{target_user_id}", status_code=204)
async def remove_member(
    group_id: uuid.UUID, target_user_id: uuid.UUID, request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> None:
    await GroupService(db).remove_member(_uid(request), group_id, target_user_id)


@router.delete("/{group_id}/members", response_model=GroupResponse)
async def remove_members(
    group_id: uuid.UUID, data: MemberRemoveRequest, request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> GroupResponse:
    return await GroupService(db).remove_members(_uid(request), group_id, data.user_ids)


# ── Role Endpoints ───────────────────────────

@router.get("/{group_id}/roles", response_model=list[GroupRoleResponse])
async def list_roles(
    group_id: uuid.UUID, request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> list[GroupRoleResponse]:
    return await GroupService(db).list_roles(_uid(request), group_id)


@router.post("/{group_id}/roles", response_model=GroupRoleResponse, status_code=201)
async def create_role(
    group_id: uuid.UUID, data: GroupRoleCreate, request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> GroupRoleResponse:
    return await GroupService(db).create_role(_uid(request), group_id, data)


@router.put("/{group_id}/roles/reorder", response_model=list[GroupRoleResponse])
async def reorder_roles(
    group_id: uuid.UUID, data: GroupRoleReorderRequest, request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> list[GroupRoleResponse]:
    return await GroupService(db).reorder_roles(_uid(request), group_id, data)


@router.put("/{group_id}/roles/{role_id}", response_model=GroupRoleResponse)
async def update_role(
    group_id: uuid.UUID, role_id: uuid.UUID, data: GroupRoleUpdate, request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> GroupRoleResponse:
    return await GroupService(db).update_role(_uid(request), group_id, role_id, data)


@router.delete("/{group_id}/roles/{role_id}", status_code=204)
async def delete_role(
    group_id: uuid.UUID,
    role_id: uuid.UUID,
    request: Request,
    fallback_role_id: uuid.UUID | None = Query(default=None),
    db: AsyncSession = Depends(get_db_session),
) -> None:
    await GroupService(db).delete_role(_uid(request), group_id, role_id, fallback_role_id=fallback_role_id)


# ── Group Invite Management ───────────────────

@router.post("/{group_id}/invites", response_model=GroupInviteResponse, status_code=201)
async def create_invite_link(
    group_id: uuid.UUID,
    request: Request,
    data: GroupInviteCreate = GroupInviteCreate(),
    db: AsyncSession = Depends(get_db_session),
) -> GroupInviteResponse:
    """Generate a single-use expiring invite link token."""
    return await GroupService(db).create_invite_link(group_id, _uid(request), expires_hours=data.expires_hours)


@router.post("/{group_id}/invite-user", response_model=UserInviteResponse)
async def invite_user(
    group_id: uuid.UUID,
    data: UserInviteRequest,
    request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> UserInviteResponse:
    """Invite a specific user by @username or user ID with a notification containing Accept/Reject actions."""
    target = data.user_id if data.user_id else (data.username or "")
    return await GroupService(db).invite_user_by_handle_or_id(group_id, _uid(request), target, role_id=data.role_id)


@router.post("/{group_id}/invitations/respond")
async def respond_to_invitation(
    group_id: uuid.UUID,
    data: InviteRespondRequest,
    request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> dict:
    """Accept or reject a group invitation."""
    return await GroupService(db).respond_to_invitation(group_id, _uid(request), data.action, notification_id=data.notification_id)


# ── Super Admin Force Message Override ────────

@router.post("/{group_id}/force-message-override")
async def activate_force_message_override(
    group_id: uuid.UUID,
    request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> dict:
    """Super Admin activates a temporary 2-minute Force Message override on a non-member group."""
    return await GroupService(db).activate_force_message_override(_uid(request), group_id, duration_seconds=120)


@router.get("/{group_id}/force-message-override")
async def get_force_message_override(
    group_id: uuid.UUID,
    request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> dict:
    """Check remaining seconds on Super Admin Force Message override."""
    return await GroupService(db).get_force_message_override_status(_uid(request), group_id)

