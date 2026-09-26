"""
ConnectHub — Event Schemas.

Defines the base event envelope that all events must use.
This ensures consistent structure for logging, auditing, and replay.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone
from typing import Any

from pydantic import BaseModel, Field


class BaseEvent(BaseModel):
    """Base event envelope — all events inherit from this.

    Provides consistent metadata for every event flowing through
    the event bus, regardless of the underlying broker.
    """

    event_id: str = Field(
        default_factory=lambda: str(uuid.uuid4()),
        description="Unique identifier for this event instance.",
    )
    event_type: str = Field(
        ...,
        description="Dot-separated event type (e.g., 'user.created', 'message.sent').",
    )
    timestamp: datetime = Field(
        default_factory=lambda: datetime.now(timezone.utc),
        description="UTC timestamp when the event was created.",
    )
    source_module: str = Field(
        ...,
        description="The module that produced this event (e.g., 'auth', 'messaging').",
    )
    correlation_id: str | None = Field(
        default=None,
        description="Optional correlation ID for tracing related events across modules.",
    )
    payload: dict[str, Any] = Field(
        default_factory=dict,
        description="The event-specific data payload.",
    )

    def to_bytes(self) -> bytes:
        """Serialize the event to bytes for broker transmission."""
        return self.model_dump_json().encode("utf-8")

    @classmethod
    def from_bytes(cls, data: bytes) -> BaseEvent:
        """Deserialize an event from bytes received from the broker."""
        return cls.model_validate_json(data)
