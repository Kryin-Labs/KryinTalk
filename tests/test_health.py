"""
ConnectHub — Health Endpoint Tests.

Verifies that the /health endpoint returns correct status
and reports on all infrastructure services.
"""

from __future__ import annotations

from unittest.mock import MagicMock

import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_health_endpoint_all_healthy(client: AsyncClient) -> None:
    """Health endpoint returns 'healthy' when all services are up."""
    response = await client.get("/health")

    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"
    assert data["version"] == "0.1.0"
    assert data["services"]["postgresql"]["status"] == "up"
    assert data["services"]["redis"]["status"] == "up"
    assert data["services"]["nats"]["status"] == "up"


@pytest.mark.asyncio
async def test_health_endpoint_degraded_when_db_down(
    client: AsyncClient,
    mock_db_engine: MagicMock,
) -> None:
    """Health endpoint returns 'degraded' when PostgreSQL is down."""
    mock_db_engine.health_check.return_value = False

    response = await client.get("/health")

    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "degraded"
    assert data["services"]["postgresql"]["status"] == "down"
    assert data["services"]["redis"]["status"] == "up"
    assert data["services"]["nats"]["status"] == "up"


@pytest.mark.asyncio
async def test_health_endpoint_degraded_when_redis_down(
    client: AsyncClient,
    mock_redis_client: MagicMock,
) -> None:
    """Health endpoint returns 'degraded' when Redis is down."""
    mock_redis_client.health_check.return_value = False

    response = await client.get("/health")

    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "degraded"
    assert data["services"]["redis"]["status"] == "down"


@pytest.mark.asyncio
async def test_health_endpoint_degraded_when_nats_down(
    client: AsyncClient,
    mock_nats_backend: MagicMock,
) -> None:
    """Health endpoint returns 'degraded' when NATS is down."""
    mock_nats_backend.health_check.return_value = False

    response = await client.get("/health")

    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "degraded"
    assert data["services"]["nats"]["status"] == "down"


@pytest.mark.asyncio
async def test_health_endpoint_returns_correlation_id(client: AsyncClient) -> None:
    """Health endpoint response includes a correlation ID header."""
    response = await client.get("/health")

    assert response.status_code == 200
    assert "x-correlation-id" in response.headers


async def test_ready_when_all_dependencies_are_healthy(client):
    response = await client.get("/ready")
    assert response.status_code == 200
    assert response.json()["status"] == "healthy"


@pytest.mark.parametrize("dependency", ["mock_db_engine", "mock_redis_client", "mock_nats_backend"])
async def test_ready_rejects_degraded_dependencies(client, request, dependency):
    request.getfixturevalue(dependency).health_check.return_value = False
    response = await client.get("/ready")
    assert response.status_code == 503
    assert response.json()["status"] == "degraded"


async def test_health_handles_a_failing_dependency_probe(client, mock_nats_backend):
    mock_nats_backend.health_check.side_effect = RuntimeError("probe failed")
    response = await client.get("/health")
    assert response.status_code == 200
    assert response.json()["services"]["nats"]["status"] == "down"
