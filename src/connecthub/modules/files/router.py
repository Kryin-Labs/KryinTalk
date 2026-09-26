"""
ConnectHub File Module — REST Endpoints.

Routes:
    POST   /files/upload                   — Upload file to conversation
    GET    /files/{id}                      — File metadata
    GET    /files/{id}/download             — Download file content
    GET    /files/conversation/{conv_id}    — List files in conversation
    DELETE /files/{id}                      — Soft-delete file
"""

from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, Query, Request, UploadFile
from fastapi import File as FastAPIFile
from fastapi.responses import Response
from sqlalchemy.ext.asyncio import AsyncSession

from connecthub.core.database.session import get_db_session
from connecthub.modules.files.schemas import FileListResponse, FileResponse, FileUploadResponse
from connecthub.modules.files.service import FileService

router = APIRouter()


def _uid(request: Request) -> uuid.UUID:
    return request.state.user_id


@router.post("/upload", response_model=FileUploadResponse, status_code=201)
async def upload_file(
    request: Request,
    conversation_id: uuid.UUID = Query(...),
    file: UploadFile = FastAPIFile(...),
    db: AsyncSession = Depends(get_db_session),
) -> FileUploadResponse:
    content = await file.read()
    return await FileService(db).upload_file(
        user_id=_uid(request),
        conversation_id=conversation_id,
        filename=file.filename or "unknown",
        content=content,
        content_type=file.content_type or "application/octet-stream",
    )


@router.get("/{file_id}", response_model=FileResponse)
async def get_file_info(
    file_id: uuid.UUID,
    request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> FileResponse:
    return await FileService(db).get_file_info(_uid(request), file_id)


@router.get("/{file_id}/download")
async def download_file(
    file_id: uuid.UUID,
    request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> Response:
    content, filename, content_type = await FileService(db).download_file(
        _uid(request), file_id,
    )
    # Keep user-provided names out of HTTP header syntax.
    safe_filename = (
        filename.replace("\\", "_")
        .replace("/", "_")
        .replace('"', "")
        .replace("\r", "")
        .replace("\n", "")
    ) or "download"
    return Response(
        content=content,
        media_type=content_type,
        headers={"Content-Disposition": f'attachment; filename="{safe_filename}"'},
    )


@router.get("/conversation/{conversation_id}", response_model=FileListResponse)
async def list_conversation_files(
    conversation_id: uuid.UUID,
    request: Request,
    limit: int = Query(default=50, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    db: AsyncSession = Depends(get_db_session),
) -> FileListResponse:
    return await FileService(db).list_files(
        _uid(request), conversation_id, limit, offset,
    )


@router.delete("/{file_id}", status_code=204)
async def delete_file(
    file_id: uuid.UUID,
    request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> None:
    await FileService(db).delete_file(_uid(request), file_id)
