"""
ConnectHub — Redis Client Tests.

Tests the RedisClient lifecycle (connect, disconnect, health check)
without requiring a real Redis instance.
"""

from __future__ import annotations

from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from connecthub.core.redis.client import RedisClient


@pytest.mark.asyncio
async def test_redis_client_not_initialized() -> None:
    """Accessing client before connect() raises RuntimeError."""
    rc = RedisClient()
    with pytest.raises(RuntimeError, match="not initialized"):
        _ = rc.client


@pytest.mark.asyncio
async def test_health_check_returns_false_when_not_connected() -> None:
    """Health check returns False when client is not initialized."""
    rc = RedisClient()
    result = await rc.health_check()
    assert result is False


@pytest.mark.asyncio
async def test_disconnect_when_not_connected() -> None:
    """Disconnect is safe to call when client is not initialized."""
    rc = RedisClient()
    await rc.disconnect()  # Should not raise


@pytest.mark.asyncio
@patch("connecthub.core.redis.client.aioredis")
async def test_connect_creates_client(mock_aioredis: MagicMock) -> None:
    """Connect creates a Redis client and verifies connectivity."""
    mock_client = AsyncMock()
    mock_client.ping = AsyncMock(return_value=True)
    mock_aioredis.from_url.return_value = mock_client

    rc = RedisClient()
    await rc.connect()

    assert rc._client is not None
    mock_client.ping.assert_awaited_once()


@pytest.mark.asyncio
@patch("connecthub.core.redis.client.aioredis")
async def test_disconnect_closes_client(mock_aioredis: MagicMock) -> None:
    """Disconnect closes the Redis connection pool."""
    mock_client = AsyncMock()
    mock_client.ping = AsyncMock(return_value=True)
    mock_client.aclose = AsyncMock()
    mock_aioredis.from_url.return_value = mock_client

    rc = RedisClient()
    await rc.connect()
    await rc.disconnect()

    assert rc._client is None
    mock_client.aclose.assert_awaited_once()


@pytest.mark.asyncio
@patch("connecthub.core.redis.client.aioredis")
async def test_health_check_returns_true_when_connected(mock_aioredis: MagicMock) -> None:
    """Health check returns True when Redis responds to ping."""
    mock_client = AsyncMock()
    mock_client.ping = AsyncMock(return_value=True)
    mock_aioredis.from_url.return_value = mock_client

    rc = RedisClient()
    await rc.connect()

    result = await rc.health_check()
    assert result is True


@patch("connecthub.core.redis.client.aioredis")
async def test_failed_connect_closes_pool(mock_aioredis: MagicMock) -> None:
    mock_client = AsyncMock()
    mock_client.ping.side_effect = ConnectionError("redis unavailable")
    mock_aioredis.from_url.return_value = mock_client
    rc = RedisClient()
    with pytest.raises(ConnectionError):
        await rc.connect()
    mock_client.aclose.assert_awaited_once()
    assert rc._client is None
