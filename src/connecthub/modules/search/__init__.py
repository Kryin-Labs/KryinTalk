"""ConnectHub Search Module — Full-text search."""

from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from fastapi import FastAPI


def register(app: FastAPI) -> None:
    """Register the Search module with the application."""
    from connecthub.modules.search.router import router

    app.include_router(router, prefix="/search", tags=["search"])
