"""Display filenames must never become storage paths or invalid HTTP headers."""

import re
import uuid
from unittest.mock import AsyncMock, patch
from urllib.parse import unquote

import pytest
from starlette.requests import Request

from connecthub.modules.files.router import download_file
from connecthub.modules.files.storage import generate_stored_filename


@pytest.mark.parametrize("name", [
    "report.pdf/../../other", "report.\\..\\other", "report.txt\r\nInjected",
    "photo." + "x" * 300, "file.💾", "archive.tar.gz", "résumé.PDF",
])
def test_generated_key_is_a_portable_basename(name):
    key = generate_stored_filename(name)
    assert re.fullmatch(r"[0-9a-f]{32}(\.[a-z0-9]{1,16})?", key)


async def test_storage_cannot_write_into_another_org(storage_backend):
    with pytest.raises(ValueError, match="filename"):
        await storage_backend.save(uuid.uuid4(), "../another-org/file.txt", b"content")


@pytest.mark.parametrize("name", ["बजट 2026.pdf", "résumé.pdf", "bad\r\n\"/\\name.txt"])
async def test_download_encodes_display_name(name):
    request = Request({"type": "http", "state": {"user_id": uuid.uuid4()}})
    with patch("connecthub.modules.files.router.FileService") as service:
        service.return_value.download_file = AsyncMock(return_value=(b"hello", name, "text/plain"))
        response = await download_file(uuid.uuid4(), request, None)
    header = response.headers["content-disposition"]
    assert header.startswith("attachment; filename*=UTF-8''")
    decoded = unquote(header.split("''", 1)[1])
    assert all(char not in decoded for char in '\r\n"/\\')
    assert response.body == b"hello"
