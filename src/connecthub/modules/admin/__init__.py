"""ConnectHub Admin Module — Admin console APIs, audit log viewer, backup & restore."""

from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from fastapi import FastAPI


def register(app: FastAPI) -> None:
    """Register the Admin module with the application."""
    from connecthub.modules.admin.router import router

    app.include_router(router, prefix="/admin", tags=["admin"])
