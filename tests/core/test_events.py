"""
ConnectHub — Event Bus Interface Tests.

Tests the event bus abstraction layer using an in-memory fake backend.
Verifies the contract that all event backends must satisfy,
without requiring a real NATS server.
"""

from __future__ import annotations

import asyncio
from typing import Any

import pytest

from connecthub.core.events.interface import EventBackend, EventHandler
from connecthub.core.events.schemas import BaseEvent


# ──────────────────────────────────────────────
# In-Memory Fake Backend (for testing)
# ──────────────────────────────────────────────
class InMemoryEventBackend(EventBackend):
    """In-memory event backend for testing the interface contract."""

    def __init__(self) -> None:
        self._connected = False
        self._subscriptions: dict[str, list[EventHandler]] = {}
        self._published: list[tuple[str, BaseEvent]] = []

    async def connect(self) -> None:
        self._connected = True

    async def disconnect(self) -> None:
        self._connected = False
        self._subscriptions.clear()

    async def health_check(self) -> bool:
        return self._connected

    async def publish(self, subject: str, event: BaseEvent) -> None:
        self._published.append((subject, event))
        # Deliver to subscribers
        for handler in self._subscriptions.get(subject, []):
            await handler(event)

    async def publish_durable(self, stream: str, subject: str, event: BaseEvent) -> None:
        # In memory, treat durable same as regular publish
        await self.publish(subject, event)

    async def subscribe(
        self,
        subject: str,
        handler: EventHandler,
        queue_group: str | None = None,
    ) -> Any:
        self._subscriptions.setdefault(subject, []).append(handler)
        return (subject, handler)

    async def subscribe_durable(
        self,
        stream: str,
        subject: str,
        handler: EventHandler,
        durable_name: str,
        queue_group: str | None = None,
    ) -> Any:
        return await self.subscribe(subject, handler, queue_group)

    async def unsubscribe(self, subscription: Any) -> None:
        subject, handler = subscription
        if subject in self._subscriptions:
            self._subscriptions[subject].remove(handler)


# ──────────────────────────────────────────────
# Tests
# ──────────────────────────────────────────────


@pytest.mark.asyncio
async def test_backend_lifecycle() -> None:
    """Backend can connect, report healthy, and disconnect."""
    backend = InMemoryEventBackend()

    assert await backend.health_check() is False

    await backend.connect()
    assert await backend.health_check() is True

    await backend.disconnect()
    assert await backend.health_check() is False


@pytest.mark.asyncio
async def test_publish_and_subscribe() -> None:
    """Published events are delivered to subscribers."""
    backend = InMemoryEventBackend()
    await backend.connect()

    received_events: list[BaseEvent] = []

    async def handler(event: BaseEvent) -> None:
        received_events.append(event)

    await backend.subscribe("test.subject", handler)

    event = BaseEvent(event_type="test.created", source_module="test")
    await backend.publish("test.subject", event)

    assert len(received_events) == 1
    assert received_events[0].event_type == "test.created"
    assert received_events[0].source_module == "test"


@pytest.mark.asyncio
async def test_unsubscribe_stops_delivery() -> None:
    """Unsubscribed handlers no longer receive events."""
    backend = InMemoryEventBackend()
    await backend.connect()

    received_events: list[BaseEvent] = []

    async def handler(event: BaseEvent) -> None:
        received_events.append(event)

    sub = await backend.subscribe("test.subject", handler)
    await backend.unsubscribe(sub)

    event = BaseEvent(event_type="test.created", source_module="test")
    await backend.publish("test.subject", event)

    assert len(received_events) == 0


@pytest.mark.asyncio
async def test_multiple_subscribers() -> None:
    """Multiple subscribers on the same subject all receive the event."""
    backend = InMemoryEventBackend()
    await backend.connect()

    results_a: list[BaseEvent] = []
    results_b: list[BaseEvent] = []

    async def handler_a(event: BaseEvent) -> None:
        results_a.append(event)

    async def handler_b(event: BaseEvent) -> None:
        results_b.append(event)

    await backend.subscribe("multi.subject", handler_a)
    await backend.subscribe("multi.subject", handler_b)

    event = BaseEvent(event_type="multi.test", source_module="test")
    await backend.publish("multi.subject", event)

    assert len(results_a) == 1
    assert len(results_b) == 1


@pytest.mark.asyncio
async def test_event_serialization_roundtrip() -> None:
    """Events can be serialized to bytes and deserialized back."""
    original = BaseEvent(
        event_type="user.created",
        source_module="auth",
        payload={"user_id": "abc-123", "email": "test@example.com"},
    )

    serialized = original.to_bytes()
    assert isinstance(serialized, bytes)

    deserialized = BaseEvent.from_bytes(serialized)
    assert deserialized.event_type == "user.created"
    assert deserialized.source_module == "auth"
    assert deserialized.payload["user_id"] == "abc-123"
    assert deserialized.event_id == original.event_id


@pytest.mark.asyncio
async def test_event_has_auto_generated_fields() -> None:
    """Events automatically generate event_id and timestamp."""
    event = BaseEvent(event_type="test.event", source_module="test")

    assert event.event_id is not None
    assert len(event.event_id) > 0
    assert event.timestamp is not None


@pytest.mark.asyncio
async def test_durable_publish_and_subscribe() -> None:
    """Durable publish/subscribe follows the same contract."""
    backend = InMemoryEventBackend()
    await backend.connect()

    received: list[BaseEvent] = []

    async def handler(event: BaseEvent) -> None:
        received.append(event)

    await backend.subscribe_durable(
        stream="EVENTS",
        subject="durable.test",
        handler=handler,
        durable_name="test-consumer",
    )

    event = BaseEvent(event_type="durable.created", source_module="test")
    await backend.publish_durable("EVENTS", "durable.test", event)

    assert len(received) == 1
    assert received[0].event_type == "durable.created"
