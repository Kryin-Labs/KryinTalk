"""ConnectHub File Module — File sharing and document preview."""

from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from fastapi import FastAPI


def register(app: FastAPI) -> None:
    """Register the File module with the application."""
    from connecthub.modules.files.router import router

    app.include_router(router, prefix="/files", tags=["files"])
