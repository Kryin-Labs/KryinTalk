"""
ConnectHub — Async SQLAlchemy Engine.

Provides the async engine and session factory. Manages connection lifecycle
(connect/disconnect) and health checking.
"""

from __future__ import annotations

import logging
import uuid
from typing import Any

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, create_async_engine
from sqlalchemy.orm import sessionmaker

from connecthub.config import settings

logger = logging.getLogger(__name__)


class DatabaseEngine:
    """Manages the async SQLAlchemy engine lifecycle."""

    def __init__(self) -> None:
        self._engine: AsyncEngine | None = None
        self._session_factory: sessionmaker | None = None  # type: ignore[type-arg]

    async def connect(self) -> None:
        """Create the async engine and session factory. Fallback to SQLite if PostgreSQL is unreachable."""
        url = settings.DATABASE_URL

        try:
            kwargs: dict[str, Any] = {
                "echo": settings.APP_DEBUG,
            }
            if "sqlite" not in url:
                kwargs["pool_size"] = 20
                kwargs["max_overflow"] = 10
                kwargs["pool_pre_ping"] = True
                kwargs["pool_recycle"] = 3600

            engine = create_async_engine(url, **kwargs)
            async with engine.connect() as conn:
                await conn.execute(text("SELECT 1"))
            self._engine = engine
            logger.info("Database connected successfully using: %s", url)
        except Exception as e:
            logger.warning("Primary database connection failed (%s): %s. Falling back to local SQLite database.", url, e)
            fallback_url = "sqlite+aiosqlite:///./connecthub.db"
            from sqlalchemy.pool import NullPool
            self._engine = create_async_engine(
                fallback_url,
                echo=settings.APP_DEBUG,
                connect_args={"check_same_thread": False, "timeout": 60},
                poolclass=NullPool,
            )
            async with self._engine.connect() as conn:
                await conn.execute(text("PRAGMA journal_mode=WAL;"))
                await conn.execute(text("PRAGMA busy_timeout=60000;"))
            logger.info("Database fallback active with WAL mode & NullPool: %s", fallback_url)

        self._session_factory = sessionmaker(
            bind=self._engine,
            class_=AsyncSession,
            expire_on_commit=False,
        )

        try:
            await self._initialize_schema_and_seeds()
        except Exception as err:
            logger.warning("Database schema/seed initialization note: %s", err)

    async def _initialize_schema_and_seeds(self) -> None:
        """Create tables if needed and seed default super admin user."""
        if self._engine is None or self._session_factory is None:
            return

        import importlib
        for mod in [
            "connecthub.modules.auth.models",
            "connecthub.modules.messaging.models",
            "connecthub.modules.group.models",
            "connecthub.modules.files.models",
            "connecthub.modules.notifications.models",
            "connecthub.modules.admin.models",
            "connecthub.core.permissions.models",
        ]:
            try:
                importlib.import_module(mod)
            except Exception:
                pass

        from connecthub.core.database.base import Base
        async with self._engine.begin() as conn:
            await conn.run_sync(Base.metadata.create_all)

        from connecthub.modules.auth.models import Organization, User
        from connecthub.core.security.hashing import hash_password

        async with self._session_factory() as session:
            res = await session.execute(text("SELECT count(*) FROM users"))
            user_count = res.scalar() or 0
            if user_count == 0:
                logger.info("Seeding default Organization and Super Admin user...")
                org_id = uuid.uuid4()
                org = Organization(
                    id=org_id,
                    name="ConnectHub Enterprise",
                    slug="connecthub",
                    is_active=True,
                )
                session.add(org)

                from connecthub.core.permissions.models import Role, UserRole

                super_role_id = uuid.uuid4()
                super_role = Role(
                    id=super_role_id,
                    organization_id=org_id,
                    code="super_admin",
                    name="Super Admin",
                    description="Full administrative access across all domains",
                    is_system=True,
                    is_active=True,
                )
                session.add(super_role)

                user_id = uuid.uuid4()
                admin_user = User(
                    id=user_id,
                    organization_id=org_id,
                    email="admin@connecthub.com",
                    username="admin",
                    password_hash=hash_password("admin123"),
                    display_name="Super Admin",
                    is_active=True,
                    is_suspended=False,
                )
                session.add(admin_user)

                user_role = UserRole(
                    id=uuid.uuid4(),
                    user_id=user_id,
                    role_id=super_role_id,
                    granted_by=user_id,
                )
                session.add(user_role)
                await session.commit()
                logger.info("Default Super Admin created: admin@connecthub.com / admin123")

    async def disconnect(self) -> None:
        """Dispose of the engine and close all connections."""
        if self._engine:
            await self._engine.dispose()
            self._engine = None
            self._session_factory = None
            logger.info("Database engine disposed.")

    @property
    def engine(self) -> AsyncEngine:
        """Return the async engine (raises if not connected)."""
        if self._engine is None:
            raise RuntimeError("Database engine is not initialized. Call connect() first.")
        return self._engine

    @property
    def session_factory(self) -> sessionmaker:  # type: ignore[type-arg]
        """Return the session factory (raises if not connected)."""
        if self._session_factory is None:
            raise RuntimeError("Session factory is not initialized. Call connect() first.")
        return self._session_factory

    async def health_check(self) -> bool:
        """Check if the database is reachable."""
        try:
            if self._engine is None:
                return False
            async with self._engine.connect() as conn:
                await conn.execute(text("SELECT 1"))
            return True
        except Exception:
            logger.exception("Database health check failed.")
            return False


# Module-level singleton
db_engine = DatabaseEngine()
