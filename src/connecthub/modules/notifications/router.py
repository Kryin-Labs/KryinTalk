"""
ConnectHub Notification Module — REST Endpoints.

Routes:
    GET  /notifications              — List user's notifications
    GET  /notifications/unread-count — Badge count
    PUT  /notifications/{id}/read    — Mark single as read
    PUT  /notifications/read-all     — Mark all as read
"""

from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, Query, Request
from sqlalchemy.ext.asyncio import AsyncSession

from connecthub.core.database.session import get_db_session
from connecthub.modules.notifications.models import NotificationType
from connecthub.modules.notifications.schemas import (
    NotificationCreate,
    NotificationListResponse,
    NotificationResponse,
    UnreadCountResponse,
)
from connecthub.modules.notifications.service import NotificationService

router = APIRouter()


def _uid(request: Request) -> uuid.UUID:
    return request.state.user_id


@router.post("", response_model=NotificationResponse, status_code=201)
async def create_notification(
    data: NotificationCreate,
    request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> NotificationResponse:
    target_user = data.user_id or _uid(request)
    return await NotificationService(db).create_notification(
        user_id=target_user,
        notification_type=data.notification_type,
        title=data.title,
        body=data.body,
        resource_type=data.resource_type,
        resource_id=data.resource_id,
        conversation_id=data.conversation_id,
    )


@router.get("", response_model=NotificationListResponse)
async def list_notifications(
    request: Request,
    type: NotificationType | None = Query(default=None),
    unread_only: bool = Query(default=False),
    limit: int = Query(default=50, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    db: AsyncSession = Depends(get_db_session),
) -> NotificationListResponse:
    return await NotificationService(db).list_notifications(
        _uid(request), limit=limit, offset=offset, notification_type=type, unread_only=unread_only,
    )


@router.get("/unread-count", response_model=UnreadCountResponse)
async def get_unread_count(
    request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> UnreadCountResponse:
    return await NotificationService(db).get_unread_count(_uid(request))


@router.put("/{notification_id}/read", status_code=204)
@router.post("/{notification_id}/read", status_code=204)
async def mark_read(
    notification_id: uuid.UUID,
    request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> None:
    await NotificationService(db).mark_read(_uid(request), notification_id)


@router.put("/conversation/{conversation_id}/read", status_code=204)
@router.post("/conversation/{conversation_id}/read", status_code=204)
async def mark_conversation_read(
    conversation_id: uuid.UUID,
    request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> None:
    await NotificationService(db).mark_conversation_read(_uid(request), conversation_id)


@router.put("/read-all", status_code=204)
@router.post("/read-all", status_code=204)
async def mark_all_read(
    request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> None:
    await NotificationService(db).mark_all_read(_uid(request))

