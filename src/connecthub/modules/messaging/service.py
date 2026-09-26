"""
ConnectHub Messaging Module — Business Logic.

Messages persist to PostgreSQL first (system of record),
then fan out via NATS for real-time delivery (Section 3.1).
Includes pin management and group permission enforcement.
"""

from __future__ import annotations

import logging
import re
import uuid

from sqlalchemy import and_, select
from sqlalchemy.ext.asyncio import AsyncSession

from connecthub.core.audit.service import AuditService
from connecthub.core.exceptions import ForbiddenError, NotFoundError
from connecthub.core.permissions.policy import PolicyService
from connecthub.modules.auth.models import User
from connecthub.modules.auth.repository import AuthRepository
from connecthub.modules.messaging.models import ConversationType, MessageReaction
from connecthub.modules.messaging.repository import MessagingRepository
from connecthub.modules.messaging.schemas import (
    ConversationListResponse,
    ConversationResponse,
    MessageCreate,
    MessageListResponse,
    MessageResponse,
    ParticipantSummary,
    ReactionResponse,
    ReactionSummary,
)

from connecthub.modules.notifications.models import NotificationType
from connecthub.modules.notifications.service import NotificationService

logger = logging.getLogger(__name__)


def _msg_response(msg, reactions: list[ReactionSummary] | None = None, is_seen: bool = False) -> MessageResponse:
    return MessageResponse(
        id=msg.id,
        conversation_id=msg.conversation_id,
        sender_id=msg.sender_id,
        content=msg.content,
        message_type=msg.message_type,
        parent_id=msg.parent_id,
        sequence_num=msg.sequence_num,
        is_pinned=getattr(msg, "is_pinned", False),
        pinned_at=getattr(msg, "pinned_at", None),
        pinned_by=getattr(msg, "pinned_by", None),
        is_seen=is_seen,
        created_at=msg.created_at,
        reactions=reactions or [],
    )


def _conv_response(
    conv,
    last_msg=None,
    unread_count: int = 0,
    name: str | None = None,
    title: str | None = None,
    display_name: str | None = None,
    recipient_id: uuid.UUID | None = None,
    recipient_name: str | None = None,
    recipient_username: str | None = None,
    recipient_avatar_url: str | None = None,
    participant_details: list[ParticipantSummary] | None = None,
) -> ConversationResponse:
    p_ids = [p.user_id for p in conv.participants] if conv.participants else []
    return ConversationResponse(
        id=conv.id,
        organization_id=conv.organization_id,
        conversation_type=conv.conversation_type,
        target_id=conv.target_id,
        name=name or getattr(conv, "name", None),
        title=title or getattr(conv, "title", None) or name or getattr(conv, "name", None),
        display_name=display_name or title or getattr(conv, "title", None) or name or getattr(conv, "name", None),
        recipient_id=recipient_id,
        recipient_name=recipient_name,
        recipient_username=recipient_username,
        recipient_avatar_url=recipient_avatar_url,
        participant_count=len(p_ids),
        participants=p_ids,
        participant_details=participant_details or [],
        last_message=_msg_response(last_msg) if last_msg else None,
        unread_count=unread_count,
        created_at=conv.created_at,
    )



class MessagingService:
    """Messaging service — persist + fan-out + permission gating."""

    def __init__(self, session: AsyncSession) -> None:
        self._session = session
        self._repo = MessagingRepository(session)
        self._auth_repo = AuthRepository(session)
        self._policy = PolicyService(session)
        self._audit = AuditService(session)

    async def _get_org_id(self, user_id: uuid.UUID) -> uuid.UUID:
        user = await self._auth_repo.get_user_by_id(user_id)
        if user is None:
            raise NotFoundError("Resource not found.")
        return user.organization_id

    async def _require_participant(
        self, user_id: uuid.UUID, conversation_id: uuid.UUID,
    ) -> None:
        """Ensure user is a participant. For Groups, strictly enforces that user is currently a group member/creator/admin."""
        conv = await self._repo.get_conversation_by_id(conversation_id)
        if conv is None:
            raise NotFoundError("Resource not found.")

        # Special strict handling for Group conversations
        if conv.conversation_type == ConversationType.GROUP and conv.target_id:
            from connecthub.modules.group.models import GroupMember
            from connecthub.modules.group.service import GroupService

            is_sa = await self._policy.is_super_admin(user_id)
            if is_sa:
                if not await self._repo.is_participant(conversation_id, user_id):
                    await self._repo.add_participant(conversation_id, user_id)
                return

            group_service = GroupService(self._session)
            try:
                grp = await group_service.get_group(user_id, conv.target_id)
            except Exception:
                raise ForbiddenError("You do not have access to this group.")

            # Verify active membership / creator / admin status
            mem_stmt = select(GroupMember).where(
                and_(
                    GroupMember.group_id == conv.target_id,
                    GroupMember.user_id == user_id,
                )
            )
            is_mem = (await self._session.execute(mem_stmt)).scalar_one_or_none() is not None
            is_creator = str(grp.created_by) == str(user_id)
            is_admin = await group_service._can_read_all_groups(user_id)
            is_org_wide = getattr(grp, 'visibility', '') == 'organization' and not getattr(grp, 'is_private', True)

            if not (is_mem or is_creator or is_admin or is_org_wide):
                raise ForbiddenError("You are not a member of this group.")

            if not await self._repo.is_participant(conversation_id, user_id):
                await self._repo.add_participant(conversation_id, user_id)
            return

        if await self._repo.is_participant(conversation_id, user_id):
            return

        user = await self._auth_repo.get_user_by_id(user_id)
        if conv is not None and user is not None:
            is_sa = await self._policy.is_super_admin(user_id)
            if is_sa:
                await self._repo.add_participant(conversation_id, user_id)
                return

        raise NotFoundError("Resource not found.")

    async def _check_group_perm(
        self, conversation_id: uuid.UUID, user_id: uuid.UUID, permission_key: str,
    ) -> None:
        """If conversation is a group, enforce group custom permission."""
        conv = await self._repo.get_conversation_by_id(conversation_id)
        if conv and conv.conversation_type == ConversationType.GROUP and conv.target_id:
            from connecthub.modules.group.service import GroupService
            group_service = GroupService(self._session)
            has_perm = await group_service.check_group_permission(conv.target_id, user_id, permission_key)
            if not has_perm:
                raise ForbiddenError(f"You do not have permission to '{permission_key}' in this group.")

    # ── Direct Messaging ─────────────────────

    async def start_direct_message(
        self,
        user_id: uuid.UUID,
        recipient_id: uuid.UUID,
    ) -> ConversationResponse:
        """Get or create a DM conversation (idempotent)."""
        org_id = await self._get_org_id(user_id)

        recipient = await self._auth_repo.get_user_by_id(recipient_id)
        if recipient is None or recipient.organization_id != org_id:
            raise NotFoundError("Resource not found.")

        conv = await self._repo.get_direct_conversation(org_id, user_id, recipient_id)
        if conv is None:
            conv = await self._repo.create_conversation(
                organization_id=org_id,
                conversation_type=ConversationType.DIRECT,
            )
            await self._repo.add_participant(conv.id, user_id)
            await self._repo.add_participant(conv.id, recipient_id)

            await self._audit.log(
                user_id=user_id,
                action="conversation.dm.created",
                resource_type="conversation",
                resource_id=str(conv.id),
            )
            conv = await self._repo.get_conversation_by_id(conv.id)

        return _conv_response(conv)

    async def get_or_create_conversation(
        self,
        user_id: uuid.UUID,
        conversation_type: ConversationType,
        target_id: uuid.UUID | None = None,
        recipient_id: uuid.UUID | None = None,
    ) -> ConversationResponse:
        """Get or create conversation for direct, channel, or group."""
        org_id = await self._get_org_id(user_id)
        if conversation_type == ConversationType.DIRECT or recipient_id:
            if recipient_id is None:
                raise NotFoundError("Recipient is required for direct conversation.")
            return await self.start_direct_message(user_id, recipient_id)

        if target_id is None:
            raise NotFoundError("Target ID is required for channel or group conversation.")

        conv = await self._repo.get_conversation_for_target(org_id, conversation_type, target_id)
        if conv is None:
            conv = await self._repo.create_conversation(
                organization_id=org_id,
                conversation_type=conversation_type,
                target_id=target_id,
            )
            await self._repo.add_participant(conv.id, user_id)
            await self._audit.log(
                user_id=user_id,
                action=f"conversation.{conversation_type.value}.created",
                resource_type="conversation",
                resource_id=str(conv.id),
            )
            conv = await self._repo.get_conversation_by_id(conv.id)
        else:
            if not await self._repo.is_participant(conv.id, user_id):
                await self._repo.add_participant(conv.id, user_id)
                conv = await self._repo.get_conversation_by_id(conv.id)

        return _conv_response(conv)

    async def _handle_message_notifications(
        self,
        sender_id: uuid.UUID,
        conversation_id: uuid.UUID,
        content: str,
        message_id: uuid.UUID | None = None,
    ) -> None:
        """Create notifications for mentions (@username) and direct messages."""
        try:
            conv = await self._repo.get_conversation_by_id(conversation_id)
            if conv is None:
                return

            sender = await self._auth_repo.get_user_by_id(sender_id)
            sender_name = sender.display_name if sender else "User"
            sender_uname = sender.username if sender else "user"

            notif_service = NotificationService(self._session)

            conv_name = "Conversation"
            if conv.conversation_type == ConversationType.GROUP and conv.target_id:
                from connecthub.modules.group.service import GroupService
                group_service = GroupService(self._session)
                try:
                    g = await group_service.get_group(sender_id, conv.target_id)
                    conv_name = f"group '{g.name}'"
                except Exception:
                    conv_name = "the group"
            # 1. Parse @mentions
            mention_pattern = r"@([a-zA-Z0-9_\.\-]+)"
            mentioned_tags = set(re.findall(mention_pattern, content))
            notified_user_ids: set[uuid.UUID] = set()

            if mentioned_tags and sender is not None:
                all_users = await self._auth_repo.list_users_by_org(sender.organization_id)
                user_by_uname = {u.username.lower(): u for u in all_users if u.username}
                user_by_email = {u.email.lower(): u for u in all_users if u.email}

                for tag in mentioned_tags:
                    tag_lower = tag.lower()
                    target_user = user_by_uname.get(tag_lower) or user_by_email.get(tag_lower)
                    if target_user and target_user.id != sender_id:
                        notified_user_ids.add(target_user.id)
                        snippet = content[:180] + ("..." if len(content) > 180 else "")
                        await notif_service.create_notification(
                            user_id=target_user.id,
                            notification_type=NotificationType.MENTION,
                            title=f"You were mentioned by @{sender_uname} in {conv_name}",
                            body=snippet,
                            resource_type="message",
                            resource_id=str(message_id) if message_id else str(conversation_id),
                            conversation_id=conversation_id,
                        )

            # 2. For Direct Messages, notify the other participant
            if conv.conversation_type == ConversationType.DIRECT:
                p_ids = await self._repo.get_participant_ids(conversation_id)
                for pid in p_ids:
                    if pid != sender_id and pid not in notified_user_ids:
                        snippet = content[:180] + ("..." if len(content) > 180 else "")
                        await notif_service.create_notification(
                            user_id=pid,
                            notification_type=NotificationType.MESSAGE,
                            title=f"New message from {sender_name} (@{sender_uname})",
                            body=snippet,
                            resource_type="message",
                            resource_id=str(message_id) if message_id else str(conversation_id),
                            conversation_id=conversation_id,
                        )
        except Exception:
            logger.exception("Failed to dispatch message notifications for conv %s", conversation_id)

    # ── Send Message ─────────────────────────

    async def send_message(
        self,
        user_id: uuid.UUID,
        conversation_id: uuid.UUID,
        data: MessageCreate,
    ) -> MessageResponse:
        """Send a message with group permission enforcement (channels.md 2.13)."""
        await self._require_participant(user_id, conversation_id)

        # Enforce group permissions
        await self._check_group_perm(conversation_id, user_id, "send_messages")

        if data.parent_id:
            await self._check_group_perm(conversation_id, user_id, "reply_messages")

        if "http://" in data.content or "https://" in data.content:
            await self._check_group_perm(conversation_id, user_id, "send_links")

        if "@" in data.content:
            await self._check_group_perm(conversation_id, user_id, "mention_users")

        msg = await self._repo.create_message(
            conversation_id=conversation_id,
            sender_id=user_id,
            content=data.content,
            message_type=data.message_type,
            parent_id=data.parent_id,
        )

        # Update sender's last_read_at
        await self._repo.update_last_read(conversation_id, user_id, msg.created_at)

        # Dispatch mention and DM notifications
        await self._handle_message_notifications(user_id, conversation_id, data.content, message_id=msg.id)

        logger.info("Message %s sent by user %s in conversation %s",
                     msg.id, user_id, conversation_id)
        return _msg_response(msg)

    # ── Message History ──────────────────────

    async def get_messages(
        self,
        user_id: uuid.UUID,
        conversation_id: uuid.UUID,
        limit: int = 50,
        before_seq: int | None = None,
    ) -> MessageListResponse:
        """Get message history with seen read receipt indicators."""
        await self._require_participant(user_id, conversation_id)
        await self._check_group_perm(conversation_id, user_id, "view_messages")

        messages = await self._repo.list_messages(
            conversation_id, limit=limit + 1, before_seq=before_seq,
        )

        has_more = len(messages) > limit
        if has_more:
            messages = messages[:limit]

        other_last_read = await self._repo.get_other_participant_last_read(conversation_id, user_id)

        items = []
        if messages:
            msg_ids = [m.id for m in messages]
            all_reactions = await self._repo.list_reactions_for_messages(msg_ids)
            reactions_by_msg: dict[uuid.UUID, list[MessageReaction]] = {}
            for r in all_reactions:
                reactions_by_msg.setdefault(r.message_id, []).append(r)

            for message in messages:
                m_reactions = reactions_by_msg.get(message.id, [])
                grouped: dict[str, set[uuid.UUID]] = {}
                for reaction in m_reactions:
                    grouped.setdefault(reaction.emoji, set()).add(reaction.user_id)
                summaries = [
                    ReactionSummary(
                        emoji=emoji,
                        count=len(user_ids),
                        reacted=user_id in user_ids,
                        user_ids=sorted(user_ids, key=str),
                    )
                    for emoji, user_ids in sorted(grouped.items())
                ]

                # WhatsApp-style Seen detection:
                # If message is from current user and other participant's last_read_at >= message.created_at
                is_seen = False
                if message.sender_id == user_id and other_last_read is not None:
                    if other_last_read >= message.created_at:
                        is_seen = True

                items.append(_msg_response(message, summaries, is_seen=is_seen))

        return MessageListResponse(items=items, has_more=has_more)


    async def update_message(
        self, user_id: uuid.UUID, conversation_id: uuid.UUID, message_id: uuid.UUID, content: str,
    ) -> MessageResponse:
        await self._require_participant(user_id, conversation_id)
        msg = await self._repo.get_message_by_id(message_id)
        if msg is None or msg.conversation_id != conversation_id:
            raise NotFoundError("Resource not found.")

        if msg.sender_id == user_id:
            await self._check_group_perm(conversation_id, user_id, "edit_own_messages")
        else:
            await self._check_group_perm(conversation_id, user_id, "edit_other_messages")

        updated = await self._repo.update_message(message_id, content)
        return _msg_response(updated)

    async def delete_message(
        self, user_id: uuid.UUID, conversation_id: uuid.UUID, message_id: uuid.UUID,
    ) -> None:
        is_sa = await self._policy.is_super_admin(user_id)
        if not is_sa:
            await self._require_participant(user_id, conversation_id)

        msg = await self._repo.get_message_by_id(message_id)
        if msg is None or msg.conversation_id != conversation_id:
            raise NotFoundError("Resource not found.")

        if not is_sa:
            if msg.sender_id == user_id:
                await self._check_group_perm(conversation_id, user_id, "delete_own_messages")
            else:
                await self._check_group_perm(conversation_id, user_id, "delete_other_messages")

        await self._repo.soft_delete_message(message_id)

    async def toggle_reaction(
        self,
        user_id: uuid.UUID,
        conversation_id: uuid.UUID,
        message_id: uuid.UUID,
        emoji: str,
    ) -> ReactionResponse:
        """Add or remove reaction with group permission check."""
        await self._require_participant(user_id, conversation_id)
        message = await self._repo.get_message_by_id(message_id)
        if message is None or message.conversation_id != conversation_id:
            raise NotFoundError("Resource not found.")

        existing = await self._repo.get_reaction(message_id, user_id, emoji)
        if existing is None:
            await self._check_group_perm(conversation_id, user_id, "add_reactions")
            await self._repo.add_reaction(message_id, user_id, emoji)
            active = True
        else:
            await self._check_group_perm(conversation_id, user_id, "remove_reactions")
            await self._repo.remove_reaction(existing)
            active = False

        return ReactionResponse(
            emoji=emoji,
            active=active,
            count=await self._repo.count_reactions(message_id, emoji),
        )

    # ── Pinned Messages ──────────────────────

    async def pin_message(
        self,
        user_id: uuid.UUID,
        conversation_id: uuid.UUID,
        message_id: uuid.UUID,
    ) -> MessageResponse:
        """Pin a message in a conversation (channels.md 2.13)."""
        await self._require_participant(user_id, conversation_id)
        await self._check_group_perm(conversation_id, user_id, "pin_messages")

        msg = await self._repo.get_message_by_id(message_id)
        if msg is None or msg.conversation_id != conversation_id:
            raise NotFoundError("Message not found.")

        pinned = await self._repo.pin_message(message_id, user_id)
        return _msg_response(pinned)

    async def unpin_message(
        self,
        user_id: uuid.UUID,
        conversation_id: uuid.UUID,
        message_id: uuid.UUID,
    ) -> MessageResponse:
        """Unpin a message in a conversation."""
        await self._require_participant(user_id, conversation_id)
        await self._check_group_perm(conversation_id, user_id, "unpin_messages")

        msg = await self._repo.get_message_by_id(message_id)
        if msg is None or msg.conversation_id != conversation_id:
            raise NotFoundError("Message not found.")

        unpinned = await self._repo.unpin_message(message_id)
        return _msg_response(unpinned)

    async def list_pinned_messages(
        self,
        user_id: uuid.UUID,
        conversation_id: uuid.UUID,
    ) -> list[MessageResponse]:
        """List all pinned messages in a conversation."""
        await self._require_participant(user_id, conversation_id)
        await self._check_group_perm(conversation_id, user_id, "view_messages")

        pinned_msgs = await self._repo.list_pinned_messages(conversation_id)
        return [_msg_response(m) for m in pinned_msgs]

    # ── Conversations ────────────────────────

    async def get_conversations(
        self,
        user_id: uuid.UUID,
        limit: int = 50,
        offset: int = 0,
    ) -> ConversationListResponse:
        """List user's conversations with last message preview and unread counts."""
        conversations = await self._repo.list_conversations_for_user(
            user_id, limit=limit, offset=offset,
        )
        total = await self._repo.count_conversations_for_user(user_id)

        conv_ids = [c.id for c in conversations]
        unread_map = await self._repo.get_batch_unread_counts(conv_ids, user_id)

        # Batch resolve group names for group conversations
        group_ids = [c.target_id for c in conversations if c.conversation_type == ConversationType.GROUP and c.target_id]
        group_names: dict[uuid.UUID, str] = {}
        if group_ids:
            try:
                from connecthub.modules.group.models import Group
                g_stmt = select(Group.id, Group.name).where(Group.id.in_(group_ids))
                g_res = await self._session.execute(g_stmt)
                for gid, gname in g_res.all():
                    group_names[gid] = gname
            except Exception:
                pass

        # Batch collect all participant user IDs across all conversations
        all_participant_uids: set[uuid.UUID] = set()
        for conv in conversations:
            if conv.participants:
                for p in conv.participants:
                    all_participant_uids.add(p.user_id)

        user_map: dict[uuid.UUID, User] = {}
        if all_participant_uids:
            try:
                u_stmt = select(User).where(User.id.in_(all_participant_uids))
                u_res = await self._session.execute(u_stmt)
                for u in u_res.scalars().all():
                    user_map[u.id] = u
            except Exception:
                pass

        items = []
        for conv in conversations:
            last_msg = await self._repo.get_last_message(conv.id)
            unread_count = unread_map.get(conv.id, 0)

            name = None
            title = None
            display_name = None
            recipient_id = None
            recipient_name = None
            recipient_username = None
            recipient_avatar_url = None

            if conv.conversation_type == ConversationType.GROUP:
                name = group_names.get(conv.target_id)
                title = name
                display_name = name
            elif conv.conversation_type == ConversationType.DIRECT:
                other_uid = None
                if conv.participants:
                    for p in conv.participants:
                        if p.user_id != user_id:
                            other_uid = p.user_id
                            break
                    if not other_uid and conv.participants:
                        other_uid = conv.participants[0].user_id

                if other_uid:
                    other_u = user_map.get(other_uid)
                    if other_u:
                        recipient_id = other_u.id
                        recipient_name = other_u.display_name or other_u.username
                        recipient_username = other_u.username
                        recipient_avatar_url = getattr(other_u, "avatar_url", None)
                        name = recipient_name
                        title = recipient_name
                        display_name = recipient_name

            p_details = []
            if conv.participants:
                for p in conv.participants:
                    u = user_map.get(p.user_id)
                    if u:
                        p_details.append(
                            ParticipantSummary(
                                id=u.id,
                                username=u.username,
                                display_name=u.display_name or u.username,
                                avatar_url=getattr(u, "avatar_url", None),
                                role=getattr(u, "role", "member") or "member",
                            )
                        )

            items.append(
                _conv_response(
                    conv,
                    last_msg,
                    unread_count=unread_count,
                    name=name,
                    title=title,
                    display_name=display_name,
                    recipient_id=recipient_id,
                    recipient_name=recipient_name,
                    recipient_username=recipient_username,
                    recipient_avatar_url=recipient_avatar_url,
                    participant_details=p_details,
                )
            )

        return ConversationListResponse(items=items, total=total)

    async def get_conversation(
        self,
        user_id: uuid.UUID,
        conversation_id: uuid.UUID,
    ) -> ConversationResponse:
        """Get a single conversation. Non-participant gets 404."""
        await self._require_participant(user_id, conversation_id)

        conv = await self._repo.get_conversation_by_id(conversation_id)
        if conv is None:
            raise NotFoundError("Resource not found.")

        name = None
        title = None
        display_name = None
        recipient_id = None
        recipient_name = None
        recipient_username = None
        recipient_avatar_url = None

        p_uids = [p.user_id for p in conv.participants] if conv.participants else []
        user_map: dict[uuid.UUID, User] = {}
        if p_uids:
            try:
                u_stmt = select(User).where(User.id.in_(p_uids))
                u_res = await self._session.execute(u_stmt)
                for u in u_res.scalars().all():
                    user_map[u.id] = u
            except Exception:
                pass

        if conv.conversation_type == ConversationType.GROUP and conv.target_id:
            try:
                from connecthub.modules.group.models import Group
                g_stmt = select(Group.name).where(Group.id == conv.target_id)
                g_res = await self._session.execute(g_stmt)
                name = g_res.scalar_one_or_none()
                title = name
                display_name = name
            except Exception:
                pass
        elif conv.conversation_type == ConversationType.DIRECT:
            other_uid = None
            if conv.participants:
                for p in conv.participants:
                    if p.user_id != user_id:
                        other_uid = p.user_id
                        break
                if not other_uid and conv.participants:
                    other_uid = conv.participants[0].user_id

            if other_uid:
                other_u = user_map.get(other_uid)
                if other_u:
                    recipient_id = other_u.id
                    recipient_name = other_u.display_name or other_u.username
                    recipient_username = other_u.username
                    recipient_avatar_url = getattr(other_u, "avatar_url", None)
                    name = recipient_name
                    title = recipient_name
                    display_name = recipient_name

        p_details = []
        if conv.participants:
            for p in conv.participants:
                u = user_map.get(p.user_id)
                if u:
                    p_details.append(
                        ParticipantSummary(
                            id=u.id,
                            username=u.username,
                            display_name=u.display_name or u.username,
                            avatar_url=getattr(u, "avatar_url", None),
                            role=getattr(u, "role", "member") or "member",
                        )
                    )

        last_msg = await self._repo.get_last_message(conv.id)
        unread_count = await self._repo.get_unread_count(conv.id, user_id)
        return _conv_response(
            conv,
            last_msg,
            unread_count=unread_count,
            name=name,
            title=title,
            display_name=display_name,
            recipient_id=recipient_id,
            recipient_name=recipient_name,
            recipient_username=recipient_username,
            recipient_avatar_url=recipient_avatar_url,
            participant_details=p_details,
        )

    # ── Read Receipts ────────────────────────

    async def mark_read(
        self,
        user_id: uuid.UUID,
        conversation_id: uuid.UUID,
    ) -> None:
        """Mark a conversation as read up to now and clear associated notifications."""
        await self._require_participant(user_id, conversation_id)
        await self._repo.update_last_read(conversation_id, user_id)
        try:
            notif_service = NotificationService(self._session)
            await notif_service.mark_conversation_read(user_id, conversation_id)
        except Exception:
            pass

    async def mark_unread(
        self,
        user_id: uuid.UUID,
        conversation_id: uuid.UUID,
    ) -> None:
        """Mark a conversation as unread."""
        await self._require_participant(user_id, conversation_id)
        await self._repo.mark_unread(conversation_id, user_id)

    # ── Participant IDs (for WebSocket fan-out) ──

    async def get_participant_ids(
        self, conversation_id: uuid.UUID,
    ) -> list[uuid.UUID]:
        """Get participant user IDs for a conversation."""
        return await self._repo.get_participant_ids(conversation_id)
