"""NATS connection failure must remain visible to the application lifecycle."""

from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from connecthub.core.events.nats_backend import NATSEventBackend


async def test_failed_connection_is_reported():
    backend = NATSEventBackend()
    with patch("connecthub.core.events.nats_backend.nats.connect", new_callable=AsyncMock) as connect:
        connect.side_effect = OSError("broker unavailable")
        with pytest.raises(OSError, match="broker unavailable"):
            await backend.connect()
    assert not await backend.health_check()


async def test_partial_connection_is_closed():
    backend = NATSEventBackend()
    connection = MagicMock()
    connection.close = AsyncMock()
    connection.jetstream.side_effect = RuntimeError("JetStream unavailable")
    with patch("connecthub.core.events.nats_backend.nats.connect", new_callable=AsyncMock) as connect:
        connect.return_value = connection
        with pytest.raises(RuntimeError, match="JetStream unavailable"):
            await backend.connect()
    connection.close.assert_awaited_once()
    assert not await backend.health_check()


async def test_reconnecting_nats_is_not_ready():
    backend = NATSEventBackend()
    backend._nc = MagicMock(is_closed=False, is_connected=False, flush=AsyncMock())
    assert not await backend.health_check()
    backend._nc.flush.assert_not_awaited()


async def test_disconnect_clears_already_closed_client():
    backend = NATSEventBackend()
    backend._nc = MagicMock(is_closed=True)
    backend._js = MagicMock()
    await backend.disconnect()
    assert backend._nc is None
    assert backend._js is None
