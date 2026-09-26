"""
ConnectHub File Module — Pydantic Schemas.
"""

from __future__ import annotations

import uuid
from datetime import datetime

from pydantic import BaseModel


class FileUploadResponse(BaseModel):
    """Returned after successful file upload."""

    id: uuid.UUID
    original_filename: str
    content_type: str
    size_bytes: int
    conversation_id: uuid.UUID
    uploaded_by: uuid.UUID
    has_preview: bool
    created_at: datetime

    model_config = {"from_attributes": True}


class FileResponse(BaseModel):
    """File metadata."""

    id: uuid.UUID
    original_filename: str
    content_type: str
    size_bytes: int
    conversation_id: uuid.UUID
    uploaded_by: uuid.UUID
    has_preview: bool
    created_at: datetime

    model_config = {"from_attributes": True}


class FileListResponse(BaseModel):
    """Paginated file list."""

    items: list[FileResponse]
    total: int
