"""
ConnectHub File Module — Storage Backend.

Abstracted behind a protocol so local filesystem can be swapped
for S3/MinIO in the future without touching business logic.
"""

from __future__ import annotations

import logging
import uuid
from pathlib import Path
from typing import Protocol

logger = logging.getLogger(__name__)

# Default upload directory relative to project root
DEFAULT_UPLOAD_DIR = "data/uploads"

# Default max file size: 50MB
DEFAULT_MAX_FILE_SIZE = 50 * 1024 * 1024


class StorageBackend(Protocol):
    """Protocol for file storage backends."""

    async def save(
        self, org_id: uuid.UUID, stored_filename: str, content: bytes,
    ) -> str:
        """Save file content. Returns storage path."""
        ...

    async def read(self, storage_path: str) -> bytes:
        """Read file content by storage path."""
        ...

    async def delete(self, storage_path: str) -> None:
        """Delete file content."""
        ...

    async def exists(self, storage_path: str) -> bool:
        """Check if file exists."""
        ...


class LocalStorageBackend:
    """Local filesystem storage backend.

    Files stored as: {base_dir}/{org_id}/{stored_filename}
    """

    def __init__(self, base_dir: str = DEFAULT_UPLOAD_DIR) -> None:
        self._base_dir = Path(base_dir)

    def _org_dir(self, org_id: uuid.UUID) -> Path:
        return self._base_dir / str(org_id)

    def _safe_path(self, storage_path: str) -> Path:
        """Resolve a stored path and reject traversal outside the upload root."""
        base = self._base_dir.resolve()
        candidate = (base / storage_path).resolve()
        if candidate == base or base not in candidate.parents:
            raise ValueError("Invalid storage path")
        return candidate

    async def save(
        self, org_id: uuid.UUID, stored_filename: str, content: bytes,
    ) -> str:
        """Save file to local filesystem. Returns relative storage path."""
        file_path = self._safe_path(f"{org_id}/{stored_filename}")
        org_dir = file_path.parent
        org_dir.mkdir(parents=True, exist_ok=True)

        file_path.write_bytes(content)

        storage_path = f"{org_id}/{stored_filename}"
        logger.info("File saved: %s (%d bytes)", storage_path, len(content))
        return storage_path

    async def read(self, storage_path: str) -> bytes:
        """Read file from local filesystem."""
        file_path = self._safe_path(storage_path)
        if not file_path.exists():
            raise FileNotFoundError(f"File not found: {storage_path}")
        return file_path.read_bytes()

    async def delete(self, storage_path: str) -> None:
        """Delete file from local filesystem."""
        file_path = self._safe_path(storage_path)
        if file_path.exists():
            file_path.unlink()
            logger.info("File deleted: %s", storage_path)

    async def exists(self, storage_path: str) -> bool:
        """Check if file exists on local filesystem."""
        return self._safe_path(storage_path).exists()


def generate_stored_filename(original_filename: str) -> str:
    """Generate a collision-free stored filename.

    Preserves the original extension for content-type inference.
    """
    ext = ""
    if "." in original_filename:
        ext = "." + original_filename.rsplit(".", 1)[-1].lower()
    return f"{uuid.uuid4().hex}{ext}"
