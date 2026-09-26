"""
ConnectHub — Unread Count, Mention Alerts, Read Receipts, and Notification Sync Tests.
"""

from __future__ import annotations

import pytest

from connecthub.modules.messaging.schemas import MessageCreate
from connecthub.modules.notifications.service import NotificationService


@pytest.mark.asyncio
async def test_dm_notification_and_unread_count(
    messaging_service, user_alice, user_bob, db_session,
):
    await db_session.commit()
    # 1. Start DM
    conv = await messaging_service.start_direct_message(user_alice.id, user_bob.id)
    await db_session.commit()

    # Alice sends message to Bob
    msg1 = await messaging_service.send_message(
        user_alice.id, conv.id, MessageCreate(content="Hello Bob!"),
    )
    await db_session.commit()

    # Bob's unread count for the conversation should be 1
    bob_conv = await messaging_service.get_conversation(user_bob.id, conv.id)
    assert bob_conv.unread_count == 1

    # Bob should have received a notification
    notif_service = NotificationService(db_session)
    bob_notifs = await notif_service.list_notifications(user_bob.id)
    assert len(bob_notifs.items) >= 1
    assert "New message from Alice" in bob_notifs.items[0].title

    # Alice (the sender) unread count should be 0
    alice_conv = await messaging_service.get_conversation(user_alice.id, conv.id)
    assert alice_conv.unread_count == 0


@pytest.mark.asyncio
async def test_mention_notification_created(
    messaging_service, user_alice, user_bob, db_session,
):
    await db_session.commit()
    conv = await messaging_service.start_direct_message(user_alice.id, user_bob.id)
    await db_session.commit()

    # Alice tags @bob
    await messaging_service.send_message(
        user_alice.id, conv.id, MessageCreate(content="Hey @bob please review this PR"),
    )
    await db_session.commit()

    notif_service = NotificationService(db_session)
    bob_notifs = await notif_service.list_notifications(user_bob.id)
    titles = [n.title for n in bob_notifs.items]
    assert any("mentioned by @alice" in t for t in titles)


@pytest.mark.asyncio
async def test_mark_read_and_seen_receipt(
    messaging_service, user_alice, user_bob, db_session,
):
    await db_session.commit()
    conv = await messaging_service.start_direct_message(user_alice.id, user_bob.id)
    await db_session.commit()

    # Alice sends message
    await messaging_service.send_message(
        user_alice.id, conv.id, MessageCreate(content="Check this seen state"),
    )
    await db_session.commit()

    # Before Bob reads: Alice checks messages -> is_seen should be False
    alice_msgs_before = await messaging_service.get_messages(user_alice.id, conv.id)
    assert alice_msgs_before.items[0].is_seen is False

    # Bob marks conversation as read
    await messaging_service.mark_read(user_bob.id, conv.id)
    await db_session.commit()

    # Bob's unread count should now be 0
    bob_conv = await messaging_service.get_conversation(user_bob.id, conv.id)
    assert bob_conv.unread_count == 0

    # Bob's conversation notifications should be marked read
    notif_service = NotificationService(db_session)
    bob_unread_notifs = await notif_service.get_unread_count(user_bob.id)
    assert bob_unread_notifs.count == 0

    # Now Alice checks messages -> is_seen should be True (double blue ticks!)
    alice_msgs_after = await messaging_service.get_messages(user_alice.id, conv.id)
    assert alice_msgs_after.items[0].is_seen is True


@pytest.mark.asyncio
async def test_mark_unread(
    messaging_service, user_alice, user_bob, db_session,
):
    await db_session.commit()
    conv = await messaging_service.start_direct_message(user_alice.id, user_bob.id)
    await db_session.commit()

    await messaging_service.send_message(
        user_alice.id, conv.id, MessageCreate(content="Unread test"),
    )
    await db_session.commit()

    # Bob reads
    await messaging_service.mark_read(user_bob.id, conv.id)
    await db_session.commit()
    assert (await messaging_service.get_conversation(user_bob.id, conv.id)).unread_count == 0

    # Bob marks conversation as unread
    await messaging_service.mark_unread(user_bob.id, conv.id)
    await db_session.commit()
    assert (await messaging_service.get_conversation(user_bob.id, conv.id)).unread_count == 1
