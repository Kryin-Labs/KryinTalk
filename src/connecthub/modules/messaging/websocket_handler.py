"""
ConnectHub Messaging Module — WebSocket Handler.

Authenticated WebSocket endpoint for real-time messaging.
JWT token passed as query parameter for authentication.
"""

from __future__ import annotations

import json
import logging
import uuid

from fastapi import APIRouter, Depends, Query, WebSocket, WebSocketDisconnect
from sqlalchemy.ext.asyncio import AsyncSession

from connecthub.core.database.session import get_db_session
from connecthub.core.security.jwt import verify_token
from connecthub.core.websocket.manager import ws_manager
from connecthub.modules.messaging.schemas import MessageCreate
from connecthub.modules.messaging.service import MessagingService

logger = logging.getLogger(__name__)

ws_router = APIRouter()


async def _authenticate_ws(token: str) -> uuid.UUID | None:
    """Authenticate a WebSocket connection via JWT token."""
    payload = verify_token(token)
    if payload is None:
        return None
    user_id = payload.get("sub")
    if user_id is None:
        return None
    try:
        return uuid.UUID(user_id)
    except (ValueError, TypeError):
        return None


@ws_router.websocket("/ws")
async def websocket_endpoint(
    websocket: WebSocket,
    token: str = Query(...),
) -> None:
    """WebSocket endpoint for real-time messaging.

    Authentication: JWT token as query parameter.

    Incoming events:
        {"type": "send_message", "conversation_id": "...", "content": "..."}
        {"type": "mark_read", "conversation_id": "..."}
        {"type": "typing", "conversation_id": "..."}

    Outgoing events:
        {"type": "new_message", "message": {...}}
        {"type": "typing", "conversation_id": "...", "user_id": "..."}
        {"type": "error", "detail": "..."}
    """
    # Authenticate
    user_id = await _authenticate_ws(token)
    if user_id is None:
        await websocket.close(code=4001, reason="Authentication failed")
        return

    # Connect
    await ws_manager.connect(user_id, websocket)

    try:
        while True:
            raw = await websocket.receive_text()
            try:
                data = json.loads(raw)
            except json.JSONDecodeError:
                await websocket.send_json(
                    {"type": "error", "detail": "Invalid JSON"},
                )
                continue

            event_type = data.get("type")

            if event_type == "send_message":
                await _handle_send_message(user_id, data, websocket)
            elif event_type == "mark_read":
                await _handle_mark_read(user_id, data, websocket)
            elif event_type == "typing":
                await _handle_typing(user_id, data)
            else:
                await websocket.send_json(
                    {"type": "error", "detail": f"Unknown event type: {event_type}"},
                )

    except WebSocketDisconnect:
        ws_manager.disconnect(user_id, websocket)
    except Exception:
        logger.exception("WebSocket error for user %s", user_id)
        ws_manager.disconnect(user_id, websocket)


async def _handle_send_message(
    user_id: uuid.UUID,
    data: dict,
    websocket: WebSocket,
) -> None:
    """Handle a send_message event."""
    from connecthub.core.database.session import get_session_factory

    conversation_id_str = data.get("conversation_id")
    content = data.get("content")

    if not conversation_id_str or not content:
        await websocket.send_json(
            {"type": "error", "detail": "Missing conversation_id or content"},
        )
        return

    try:
        conversation_id = uuid.UUID(conversation_id_str)
    except ValueError:
        await websocket.send_json(
            {"type": "error", "detail": "Invalid conversation_id"},
        )
        return

    # Use a fresh session for the operation
    session_factory = get_session_factory()
    if session_factory is None:
        await websocket.send_json(
            {"type": "error", "detail": "Database not available"},
        )
        return

    async with session_factory() as session:
        service = MessagingService(session)
        try:
            msg = await service.send_message(
                user_id=user_id,
                conversation_id=conversation_id,
                data=MessageCreate(content=content),
            )
            await session.commit()

            # Fan out to participants
            participant_ids = await service.get_participant_ids(conversation_id)
            payload = {
                "type": "new_message",
                "message": msg.model_dump(mode="json"),
            }
            await ws_manager.broadcast_to_users(participant_ids, payload)

        except Exception as e:
            await session.rollback()
            await websocket.send_json(
                {"type": "error", "detail": str(e)},
            )


async def _handle_mark_read(
    user_id: uuid.UUID,
    data: dict,
    websocket: WebSocket,
) -> None:
    """Handle a mark_read event."""
    from connecthub.core.database.session import get_session_factory

    conversation_id_str = data.get("conversation_id")
    if not conversation_id_str:
        return

    try:
        conversation_id = uuid.UUID(conversation_id_str)
    except ValueError:
        return

    session_factory = get_session_factory()
    if session_factory is None:
        return

    async with session_factory() as session:
        service = MessagingService(session)
        try:
            await service.mark_read(user_id, conversation_id)
            await session.commit()
        except Exception:
            await session.rollback()


async def _handle_typing(user_id: uuid.UUID, data: dict) -> None:
    """Handle a typing indicator event — fan out to participants."""
    from connecthub.core.database.session import get_session_factory

    conversation_id_str = data.get("conversation_id")
    if not conversation_id_str:
        return

    try:
        conversation_id = uuid.UUID(conversation_id_str)
    except ValueError:
        return

    session_factory = get_session_factory()
    if session_factory is None:
        return

    async with session_factory() as session:
        service = MessagingService(session)
        participant_ids = await service.get_participant_ids(conversation_id)
        payload = {
            "type": "typing",
            "conversation_id": str(conversation_id),
            "user_id": str(user_id),
        }
        await ws_manager.broadcast_to_users(participant_ids, payload, exclude=user_id)
