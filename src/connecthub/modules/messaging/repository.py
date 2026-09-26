"""
ConnectHub Messaging Module — Data Access Layer.

All message queries filter out soft-deleted records.
PostgreSQL is the system of record (Section 3.1).
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone

from sqlalchemy import and_, or_, select, func as sqlfunc
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from connecthub.modules.messaging.models import (
    Conversation,
    ConversationParticipant,
    ConversationType,
    Message,
    MessageReaction,
    MessageType,
)


class MessagingRepository:
    """Data access for conversations and messages."""

    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    # ── Conversations ────────────────────────

    async def create_conversation(
        self,
        organization_id: uuid.UUID,
        conversation_type: ConversationType,
        target_id: uuid.UUID | None = None,
    ) -> Conversation:
        conv = Conversation(
            organization_id=organization_id,
            conversation_type=conversation_type,
            target_id=target_id,
        )
        self._session.add(conv)
        await self._session.flush()
        return conv

    async def get_conversation_by_id(
        self, conversation_id: uuid.UUID,
    ) -> Conversation | None:
        stmt = select(Conversation).where(
            Conversation.id == conversation_id,
        ).options(selectinload(Conversation.participants))
        result = await self._session.execute(stmt)
        return result.scalar_one_or_none()

    async def get_direct_conversation(
        self,
        organization_id: uuid.UUID,
        user_a: uuid.UUID,
        user_b: uuid.UUID,
    ) -> Conversation | None:
        """Find an existing DM conversation between two users."""
        # Subquery: conversations where both users are participants
        stmt = (
            select(Conversation)
            .join(ConversationParticipant)
            .where(
                and_(
                    Conversation.organization_id == organization_id,
                    Conversation.conversation_type == ConversationType.DIRECT,
                    ConversationParticipant.user_id.in_([user_a, user_b]),
                ),
            )
            .group_by(Conversation.id)
            .having(sqlfunc.count(ConversationParticipant.id) == 2)
            .options(selectinload(Conversation.participants))
        )
        result = await self._session.execute(stmt)
        return result.scalar_one_or_none()

    async def get_conversation_for_target(
        self,
        organization_id: uuid.UUID,
        conversation_type: ConversationType,
        target_id: uuid.UUID,
    ) -> Conversation | None:
        """Get conversation for a channel or group."""
        stmt = select(Conversation).where(
            and_(
                Conversation.organization_id == organization_id,
                Conversation.conversation_type == conversation_type,
                Conversation.target_id == target_id,
            ),
        ).options(selectinload(Conversation.participants))
        result = await self._session.execute(stmt)
        return result.scalar_one_or_none()

    async def list_conversations_for_user(
        self,
        user_id: uuid.UUID,
        limit: int = 50,
        offset: int = 0,
    ) -> list[Conversation]:
        """List direct messages and groups visible to the user."""
        from connecthub.modules.group.models import Group, GroupMember

        group_member_subq = select(GroupMember.group_id).where(GroupMember.user_id == user_id)
        group_creator_subq = select(Group.id).where(Group.created_by == user_id)
        part_conv_ids_subq = select(ConversationParticipant.conversation_id).where(ConversationParticipant.user_id == user_id)

        direct_condition = and_(
            Conversation.conversation_type == ConversationType.DIRECT,
            Conversation.id.in_(part_conv_ids_subq),
        )

        # For group conversations: User MUST be an active group member or creator
        group_condition = and_(
            Conversation.conversation_type == ConversationType.GROUP,
            or_(
                Conversation.target_id.in_(group_member_subq),
                Conversation.target_id.in_(group_creator_subq),
            ),
        )

        stmt = (
            select(Conversation)
            .where(or_(direct_condition, group_condition))
            .options(selectinload(Conversation.participants))
            .order_by(Conversation.updated_at.desc())
            .limit(limit)
            .offset(offset)
        )
        result = await self._session.execute(stmt)
        return list(result.scalars().unique().all())

    async def count_conversations_for_user(self, user_id: uuid.UUID) -> int:
        from connecthub.modules.group.models import Group, GroupMember

        group_member_subq = select(GroupMember.group_id).where(GroupMember.user_id == user_id)
        group_creator_subq = select(Group.id).where(Group.created_by == user_id)
        part_conv_ids_subq = select(ConversationParticipant.conversation_id).where(ConversationParticipant.user_id == user_id)

        direct_condition = and_(
            Conversation.conversation_type == ConversationType.DIRECT,
            Conversation.id.in_(part_conv_ids_subq),
        )

        group_condition = and_(
            Conversation.conversation_type == ConversationType.GROUP,
            or_(
                Conversation.target_id.in_(group_member_subq),
                Conversation.target_id.in_(group_creator_subq),
            ),
        )

        stmt = (
            select(sqlfunc.count(Conversation.id))
            .where(or_(direct_condition, group_condition))
        )
        result = await self._session.execute(stmt)
        return result.scalar() or 0

    # ── Participants ─────────────────────────

    async def add_participant(
        self,
        conversation_id: uuid.UUID,
        user_id: uuid.UUID,
    ) -> ConversationParticipant:
        stmt = select(ConversationParticipant).where(
            and_(
                ConversationParticipant.conversation_id == conversation_id,
                ConversationParticipant.user_id == user_id,
            )
        )
        existing = (await self._session.execute(stmt)).scalar_one_or_none()
        if existing is not None:
            return existing

        participant = ConversationParticipant(
            conversation_id=conversation_id,
            user_id=user_id,
        )
        self._session.add(participant)
        await self._session.flush()
        return participant

    async def is_participant(
        self,
        conversation_id: uuid.UUID,
        user_id: uuid.UUID,
    ) -> bool:
        stmt = select(sqlfunc.count(ConversationParticipant.id)).where(
            and_(
                ConversationParticipant.conversation_id == conversation_id,
                ConversationParticipant.user_id == user_id,
            ),
        )
        result = await self._session.execute(stmt)
        return result.scalar_one() > 0

    async def get_participant_ids(
        self, conversation_id: uuid.UUID,
    ) -> list[uuid.UUID]:
        stmt = select(ConversationParticipant.user_id).where(
            ConversationParticipant.conversation_id == conversation_id,
        )
        result = await self._session.execute(stmt)
        return list(result.scalars().all())

    async def update_last_read(
        self,
        conversation_id: uuid.UUID,
        user_id: uuid.UUID,
        timestamp: datetime | None = None,
    ) -> None:
        ts = timestamp or datetime.now(timezone.utc)
        stmt = select(ConversationParticipant).where(
            and_(
                ConversationParticipant.conversation_id == conversation_id,
                ConversationParticipant.user_id == user_id,
            ),
        )
        result = await self._session.execute(stmt)
        participant = result.scalar_one_or_none()
        if participant:
            participant.last_read_at = ts
        else:
            p = ConversationParticipant(
                conversation_id=conversation_id,
                user_id=user_id,
                last_read_at=ts,
            )
            self._session.add(p)
        await self._session.flush()

    async def mark_unread(
        self,
        conversation_id: uuid.UUID,
        user_id: uuid.UUID,
    ) -> None:
        """Mark a conversation as unread by clearing last_read_at."""
        stmt = select(ConversationParticipant).where(
            and_(
                ConversationParticipant.conversation_id == conversation_id,
                ConversationParticipant.user_id == user_id,
            ),
        )
        result = await self._session.execute(stmt)
        participant = result.scalar_one_or_none()
        if participant:
            participant.last_read_at = None
        else:
            p = ConversationParticipant(
                conversation_id=conversation_id,
                user_id=user_id,
                last_read_at=None,
            )
            self._session.add(p)
        await self._session.flush()

    async def get_unread_count(
        self,
        conversation_id: uuid.UUID,
        user_id: uuid.UUID,
    ) -> int:
        """Calculate unread message count for a single conversation for a user."""
        stmt_part = select(ConversationParticipant.last_read_at).where(
            and_(
                ConversationParticipant.conversation_id == conversation_id,
                ConversationParticipant.user_id == user_id,
            )
        )
        last_read = (await self._session.execute(stmt_part)).scalar_one_or_none()

        filters = [
            Message.conversation_id == conversation_id,
            Message.sender_id != user_id,
            Message.deleted_at.is_(None),
        ]
        if last_read is not None:
            filters.append(Message.created_at > last_read)

        stmt_msg = select(sqlfunc.count(Message.id)).where(and_(*filters))
        result = await self._session.execute(stmt_msg)
        return result.scalar() or 0

    async def get_batch_unread_counts(
        self,
        conversation_ids: list[uuid.UUID],
        user_id: uuid.UUID,
    ) -> dict[uuid.UUID, int]:
        """Calculate unread counts for a list of conversations for a user."""
        if not conversation_ids:
            return {}

        counts: dict[uuid.UUID, int] = {}
        for cid in conversation_ids:
            counts[cid] = await self.get_unread_count(cid, user_id)
        return counts

    async def get_other_participant_last_read(
        self,
        conversation_id: uuid.UUID,
        user_id: uuid.UUID,
    ) -> datetime | None:
        """Get the latest last_read_at among other participants in the conversation."""
        stmt = select(sqlfunc.max(ConversationParticipant.last_read_at)).where(
            and_(
                ConversationParticipant.conversation_id == conversation_id,
                ConversationParticipant.user_id != user_id,
            )
        )
        result = await self._session.execute(stmt)
        return result.scalar()

    # ── Messages ─────────────────────────────

    async def create_message(
        self,
        conversation_id: uuid.UUID,
        sender_id: uuid.UUID,
        content: str,
        message_type: MessageType = MessageType.TEXT,
        parent_id: uuid.UUID | None = None,
        metadata_json: dict | None = None,
    ) -> Message:
        msg = Message(
            conversation_id=conversation_id,
            sender_id=sender_id,
            content=content,
            message_type=message_type,
            parent_id=parent_id,
            metadata_json=metadata_json,
        )
        self._session.add(msg)
        await self._session.flush()
        return msg

    async def get_message_by_id(self, message_id: uuid.UUID) -> Message | None:
        stmt = select(Message).where(
            and_(Message.id == message_id, Message.deleted_at.is_(None)),
        )
        result = await self._session.execute(stmt)
        return result.scalar_one_or_none()

    async def list_messages(
        self,
        conversation_id: uuid.UUID,
        limit: int = 50,
        before_seq: int | None = None,
    ) -> list[Message]:
        """List messages in a conversation, newest first.

        Uses cursor-based pagination via `before_seq` (sequence number).
        """
        stmt = select(Message).where(
            and_(
                Message.conversation_id == conversation_id,
                Message.deleted_at.is_(None),
            ),
        )
        if before_seq is not None:
            stmt = stmt.where(Message.sequence_num < before_seq)
        stmt = stmt.order_by(Message.sequence_num.desc()).limit(limit)
        result = await self._session.execute(stmt)
        return list(result.scalars().all())

    async def get_last_message(
        self, conversation_id: uuid.UUID,
    ) -> Message | None:
        stmt = (
            select(Message)
            .where(
                and_(
                    Message.conversation_id == conversation_id,
                    Message.deleted_at.is_(None),
                ),
            )
            .order_by(Message.sequence_num.desc())
            .limit(1)
        )
        result = await self._session.execute(stmt)
        return result.scalar_one_or_none()

    async def update_message(self, message_id: uuid.UUID, content: str) -> Message | None:
        msg = await self.get_message_by_id(message_id)
        if msg:
            msg.content = content
            meta = dict(msg.metadata_json or {})
            meta["edited"] = True
            msg.metadata_json = meta
        return msg

    async def soft_delete_message(self, message_id: uuid.UUID) -> Message | None:
        msg = await self.get_message_by_id(message_id)
        if msg:
            msg.deleted_at = datetime.now(timezone.utc)
        return msg

    async def get_reaction(
        self,
        message_id: uuid.UUID,
        user_id: uuid.UUID,
        emoji: str,
    ) -> MessageReaction | None:
        stmt = select(MessageReaction).where(
            and_(
                MessageReaction.message_id == message_id,
                MessageReaction.user_id == user_id,
                MessageReaction.emoji == emoji,
            ),
        )
        result = await self._session.execute(stmt)
        return result.scalar_one_or_none()

    async def add_reaction(
        self,
        message_id: uuid.UUID,
        user_id: uuid.UUID,
        emoji: str,
    ) -> MessageReaction:
        reaction = MessageReaction(message_id=message_id, user_id=user_id, emoji=emoji)
        self._session.add(reaction)
        await self._session.flush()
        return reaction

    async def remove_reaction(self, reaction: MessageReaction) -> None:
        await self._session.delete(reaction)
        await self._session.flush()

    async def count_reactions(self, message_id: uuid.UUID, emoji: str) -> int:
        stmt = select(sqlfunc.count(MessageReaction.id)).where(
            and_(MessageReaction.message_id == message_id, MessageReaction.emoji == emoji),
        )
        result = await self._session.execute(stmt)
        return result.scalar_one()

    async def list_reactions(self, message_id: uuid.UUID) -> list[MessageReaction]:
        stmt = select(MessageReaction).where(MessageReaction.message_id == message_id)
        result = await self._session.execute(stmt)
        return list(result.scalars().all())

    async def list_reactions_for_messages(
        self, message_ids: list[uuid.UUID],
    ) -> list[MessageReaction]:
        if not message_ids:
            return []
        stmt = select(MessageReaction).where(MessageReaction.message_id.in_(message_ids))
        result = await self._session.execute(stmt)
        return list(result.scalars().all())

    # ── Pinned Messages ──────────────────────

    async def pin_message(self, message_id: uuid.UUID, user_id: uuid.UUID) -> Message | None:
        msg = await self.get_message_by_id(message_id)
        if msg:
            msg.is_pinned = True
            msg.pinned_at = datetime.now(timezone.utc)
            msg.pinned_by = user_id
            await self._session.flush()
        return msg

    async def unpin_message(self, message_id: uuid.UUID) -> Message | None:
        msg = await self.get_message_by_id(message_id)
        if msg:
            msg.is_pinned = False
            msg.pinned_at = None
            msg.pinned_by = None
            await self._session.flush()
        return msg

    async def list_pinned_messages(self, conversation_id: uuid.UUID) -> list[Message]:
        stmt = select(Message).where(
            and_(
                Message.conversation_id == conversation_id,
                Message.is_pinned.is_(True),
                Message.deleted_at.is_(None),
            ),
        ).order_by(Message.pinned_at.desc())
        result = await self._session.execute(stmt)
        return list(result.scalars().all())
