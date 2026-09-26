"""
ConnectHub — CLI Commands.

Bootstrap and management commands for the ConnectHub platform.

Usage:
    uv run python -m connecthub.cli bootstrap-superadmin

The bootstrap command creates the initial organization, Super Admin user,
and assigns the super_admin system role. It is idempotent — it refuses
to run if a Super Admin already exists.
"""

from __future__ import annotations

import asyncio
import logging
import sys
import uuid
from typing import Any

logger = logging.getLogger(__name__)


async def bootstrap_superadmin(
    org_name: str,
    org_slug: str,
    email: str,
    username: str,
    display_name: str,
    password: str,
) -> dict[str, Any]:
    """Bootstrap the first organization and Super Admin.

    This is the initial setup command. It:
    1. Creates the organization
    2. Creates the Super Admin user
    3. Assigns the super_admin system role

    Raises:
        RuntimeError: If a Super Admin already exists.

    Returns:
        Dict with created org_id and user_id.
    """
    from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
    from sqlalchemy.orm import sessionmaker

    from connecthub.config import settings
    from connecthub.core.audit.service import AuditService
    from connecthub.core.permissions.constants import SUPER_ADMIN_ROLE
    from connecthub.core.permissions.repository import PermissionRepository
    from connecthub.core.security.hashing import hash_password
    from connecthub.modules.auth.repository import AuthRepository

    engine = create_async_engine(settings.DATABASE_URL, echo=False)
    async_session = sessionmaker(bind=engine, class_=AsyncSession, expire_on_commit=False)

    async with async_session() as session:
        auth_repo = AuthRepository(session)
        perm_repo = PermissionRepository(session)
        audit = AuditService(session)

        # Check if Super Admin already exists
        sa_role = await perm_repo.get_role_by_code(SUPER_ADMIN_ROLE)
        if sa_role is None:
            raise RuntimeError(
                "Super Admin role not found. Run database migrations first."
            )

        # Check if any user has the super_admin role
        from sqlalchemy import select
        from connecthub.core.permissions.models import UserRole
        stmt = select(UserRole).where(UserRole.role_id == sa_role.id)
        result = await session.execute(stmt)
        existing_sa = result.scalar_one_or_none()

        if existing_sa is not None:
            raise RuntimeError(
                "A Super Admin already exists. Bootstrap can only be run once."
            )

        # Check for duplicate email/username
        if await auth_repo.get_user_by_email(email):
            raise RuntimeError(f"Email '{email}' is already registered.")
        if await auth_repo.get_user_by_username(username):
            raise RuntimeError(f"Username '{username}' is already taken.")

        # 1. Create organization
        org = await auth_repo.create_organization(name=org_name, slug=org_slug)

        # 2. Create Super Admin user
        user = await auth_repo.create_user(
            organization_id=org.id,
            email=email,
            username=username,
            display_name=display_name,
            password_hash=hash_password(password),
        )

        # 3. Assign super_admin role
        await perm_repo.assign_role_to_user(user.id, sa_role.id)

        # 4. Audit
        await audit.log(
            user_id=user.id,
            action="superadmin.bootstrapped",
            resource_type="system",
            resource_id=str(org.id),
            details={
                "org_name": org_name,
                "org_slug": org_slug,
                "admin_email": email,
                "admin_username": username,
            },
        )

        await session.commit()

        logger.info(
            "Super Admin bootstrapped: org='%s', user='%s'", org_name, username,
        )

        return {
            "organization_id": str(org.id),
            "user_id": str(user.id),
            "email": email,
            "username": username,
        }

    await engine.dispose()


def main() -> None:
    """CLI entry point."""
    if len(sys.argv) < 2:
        print("Usage: python -m connecthub.cli <command>")
        print("Commands:")
        print("  bootstrap-superadmin    Create the initial organization and Super Admin")
        sys.exit(1)

    command = sys.argv[1]

    if command == "bootstrap-superadmin":
        print("=" * 50)
        print("ConnectHub — Super Admin Bootstrap")
        print("=" * 50)
        print()

        org_name = input("Organization name: ").strip()
        org_slug = input("Organization slug (URL-friendly): ").strip()
        email = input("Super Admin email: ").strip()
        username = input("Super Admin username: ").strip()
        display_name = input("Super Admin display name: ").strip()
        password = input("Super Admin password: ").strip()

        if not all([org_name, org_slug, email, username, display_name, password]):
            print("Error: All fields are required.")
            sys.exit(1)

        if len(password) < 8:
            print("Error: Password must be at least 8 characters.")
            sys.exit(1)

        try:
            result = asyncio.run(
                bootstrap_superadmin(
                    org_name=org_name,
                    org_slug=org_slug,
                    email=email,
                    username=username,
                    display_name=display_name,
                    password=password,
                )
            )
            print()
            print("✅ Super Admin bootstrapped successfully!")
            print(f"   Organization ID: {result['organization_id']}")
            print(f"   User ID: {result['user_id']}")
            print(f"   Email: {result['email']}")
            print(f"   Username: {result['username']}")

        except RuntimeError as e:
            print(f"Error: {e}")
            sys.exit(1)
        except Exception as e:
            print(f"Unexpected error: {e}")
            sys.exit(1)

    else:
        print(f"Unknown command: {command}")
        sys.exit(1)


if __name__ == "__main__":
    main()
