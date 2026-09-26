"""
ConnectHub — Presence Tracker Unit & Integration Tests.
"""

from __future__ import annotations

import uuid
from connecthub.core.presence.tracker import PresenceTracker


def test_presence_tracker_lifecycle():
    tracker = PresenceTracker()
    uid = uuid.uuid4()

    assert tracker.is_online(uid) is False
    status = tracker.get_user_status(uid)
    assert status["status"] == "offline"

    hb = tracker.heartbeat(uid)
    assert hb["status"] == "online"
    assert tracker.is_online(uid) is True

    status = tracker.get_user_status(uid)
    assert status["status"] == "online"
    assert status["last_seen_at"] != ""

    all_presence = tracker.get_all_presence()
    assert str(uid) in all_presence
    assert all_presence[str(uid)]["status"] == "online"
