"""
ConnectHub Search Module — Pydantic Schemas.
"""

from __future__ import annotations

import uuid
from datetime import datetime

from pydantic import BaseModel, Field


class SearchQuery(BaseModel):
    """Search request."""

    query: str = Field(..., min_length=1, max_length=500)
    conversation_id: uuid.UUID | None = None
    search_messages: bool = True
    search_files: bool = True
    limit: int = Field(default=20, ge=1, le=100)
    offset: int = Field(default=0, ge=0)


class SearchResultItem(BaseModel):
    """A single search result."""

    result_type: str  # "message" or "file"
    resource_id: uuid.UUID
    conversation_id: uuid.UUID
    title: str
    snippet: str
    created_at: datetime


class SearchResponse(BaseModel):
    """Search results."""

    items: list[SearchResultItem]
    total: int
    query: str
