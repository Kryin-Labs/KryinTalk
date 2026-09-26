"""ConnectHub Auth Module — Authentication and admin management.

Registers the auth module's routes with the application.
This module also registers its permission domains on startup.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from fastapi import FastAPI


def register(app: FastAPI) -> None:
    """Register the Auth module with the application."""
    from connecthub.modules.auth.router import router

    app.include_router(router, prefix="/auth", tags=["auth"])
