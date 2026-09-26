"""ConnectHub Notification Module — In-app notifications."""

from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from fastapi import FastAPI


def register(app: FastAPI) -> None:
    """Register the Notification module with the application."""
    from connecthub.modules.notifications.router import router

    app.include_router(router, prefix="/notifications", tags=["notifications"])
