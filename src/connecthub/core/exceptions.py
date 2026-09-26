"""
ConnectHub — Application-Wide Exception Classes.

All custom exceptions inherit from ConnectHubError, which provides
a consistent structure for API error responses (status_code, error_code, message).

Security note: error messages must never leak internal details or confirm
the existence of hidden resources (Section 5 — no metadata leakage).
"""

from __future__ import annotations


class ConnectHubError(Exception):
    """Base exception for all ConnectHub application errors."""

    def __init__(
        self,
        message: str = "An unexpected error occurred.",
        status_code: int = 500,
        error_code: str = "INTERNAL_ERROR",
    ) -> None:
        self.message = message
        self.status_code = status_code
        self.error_code = error_code
        super().__init__(self.message)


class NotFoundError(ConnectHubError):
    """Resource not found — returns 404.

    IMPORTANT: Use the same 404 response for both "does not exist" and
    "exists but you lack permission" to prevent information leakage
    (Section 5 — permission-based visibility).
    """

    def __init__(self, message: str = "Resource not found.") -> None:
        super().__init__(message=message, status_code=404, error_code="NOT_FOUND")


class ForbiddenError(ConnectHubError):
    """Insufficient permissions — returns 403.

    WARNING: Only use this for authenticated users accessing their own
    resources beyond their role. For cross-entity access, prefer NotFoundError
    to avoid confirming existence of hidden resources.
    """

    def __init__(self, message: str = "Insufficient permissions.") -> None:
        super().__init__(message=message, status_code=403, error_code="FORBIDDEN")


class UnauthorizedError(ConnectHubError):
    """Authentication required or invalid — returns 401."""

    def __init__(self, message: str = "Authentication required.") -> None:
        super().__init__(message=message, status_code=401, error_code="UNAUTHORIZED")


class ValidationError(ConnectHubError):
    """Request validation error — returns 422."""

    def __init__(self, message: str = "Validation error.") -> None:
        super().__init__(message=message, status_code=422, error_code="VALIDATION_ERROR")


class ConflictError(ConnectHubError):
    """Resource conflict (e.g., duplicate) — returns 409."""

    def __init__(self, message: str = "Resource conflict.") -> None:
        super().__init__(message=message, status_code=409, error_code="CONFLICT")


class ServiceUnavailableError(ConnectHubError):
    """Downstream service unavailable — returns 503."""

    def __init__(self, message: str = "Service temporarily unavailable.") -> None:
        super().__init__(message=message, status_code=503, error_code="SERVICE_UNAVAILABLE")
