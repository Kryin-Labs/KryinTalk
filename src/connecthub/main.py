"""
ConnectHub — Application Entrypoint.

FastAPI application factory with lifespan management.
Connects to PostgreSQL, Redis, and NATS on startup;
gracefully disconnects on shutdown.
"""

from __future__ import annotations

import asyncio
import logging
from contextlib import asynccontextmanager
from typing import AsyncGenerator

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from connecthub.config import settings
from connecthub.core.database.engine import db_engine
from connecthub.core.events.nats_backend import nats_event_backend
from connecthub.core.exceptions import ConnectHubError
from connecthub.core.middleware.logging import StructuredLoggingMiddleware
from connecthub.core.redis.client import redis_client

logger = logging.getLogger(__name__)


# ──────────────────────────────────────────────
# Lifespan — startup / shutdown
# ──────────────────────────────────────────────
@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:
    """Manage application lifecycle: connect and disconnect infrastructure."""
    logger.info("Starting ConnectHub v%s [%s]", "0.1.0", settings.APP_ENV)

    # ── Startup ──────────────────────────────
    # 1. Database
    try:
        await db_engine.connect()
        logger.info("Database connected successfully.")
    except Exception as e:
        logger.warning("Database connection failed during startup: %s", e)

    # 2. Redis
    try:
        await redis_client.connect()
        logger.info("Redis connected: %s:%s", settings.REDIS_HOST, settings.REDIS_PORT)
    except Exception as e:
        logger.warning("Redis connection skipped/failed: %s", e)

    # 3. NATS (event broker)
    try:
        await nats_event_backend.connect()
        logger.info("NATS connected: %s", settings.NATS_URL)
    except Exception as e:
        logger.warning("NATS connection skipped/failed: %s", e)

    # 4. Auto Backup Scheduler Daemon (12-Hour Dual Database + Website Vault)
    backup_task = None
    try:
        from connecthub.modules.admin.backup_service import auto_backup_scheduler_daemon
        backup_task = asyncio.create_task(auto_backup_scheduler_daemon())
        logger.info("Auto Backup Scheduler daemon started.")
    except Exception as e:
        logger.warning("Could not launch Auto Backup Scheduler: %s", e)

    logger.info("ConnectHub startup complete — application running.")

    yield  # Application is running

    # ── Shutdown ─────────────────────────────
    logger.info("Shutting down ConnectHub...")

    if backup_task and not backup_task.done():
        backup_task.cancel()

    try:
        await nats_event_backend.disconnect()
    except Exception:
        pass

    try:
        await redis_client.disconnect()
    except Exception:
        pass

    try:
        await db_engine.disconnect()
    except Exception:
        pass

    logger.info("ConnectHub shutdown complete.")


# ──────────────────────────────────────────────
# Application Factory
# ──────────────────────────────────────────────
def create_app() -> FastAPI:
    """Create and configure the FastAPI application."""
    application = FastAPI(
        title=settings.APP_NAME,
        description="Enterprise Communication Platform — Simplified. Secured.",
        version="0.1.0",
        docs_url="/docs" if settings.APP_DEBUG else None,
        redoc_url="/redoc" if settings.APP_DEBUG else None,
        lifespan=lifespan,
    )

    # ── Middleware ────────────────────────────
    application.add_middleware(StructuredLoggingMiddleware)

    # Authentication middleware — extracts JWT and sets request.state.user_id
    from connecthub.core.security.auth_middleware import AuthenticationMiddleware
    application.add_middleware(AuthenticationMiddleware)

    # CORS Middleware — handles localhost, 127.0.0.1 on all dev ports (3000, etc.) and production domains
    application.add_middleware(
        CORSMiddleware,
        allow_origins=settings.CORS_ORIGINS,
        allow_origin_regex=settings.CORS_ORIGIN_REGEX,
        allow_credentials=True,
        allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD", "PATCH"],
        allow_headers=["*"],
        expose_headers=["*"],
    )

    # ── Exception Handlers ───────────────────
    @application.exception_handler(ConnectHubError)
    async def connecthub_error_handler(request: Request, exc: ConnectHubError) -> JSONResponse:
        return JSONResponse(
            status_code=exc.status_code,
            content={
                "error": exc.error_code,
                "message": exc.message,
            },
        )

    @application.exception_handler(Exception)
    async def global_exception_handler(request: Request, exc: Exception) -> JSONResponse:
        logger.error("Unhandled server exception: %s", exc, exc_info=True)
        return JSONResponse(
            status_code=500,
            content={
                "error": "INTERNAL_SERVER_ERROR",
                "message": "An internal server error occurred.",
            },
        )

    # ── Health Check ─────────────────────────
    @application.get(
        "/health",
        tags=["system"],
        summary="Health check",
        response_description="Infrastructure service status",
    )
    async def health_check() -> dict:
        """Return the health status of all infrastructure services."""
        db_healthy = await db_engine.health_check()
        redis_healthy = await redis_client.health_check()
        nats_healthy = await nats_event_backend.health_check()

        all_healthy = db_healthy and redis_healthy and nats_healthy

        return {
            "status": "healthy" if all_healthy else "degraded",
            "version": "0.1.0",
            "environment": settings.APP_ENV,
            "services": {
                "postgresql": {"status": "up" if db_healthy else "down"},
                "redis": {"status": "up" if redis_healthy else "down"},
                "nats": {"status": "up" if nats_healthy else "down"},
            },
        }

    @application.get(
        "/app/version",
        tags=["system"],
        summary="Check latest mobile app version for in-app direct updates",
    )
    async def get_app_version() -> dict:
        """Returns the latest available mobile APK build version and release notes."""
        return {
            "version": "0.1.2",
            "build_number": 2,
            "release_notes": "Added mobile back navigation buttons, fixed 101px header overflow, and improved diagnostics.",
            "download_url": "/connecthub-debug.apk",
            "force_update": False,
        }

    # ── Module Registration ──────────────────
    from connecthub.modules import discover_and_register_modules
    registered = discover_and_register_modules(application)
    if registered:
        logger.info("Registered modules: %s", ", ".join(registered))

    # ── Mount Direct APK Download & Web Frontend ─────────────────
    from pathlib import Path
    from fastapi.staticfiles import StaticFiles
    from fastapi.responses import RedirectResponse, FileResponse
    from fastapi import HTTPException

    @application.api_route("/connecthub-debug.apk", methods=["GET", "HEAD"], include_in_schema=False)
    async def download_apk() -> FileResponse:
        """Serve the latest compiled Android APK directly for in-app OTA updates."""
        apk_path = Path(__file__).parents[2] / "connecthub-debug.apk"
        if apk_path.exists():
            return FileResponse(
                path=str(apk_path),
                media_type="application/vnd.android.package-archive",
                filename="connecthub-debug.apk",
            )
        raise HTTPException(status_code=404, detail="APK not found")

    web_build_dir = Path(__file__).parents[2] / "clients" / "web" / "build" / "web"
    if web_build_dir.exists():
        logger.info("Mounting Flutter Web frontend from %s", web_build_dir)
        application.mount("/app", StaticFiles(directory=str(web_build_dir), html=True), name="web_app")

        @application.get("/", include_in_schema=False)
        async def root_redirect():
            return RedirectResponse(url="/app/")

    return application



# Create the app instance — used by uvicorn
app = create_app()
