"""
ConnectHub — Search Service Tests.

Message/file search, Section 5 participant filtering, soft-delete exclusion.
"""

from __future__ import annotations

import pytest

from connecthub.modules.messaging.schemas import MessageCreate
from connecthub.modules.search.schemas import SearchQuery
from connecthub.modules.search.service import SearchService


@pytest.mark.asyncio
async def test_search_messages_by_content(
    search_service, messaging_service, user_alice, user_bob, dm_alice_bob, db_session,
):
    """Search finds messages matching query content."""
    await messaging_service.send_message(
        user_alice.id, dm_alice_bob.id, MessageCreate(content="Hello world"),
    )
    await messaging_service.send_message(
        user_alice.id, dm_alice_bob.id, MessageCreate(content="Goodbye moon"),
    )
    await db_session.commit()

    result = await search_service.search(
        user_alice.id, SearchQuery(query="Hello"),
    )
    assert len(result.items) == 1
    assert result.items[0].result_type == "message"
    assert "Hello" in result.items[0].snippet


@pytest.mark.asyncio
async def test_search_files_by_filename(
    search_service, file_service, user_alice, dm_alice_bob, db_session,
):
    """Search finds files matching query in filename."""
    await file_service.upload_file(
        user_alice.id, dm_alice_bob.id,
        filename="project_report.pdf", content=b"report", content_type="application/pdf",
    )
    await file_service.upload_file(
        user_alice.id, dm_alice_bob.id,
        filename="photo.jpg", content=b"image", content_type="image/jpeg",
    )
    await db_session.commit()

    result = await search_service.search(
        user_alice.id, SearchQuery(query="report"),
    )
    assert len(result.items) == 1
    assert result.items[0].result_type == "file"
    assert "report" in result.items[0].title.lower()


@pytest.mark.asyncio
async def test_search_excludes_non_participant_conversations(
    search_service, messaging_service, user_alice, user_bob, user_charlie,
    dm_alice_bob, db_session,
):
    """Section 5: Charlie cannot see messages in Alice-Bob conversation."""
    await messaging_service.send_message(
        user_alice.id, dm_alice_bob.id,
        MessageCreate(content="Secret project update"),
    )
    await db_session.commit()

    # Alice finds it
    alice_result = await search_service.search(
        user_alice.id, SearchQuery(query="Secret"),
    )
    assert len(alice_result.items) == 1

    # Charlie finds nothing (not a participant)
    charlie_result = await search_service.search(
        user_charlie.id, SearchQuery(query="Secret"),
    )
    assert len(charlie_result.items) == 0
    assert charlie_result.total == 0


@pytest.mark.asyncio
async def test_search_excludes_non_participant_files(
    search_service, file_service, user_alice, user_charlie,
    dm_alice_bob, db_session,
):
    """Section 5: Charlie cannot see files in Alice-Bob conversation."""
    await file_service.upload_file(
        user_alice.id, dm_alice_bob.id,
        filename="confidential.pdf", content=b"secret", content_type="application/pdf",
    )
    await db_session.commit()

    charlie_result = await search_service.search(
        user_charlie.id, SearchQuery(query="confidential"),
    )
    assert len(charlie_result.items) == 0


@pytest.mark.asyncio
async def test_search_empty_for_no_conversations(
    search_service, user_charlie, db_session,
):
    """User with no conversations gets empty results."""
    await db_session.commit()
    result = await search_service.search(
        user_charlie.id, SearchQuery(query="anything"),
    )
    assert len(result.items) == 0
    assert result.total == 0


@pytest.mark.asyncio
async def test_search_respects_soft_deleted_messages(
    search_service, messaging_service, user_alice, dm_alice_bob, db_session,
):
    """Soft-deleted messages excluded from search results."""
    from connecthub.modules.messaging.repository import MessagingRepository

    msg = await messaging_service.send_message(
        user_alice.id, dm_alice_bob.id,
        MessageCreate(content="Delete me later"),
    )
    await db_session.commit()

    # Should find it
    result = await search_service.search(
        user_alice.id, SearchQuery(query="Delete me"),
    )
    assert len(result.items) == 1

    # Soft delete
    repo = MessagingRepository(db_session)
    await repo.soft_delete_message(msg.id)
    await db_session.commit()

    # Should NOT find it
    result = await search_service.search(
        user_alice.id, SearchQuery(query="Delete me"),
    )
    assert len(result.items) == 0


@pytest.mark.asyncio
async def test_search_messages_only_filter(
    search_service, messaging_service, file_service,
    user_alice, dm_alice_bob, db_session,
):
    """Can filter to search only messages (not files)."""
    await messaging_service.send_message(
        user_alice.id, dm_alice_bob.id,
        MessageCreate(content="Important update"),
    )
    await file_service.upload_file(
        user_alice.id, dm_alice_bob.id,
        filename="important.pdf", content=b"data",
    )
    await db_session.commit()

    result = await search_service.search(
        user_alice.id,
        SearchQuery(query="important", search_messages=True, search_files=False),
    )
    assert all(r.result_type == "message" for r in result.items)
