"""
ConnectHub Search Module — Business Logic.

Search across messages and files, filtered to only conversations
where the requesting user is a participant (Section 5).

Non-participant conversations are excluded entirely — not masked.
"""

from __future__ import annotations

import logging
import uuid

from sqlalchemy import and_, select, func as sqlfunc
from sqlalchemy.ext.asyncio import AsyncSession

from connecthub.modules.files.models import FileAttachment
from connecthub.modules.messaging.models import (
    ConversationParticipant,
    Message,
)
from connecthub.modules.search.schemas import SearchQuery, SearchResponse, SearchResultItem

logger = logging.getLogger(__name__)


class SearchService:
    """Search service — participant-filtered (Section 5).

    All results are limited to conversations where the
    requesting user is a participant. Non-participant
    conversations are excluded entirely.
    """

    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def _get_participant_conversation_ids(
        self, user_id: uuid.UUID,
    ) -> list[uuid.UUID]:
        """Get all conversation IDs where user is a participant."""
        stmt = select(ConversationParticipant.conversation_id).where(
            ConversationParticipant.user_id == user_id,
        )
        result = await self._session.execute(stmt)
        return list(result.scalars().all())

    async def search(
        self, user_id: uuid.UUID, query: SearchQuery,
    ) -> SearchResponse:
        """Search messages and files.

        Results are filtered to only conversations where the user
        is a participant. Non-participant conversations are excluded
        entirely (Section 5 — zero metadata leakage).
        """
        # Get user's conversation IDs
        conv_ids = await self._get_participant_conversation_ids(user_id)

        if not conv_ids:
            return SearchResponse(items=[], total=0, query=query.query)

        # Filter to specific conversation if requested
        if query.conversation_id is not None:
            if query.conversation_id not in conv_ids:
                return SearchResponse(items=[], total=0, query=query.query)
            conv_ids = [query.conversation_id]

        results: list[SearchResultItem] = []
        total = 0

        search_term = f"%{query.query}%"

        # Search messages
        if query.search_messages:
            msg_items, msg_count = await self._search_messages(
                conv_ids, search_term, query.limit, query.offset,
            )
            results.extend(msg_items)
            total += msg_count

        # Search files
        if query.search_files:
            file_items, file_count = await self._search_files(
                conv_ids, search_term, query.limit, query.offset,
            )
            results.extend(file_items)
            total += file_count

        # Sort by created_at descending, limit
        results.sort(key=lambda r: r.created_at, reverse=True)
        results = results[:query.limit]

        return SearchResponse(items=results, total=total, query=query.query)

    async def _search_messages(
        self,
        conv_ids: list[uuid.UUID],
        search_term: str,
        limit: int,
        offset: int,
    ) -> tuple[list[SearchResultItem], int]:
        """Search messages by content."""
        base_filter = and_(
            Message.conversation_id.in_(conv_ids),
            Message.content.ilike(search_term),
            Message.deleted_at.is_(None),
        )

        # Count
        count_stmt = select(sqlfunc.count(Message.id)).where(base_filter)
        count_result = await self._session.execute(count_stmt)
        total = count_result.scalar_one()

        # Results
        stmt = (
            select(Message)
            .where(base_filter)
            .order_by(Message.created_at.desc())
            .limit(limit)
            .offset(offset)
        )
        result = await self._session.execute(stmt)
        messages = result.scalars().all()

        items = []
        for msg in messages:
            # Create a snippet (truncate content)
            snippet = msg.content[:200]
            if len(msg.content) > 200:
                snippet += "..."

            items.append(SearchResultItem(
                result_type="message",
                resource_id=msg.id,
                conversation_id=msg.conversation_id,
                title="Message",
                snippet=snippet,
                created_at=msg.created_at,
            ))

        return items, total

    async def _search_files(
        self,
        conv_ids: list[uuid.UUID],
        search_term: str,
        limit: int,
        offset: int,
    ) -> tuple[list[SearchResultItem], int]:
        """Search files by filename."""
        base_filter = and_(
            FileAttachment.conversation_id.in_(conv_ids),
            FileAttachment.original_filename.ilike(search_term),
            FileAttachment.deleted_at.is_(None),
        )

        # Count
        count_stmt = select(sqlfunc.count(FileAttachment.id)).where(base_filter)
        count_result = await self._session.execute(count_stmt)
        total = count_result.scalar_one()

        # Results
        stmt = (
            select(FileAttachment)
            .where(base_filter)
            .order_by(FileAttachment.created_at.desc())
            .limit(limit)
            .offset(offset)
        )
        result = await self._session.execute(stmt)
        files = result.scalars().all()

        items = []
        for f in files:
            items.append(SearchResultItem(
                result_type="file",
                resource_id=f.id,
                conversation_id=f.conversation_id,
                title=f.original_filename,
                snippet=f"{f.original_filename} ({f.content_type}, {f.size_bytes} bytes)",
                created_at=f.created_at,
            ))

        return items, total
