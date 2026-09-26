"""
ConnectHub — Database Engine Tests.

Tests the DatabaseEngine lifecycle (connect, disconnect, health check)
without requiring a real PostgreSQL instance.
"""

from __future__ import annotations

from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from connecthub.core.database.engine import DatabaseEngine


@pytest.mark.asyncio
async def test_database_engine_not_initialized() -> None:
    """Accessing engine before connect() raises RuntimeError."""
    engine = DatabaseEngine()
    with pytest.raises(RuntimeError, match="not initialized"):
        _ = engine.engine


@pytest.mark.asyncio
async def test_session_factory_not_initialized() -> None:
    """Accessing session_factory before connect() raises RuntimeError."""
    engine = DatabaseEngine()
    with pytest.raises(RuntimeError, match="not initialized"):
        _ = engine.session_factory


@pytest.mark.asyncio
async def test_health_check_returns_false_when_not_connected() -> None:
    """Health check returns False when engine is not initialized."""
    engine = DatabaseEngine()
    result = await engine.health_check()
    assert result is False


@pytest.mark.asyncio
async def test_disconnect_when_not_connected() -> None:
    """Disconnect is safe to call when engine is not initialized."""
    engine = DatabaseEngine()
    await engine.disconnect()  # Should not raise


@pytest.mark.asyncio
@patch("connecthub.core.database.engine.create_async_engine")
async def test_connect_creates_engine(mock_create_engine: MagicMock) -> None:
    """Connect creates an async engine and session factory."""
    mock_engine = MagicMock()
    mock_engine.dispose = AsyncMock()
    mock_create_engine.return_value = mock_engine

    db = DatabaseEngine()
    await db.connect()

    assert db._engine is not None
    assert db._session_factory is not None
    mock_create_engine.assert_called_once()


@pytest.mark.asyncio
@patch("connecthub.core.database.engine.create_async_engine")
async def test_disconnect_disposes_engine(mock_create_engine: MagicMock) -> None:
    """Disconnect disposes the engine and resets state."""
    mock_engine = MagicMock()
    mock_engine.dispose = AsyncMock()
    mock_create_engine.return_value = mock_engine

    db = DatabaseEngine()
    await db.connect()
    await db.disconnect()

    assert db._engine is None
    assert db._session_factory is None
    mock_engine.dispose.assert_awaited_once()
