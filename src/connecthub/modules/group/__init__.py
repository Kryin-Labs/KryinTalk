"""ConnectHub Group Module — Private group management."""

from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from fastapi import FastAPI


def register(app: FastAPI) -> None:
    """Register the Group module with the application."""
    from connecthub.modules.group.router import router

    app.include_router(router, prefix="/groups", tags=["groups"])
