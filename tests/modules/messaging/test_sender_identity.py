"""REST and websocket payloads share server-resolved sender identity."""

from connecthub.modules.messaging.schemas import MessageCreate


async def test_sender_identity_survives_message_and_conversation_operations(
    messaging_service, user_alice, user_bob, db_session,
):
    user_alice.avatar_url = "https://example.test/alice.png"
    conversation = await messaging_service.start_direct_message(user_alice.id, user_bob.id)
    sent = await messaging_service.send_message(
        user_alice.id, conversation.id, MessageCreate(content="Hello Bob"),
    )
    await db_session.commit()
    history = await messaging_service.get_messages(user_bob.id, conversation.id)
    edited = await messaging_service.update_message(user_alice.id, conversation.id, sent.id, "Hello!")
    pinned = await messaging_service.pin_message(user_alice.id, conversation.id, sent.id)
    pin_list = await messaging_service.list_pinned_messages(user_bob.id, conversation.id)
    unpinned = await messaging_service.unpin_message(user_alice.id, conversation.id, sent.id)
    detail = await messaging_service.get_conversation(user_bob.id, conversation.id)
    conversations = await messaging_service.get_conversations(user_bob.id)
    for message in [sent, history.items[0], edited, pinned, pin_list[0], unpinned,
                    detail.last_message, conversations.items[0].last_message]:
        data = message.model_dump(mode="json")
        assert data["sender_id"] == str(user_alice.id)
        assert data["sender_name"] == "Alice"
        assert data["sender_username"] == "alice"
        assert data["sender_avatar_url"] == "https://example.test/alice.png"
