"""
ConnectHub — Notification Service Tests.

CRUD, read state, unread count, Section 5 ownership.
"""

from __future__ import annotations

import pytest

from connecthub.core.exceptions import NotFoundError
from connecthub.modules.notifications.models import NotificationType
from connecthub.modules.notifications.service import NotificationService


@pytest.mark.asyncio
async def test_create_notification(
    notification_service, user_alice, db_session,
):
    await db_session.commit()
    notif = await notification_service.create_notification(
        user_id=user_alice.id,
        notification_type=NotificationType.MESSAGE,
        title="New message from Bob",
        body="Hey Alice, how are you?",
    )
    await db_session.commit()
    assert notif.title == "New message from Bob"
    assert notif.is_read is False


@pytest.mark.asyncio
async def test_list_own_notifications(
    notification_service, user_alice, user_bob, db_session,
):
    """Each user only sees their own notifications."""
    await db_session.commit()
    await notification_service.create_notification(
        user_id=user_alice.id,
        notification_type=NotificationType.MESSAGE,
        title="For Alice",
    )
    await notification_service.create_notification(
        user_id=user_bob.id,
        notification_type=NotificationType.MESSAGE,
        title="For Bob",
    )
    await db_session.commit()

    alice_result = await notification_service.list_notifications(user_alice.id)
    assert len(alice_result.items) == 1
    assert alice_result.items[0].title == "For Alice"

    bob_result = await notification_service.list_notifications(user_bob.id)
    assert len(bob_result.items) == 1
    assert bob_result.items[0].title == "For Bob"


@pytest.mark.asyncio
async def test_mark_read(
    notification_service, user_alice, db_session,
):
    await db_session.commit()
    notif = await notification_service.create_notification(
        user_id=user_alice.id,
        notification_type=NotificationType.SYSTEM,
        title="System update",
    )
    await db_session.commit()
    assert notif.is_read is False

    await notification_service.mark_read(user_alice.id, notif.id)
    await db_session.commit()

    result = await notification_service.list_notifications(user_alice.id)
    assert result.items[0].is_read is True


@pytest.mark.asyncio
async def test_mark_all_read(
    notification_service, user_alice, db_session,
):
    await db_session.commit()
    for i in range(3):
        await notification_service.create_notification(
            user_id=user_alice.id,
            notification_type=NotificationType.MESSAGE,
            title=f"Msg {i}",
        )
    await db_session.commit()

    count = await notification_service.get_unread_count(user_alice.id)
    assert count.count == 3

    marked = await notification_service.mark_all_read(user_alice.id)
    await db_session.commit()
    assert marked == 3

    count = await notification_service.get_unread_count(user_alice.id)
    assert count.count == 0


@pytest.mark.asyncio
async def test_unread_count(
    notification_service, user_alice, db_session,
):
    await db_session.commit()
    n1 = await notification_service.create_notification(
        user_id=user_alice.id,
        notification_type=NotificationType.MESSAGE,
        title="Unread 1",
    )
    await notification_service.create_notification(
        user_id=user_alice.id,
        notification_type=NotificationType.FILE,
        title="Unread 2",
    )
    await db_session.commit()

    count = await notification_service.get_unread_count(user_alice.id)
    assert count.count == 2

    await notification_service.mark_read(user_alice.id, n1.id)
    await db_session.commit()

    count = await notification_service.get_unread_count(user_alice.id)
    assert count.count == 1


@pytest.mark.asyncio
async def test_cannot_read_other_users_notification(
    notification_service, user_alice, user_bob, db_session,
):
    """Section 5: User cannot mark another user's notification as read."""
    await db_session.commit()
    notif = await notification_service.create_notification(
        user_id=user_alice.id,
        notification_type=NotificationType.MESSAGE,
        title="Private",
    )
    await db_session.commit()

    with pytest.raises(NotFoundError):
        await notification_service.mark_read(user_bob.id, notif.id)
