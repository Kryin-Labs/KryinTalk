"""
ConnectHub — NATS JetStream Event Backend.

Concrete implementation of the EventBackend interface using NATS + JetStream.
This is the only file in the codebase that imports the `nats` SDK — all other
modules interact with events through the abstract interface only.

See: ConnectHub_Blueprint_v1.md Section 3.1
"""

from __future__ import annotations

import logging
from typing import Any

import nats
from nats.aio.client import Client as NATSClient
from nats.js.api import StreamConfig, RetentionPolicy, StorageType
from nats.js.client import JetStreamContext

from connecthub.config import settings
from connecthub.core.events.interface import EventBackend, EventHandler
from connecthub.core.events.schemas import BaseEvent

logger = logging.getLogger(__name__)


class NATSEventBackend(EventBackend):
    """NATS JetStream implementation of the event bus.

    Provides both fire-and-forget (Core NATS) and durable (JetStream)
    publish/subscribe patterns.
    """

    def __init__(self) -> None:
        self._nc: NATSClient | None = None
        self._js: JetStreamContext | None = None

    # ── Lifecycle ────────────────────────────

    async def connect(self) -> None:
        """Connect to the NATS server and initialize JetStream."""
        try:
            self._nc = await nats.connect(
                servers=[settings.NATS_URL],
                name=f"{settings.APP_NAME}-backend",
                max_reconnect_attempts=1,
                connect_timeout=1.0,
                reconnect_time_wait=1,
            )
            self._js = self._nc.jetstream()
            logger.info("NATS JetStream connection established.")
        except Exception as e:
            logger.warning("NATS connection skipped (not running locally): %s", e)
            self._nc = None
            self._js = None

    async def disconnect(self) -> None:
        """Gracefully close the NATS connection."""
        if self._nc and not self._nc.is_closed:
            await self._nc.drain()
            await self._nc.close()
            self._nc = None
            self._js = None
            logger.info("NATS connection closed.")

    async def health_check(self) -> bool:
        """Check if NATS is connected and responsive."""
        try:
            if self._nc is None or self._nc.is_closed:
                return False
            # Flush to verify the connection is alive
            await self._nc.flush(timeout=2)
            return True
        except Exception:
            logger.exception("NATS health check failed.")
            return False

    # ── Stream Management ────────────────────

    async def ensure_stream(
        self,
        name: str,
        subjects: list[str],
        retention: RetentionPolicy = RetentionPolicy.LIMITS,
        max_age: int = 86400 * 7,  # 7 days default
    ) -> None:
        """Ensure a JetStream stream exists with the given configuration.

        This is idempotent — if the stream already exists, it updates the config.

        Args:
            name: Stream name (e.g., "EVENTS", "MESSAGES").
            subjects: List of subject patterns the stream captures.
            retention: Retention policy (LIMITS, INTEREST, WORK_QUEUE).
            max_age: Maximum age of messages in seconds.
        """
        js = self._get_js()
        config = StreamConfig(
            name=name,
            subjects=subjects,
            retention=retention,
            storage=StorageType.FILE,
            max_age=max_age,
            num_replicas=1,  # Single-node dev; increase for production clusters
        )
        try:
            await js.find_stream_name_by_subject(subjects[0])
            await js.update_stream(config=config)
            logger.info("Stream '%s' updated.", name)
        except nats.js.errors.NotFoundError:
            await js.add_stream(config=config)
            logger.info("Stream '%s' created.", name)

    # ── Publishing ───────────────────────────

    async def publish(self, subject: str, event: BaseEvent) -> None:
        """Publish an event via Core NATS (fire-and-forget)."""
        nc = self._get_nc()
        await nc.publish(subject, event.to_bytes())
        logger.debug("Published event '%s' to subject '%s'.", event.event_type, subject)

    async def publish_durable(self, stream: str, subject: str, event: BaseEvent) -> None:
        """Publish an event to a JetStream stream (durable, with ack)."""
        js = self._get_js()
        ack = await js.publish(subject, event.to_bytes())
        logger.debug(
            "Published durable event '%s' to stream '%s' subject '%s' (seq=%s).",
            event.event_type, stream, subject, ack.seq,
        )

    # ── Subscribing ──────────────────────────

    async def subscribe(
        self,
        subject: str,
        handler: EventHandler,
        queue_group: str | None = None,
    ) -> Any:
        """Subscribe to Core NATS events (fire-and-forget)."""
        nc = self._get_nc()

        async def _msg_handler(msg: Any) -> None:
            event = BaseEvent.from_bytes(msg.data)
            await handler(event)

        sub = await nc.subscribe(subject, queue=queue_group or "", cb=_msg_handler)
        logger.info("Subscribed to subject '%s' (queue=%s).", subject, queue_group)
        return sub

    async def subscribe_durable(
        self,
        stream: str,
        subject: str,
        handler: EventHandler,
        durable_name: str,
        queue_group: str | None = None,
    ) -> Any:
        """Subscribe to a JetStream durable consumer."""
        js = self._get_js()

        async def _msg_handler(msg: Any) -> None:
            try:
                event = BaseEvent.from_bytes(msg.data)
                await handler(event)
                await msg.ack()
            except Exception:
                logger.exception("Error processing durable event on '%s'.", subject)
                await msg.nak()

        sub = await js.subscribe(
            subject,
            durable=durable_name,
            queue=queue_group or "",
            cb=_msg_handler,
        )
        logger.info(
            "Subscribed to durable stream '%s' subject '%s' (durable=%s).",
            stream, subject, durable_name,
        )
        return sub

    async def unsubscribe(self, subscription: Any) -> None:
        """Unsubscribe from a NATS subscription."""
        if subscription:
            await subscription.unsubscribe()
            logger.info("Unsubscribed from subscription.")

    # ── Internal Helpers ─────────────────────

    def _get_nc(self) -> NATSClient:
        """Return the NATS client (raises if not connected)."""
        if self._nc is None or self._nc.is_closed:
            raise RuntimeError("NATS client is not connected. Call connect() first.")
        return self._nc

    def _get_js(self) -> JetStreamContext:
        """Return the JetStream context (raises if not connected)."""
        if self._js is None:
            raise RuntimeError("JetStream is not initialized. Call connect() first.")
        return self._js


# Module-level singleton
nats_event_backend = NATSEventBackend()
