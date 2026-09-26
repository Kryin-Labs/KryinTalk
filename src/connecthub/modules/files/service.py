"""
ConnectHub File Module — Business Logic.

Files respect the same visibility rules as messages — access is
gated by conversation participation (Section 5).
"""

from __future__ import annotations

import logging
import uuid

from sqlalchemy.ext.asyncio import AsyncSession

from connecthub.core.audit.service import AuditService
from connecthub.core.exceptions import NotFoundError, ValidationError
from connecthub.core.permissions.policy import PolicyService
from connecthub.modules.auth.repository import AuthRepository
from connecthub.modules.files.models import FileAttachment
from connecthub.modules.files.repository import FileRepository
from connecthub.modules.files.schemas import FileListResponse, FileResponse, FileUploadResponse
from connecthub.modules.files.storage import (
    DEFAULT_MAX_FILE_SIZE,
    LocalStorageBackend,
    StorageBackend,
    generate_stored_filename,
)
from connecthub.modules.messaging.repository import MessagingRepository

logger = logging.getLogger(__name__)


class FileService:
    """File sharing service.

    All operations verify the user is a participant in the
    target conversation. Non-participants get 404 (Section 5).
    """

    def __init__(
        self,
        session: AsyncSession,
        storage: StorageBackend | None = None,
        max_file_size: int = DEFAULT_MAX_FILE_SIZE,
    ) -> None:
        self._repo = FileRepository(session)
        self._msg_repo = MessagingRepository(session)
        self._auth_repo = AuthRepository(session)
        self._audit = AuditService(session)
        self._policy = PolicyService(session)
        self._storage = storage or LocalStorageBackend()
        self._max_file_size = max_file_size

    async def _get_org_id(self, user_id: uuid.UUID) -> uuid.UUID:
        user = await self._auth_repo.get_user_by_id(user_id)
        if user is None:
            raise NotFoundError("Resource not found.")
        return user.organization_id

    async def _require_participant(
        self, user_id: uuid.UUID, conversation_id: uuid.UUID,
    ) -> None:
        """Ensure user is a participant. Auto-adds user if conversation is non-direct or user is superadmin."""
        if await self._msg_repo.is_participant(conversation_id, user_id):
            return

        user = await self._auth_repo.get_user_by_id(user_id)
        conv = await self._msg_repo.get_conversation_by_id(conversation_id)

        if conv is not None and user is not None:
            is_sa = await self._policy.is_super_admin(user_id)
            if is_sa:
                await self._msg_repo.add_participant(conversation_id, user_id)
                return

        raise NotFoundError("Resource not found.")

    # ── Upload ───────────────────────────────

    async def upload_file(
        self,
        user_id: uuid.UUID,
        conversation_id: uuid.UUID,
        filename: str,
        content: bytes,
        content_type: str = "application/octet-stream",
    ) -> FileUploadResponse:
        """Upload a file to a conversation.

        1. Verify user is a participant
        2. Validate file size
        3. Store file content on disk
        4. Create metadata record in PostgreSQL
        """
        await self._require_participant(user_id, conversation_id)

        # Check group permission if conversation is a group
        conv = await self._msg_repo.get_conversation_by_id(conversation_id)
        if conv and conv.conversation_type.value == "group" and conv.target_id:
            from connecthub.core.exceptions import ForbiddenError
            from connecthub.modules.group.service import GroupService
            group_svc = GroupService(self._repo._session)
            has_perm = (
                await group_svc.check_group_permission(conv.target_id, user_id, "send_attachments")
                or await group_svc.check_group_permission(conv.target_id, user_id, "send_files")
                or await group_svc.check_group_permission(conv.target_id, user_id, "send_images")
            )
            if not has_perm:
                is_sa = await self._policy.is_super_admin(user_id)
                if not is_sa:
                    raise ForbiddenError("You do not have permission to send files or attachments in this group.")

        # Validate size
        if len(content) > self._max_file_size:
            raise ValidationError(
                f"File too large. Maximum size is "
                f"{self._max_file_size // (1024 * 1024)}MB."
            )

        if len(content) == 0:
            raise ValidationError("File cannot be empty.")

        org_id = await self._get_org_id(user_id)

        # Store on disk
        stored_filename = generate_stored_filename(filename)
        storage_path = await self._storage.save(org_id, stored_filename, content)

        # Create metadata
        attachment = await self._repo.create(
            organization_id=org_id,
            conversation_id=conversation_id,
            uploaded_by=user_id,
            original_filename=filename,
            stored_filename=stored_filename,
            content_type=content_type,
            size_bytes=len(content),
            storage_path=storage_path,
        )

        await self._audit.log(
            user_id=user_id,
            action="file.uploaded",
            resource_type="file",
            resource_id=str(attachment.id),
            details={"filename": filename, "size": len(content)},
        )

        logger.info("File uploaded: %s (%s, %d bytes) by user %s",
                     attachment.id, filename, len(content), user_id)
        return FileUploadResponse.model_validate(attachment)

    # ── Download ─────────────────────────────

    async def download_file(
        self, user_id: uuid.UUID, file_id: uuid.UUID,
    ) -> tuple[bytes, str, str]:
        """Download a file. Returns (content, filename, content_type).

        Non-participants get 404 (Section 5).
        """
        attachment = await self._repo.get_by_id(file_id)
        if attachment is None:
            raise NotFoundError("Resource not found.")

        await self._require_participant(user_id, attachment.conversation_id)

        content = await self._storage.read(attachment.storage_path)
        return content, attachment.original_filename, attachment.content_type

    # ── File Info ─────────────────────────────

    async def get_file_info(
        self, user_id: uuid.UUID, file_id: uuid.UUID,
    ) -> FileResponse:
        """Get file metadata. Non-participants get 404 (Section 5)."""
        attachment = await self._repo.get_by_id(file_id)
        if attachment is None:
            raise NotFoundError("Resource not found.")

        await self._require_participant(user_id, attachment.conversation_id)
        return FileResponse.model_validate(attachment)

    # ── List Files ───────────────────────────

    async def list_files(
        self,
        user_id: uuid.UUID,
        conversation_id: uuid.UUID,
        limit: int = 50,
        offset: int = 0,
    ) -> FileListResponse:
        """List files in a conversation. Non-participants get 404 (Section 5)."""
        await self._require_participant(user_id, conversation_id)

        files = await self._repo.list_by_conversation(
            conversation_id, limit=limit, offset=offset,
        )
        total = await self._repo.count_by_conversation(conversation_id)

        return FileListResponse(
            items=[FileResponse.model_validate(f) for f in files],
            total=total,
        )

    # ── Delete ───────────────────────────────

    async def delete_file(
        self, user_id: uuid.UUID, file_id: uuid.UUID,
    ) -> None:
        """Soft-delete a file. Only the uploader can delete.

        Non-participants get 404 (Section 5).
        """
        attachment = await self._repo.get_by_id(file_id)
        if attachment is None:
            raise NotFoundError("Resource not found.")

        await self._require_participant(user_id, attachment.conversation_id)

        # Only uploader can delete
        if attachment.uploaded_by != user_id:
            raise NotFoundError("Resource not found.")

        await self._repo.soft_delete(file_id)

        await self._audit.log(
            user_id=user_id,
            action="file.deleted",
            resource_type="file",
            resource_id=str(file_id),
            details={"filename": attachment.original_filename},
        )

        logger.info("File deleted: %s by user %s", file_id, user_id)
