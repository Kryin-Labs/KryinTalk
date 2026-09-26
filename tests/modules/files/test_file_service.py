"""
ConnectHub — File Service Tests.

Upload, download, metadata, listing, Section 5 access, size limits, audit.
"""

from __future__ import annotations

import pytest

from connecthub.core.exceptions import NotFoundError, ValidationError
from connecthub.modules.files.service import FileService


# ── Upload ───────────────────────────────────

@pytest.mark.asyncio
async def test_upload_file(file_service, user_alice, dm_conversation, db_session):
    """Upload stores file on disk and metadata in DB."""
    result = await file_service.upload_file(
        user_id=user_alice.id,
        conversation_id=dm_conversation.id,
        filename="report.pdf",
        content=b"PDF content here",
        content_type="application/pdf",
    )
    await db_session.commit()
    assert result.original_filename == "report.pdf"
    assert result.content_type == "application/pdf"
    assert result.size_bytes == len(b"PDF content here")
    assert result.uploaded_by == user_alice.id


@pytest.mark.asyncio
async def test_upload_empty_file_rejected(
    file_service, user_alice, dm_conversation, db_session,
):
    """Empty files are rejected."""
    with pytest.raises(ValidationError):
        await file_service.upload_file(
            user_id=user_alice.id,
            conversation_id=dm_conversation.id,
            filename="empty.txt",
            content=b"",
        )


@pytest.mark.asyncio
async def test_upload_oversized_file_rejected(
    file_service, user_alice, dm_conversation, db_session,
):
    """Files exceeding max size are rejected (fixture set to 1MB)."""
    big_content = b"x" * (1024 * 1024 + 1)
    with pytest.raises(ValidationError, match="too large"):
        await file_service.upload_file(
            user_id=user_alice.id,
            conversation_id=dm_conversation.id,
            filename="huge.bin",
            content=big_content,
        )


# ── Download ─────────────────────────────────

@pytest.mark.asyncio
async def test_download_file(file_service, user_alice, dm_conversation, db_session):
    """Downloaded content matches uploaded content."""
    original = b"Hello, this is a test file content!"
    upload = await file_service.upload_file(
        user_id=user_alice.id,
        conversation_id=dm_conversation.id,
        filename="hello.txt",
        content=original,
        content_type="text/plain",
    )
    await db_session.commit()

    content, filename, content_type = await file_service.download_file(
        user_alice.id, upload.id,
    )
    assert content == original
    assert filename == "hello.txt"
    assert content_type == "text/plain"


@pytest.mark.asyncio
async def test_download_by_other_participant(
    file_service, user_alice, user_bob, dm_conversation, db_session,
):
    """Bob (participant) can download Alice's file."""
    upload = await file_service.upload_file(
        user_id=user_alice.id,
        conversation_id=dm_conversation.id,
        filename="shared.txt",
        content=b"Shared content",
    )
    await db_session.commit()

    content, _, _ = await file_service.download_file(user_bob.id, upload.id)
    assert content == b"Shared content"


# ── File Info ────────────────────────────────

@pytest.mark.asyncio
async def test_get_file_info(file_service, user_alice, dm_conversation, db_session):
    upload = await file_service.upload_file(
        user_id=user_alice.id,
        conversation_id=dm_conversation.id,
        filename="info.txt",
        content=b"content",
    )
    await db_session.commit()

    info = await file_service.get_file_info(user_alice.id, upload.id)
    assert info.original_filename == "info.txt"
    assert info.size_bytes == 7


# ── List Files ───────────────────────────────

@pytest.mark.asyncio
async def test_list_files_in_conversation(
    file_service, user_alice, dm_conversation, db_session,
):
    for i in range(3):
        await file_service.upload_file(
            user_id=user_alice.id,
            conversation_id=dm_conversation.id,
            filename=f"file{i}.txt",
            content=f"content {i}".encode(),
        )
    await db_session.commit()

    result = await file_service.list_files(user_alice.id, dm_conversation.id)
    assert len(result.items) == 3
    assert result.total == 3


# ── Soft Delete ──────────────────────────────

@pytest.mark.asyncio
async def test_delete_file_soft(
    file_service, user_alice, dm_conversation, db_session,
):
    upload = await file_service.upload_file(
        user_id=user_alice.id,
        conversation_id=dm_conversation.id,
        filename="temp.txt",
        content=b"temporary",
    )
    await db_session.commit()

    await file_service.delete_file(user_alice.id, upload.id)
    await db_session.commit()

    # Deleted file not found
    with pytest.raises(NotFoundError):
        await file_service.get_file_info(user_alice.id, upload.id)


@pytest.mark.asyncio
async def test_delete_by_non_uploader_denied(
    file_service, user_alice, user_bob, dm_conversation, db_session,
):
    """Only the uploader can delete a file."""
    upload = await file_service.upload_file(
        user_id=user_alice.id,
        conversation_id=dm_conversation.id,
        filename="mine.txt",
        content=b"mine",
    )
    await db_session.commit()

    # Bob is a participant but NOT the uploader
    with pytest.raises(NotFoundError):
        await file_service.delete_file(user_bob.id, upload.id)


# ── Section 5 Visibility ────────────────────

@pytest.mark.asyncio
async def test_non_participant_cannot_download(
    file_service, user_alice, user_charlie, dm_conversation, db_session,
):
    """Non-participant gets 404 on download (Section 5)."""
    upload = await file_service.upload_file(
        user_id=user_alice.id,
        conversation_id=dm_conversation.id,
        filename="secret.txt",
        content=b"secret",
    )
    await db_session.commit()

    with pytest.raises(NotFoundError):
        await file_service.download_file(user_charlie.id, upload.id)


@pytest.mark.asyncio
async def test_non_participant_cannot_get_info(
    file_service, user_alice, user_charlie, dm_conversation, db_session,
):
    """Non-participant gets 404 on file metadata (Section 5)."""
    upload = await file_service.upload_file(
        user_id=user_alice.id,
        conversation_id=dm_conversation.id,
        filename="hidden.txt",
        content=b"hidden",
    )
    await db_session.commit()

    with pytest.raises(NotFoundError):
        await file_service.get_file_info(user_charlie.id, upload.id)


@pytest.mark.asyncio
async def test_non_participant_cannot_list_files(
    file_service, user_alice, user_charlie, dm_conversation, db_session,
):
    """Non-participant gets 404 on file listing (Section 5)."""
    await file_service.upload_file(
        user_id=user_alice.id,
        conversation_id=dm_conversation.id,
        filename="visible.txt",
        content=b"visible",
    )
    await db_session.commit()

    with pytest.raises(NotFoundError):
        await file_service.list_files(user_charlie.id, dm_conversation.id)


@pytest.mark.asyncio
async def test_non_participant_cannot_upload(
    file_service, user_charlie, dm_conversation, db_session,
):
    """Non-participant gets 404 on upload (Section 5)."""
    with pytest.raises(NotFoundError):
        await file_service.upload_file(
            user_id=user_charlie.id,
            conversation_id=dm_conversation.id,
            filename="intruder.txt",
            content=b"intruder",
        )


# ── Audit ────────────────────────────────────

@pytest.mark.asyncio
async def test_file_operations_audited(
    file_service, audit_service, user_alice, dm_conversation, db_session,
):
    """Upload and delete create audit logs."""
    upload = await file_service.upload_file(
        user_id=user_alice.id,
        conversation_id=dm_conversation.id,
        filename="audited.txt",
        content=b"audited",
    )
    await db_session.commit()
    await file_service.delete_file(user_alice.id, upload.id)
    await db_session.commit()

    logs = await audit_service.query(user_id=user_alice.id)
    actions = [l.action for l in logs]
    assert "file.uploaded" in actions
    assert "file.deleted" in actions
