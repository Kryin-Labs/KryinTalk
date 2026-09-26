"""ConnectHub Messaging Module — Real-time messaging."""

from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from fastapi import FastAPI


def register(app: FastAPI) -> None:
    """Register the Messaging module with the application."""
    from connecthub.modules.messaging.router import router
    from connecthub.modules.messaging.websocket_handler import ws_router

    app.include_router(router, prefix="/messaging/conversations", tags=["messaging"])
    app.include_router(router, prefix="/conversations", tags=["messaging"])
    app.include_router(ws_router, tags=["websocket"])
