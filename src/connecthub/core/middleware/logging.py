"""
ConnectHub — Structured Logging Middleware.

Logs every HTTP request/response with a correlation ID for traceability.
Uses structlog for structured JSON output in production.
"""

from __future__ import annotations

import logging
import time
import uuid
from typing import Any

from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint
from starlette.requests import Request
from starlette.responses import Response

logger = logging.getLogger(__name__)


class StructuredLoggingMiddleware(BaseHTTPMiddleware):
    """Middleware that logs request/response details with a correlation ID."""

    async def dispatch(
        self, request: Request, call_next: RequestResponseEndpoint
    ) -> Response:
        # Generate or extract correlation ID
        correlation_id = request.headers.get("X-Correlation-ID", str(uuid.uuid4()))
        start_time = time.perf_counter()

        # Attach correlation ID to request state for downstream use
        request.state.correlation_id = correlation_id

        # Log request
        log_data: dict[str, Any] = {
            "correlation_id": correlation_id,
            "method": request.method,
            "path": request.url.path,
            "client": request.client.host if request.client else "unknown",
        }
        logger.info("Request started: %(method)s %(path)s", log_data, extra=log_data)

        try:
            response = await call_next(request)
        except Exception:
            duration_ms = (time.perf_counter() - start_time) * 1000
            log_data["duration_ms"] = round(duration_ms, 2)
            log_data["status_code"] = 500
            logger.exception("Request failed: %(method)s %(path)s", log_data, extra=log_data)
            raise

        # Log response
        duration_ms = (time.perf_counter() - start_time) * 1000
        log_data["duration_ms"] = round(duration_ms, 2)
        log_data["status_code"] = response.status_code
        logger.info(
            "Request completed: %(method)s %(path)s %(status_code)s (%(duration_ms)sms)",
            log_data,
            extra=log_data,
        )

        # Propagate correlation ID in response
        response.headers["X-Correlation-ID"] = correlation_id
        return response
