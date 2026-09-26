"""
ConnectHub — Authentication Middleware.

Extracts JWT from the Authorization header, validates it, and sets
request.state.user_id and request.state.organization_id for downstream
handlers and the permission dependency.

Public routes (health, login, register, refresh) bypass authentication.
"""

from __future__ import annotations

import logging
import uuid

from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint
from starlette.requests import Request
from starlette.responses import JSONResponse, Response

from connecthub.core.security.jwt import InvalidTokenError, decode_token

logger = logging.getLogger(__name__)

# Routes that do not require authentication
PUBLIC_PATHS: set[str] = {
    "/",
    "/health",
    "/auth/login",
    "/auth/register",
    "/auth/refresh",
    "/api/v1/auth/login",
    "/api/v1/auth/refresh",
    "/docs",
    "/openapi.json",
    "/redoc",
    "/connecthub-debug.apk",
    "/download/apk",
}


def _is_public_path(path: str, method: str = "GET") -> bool:
    """Check if the request path is a public (unauthenticated) route."""
    # Exact match
    if path in PUBLIC_PATHS:
        return True
    # Suffix match for login / refresh under any API prefix
    if (
        path.endswith("/auth/login")
        or path.endswith("/auth/register")
        or path.endswith("/auth/refresh")
        or path.endswith(".apk")
    ):
        return True
    # Prefix match for docs and app static paths
    if (
        path.startswith("/docs")
        or path.startswith("/redoc")
        or path.startswith("/app")
        or path.startswith("/health")
        or path.startswith("/download")
    ):
        return True
    # Group invite inspection is public on GET
    if method == "GET" and (
        path.startswith("/groups/invites/")
        or path.startswith("/api/v1/groups/invites/")
    ):
        return True
    return False


class AuthenticationMiddleware(BaseHTTPMiddleware):
    """Middleware that enforces JWT authentication on protected routes.

    Sets:
        request.state.user_id — UUID of the authenticated user
        request.state.organization_id — UUID of the user's organization (if present)
    """

    async def dispatch(
        self, request: Request, call_next: RequestResponseEndpoint,
    ) -> Response:
        is_public = request.method == "OPTIONS" or _is_public_path(request.url.path, request.method)

        # Extract token from Authorization header if present
        auth_header = request.headers.get("Authorization")
        if is_public and (auth_header is None or not auth_header.startswith("Bearer ")):
            return await call_next(request)

        if auth_header is None or not auth_header.startswith("Bearer "):
            return JSONResponse(
                status_code=401,
                content={
                    "error_code": "UNAUTHORIZED",
                    "message": "Authentication required.",
                },
            )

        token = auth_header.removeprefix("Bearer ").strip()

        try:
            payload = decode_token(token)
        except InvalidTokenError:
            return JSONResponse(
                status_code=401,
                content={
                    "error_code": "UNAUTHORIZED",
                    "message": "Invalid or expired token.",
                },
            )

        # Reject refresh tokens used as access tokens
        if payload.type != "access":
            return JSONResponse(
                status_code=401,
                content={
                    "error_code": "UNAUTHORIZED",
                    "message": "Invalid token type.",
                },
            )

        # Set user context on request state
        request.state.user_id = uuid.UUID(payload.sub)
        request.state.organization_id = (
            uuid.UUID(payload.org) if payload.org else None
        )

        return await call_next(request)
