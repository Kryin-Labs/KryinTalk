"""
ConnectHub File Module — Data Access Layer.
"""

from __future__ import annotations

import uuid

from sqlalchemy import and_, select, func as sqlfunc
from sqlalchemy.ext.asyncio import AsyncSession

from connecthub.modules.files.models import FileAttachment


class FileRepository:
    """Data access for file attachment metadata."""

    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def create(self, **kwargs) -> FileAttachment:
        attachment = FileAttachment(**kwargs)
        self._session.add(attachment)
        await self._session.flush()
        return attachment

    async def get_by_id(self, file_id: uuid.UUID) -> FileAttachment | None:
        stmt = select(FileAttachment).where(
            and_(
                FileAttachment.id == file_id,
                FileAttachment.deleted_at.is_(None),
            ),
        )
        result = await self._session.execute(stmt)
        return result.scalar_one_or_none()

    async def list_by_conversation(
        self,
        conversation_id: uuid.UUID,
        limit: int = 50,
        offset: int = 0,
    ) -> list[FileAttachment]:
        stmt = (
            select(FileAttachment)
            .where(
                and_(
                    FileAttachment.conversation_id == conversation_id,
                    FileAttachment.deleted_at.is_(None),
                ),
            )
            .order_by(FileAttachment.created_at.desc())
            .limit(limit)
            .offset(offset)
        )
        result = await self._session.execute(stmt)
        return list(result.scalars().all())

    async def count_by_conversation(
        self, conversation_id: uuid.UUID,
    ) -> int:
        stmt = select(sqlfunc.count(FileAttachment.id)).where(
            and_(
                FileAttachment.conversation_id == conversation_id,
                FileAttachment.deleted_at.is_(None),
            ),
        )
        result = await self._session.execute(stmt)
        return result.scalar_one()

    async def soft_delete(self, file_id: uuid.UUID) -> FileAttachment | None:
        from datetime import datetime, timezone

        attachment = await self.get_by_id(file_id)
        if attachment:
            attachment.deleted_at = datetime.now(timezone.utc)
        return attachment
