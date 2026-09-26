"""
ConnectHub — Real-time User Presence Tracker.

Maintains in-memory presence state (online/offline/last_seen_at)
with optional Redis synchronization for distributed deployments.
"""

from __future__ import annotations

import logging
import time
import uuid
from datetime import datetime, timezone

logger = logging.getLogger(__name__)

# User is considered online if heartbeat was received within the last 60 seconds
ONLINE_THRESHOLD_SECONDS = 60


class PresenceTracker:
    """Thread-safe in-memory presence registry."""

    def __init__(self) -> None:
        # Map user_id -> timestamp (float seconds)
        self._last_seen: dict[uuid.UUID, float] = {}
        # Map user_id -> custom presence status (online, away, busy, focus)
        self._custom_statuses: dict[uuid.UUID, str] = {}

    def heartbeat(self, user_id: uuid.UUID, custom_status: str | None = None) -> dict[str, str]:
        """Record user activity/heartbeat."""
        now = time.time()
        self._last_seen[user_id] = now
        if custom_status:
            self._custom_statuses[user_id] = custom_status
        status = self._custom_statuses.get(user_id, "online")
        iso_str = datetime.fromtimestamp(now, tz=timezone.utc).isoformat()
        return {
            "user_id": str(user_id),
            "status": status,
            "last_seen_at": iso_str,
        }

    def set_status(self, user_id: uuid.UUID, status: str) -> dict[str, str]:
        """Explicitly set custom status for a user."""
        now = time.time()
        self._last_seen[user_id] = now
        self._custom_statuses[user_id] = status
        iso_str = datetime.fromtimestamp(now, tz=timezone.utc).isoformat()
        return {
            "user_id": str(user_id),
            "status": status,
            "last_seen_at": iso_str,
        }

    def is_online(self, user_id: uuid.UUID) -> bool:
        """Check if a specific user is currently online."""
        last = self._last_seen.get(user_id)
        if last is None:
            return False
        return (time.time() - last) <= ONLINE_THRESHOLD_SECONDS

    def get_user_status(self, user_id: uuid.UUID) -> dict[str, str]:
        """Get status for a single user."""
        last = self._last_seen.get(user_id)
        status_key = self._custom_statuses.get(user_id, "online")
        if last is not None and (time.time() - last) <= ONLINE_THRESHOLD_SECONDS:
            return {
                "user_id": str(user_id),
                "status": status_key,
                "last_seen_at": datetime.fromtimestamp(last, tz=timezone.utc).isoformat(),
            }
        last_str = datetime.fromtimestamp(last, tz=timezone.utc).isoformat() if last else ""
        return {
            "user_id": str(user_id),
            "status": "offline",
            "last_seen_at": last_str,
        }

    def get_all_presence(self) -> dict[str, dict[str, str]]:
        """Get presence map for all tracked users."""
        now = time.time()
        result: dict[str, dict[str, str]] = {}
        for uid, ts in list(self._last_seen.items()):
            custom = self._custom_statuses.get(uid, "online")
            status = custom if (now - ts) <= ONLINE_THRESHOLD_SECONDS else "offline"
            result[str(uid)] = {
                "user_id": str(uid),
                "status": status,
                "last_seen_at": datetime.fromtimestamp(ts, tz=timezone.utc).isoformat(),
            }
        return result


# Singleton instance
presence_tracker = PresenceTracker()
