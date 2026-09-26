"""
ConnectHub — Test Fixtures.

Shared fixtures for the test suite. Provides a test HTTP client
that uses the FastAPI TestClient with overridden dependencies.
"""

from __future__ import annotations

import os
from collections.abc import AsyncGenerator
from unittest.mock import AsyncMock, MagicMock

import pytest
from httpx import ASGITransport, AsyncClient

# Never read a developer's credentials or point tests at their database.
os.environ.update({
    "CONNECTHUB_ENV_FILE": "",
    "APP_ENV": "development",
    "APP_DEBUG": "false",
    "SECRET_KEY": "offline-test-signing-key-not-for-deployment",
    "DATABASE_URL_OVERRIDE": "sqlite+aiosqlite:///:memory:",
    "REDIS_HOST": "127.0.0.1",
    "REDIS_PASSWORD": "",
    "NATS_URL": "nats://127.0.0.1:4222",
})

from connecthub.core.database.engine import DatabaseEngine
from connecthub.core.events.nats_backend import NATSEventBackend
from connecthub.core.redis.client import RedisClient


@pytest.fixture
def mock_db_engine(monkeypatch: pytest.MonkeyPatch) -> MagicMock:
    """Mock the database engine for tests that don't need a real DB."""
    mock = MagicMock(spec=DatabaseEngine)
    mock.connect = AsyncMock()
    mock.disconnect = AsyncMock()
    mock.health_check = AsyncMock(return_value=True)
    monkeypatch.setattr("connecthub.main.db_engine", mock)
    return mock


@pytest.fixture
def mock_redis_client(monkeypatch: pytest.MonkeyPatch) -> MagicMock:
    """Mock the Redis client for tests that don't need a real Redis."""
    mock = MagicMock(spec=RedisClient)
    mock.connect = AsyncMock()
    mock.disconnect = AsyncMock()
    mock.health_check = AsyncMock(return_value=True)
    monkeypatch.setattr("connecthub.main.redis_client", mock)
    return mock


@pytest.fixture
def mock_nats_backend(monkeypatch: pytest.MonkeyPatch) -> MagicMock:
    """Mock the NATS backend for tests that don't need a real NATS server."""
    mock = MagicMock(spec=NATSEventBackend)
    mock.connect = AsyncMock()
    mock.disconnect = AsyncMock()
    mock.health_check = AsyncMock(return_value=True)
    monkeypatch.setattr("connecthub.main.nats_event_backend", mock)
    return mock


@pytest.fixture
async def client(
    mock_db_engine: MagicMock,
    mock_redis_client: MagicMock,
    mock_nats_backend: MagicMock,
) -> AsyncGenerator[AsyncClient, None]:
    """Provide an async test client with all infrastructure mocked."""
    from connecthub.main import app

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://testserver") as ac:
        yield ac
