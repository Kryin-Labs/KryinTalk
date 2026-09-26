"""
ConnectHub — Request-Scoped Database Session.

Provides a FastAPI dependency that yields an async session per request
and commits/rolls back automatically.
"""

from __future__ import annotations

from collections.abc import AsyncGenerator

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import sessionmaker

from connecthub.core.database.engine import db_engine


async def get_db_session() -> AsyncGenerator[AsyncSession, None]:
    """Yield a request-scoped async database session.

    Commits on success, rolls back on exception. Use as a FastAPI dependency:

        @router.get("/items")
        async def list_items(db: AsyncSession = Depends(get_db_session)):
            ...
    """
    session: AsyncSession = db_engine.session_factory()
    try:
        yield session
        await session.commit()
    except Exception:
        await session.rollback()
        raise
    finally:
        await session.close()


@property
def async_session_factory() -> sessionmaker | None:
    """Module-level access to the session factory (for WebSocket handlers)."""
    try:
        return db_engine.session_factory
    except RuntimeError:
        return None


# Make it accessible as a simple function
def get_session_factory() -> sessionmaker | None:
    """Get the session factory, or None if not initialized."""
    try:
        return db_engine.session_factory
    except RuntimeError:
        return None

