"""
ConnectHub Messaging Module — Pydantic Schemas.
"""

from __future__ import annotations

import uuid
from datetime import datetime

from pydantic import BaseModel, Field

from connecthub.modules.messaging.models import ConversationType, MessageType


class MessageCreate(BaseModel):
    """Send a new message."""

    content: str = Field(..., min_length=1, max_length=10000)
    message_type: MessageType = MessageType.TEXT
    parent_id: uuid.UUID | None = None


class MessageResponse(BaseModel):
    """Message response."""

    id: uuid.UUID
    conversation_id: uuid.UUID
    sender_id: uuid.UUID
    content: str
    message_type: MessageType
    parent_id: uuid.UUID | None
    sequence_num: int
    is_pinned: bool = False
    pinned_at: datetime | None = None
    pinned_by: uuid.UUID | None = None
    is_seen: bool = False
    created_at: datetime
    reactions: list["ReactionSummary"] = Field(default_factory=list)

    model_config = {"from_attributes": True}


class MessageListResponse(BaseModel):
    """Paginated message list."""

    items: list[MessageResponse]
    has_more: bool


class ReactionResponse(BaseModel):
    """Result of toggling one user's reaction."""

    emoji: str
    active: bool
    count: int


class ReactionSummary(BaseModel):
    """One emoji aggregate on a message for the requesting user."""

    emoji: str
    count: int
    reacted: bool
    user_ids: list[uuid.UUID] = Field(default_factory=list)


class DirectConversationRequest(BaseModel):
    """Start or get a DM conversation."""

    recipient_id: uuid.UUID


class ConversationCreateRequest(BaseModel):
    """Create or get a conversation."""

    conversation_type: ConversationType = ConversationType.DIRECT
    target_id: uuid.UUID | None = None
    recipient_id: uuid.UUID | None = None


class ParticipantSummary(BaseModel):
    id: uuid.UUID
    username: str
    display_name: str
    avatar_url: str | None = None
    role: str = "member"

    model_config = {"from_attributes": True}


class ConversationResponse(BaseModel):
    """Conversation response."""

    id: uuid.UUID
    organization_id: uuid.UUID
    conversation_type: ConversationType
    target_id: uuid.UUID | None = None
    name: str | None = None
    title: str | None = None
    display_name: str | None = None
    recipient_id: uuid.UUID | None = None
    recipient_name: str | None = None
    recipient_username: str | None = None
    recipient_avatar_url: str | None = None
    participant_count: int = 0
    participants: list[uuid.UUID] = Field(default_factory=list)
    participant_details: list[ParticipantSummary] = Field(default_factory=list)
    last_message: MessageResponse | None = None
    unread_count: int = 0
    created_at: datetime

    model_config = {"from_attributes": True}


class ConversationListResponse(BaseModel):
    """List of conversations."""

    items: list[ConversationResponse]
    total: int
