"""
ConnectHub Auth Module — Data Access Layer.

Repository for user and organization database operations.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone

from sqlalchemy import and_, or_, select, func as sqlfunc
from sqlalchemy.ext.asyncio import AsyncSession

from connecthub.modules.auth.models import Organization, User


class AuthRepository:
    """Data access for users and organizations."""

    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    # ── Organizations ────────────────────────

    async def create_organization(
        self,
        name: str,
        slug: str,
    ) -> Organization:
        """Create a new organization."""
        org = Organization(name=name, slug=slug)
        self._session.add(org)
        await self._session.flush()
        return org

    async def get_organization_by_id(
        self, org_id: uuid.UUID,
    ) -> Organization | None:
        """Get an organization by ID."""
        stmt = select(Organization).where(
            and_(Organization.id == org_id, Organization.deleted_at.is_(None)),
        )
        result = await self._session.execute(stmt)
        return result.scalar_one_or_none()

    async def get_organization_by_slug(self, slug: str) -> Organization | None:
        """Get an organization by slug."""
        stmt = select(Organization).where(
            and_(Organization.slug == slug, Organization.deleted_at.is_(None)),
        )
        result = await self._session.execute(stmt)
        return result.scalar_one_or_none()

    # ── Users ────────────────────────────────

    async def create_user(
        self,
        organization_id: uuid.UUID,
        email: str,
        username: str,
        display_name: str,
        password_hash: str,
    ) -> User:
        """Create a new user."""
        user = User(
            organization_id=organization_id,
            email=email,
            username=username,
            display_name=display_name,
            password_hash=password_hash,
        )
        self._session.add(user)
        await self._session.flush()
        return user

    async def get_user_by_id(self, user_id: uuid.UUID) -> User | None:
        """Get a user by ID (excludes soft-deleted)."""
        stmt = select(User).where(
            and_(User.id == user_id, User.deleted_at.is_(None)),
        )
        result = await self._session.execute(stmt)
        return result.scalar_one_or_none()

    async def get_user_by_email(self, email: str) -> User | None:
        """Get a user by email or username, with fallback domain alias and case-insensitive matching."""
        clean_identifier = email.strip().lower()
        raw_identifier = clean_identifier.lstrip("@")

        # 1. Check exact or lower email match
        stmt = select(User).where(and_(sqlfunc.lower(User.email) == clean_identifier, User.deleted_at.is_(None)))
        result = await self._session.execute(stmt)
        user = result.scalars().first()
        if user:
            return user

        # 2. Check exact or lower username match (with or without @)
        stmt = select(User).where(
            and_(
                or_(
                    sqlfunc.lower(User.username) == clean_identifier,
                    sqlfunc.lower(User.username) == raw_identifier,
                ),
                User.deleted_at.is_(None),
            )
        )
        result = await self._session.execute(stmt)
        user = result.scalars().first()
        if user:
            return user

        # 3. Check domain alias fallback (.com <-> .local)
        if "@connecthub.com" in clean_identifier:
            local_alias = clean_identifier.replace("@connecthub.com", "@connecthub.local")
            stmt = select(User).where(and_(sqlfunc.lower(User.email) == local_alias, User.deleted_at.is_(None)))
            result = await self._session.execute(stmt)
            user = result.scalars().first()
            if user:
                return user
        elif "@connecthub.local" in clean_identifier:
            com_alias = clean_identifier.replace("@connecthub.local", "@connecthub.com")
            stmt = select(User).where(and_(sqlfunc.lower(User.email) == com_alias, User.deleted_at.is_(None)))
            result = await self._session.execute(stmt)
            user = result.scalars().first()
            if user:
                return user

        return None

    async def get_user_by_username(self, username: str) -> User | None:
        """Get a user by username (excludes soft-deleted)."""
        stmt = select(User).where(
            and_(User.username == username, User.deleted_at.is_(None)),
        )
        result = await self._session.execute(stmt)
        return result.scalar_one_or_none()

    async def update_last_login(self, user_id: uuid.UUID) -> None:
        """Update user's last login timestamp."""
        user = await self.get_user_by_id(user_id)
        if user:
            user.last_login_at = datetime.now(timezone.utc)

    async def suspend_user(self, user_id: uuid.UUID) -> User | None:
        """Suspend a user (prevent login)."""
        user = await self.get_user_by_id(user_id)
        if user:
            user.is_suspended = True
        return user

    async def reactivate_user(self, user_id: uuid.UUID) -> User | None:
        """Reactivate a suspended user."""
        user = await self.get_user_by_id(user_id)
        if user:
            user.is_suspended = False
        return user

    async def list_org_users(self, organization_id: uuid.UUID) -> list[User]:
        """List all active non-deleted users in the organization."""
        stmt = select(User).where(
            and_(User.organization_id == organization_id, User.is_active.is_(True), User.deleted_at.is_(None)),
        ).order_by(User.display_name)
        result = await self._session.execute(stmt)
        return list(result.scalars().all())

    async def list_users_by_org(
        self,
        organization_id: uuid.UUID,
        include_suspended: bool = False,
    ) -> list[User]:
        """List users in an organization."""
        stmt = select(User).where(
            and_(
                User.organization_id == organization_id,
                User.deleted_at.is_(None),
            ),
        )
        if not include_suspended:
            stmt = stmt.where(User.is_suspended.is_(False))
        stmt = stmt.order_by(User.display_name)
        result = await self._session.execute(stmt)
        return list(result.scalars().all())

    async def count_users(self) -> int:
        """Count total non-deleted users (for bootstrap detection)."""
        stmt = select(sqlfunc.count(User.id)).where(User.deleted_at.is_(None))
        result = await self._session.execute(stmt)
        return result.scalar_one()
