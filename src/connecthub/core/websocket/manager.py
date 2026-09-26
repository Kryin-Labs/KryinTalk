"""
ConnectHub — WebSocket Connection Manager.

Tracks active WebSocket connections per user, supporting
multiple sessions (tabs/devices). Provides fan-out delivery
to individual users or groups of users.
"""

from __future__ import annotations

import logging
import uuid
from collections import defaultdict
from typing import Any

from fastapi import WebSocket

logger = logging.getLogger(__name__)


class ConnectionManager:
    """Manages active WebSocket connections.

    Each user can have multiple concurrent connections (e.g. multiple
    browser tabs, phone + desktop). Messages are delivered to ALL
    active sessions for a user.
    """

    def __init__(self) -> None:
        # user_id -> set of active websockets
        self._connections: dict[uuid.UUID, set[WebSocket]] = defaultdict(set)

    async def connect(self, user_id: uuid.UUID, websocket: WebSocket) -> None:
        """Accept and register a WebSocket connection."""
        await websocket.accept()
        self._connections[user_id].add(websocket)
        logger.info("WebSocket connected: user=%s (sessions=%d)",
                     user_id, len(self._connections[user_id]))

    def disconnect(self, user_id: uuid.UUID, websocket: WebSocket) -> None:
        """Remove a WebSocket connection."""
        self._connections[user_id].discard(websocket)
        if not self._connections[user_id]:
            del self._connections[user_id]
        logger.info("WebSocket disconnected: user=%s", user_id)

    def is_online(self, user_id: uuid.UUID) -> bool:
        """Check if a user has any active connections."""
        return user_id in self._connections and len(self._connections[user_id]) > 0

    def online_users(self) -> set[uuid.UUID]:
        """Return set of currently online user IDs."""
        return set(self._connections.keys())

    async def send_to_user(self, user_id: uuid.UUID, payload: dict[str, Any]) -> int:
        """Send a JSON payload to all sessions of a user.

        Returns the number of sessions the message was delivered to.
        """
        connections = self._connections.get(user_id, set())
        delivered = 0
        dead: list[WebSocket] = []

        for ws in connections:
            try:
                await ws.send_json(payload)
                delivered += 1
            except Exception:
                dead.append(ws)

        # Clean up dead connections
        for ws in dead:
            self._connections[user_id].discard(ws)
        if not self._connections.get(user_id):
            self._connections.pop(user_id, None)

        return delivered

    async def broadcast_to_users(
        self,
        user_ids: list[uuid.UUID],
        payload: dict[str, Any],
        exclude: uuid.UUID | None = None,
    ) -> int:
        """Send a JSON payload to all sessions of multiple users.

        Args:
            user_ids: Target user IDs.
            payload: JSON-serializable data.
            exclude: Optional user to skip (e.g. the sender).

        Returns total sessions delivered to.
        """
        total = 0
        for uid in user_ids:
            if uid == exclude:
                continue
            total += await self.send_to_user(uid, payload)
        return total

    @property
    def connection_count(self) -> int:
        """Total number of active WebSocket connections."""
        return sum(len(conns) for conns in self._connections.values())


# Singleton instance — shared across the application
ws_manager = ConnectionManager()
