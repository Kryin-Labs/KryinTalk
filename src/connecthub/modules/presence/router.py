"""
ConnectHub Presence Module — REST Endpoints.

Routes:
    POST /presence/heartbeat  — Record heartbeat / mark current user online
    GET  /presence            — Get presence states for all users
    GET  /presence/{user_id}  — Get presence state for a specific user
"""

from __future__ import annotations

import uuid
from typing import Any

from fastapi import APIRouter, Request

from connecthub.core.presence.tracker import presence_tracker

router = APIRouter()


def _uid(request: Request) -> uuid.UUID:
    return request.state.user_id


from pydantic import BaseModel

class StatusUpdateRequest(BaseModel):
    status: str = "online"


@router.post("/heartbeat")
async def send_heartbeat(
    request: Request,
    data: StatusUpdateRequest | None = None,
) -> dict[str, Any]:
    """Record heartbeat for the authenticated user."""
    uid = _uid(request)
    custom_status = data.status if data else None
    return presence_tracker.heartbeat(uid, custom_status=custom_status)


@router.post("/status")
@router.put("/status")
async def update_status(
    data: StatusUpdateRequest,
    request: Request,
) -> dict[str, Any]:
    """Set custom presence status (online, away, busy, focus, offline)."""
    uid = _uid(request)
    return presence_tracker.set_status(uid, data.status)


@router.get("")
async def get_presence_map() -> dict[str, Any]:
    """Get real-time presence map for all users."""
    items = presence_tracker.get_all_presence()
    return {"users": items}


@router.get("/{user_id}")
async def get_user_presence(user_id: uuid.UUID) -> dict[str, Any]:
    """Get presence state for a single user."""
    return presence_tracker.get_user_status(user_id)
