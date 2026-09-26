"""
ConnectHub — Async Redis Client.

Provides an async Redis connection pool with health checking.
Used for caching, pub/sub, session management, and presence tracking.
"""

from __future__ import annotations

import asyncio
import logging

import redis.asyncio as aioredis

from connecthub.config import settings

logger = logging.getLogger(__name__)


class RedisClient:
    """Manages the async Redis connection lifecycle."""

    def __init__(self) -> None:
        self._client: aioredis.Redis | None = None  # type: ignore[type-arg]

    async def connect(self) -> None:
        """Create the Redis connection pool."""
        self._client = aioredis.from_url(
            settings.REDIS_URL,
            encoding="utf-8",
            decode_responses=True,
            max_connections=20,
            socket_connect_timeout=5,
            socket_keepalive=True,
            health_check_interval=30,
        )
        # Verify connectivity
        await self._client.ping()
        logger.info("Redis connection pool created.")

    async def disconnect(self) -> None:
        """Close the Redis connection pool."""
        if self._client:
            await self._client.aclose()
            self._client = None
            logger.info("Redis connection pool closed.")

    @property
    def client(self) -> aioredis.Redis:  # type: ignore[type-arg]
        """Return the Redis client (raises if not connected)."""
        if self._client is None:
            raise RuntimeError("Redis client is not initialized. Call connect() first.")
        return self._client

    async def health_check(self) -> bool:
        """Check if Redis is reachable."""
        try:
            if self._client is None:
                return False
            return bool(await asyncio.wait_for(self._client.ping(), timeout=0.2))
        except Exception:
            return False


# Module-level singleton
redis_client = RedisClient()
