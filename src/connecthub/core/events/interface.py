"""
ConnectHub — Event Bus Interface (Broker-Agnostic).

Defines the protocols that all event bus implementations must satisfy.
Modules publish/consume events through these interfaces — never through
direct broker SDK calls. This allows swapping the underlying broker
(NATS, RabbitMQ, etc.) without touching module code.

See: ConnectHub_Blueprint_v1.md Section 3.1 — Architectural Constraints.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from collections.abc import Awaitable, Callable
from typing import Any

from connecthub.core.events.schemas import BaseEvent


# Type alias for event handler callbacks
EventHandler = Callable[[BaseEvent], Awaitable[None]]


class EventPublisher(ABC):
    """Protocol for publishing events to the event bus."""

    @abstractmethod
    async def publish(self, subject: str, event: BaseEvent) -> None:
        """Publish an event to a subject.

        Args:
            subject: The event subject/topic (e.g., "user.created", "message.sent").
            event: The event envelope containing metadata and payload.
        """

    @abstractmethod
    async def publish_durable(self, stream: str, subject: str, event: BaseEvent) -> None:
        """Publish an event to a durable stream (with delivery guarantees).

        Args:
            stream: The durable stream name (e.g., "MESSAGES").
            subject: The event subject within the stream.
            event: The event envelope containing metadata and payload.
        """


class EventSubscriber(ABC):
    """Protocol for subscribing to events from the event bus."""

    @abstractmethod
    async def subscribe(
        self,
        subject: str,
        handler: EventHandler,
        queue_group: str | None = None,
    ) -> Any:
        """Subscribe to events on a subject (fire-and-forget delivery).

        Args:
            subject: The event subject pattern (supports wildcards).
            handler: Async callback invoked for each event.
            queue_group: Optional queue group for load-balanced consumption.

        Returns:
            A subscription handle (implementation-specific).
        """

    @abstractmethod
    async def subscribe_durable(
        self,
        stream: str,
        subject: str,
        handler: EventHandler,
        durable_name: str,
        queue_group: str | None = None,
    ) -> Any:
        """Subscribe to a durable stream with acknowledgment.

        Args:
            stream: The durable stream name.
            subject: The event subject within the stream.
            handler: Async callback invoked for each event (must ack/nak).
            durable_name: Name for the durable consumer (survives restarts).
            queue_group: Optional queue group for load-balanced consumption.

        Returns:
            A subscription handle (implementation-specific).
        """

    @abstractmethod
    async def unsubscribe(self, subscription: Any) -> None:
        """Unsubscribe from a previously created subscription.

        Args:
            subscription: The subscription handle returned by subscribe/subscribe_durable.
        """


class EventBackend(EventPublisher, EventSubscriber, ABC):
    """Combined interface for a full event bus backend.

    Implementations must provide both publishing and subscribing capabilities,
    plus lifecycle management (connect/disconnect/health_check).
    """

    @abstractmethod
    async def connect(self) -> None:
        """Establish connection to the event broker."""

    @abstractmethod
    async def disconnect(self) -> None:
        """Gracefully disconnect from the event broker."""

    @abstractmethod
    async def health_check(self) -> bool:
        """Check if the event broker is reachable and healthy."""
