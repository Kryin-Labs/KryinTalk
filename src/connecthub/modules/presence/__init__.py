"""ConnectHub Presence Module."""
from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from fastapi import FastAPI


def register(app: FastAPI) -> None:
    """Register the Presence module with the application."""
    from connecthub.modules.presence.router import router

    app.include_router(router, prefix="/presence", tags=["presence"])


__all__ = ["register"]

