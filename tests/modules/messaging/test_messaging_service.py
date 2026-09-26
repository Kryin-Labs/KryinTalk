"""
ConnectHub — Messaging Service Tests.

DM conversations, message send/persist, history, permissions, read receipts.
"""

from __future__ import annotations

import pytest

from connecthub.core.exceptions import NotFoundError
from connecthub.modules.messaging.models import ConversationType
from connecthub.modules.messaging.schemas import MessageCreate
from connecthub.modules.messaging.service import MessagingService


# ── DM Conversations ────────────────────────

@pytest.mark.asyncio
async def test_start_dm_creates_conversation(
    messaging_service, user_alice, user_bob, db_session,
):
    """Starting a DM creates a conversation with both users as participants."""
    await db_session.commit()
    conv = await messaging_service.start_direct_message(
        user_alice.id, user_bob.id,
    )
    await db_session.commit()
    assert conv.conversation_type == ConversationType.DIRECT
    assert conv.participant_count == 2


@pytest.mark.asyncio
async def test_start_dm_idempotent(
    messaging_service, user_alice, user_bob, db_session,
):
    """Starting a DM with the same user twice returns the same conversation."""
    await db_session.commit()
    conv1 = await messaging_service.start_direct_message(
        user_alice.id, user_bob.id,
    )
    await db_session.commit()
    conv2 = await messaging_service.start_direct_message(
        user_alice.id, user_bob.id,
    )
    await db_session.commit()
    assert conv1.id == conv2.id


@pytest.mark.asyncio
async def test_start_dm_reverse_order_same_conversation(
    messaging_service, user_alice, user_bob, db_session,
):
    """DM(A→B) and DM(B→A) return the same conversation."""
    await db_session.commit()
    conv1 = await messaging_service.start_direct_message(
        user_alice.id, user_bob.id,
    )
    await db_session.commit()
    conv2 = await messaging_service.start_direct_message(
        user_bob.id, user_alice.id,
    )
    await db_session.commit()
    assert conv1.id == conv2.id


# ── Send Message ─────────────────────────────

@pytest.mark.asyncio
async def test_send_message_persists(
    messaging_service, user_alice, user_bob, db_session,
):
    """Sent message persists in PostgreSQL (system of record)."""
    await db_session.commit()
    conv = await messaging_service.start_direct_message(
        user_alice.id, user_bob.id,
    )
    await db_session.commit()
    msg = await messaging_service.send_message(
        user_alice.id, conv.id, MessageCreate(content="Hello Bob!"),
    )
    await db_session.commit()
    assert msg.content == "Hello Bob!"
    assert msg.sender_id == user_alice.id
    assert msg.conversation_id == conv.id


@pytest.mark.asyncio
async def test_send_multiple_messages(
    messaging_service, user_alice, user_bob, db_session,
):
    await db_session.commit()
    conv = await messaging_service.start_direct_message(
        user_alice.id, user_bob.id,
    )
    await db_session.commit()
    await messaging_service.send_message(
        user_alice.id, conv.id, MessageCreate(content="Hello"),
    )
    await messaging_service.send_message(
        user_bob.id, conv.id, MessageCreate(content="Hi back"),
    )
    await messaging_service.send_message(
        user_alice.id, conv.id, MessageCreate(content="How are you?"),
    )
    await db_session.commit()

    result = await messaging_service.get_messages(user_alice.id, conv.id)
    assert len(result.items) == 3


# ── Message History ──────────────────────────

@pytest.mark.asyncio
async def test_message_history_newest_first(
    messaging_service, user_alice, user_bob, db_session,
):
    """Messages returned newest first."""
    await db_session.commit()
    conv = await messaging_service.start_direct_message(
        user_alice.id, user_bob.id,
    )
    await db_session.commit()
    msg1 = await messaging_service.send_message(
        user_alice.id, conv.id, MessageCreate(content="First"),
    )
    msg2 = await messaging_service.send_message(
        user_alice.id, conv.id, MessageCreate(content="Second"),
    )
    await db_session.commit()

    result = await messaging_service.get_messages(user_alice.id, conv.id)
    assert result.items[0].content == "Second"
    assert result.items[1].content == "First"


@pytest.mark.asyncio
async def test_message_history_pagination(
    messaging_service, user_alice, user_bob, db_session,
):
    """History supports cursor-based pagination."""
    await db_session.commit()
    conv = await messaging_service.start_direct_message(
        user_alice.id, user_bob.id,
    )
    await db_session.commit()
    for i in range(5):
        await messaging_service.send_message(
            user_alice.id, conv.id, MessageCreate(content=f"Msg {i}"),
        )
    await db_session.commit()

    page1 = await messaging_service.get_messages(user_alice.id, conv.id, limit=3)
    assert len(page1.items) == 3
    assert page1.has_more is True

    page2 = await messaging_service.get_messages(
        user_alice.id, conv.id, limit=3, before_seq=page1.items[-1].sequence_num,
    )
    assert len(page2.items) == 2
    assert page2.has_more is False


# ── Permission (Section 5) ──────────────────

@pytest.mark.asyncio
async def test_non_participant_cannot_read_messages(
    messaging_service, user_alice, user_bob, user_charlie, db_session,
):
    """Non-participant gets 404 when reading messages (Section 5)."""
    await db_session.commit()
    conv = await messaging_service.start_direct_message(
        user_alice.id, user_bob.id,
    )
    await db_session.commit()
    await messaging_service.send_message(
        user_alice.id, conv.id, MessageCreate(content="Secret"),
    )
    await db_session.commit()

    # Charlie is NOT a participant
    with pytest.raises(NotFoundError):
        await messaging_service.get_messages(user_charlie.id, conv.id)


@pytest.mark.asyncio
async def test_non_participant_cannot_send_message(
    messaging_service, user_alice, user_bob, user_charlie, db_session,
):
    """Non-participant gets 404 when sending (Section 5)."""
    await db_session.commit()
    conv = await messaging_service.start_direct_message(
        user_alice.id, user_bob.id,
    )
    await db_session.commit()

    with pytest.raises(NotFoundError):
        await messaging_service.send_message(
            user_charlie.id, conv.id, MessageCreate(content="Intruder"),
        )


@pytest.mark.asyncio
async def test_non_participant_cannot_get_conversation(
    messaging_service, user_alice, user_bob, user_charlie, db_session,
):
    """Non-participant gets 404 on conversation detail (Section 5)."""
    await db_session.commit()
    conv = await messaging_service.start_direct_message(
        user_alice.id, user_bob.id,
    )
    await db_session.commit()

    with pytest.raises(NotFoundError):
        await messaging_service.get_conversation(user_charlie.id, conv.id)


# ── Conversations List ──────────────────────

@pytest.mark.asyncio
async def test_list_conversations_only_own(
    messaging_service, user_alice, user_bob, user_charlie, db_session,
):
    """User only sees conversations they participate in."""
    await db_session.commit()
    await messaging_service.start_direct_message(user_alice.id, user_bob.id)
    await db_session.commit()

    alice_convs = await messaging_service.get_conversations(user_alice.id)
    assert alice_convs.total == 1

    charlie_convs = await messaging_service.get_conversations(user_charlie.id)
    assert charlie_convs.total == 0


@pytest.mark.asyncio
async def test_conversation_includes_last_message(
    messaging_service, user_alice, user_bob, db_session,
):
    """Conversation list includes last message preview."""
    await db_session.commit()
    conv = await messaging_service.start_direct_message(
        user_alice.id, user_bob.id,
    )
    await db_session.commit()
    await messaging_service.send_message(
        user_alice.id, conv.id, MessageCreate(content="First"),
    )
    await messaging_service.send_message(
        user_bob.id, conv.id, MessageCreate(content="Latest"),
    )
    await db_session.commit()

    result = await messaging_service.get_conversations(user_alice.id)
    assert result.items[0].last_message is not None
    assert result.items[0].last_message.content == "Latest"


# ── Read Receipts ────────────────────────────

@pytest.mark.asyncio
async def test_mark_read(
    messaging_service, user_alice, user_bob, db_session,
):
    """Mark read updates last_read_at."""
    await db_session.commit()
    conv = await messaging_service.start_direct_message(
        user_alice.id, user_bob.id,
    )
    await db_session.commit()
    await messaging_service.send_message(
        user_bob.id, conv.id, MessageCreate(content="Ping"),
    )
    await db_session.commit()

    # Should not raise
    await messaging_service.mark_read(user_alice.id, conv.id)
    await db_session.commit()


@pytest.mark.asyncio
async def test_mark_read_non_participant_denied(
    messaging_service, user_alice, user_bob, user_charlie, db_session,
):
    """Non-participant cannot mark as read (Section 5)."""
    await db_session.commit()
    conv = await messaging_service.start_direct_message(
        user_alice.id, user_bob.id,
    )
    await db_session.commit()

    with pytest.raises(NotFoundError):
        await messaging_service.mark_read(user_charlie.id, conv.id)


# ── Message reactions ─────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_participant_can_toggle_own_reaction(
    messaging_service, user_alice, user_bob, db_session,
):
    """A participant can add and remove only their own reaction."""
    await db_session.commit()
    conversation = await messaging_service.start_direct_message(
        user_alice.id, user_bob.id,
    )
    message = await messaging_service.send_message(
        user_alice.id, conversation.id, MessageCreate(content="Ship it"),
    )
    await db_session.commit()

    added = await messaging_service.toggle_reaction(
        user_bob.id, conversation.id, message.id, "rocket",
    )
    await db_session.commit()

    assert added.emoji == "rocket"
    assert added.active is True
    assert added.count == 1

    history = await messaging_service.get_messages(user_bob.id, conversation.id)
    assert history.items[0].reactions[0].emoji == "rocket"
    assert history.items[0].reactions[0].count == 1
    assert history.items[0].reactions[0].reacted is True
    assert history.items[0].reactions[0].user_ids == [user_bob.id]

    removed = await messaging_service.toggle_reaction(
        user_bob.id, conversation.id, message.id, "rocket",
    )
    await db_session.commit()

    assert removed.emoji == "rocket"
    assert removed.active is False


# ── Pinned messages ───────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_pin_and_unpin_message(
    messaging_service, user_alice, user_bob, db_session,
):
    """A participant can pin, list, and unpin messages in a conversation."""
    await db_session.commit()
    conversation = await messaging_service.start_direct_message(
        user_alice.id, user_bob.id,
    )
    msg1 = await messaging_service.send_message(
        user_alice.id, conversation.id, MessageCreate(content="Important announcement"),
    )
    msg2 = await messaging_service.send_message(
        user_bob.id, conversation.id, MessageCreate(content="Normal message"),
    )
    await db_session.commit()

    # Pin msg1
    pinned = await messaging_service.pin_message(user_alice.id, conversation.id, msg1.id)
    await db_session.commit()
    assert pinned.is_pinned is True
    assert pinned.pinned_at is not None
    assert pinned.pinned_by == user_alice.id

    # List pins
    pins = await messaging_service.list_pinned_messages(user_bob.id, conversation.id)
    assert len(pins) == 1
    assert pins[0].id == msg1.id

    # Unpin msg1
    unpinned = await messaging_service.unpin_message(user_alice.id, conversation.id, msg1.id)
    await db_session.commit()
    assert unpinned.is_pinned is False

    pins_after = await messaging_service.list_pinned_messages(user_bob.id, conversation.id)
    assert len(pins_after) == 0
