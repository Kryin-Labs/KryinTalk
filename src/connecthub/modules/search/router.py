"""
ConnectHub Search Module — REST Endpoint.

Routes:
    GET /search — Unified search across messages and files
"""

from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, Query, Request
from sqlalchemy.ext.asyncio import AsyncSession

from connecthub.core.database.session import get_db_session
from connecthub.modules.search.schemas import SearchResponse
from connecthub.modules.search.service import SearchService

router = APIRouter()


def _uid(request: Request) -> uuid.UUID:
    return request.state.user_id


@router.get("", response_model=SearchResponse)
async def search(
    request: Request,
    q: str = Query(..., min_length=1, max_length=500),
    conversation_id: uuid.UUID | None = Query(default=None),
    search_messages: bool = Query(default=True),
    search_files: bool = Query(default=True),
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    db: AsyncSession = Depends(get_db_session),
) -> SearchResponse:
    from connecthub.modules.search.schemas import SearchQuery

    query = SearchQuery(
        query=q,
        conversation_id=conversation_id,
        search_messages=search_messages,
        search_files=search_files,
        limit=limit,
        offset=offset,
    )
    return await SearchService(db).search(_uid(request), query)
