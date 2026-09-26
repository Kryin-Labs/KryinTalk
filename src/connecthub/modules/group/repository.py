"""
ConnectHub Group Module — Data Access Layer.

Handles Groups, GroupRoles, and GroupMembers persistence and queries.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone

from sqlalchemy import and_, or_, select, func as sqlfunc
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from connecthub.modules.group.models import Group, GroupInvite, GroupMember, GroupRole
from connecthub.modules.auth.models import User


class GroupRepository:
    """Data access for groups, custom roles, and membership."""

    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def create(
        self,
        organization_id: uuid.UUID,
        name: str,
        slug: str,
        description: str | None = None,
        icon: str | None = None,
        color: str | None = None,
        visibility: str = "private",
        is_private: bool = True,
        only_admin_invites: bool = True,
        created_by: uuid.UUID | None = None,
    ) -> Group:
        group = Group(
            organization_id=organization_id,
            name=name,
            slug=slug,
            description=description,
            icon=icon,
            color=color,
            visibility=visibility,
            is_private=is_private,
            only_admin_invites=only_admin_invites,
            created_by=created_by,
        )
        self._session.add(group)
        await self._session.flush()
        return group

    async def count_groups_created_by(self, user_id: uuid.UUID) -> int:
        stmt = select(sqlfunc.count(Group.id)).where(
            and_(
                Group.created_by == user_id,
                Group.deleted_at.is_(None),
            )
        )
        result = await self._session.execute(stmt)
        return result.scalar_one() or 0

    async def get_by_id(self, group_id: uuid.UUID) -> Group | None:
        stmt = select(Group).where(
            and_(Group.id == group_id, Group.deleted_at.is_(None)),
        ).options(
            selectinload(Group.members),
            selectinload(Group.roles),
        )
        result = await self._session.execute(stmt)
        return result.scalar_one_or_none()

    async def get_by_slug(
        self, organization_id: uuid.UUID, slug: str,
    ) -> Group | None:
        stmt = select(Group).where(
            and_(
                Group.organization_id == organization_id,
                Group.slug == slug,
                Group.deleted_at.is_(None),
            ),
        )
        result = await self._session.execute(stmt)
        return result.scalar_one_or_none()

    async def list_by_org(
        self,
        organization_id: uuid.UUID,
        active_only: bool = True,
        limit: int = 100,
        offset: int = 0,
    ) -> list[Group]:
        stmt = select(Group).where(
            and_(
                Group.organization_id == organization_id,
                Group.deleted_at.is_(None),
            ),
        ).options(
            selectinload(Group.members),
            selectinload(Group.roles),
        )
        if active_only:
            stmt = stmt.where(Group.is_active.is_(True))
        stmt = stmt.order_by(Group.name).limit(limit).offset(offset)
        result = await self._session.execute(stmt)
        return list(result.scalars().unique().all())

    async def list_visible_for_user(
        self,
        organization_id: uuid.UUID,
        user_id: uuid.UUID,
        is_admin: bool = False,
        active_only: bool = True,
        limit: int = 100,
        offset: int = 0,
    ) -> list[Group]:
        """List groups visible to a user (org-wide or where user is member/creator, or all if admin)."""
        stmt = select(Group).where(
            and_(
                Group.organization_id == organization_id,
                Group.deleted_at.is_(None),
            ),
        ).options(
            selectinload(Group.members),
            selectinload(Group.roles),
        )
        if active_only:
            stmt = stmt.where(Group.is_active.is_(True))

        if not is_admin:
            member_group_ids_subquery = select(GroupMember.group_id).where(GroupMember.user_id == user_id)
            stmt = stmt.where(
                or_(
                    and_(
                        Group.visibility == "organization",
                        Group.is_private.is_(False),
                    ),
                    Group.created_by == user_id,
                    Group.id.in_(member_group_ids_subquery),
                )
            )

        stmt = stmt.order_by(Group.name).limit(limit).offset(offset)
        result = await self._session.execute(stmt)
        return list(result.scalars().unique().all())

    async def count_by_org(
        self,
        organization_id: uuid.UUID,
        active_only: bool = True,
    ) -> int:
        stmt = select(sqlfunc.count(Group.id)).where(
            and_(
                Group.organization_id == organization_id,
                Group.deleted_at.is_(None),
            ),
        )
        if active_only:
            stmt = stmt.where(Group.is_active.is_(True))
        result = await self._session.execute(stmt)
        return result.scalar_one()

    async def count_visible_for_user(
        self,
        organization_id: uuid.UUID,
        user_id: uuid.UUID,
        is_admin: bool = False,
        active_only: bool = True,
    ) -> int:
        stmt = select(sqlfunc.count(Group.id)).where(
            and_(
                Group.organization_id == organization_id,
                Group.deleted_at.is_(None),
            ),
        )
        if active_only:
            stmt = stmt.where(Group.is_active.is_(True))

        if not is_admin:
            member_group_ids_subquery = select(GroupMember.group_id).where(GroupMember.user_id == user_id)
            stmt = stmt.where(
                or_(
                    and_(
                        Group.visibility == "organization",
                        Group.is_private.is_(False),
                    ),
                    Group.created_by == user_id,
                    Group.id.in_(member_group_ids_subquery),
                )
            )

        result = await self._session.execute(stmt)
        return result.scalar() or 0

    async def update(self, group: Group, **kwargs) -> Group:
        for key, value in kwargs.items():
            if value is not None and hasattr(group, key):
                setattr(group, key, value)
        await self._session.flush()
        await self._session.refresh(group, attribute_names=["updated_at"])
        return group

    async def soft_delete(self, group_id: uuid.UUID) -> Group | None:
        group = await self.get_by_id(group_id)
        if group:
            group.deleted_at = datetime.now(timezone.utc)
        return group

    # ── Role Management ───────────────────────

    async def create_role(
        self,
        group_id: uuid.UUID,
        name: str,
        color: str | None = None,
        description: str | None = None,
        hierarchy_rank: int = 100,
        is_system: bool = False,
        is_default: bool = False,
        permissions: dict | None = None,
    ) -> GroupRole:
        if is_default:
            # Clear previous default
            await self.clear_default_role(group_id)

        role = GroupRole(
            group_id=group_id,
            name=name,
            color=color,
            description=description,
            hierarchy_rank=hierarchy_rank,
            is_system=is_system,
            is_default=is_default,
            permissions=permissions or {},
        )
        self._session.add(role)
        await self._session.flush()
        return role

    async def get_role_by_id(self, role_id: uuid.UUID) -> GroupRole | None:
        stmt = select(GroupRole).where(GroupRole.id == role_id)
        result = await self._session.execute(stmt)
        return result.scalar_one_or_none()

    async def get_role_by_name(self, group_id: uuid.UUID, name: str) -> GroupRole | None:
        stmt = select(GroupRole).where(
            and_(GroupRole.group_id == group_id, GroupRole.name == name),
        )
        result = await self._session.execute(stmt)
        return result.scalar_one_or_none()

    async def list_roles_by_group(self, group_id: uuid.UUID) -> list[GroupRole]:
        stmt = select(GroupRole).where(
            GroupRole.group_id == group_id,
        ).order_by(GroupRole.hierarchy_rank.asc(), GroupRole.created_at.asc())
        result = await self._session.execute(stmt)
        return list(result.scalars().all())

    async def get_default_role(self, group_id: uuid.UUID) -> GroupRole | None:
        stmt = select(GroupRole).where(
            and_(GroupRole.group_id == group_id, GroupRole.is_default.is_(True)),
        )
        result = await self._session.execute(stmt)
        role = result.scalar_one_or_none()
        if role is None:
            # Fallback to Group Member role
            role = await self.get_role_by_name(group_id, "Group Member")
        return role

    async def clear_default_role(self, group_id: uuid.UUID) -> None:
        roles = await self.list_roles_by_group(group_id)
        for r in roles:
            if r.is_default:
                r.is_default = False
        await self._session.flush()

    async def set_default_role(self, group_id: uuid.UUID, role_id: uuid.UUID) -> GroupRole | None:
        await self.clear_default_role(group_id)
        role = await self.get_role_by_id(role_id)
        if role and role.group_id == group_id:
            role.is_default = True
            await self._session.flush()
        return role

    async def update_role(self, role: GroupRole, **kwargs) -> GroupRole:
        if kwargs.get("is_default") is True:
            await self.clear_default_role(role.group_id)

        for key, value in kwargs.items():
            if value is not None and hasattr(role, key):
                setattr(role, key, value)
        await self._session.flush()
        return role

    async def count_members_by_role(self, role_id: uuid.UUID) -> int:
        stmt = select(sqlfunc.count(GroupMember.id)).where(GroupMember.role_id == role_id)
        result = await self._session.execute(stmt)
        return result.scalar_one()

    async def reassign_members_role(
        self, group_id: uuid.UUID, old_role_id: uuid.UUID, new_role_id: uuid.UUID | None,
    ) -> None:
        stmt = select(GroupMember).where(
            and_(GroupMember.group_id == group_id, GroupMember.role_id == old_role_id),
        )
        result = await self._session.execute(stmt)
        members = result.scalars().all()
        for m in members:
            m.role_id = new_role_id
        await self._session.flush()

    async def delete_role(self, role_id: uuid.UUID) -> bool:
        role = await self.get_role_by_id(role_id)
        if role:
            await self._session.delete(role)
            await self._session.flush()
            return True
        return False

    # ── Membership ────────────────────────────

    async def add_member(
        self,
        group_id: uuid.UUID,
        user_id: uuid.UUID,
        role_id: uuid.UUID | None = None,
        added_by: uuid.UUID | None = None,
    ) -> GroupMember:
        member = GroupMember(
            group_id=group_id,
            user_id=user_id,
            role_id=role_id,
            added_by=added_by,
        )
        self._session.add(member)
        await self._session.flush()
        return member

    async def get_member(self, group_id: uuid.UUID, user_id: uuid.UUID) -> GroupMember | None:
        stmt = select(GroupMember).where(
            and_(
                GroupMember.group_id == group_id,
                GroupMember.user_id == user_id,
            ),
        ).options(selectinload(GroupMember.role))
        result = await self._session.execute(stmt)
        return result.scalar_one_or_none()

    async def list_members_with_roles(self, group_id: uuid.UUID) -> list[tuple[GroupMember, User | None]]:
        stmt = (
            select(GroupMember, User)
            .join(User, GroupMember.user_id == User.id, isouter=True)
            .where(GroupMember.group_id == group_id)
            .options(selectinload(GroupMember.role))
            .order_by(GroupMember.created_at.asc())
        )
        result = await self._session.execute(stmt)
        return list(result.all())

    async def remove_member(
        self, group_id: uuid.UUID, user_id: uuid.UUID,
    ) -> bool:
        stmt = select(GroupMember).where(
            and_(
                GroupMember.group_id == group_id,
                GroupMember.user_id == user_id,
            ),
        )
        result = await self._session.execute(stmt)
        member = result.scalar_one_or_none()
        if member:
            await self._session.delete(member)
            await self._session.flush()
            return True
        return False

    async def is_member(
        self, group_id: uuid.UUID, user_id: uuid.UUID,
    ) -> bool:
        stmt = select(sqlfunc.count(GroupMember.id)).where(
            and_(
                GroupMember.group_id == group_id,
                GroupMember.user_id == user_id,
            ),
        )
        result = await self._session.execute(stmt)
        return result.scalar_one() > 0

    async def get_member_count(self, group_id: uuid.UUID) -> int:
        stmt = select(sqlfunc.count(GroupMember.id)).where(
            GroupMember.group_id == group_id,
        )
        result = await self._session.execute(stmt)
        return result.scalar_one()

    async def assign_member_role(
        self, group_id: uuid.UUID, user_id: uuid.UUID, role_id: uuid.UUID,
    ) -> GroupMember | None:
        member = await self.get_member(group_id, user_id)
        if member:
            member.role_id = role_id
            await self._session.flush()
        return member

    # ── Group Invites ─────────────────────────

    async def create_invite(
        self,
        group_id: uuid.UUID,
        token: str,
        created_by: uuid.UUID,
        expires_at: datetime,
        max_uses: int = 1,
    ) -> GroupInvite:
        invite = GroupInvite(
            group_id=group_id,
            token=token,
            created_by=created_by,
            expires_at=expires_at,
            max_uses=max_uses,
            uses_count=0,
            is_revoked=False,
        )
        self._session.add(invite)
        await self._session.flush()
        return invite

    async def get_invite_by_token(self, token: str) -> GroupInvite | None:
        stmt = select(GroupInvite).where(
            GroupInvite.token == token,
        ).options(
            selectinload(GroupInvite.group),
        )
        result = await self._session.execute(stmt)
        return result.scalar_one_or_none()

    async def increment_invite_use(self, invite: GroupInvite) -> None:
        invite.uses_count += 1
        await self._session.flush()

    async def revoke_invite(self, invite: GroupInvite) -> None:
        invite.is_revoked = True
        await self._session.flush()
