"""ConnectHub Org Settings Module — Organization settings management."""

from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from fastapi import FastAPI


def register(app: FastAPI) -> None:
    """Register the Org Settings module with the application."""
    from connecthub.modules.org_settings.router import router

    app.include_router(router, prefix="/organizations", tags=["organizations"])
