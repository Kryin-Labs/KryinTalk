"""
ConnectHub Group Module — Business Logic & Security Engine.

Enforces Group creation rules, Owner protection, role hierarchy,
permission ceilings, and member management.
Compliant with channels.md specifications.
"""

from __future__ import annotations

import logging
import secrets
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any

from sqlalchemy import and_, inspect as sa_inspect, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from connecthub.core.audit.service import AuditService
from connecthub.core.exceptions import ConflictError, ForbiddenError, NotFoundError
from connecthub.core.permissions.constants import SUPER_ADMIN_ROLE
from connecthub.core.permissions.policy import PolicyService
from connecthub.modules.auth.models import User
from connecthub.modules.auth.repository import AuthRepository
from connecthub.modules.group.models import Group, GroupInvite, GroupMember, GroupRole
from connecthub.modules.group.repository import GroupRepository
from connecthub.modules.group.schemas import (
    GroupCreate,
    GroupInviteAcceptResponse,
    GroupInviteResponse,
    GroupListResponse,
    GroupMemberListResponse,
    GroupMemberDetailResponse,
    GroupResponse,
    GroupRoleCreate,
    GroupRoleReorderRequest,
    GroupRoleResponse,
    GroupRoleUpdate,
    GroupUpdate,
    UserInviteResponse,
    default_admin_permissions,
    default_member_permissions,
    default_owner_permissions,
    default_viewer_permissions,
)
from connecthub.modules.notifications.models import NotificationType
from connecthub.modules.notifications.service import NotificationService

logger = logging.getLogger(__name__)

DOMAIN = "group_management"
ACTION_CREATE = "create"
ACTION_READ = "read"
ACTION_UPDATE = "update"
ACTION_DELETE = "delete"

_force_message_overrides: dict[tuple[uuid.UUID, uuid.UUID], datetime] = {}


def _role_to_response(role: GroupRole, member_count: int = 0) -> GroupRoleResponse:
    return GroupRoleResponse(
        id=role.id,
        group_id=role.group_id,
        name=role.name,
        color=role.color,
        description=role.description,
        hierarchy_rank=role.hierarchy_rank,
        is_system=role.is_system,
        is_default=role.is_default,
        permissions=role.permissions or {},
        member_count=member_count,
        created_at=role.created_at,
    )


def _to_response(
    group: Group,
    current_user_role: GroupRoleResponse | None = None,
    current_user_permissions: dict[str, bool] | None = None,
) -> GroupResponse:
    """Convert a Group ORM object to a GroupResponse."""
    return GroupResponse(
        id=group.id,
        organization_id=group.organization_id,
        name=group.name,
        slug=group.slug,
        description=group.description,
        icon=group.icon,
        color=group.color,
        visibility=getattr(group, "visibility", "private") or ("private" if group.is_private else "organization"),
        is_active=group.is_active,
        is_private=group.is_private,
        only_admin_invites=getattr(group, "only_admin_invites", True),
        created_by=group.created_by,
        member_count=len(group.members) if group.members else 0,
        current_user_role=current_user_role,
        current_user_permissions=current_user_permissions,
        created_at=group.created_at,
        updated_at=group.updated_at,
    )


class GroupService:
    """Group management service — permission-gated with custom roles and hierarchy."""

    def __init__(self, session: AsyncSession) -> None:
        self._session = session
        self._repo = GroupRepository(session)
        self._auth_repo = AuthRepository(session)
        self._policy = PolicyService(session)
        self._audit = AuditService(session)

    async def _get_org_id(self, user_id: uuid.UUID) -> uuid.UUID:
        user = await self._auth_repo.get_user_by_id(user_id)
        if user is None:
            raise NotFoundError("Resource not found.")
        return user.organization_id

    # ── Group Authorization & Hierarchy Checks ────────────────

    async def _is_super_admin(self, user_id: uuid.UUID) -> bool:
        return await self._policy.is_super_admin(user_id)

    async def _can_read_all_groups(self, user_id: uuid.UUID) -> bool:
        """Check if user can view all private groups (Super Admin or Admin only)."""
        if await self._is_super_admin(user_id):
            return True
        # A delegated group-management read grant is also sufficient to list
        # all groups. This keeps the directory behavior consistent with the
        # central permission policy instead of relying only on ORM roles.
        if (await self._policy.check_permission(user_id, DOMAIN, ACTION_READ)).allowed:
            return True
        user = await self._auth_repo.get_user_by_id(user_id)
        if user is None:
            return False
        for r in getattr(user, "roles", []):
            role_name = getattr(r, "name", "").lower()
            role_code = getattr(r, "code", "").lower()
            if role_name in ("super_admin", "admin", "owner") or role_code in ("super_admin", "admin", "owner"):
                return True
        return False

    async def _can_create_group(self, user_id: uuid.UUID) -> bool:
        """Check if user has authority to create groups."""
        if (await self._policy.check_permission(user_id, DOMAIN, ACTION_CREATE)).allowed:
            return True

        # Regular members may own up to two groups by default. If the user
        # has an explicit group read grant but no create grant, they are a
        # read-only delegate and must not create groups.
        read_result = await self._policy.check_permission(user_id, DOMAIN, ACTION_READ)
        return not read_result.allowed

    async def get_user_effective_role(
        self, group_id: uuid.UUID, user_id: uuid.UUID,
    ) -> tuple[GroupRole | None, bool]:
        """Get the user's role and whether they are the Group Owner.

        Returns: (role, is_owner)
        """
        group = await self._repo.get_by_id(group_id)
        if group is None:
            raise NotFoundError("Group not found.")

        # 1. Check explicit group membership first
        member = await self._repo.get_member(group_id, user_id)
        if member is not None and member.role:
            is_owner = member.role.name == "Group Owner" or member.role.hierarchy_rank == 0 or (group.created_by == user_id and member.role.name != "Group Viewer")
            return member.role, is_owner

        # 2. Check if user is the actual creator/owner of the group
        if group.created_by == user_id:
            owner_role = await self._repo.get_role_by_name(group_id, "Group Owner")
            return owner_role, True

        # 3. Super Admin who is NOT an added member has NO member role (handled in check_group_permission)
        is_super = await self._is_super_admin(user_id)
        if is_super:
            return None, False

        # 4. Organization-wide public group defaults
        if member is None:
            if group.visibility == "organization" and not group.is_private:
                default_role = await self._repo.get_default_role(group_id)
                return default_role, False
            return None, False

        default_role = await self._repo.get_default_role(group_id)
        return default_role, False

    async def check_group_permission(
        self, group_id: uuid.UUID, user_id: uuid.UUID, permission_key: str,
    ) -> bool:
        """Check if user has a specific group permission."""
        is_super = await self._is_super_admin(user_id)
        group = await self._repo.get_by_id(group_id)
        if group is None:
            return False

        member = await self._repo.get_member(group_id, user_id)
        is_creator = group.created_by == user_id

        # If Super Admin is NOT an added member and NOT creator:
        if is_super and member is None and not is_creator:
            # Super Admin can ALWAYS view, inspect settings, manage members/roles, and audit
            if permission_key in (
                "view_group", "view_messages", "view_members", "view_roles",
                "view_member_profiles", "manage_group_settings", "delete_group",
                "add_members", "remove_members", "manage_roles",
            ):
                return True

            # For messaging/chat mutations, MUST have active 2-minute Force Message override:
            key = (group_id, user_id)
            if key in _force_message_overrides:
                exp = _force_message_overrides[key]
                if exp > datetime.now(timezone.utc):
                    return True
                else:
                    _force_message_overrides.pop(key, None)

            # Not active override -> Super Admin cannot send messages
            return False

        role, is_owner = await self.get_user_effective_role(group_id, user_id)
        if is_owner and role and role.name == "Group Owner":
            return True
        if role is None:
            return False

        # Group Admin role has full group operational permissions except deleting group
        if role.name == "Group Admin" and permission_key != "delete_group":
            return True

        # Group Viewer or roles with rank >= 200 are strictly read-only for message sending
        if role.name == "Group Viewer" or getattr(role, "hierarchy_rank", 0) >= 200:
            if permission_key in ("view_group", "view_messages", "view_members", "view_roles", "view_member_profiles"):
                return True
            return False

        # Explicitly check permission in role permissions dictionary
        role_perms = role.permissions or {}
        if permission_key in role_perms:
            return bool(role_perms[permission_key])

        # Basic view permissions default to True
        if permission_key in ("view_group", "view_messages", "view_members", "view_roles", "view_member_profiles"):
            return bool(role_perms.get(permission_key, True))

        # Unpinning falls back to pin_messages
        if permission_key == "unpin_messages":
            return bool(role_perms.get("unpin_messages", role_perms.get("pin_messages", False)))

        # Operational write permissions default to True for standard members, False for viewers
        if permission_key in ("edit_own_messages", "delete_own_messages", "reply_messages", "add_reactions", "remove_reactions", "send_messages", "send_links", "send_attachments"):
            return bool(role_perms.get(permission_key, True))

        return bool(role_perms.get(permission_key, False))

    async def require_group_permission(
        self, group_id: uuid.UUID, user_id: uuid.UUID, permission_key: str,
    ) -> None:
        """Enforce group permission or raise ForbiddenError."""
        has_perm = await self.check_group_permission(group_id, user_id, permission_key)
        if not has_perm:
            raise ForbiddenError(f"You do not have permission to perform '{permission_key}'.")

    async def activate_force_message_override(
        self, user_id: uuid.UUID, group_id: uuid.UUID, duration_seconds: int = 120,
    ) -> dict[str, Any]:
        """Activate temporary Force Message override for Super Admin (valid for duration_seconds, default 2 min)."""
        is_sa = await self._is_super_admin(user_id)
        if not is_sa:
            raise ForbiddenError("Only Super Administrators can activate Force Message override.")

        group = await self._repo.get_by_id(group_id)
        if group is None:
            raise NotFoundError("Group not found.")

        expires_at = datetime.now(timezone.utc) + timedelta(seconds=duration_seconds)
        _force_message_overrides[(group_id, user_id)] = expires_at

        await self._audit.log(
            user_id=user_id,
            action="group.force_message_override.activated",
            resource_type="group",
            resource_id=str(group_id),
            details={"duration_seconds": duration_seconds, "expires_at": expires_at.isoformat()},
        )

        return {
            "active": True,
            "remaining_seconds": duration_seconds,
            "expires_at": expires_at.isoformat(),
            "group_id": str(group_id),
        }

    async def get_force_message_override_status(
        self, user_id: uuid.UUID, group_id: uuid.UUID,
    ) -> dict[str, Any]:
        """Get the current Force Message override status for Super Admin in a group."""
        is_sa = await self._is_super_admin(user_id)
        if not is_sa:
            return {"active": False, "remaining_seconds": 0, "expires_at": None, "group_id": str(group_id)}

        key = (group_id, user_id)
        if key in _force_message_overrides:
            exp = _force_message_overrides[key]
            now = datetime.now(timezone.utc)
            if exp > now:
                rem = int((exp - now).total_seconds())
                return {
                    "active": True,
                    "remaining_seconds": rem,
                    "expires_at": exp.isoformat(),
                    "group_id": str(group_id),
                }
            else:
                _force_message_overrides.pop(key, None)

        return {"active": False, "remaining_seconds": 0, "expires_at": None, "group_id": str(group_id)}

    # ── Group CRUD ────────────────────────────

    async def create_group(
        self, user_id: uuid.UUID, data: GroupCreate,
    ) -> GroupResponse:
        """Create a group. Super Admin and Admin can create unlimited groups; Managers and Members can own up to 2 groups."""
        if not await self._can_create_group(user_id):
            raise NotFoundError("Resource not found.")

        # Check if user is Super Admin or Admin
        is_sa = await self._is_super_admin(user_id)
        is_admin = False
        user = await self._auth_repo.get_user_by_id(user_id)
        if user:
            for r in getattr(user, "roles", []):
                role_name = getattr(r, "name", "").lower()
                role_code = getattr(r, "code", "").lower()
                if role_name in ("super_admin", "admin", "owner") or role_code in ("super_admin", "admin", "owner"):
                    is_admin = True
                    break

        if not (is_sa or is_admin):
            owned_count = await self._repo.count_groups_created_by(user_id)
            if owned_count >= 2:
                raise ForbiddenError("You are limited to a maximum of 2 groups. Please contact an administrator.")
        org_id = await self._get_org_id(user_id)

        if await self._repo.get_by_slug(org_id, data.slug):
            raise ConflictError(f"Group with slug '{data.slug}' already exists.")

        is_private = data.visibility == "private" if data.visibility else data.is_private

        group = await self._repo.create(
            organization_id=org_id,
            name=data.name,
            slug=data.slug,
            description=data.description,
            icon=data.icon,
            color=data.color,
            visibility=data.visibility or ("private" if is_private else "organization"),
            is_private=is_private,
            only_admin_invites=bool(getattr(data, "only_admin_invites", True)),
            created_by=user_id,
        )

        # 1. Create Default Roles (channels.md 2.2, 2.5)
        # Group Owner (rank 0, protected, system)
        owner_role = await self._repo.create_role(
            group_id=group.id,
            name="Group Owner",
            color="#F59E0B",
            description="Permanent group owner with absolute management authority",
            hierarchy_rank=0,
            is_system=True,
            is_default=False,
            permissions=default_owner_permissions(),
        )

        # Group Admin (rank 10, system)
        admin_role = await self._repo.create_role(
            group_id=group.id,
            name="Group Admin",
            color="#8B5CF6",
            description="Group administrator with management authority",
            hierarchy_rank=10,
            is_system=True,
            is_default=False,
            permissions=default_admin_permissions(),
        )

        is_view_only = bool(getattr(data, "is_view_only", False))

        # Group Member (rank 100, system, default role if not view-only)
        member_role = await self._repo.create_role(
            group_id=group.id,
            name="Group Member",
            color="#64748B",
            description="Standard group member",
            hierarchy_rank=100,
            is_system=True,
            is_default=not is_view_only,
            permissions=default_member_permissions(),
        )

        # Group Viewer (rank 200, system, view-only, default role if view-only)
        viewer_role = await self._repo.create_role(
            group_id=group.id,
            name="Group Viewer",
            color="#94A3B8",
            description="View-only participant with no posting or management rights",
            hierarchy_rank=200,
            is_system=True,
            is_default=is_view_only,
            permissions=default_viewer_permissions(),
        )

        # 2. Add creator as Owner member (Creator is ALWAYS Group Owner)
        await self._repo.add_member(
            group_id=group.id,
            user_id=user_id,
            role_id=owner_role.id,
            added_by=user_id,
        )

        # 3. Add initial members with default role (viewer_role if view-only, else member_role)
        default_assigned_role = viewer_role if is_view_only else member_role
        for mid in data.member_ids:
            if mid != user_id:
                await self._repo.add_member(
                    group_id=group.id,
                    user_id=mid,
                    role_id=default_assigned_role.id,
                    added_by=user_id,
                )

        # 4. Auto-create/sync Conversation for this group and participants
        try:
            from connecthub.modules.messaging.models import Conversation, ConversationParticipant, ConversationType
            from sqlalchemy import and_, select

            stmt = select(Conversation).where(
                and_(
                    Conversation.organization_id == org_id,
                    Conversation.conversation_type == ConversationType.GROUP,
                    Conversation.target_id == group.id,
                )
            )
            conv = (await self._session.execute(stmt)).scalar_one_or_none()
            if conv is None:
                conv = Conversation(
                    organization_id=org_id,
                    conversation_type=ConversationType.GROUP,
                    target_id=group.id,
                )
                self._session.add(conv)
                await self._session.flush()

            all_initial_uids = [user_id] + [mid for mid in data.member_ids if mid != user_id]
            for uid in all_initial_uids:
                part_check = select(ConversationParticipant).where(
                    and_(
                        ConversationParticipant.conversation_id == conv.id,
                        ConversationParticipant.user_id == uid,
                    )
                )
                if (await self._session.execute(part_check)).scalar_one_or_none() is None:
                    self._session.add(ConversationParticipant(conversation_id=conv.id, user_id=uid))
            await self._session.flush()
        except Exception as conv_err:
            logger.warning("Conversation auto-creation for group %s deferred: %s", group.id, conv_err)

        await self._audit.log(
            user_id=user_id,
            action="group.created",
            resource_type="group",
            resource_id=str(group.id),
            details={
                "name": data.name,
                "slug": data.slug,
                "visibility": group.visibility,
                "initial_members": len(data.member_ids) + 1,
            },
        )

        # Refresh group
        group = await self._repo.get_by_id(group.id)
        role_resp = _role_to_response(owner_role)
        return _to_response(
            group,
            current_user_role=role_resp,
            current_user_permissions=default_owner_permissions(),
        )

    async def list_groups(
        self, user_id: uuid.UUID, limit: int = 100, offset: int = 0,
    ) -> GroupListResponse:
        """List groups visible to the current user.
        - Admins/Super Admins see all groups in the organization.
        - Other members (standard users, guests, etc.) see all organization-wide groups + private groups they are members of.
        """
        org_id = await self._get_org_id(user_id)
        is_admin = await self._can_read_all_groups(user_id)

        groups = await self._repo.list_visible_for_user(
            organization_id=org_id,
            user_id=user_id,
            is_admin=is_admin,
            limit=limit,
            offset=offset,
        )
        total = await self._repo.count_visible_for_user(
            organization_id=org_id,
            user_id=user_id,
            is_admin=is_admin,
        )

        items = []
        for g in groups:
            role, is_owner = await self.get_user_effective_role(g.id, user_id)
            role_resp = _role_to_response(role) if role else None
            perms = default_owner_permissions() if is_owner else (role.permissions if role else None)
            items.append(_to_response(g, role_resp, perms))

        return GroupListResponse(
            items=items,
            total=total,
            limit=limit,
            offset=offset,
        )

    async def get_group(
        self, user_id: uuid.UUID, group_id: uuid.UUID,
    ) -> GroupResponse:
        """Get group detail with current user's role and permissions."""
        org_id = await self._get_org_id(user_id)
        group = await self._repo.get_by_id(group_id)
        if group is None or group.organization_id != org_id:
            raise NotFoundError("Resource not found.")

        # Check visibility: Super Admin/Admin, creator, member, or organization-wide group
        is_admin = await self._can_read_all_groups(user_id)
        is_mem = any(m.user_id == user_id for m in group.members) or group.created_by == user_id
        is_org_wide = (group.visibility == "organization" and not group.is_private)
        if not is_admin and not is_mem and not is_org_wide:
            raise NotFoundError("Resource not found.")

        role, is_owner = await self.get_user_effective_role(group_id, user_id)
        role_resp = _role_to_response(role) if role else None
        perms = default_owner_permissions() if is_owner else (role.permissions if role else None)

        return _to_response(group, role_resp, perms)

    async def update_group(
        self, user_id: uuid.UUID, group_id: uuid.UUID, data: GroupUpdate,
    ) -> GroupResponse:
        """Update group settings. Requires `manage_group_settings` or `edit_group_name`."""
        org_id = await self._get_org_id(user_id)
        group = await self._repo.get_by_id(group_id)
        if group is None or group.organization_id != org_id:
            raise NotFoundError("Resource not found.")

        await self.require_group_permission(group_id, user_id, "manage_group_settings")

        update_dict = data.model_dump(exclude_unset=True)
        if "visibility" in update_dict:
            update_dict["is_private"] = update_dict["visibility"] == "private"
        elif "is_private" in update_dict:
            update_dict["visibility"] = "private" if update_dict["is_private"] else "organization"

        await self._repo.update(group, **update_dict)

        await self._audit.log(
            user_id=user_id,
            action="group.updated",
            resource_type="group",
            resource_id=str(group_id),
            details=update_dict,
        )

        group = await self._repo.get_by_id(group_id)
        role, is_owner = await self.get_user_effective_role(group_id, user_id)
        role_resp = _role_to_response(role) if role else None
        perms = default_owner_permissions() if is_owner else (role.permissions if role else None)
        return _to_response(group, role_resp, perms)

    async def delete_group(
        self, user_id: uuid.UUID, group_id: uuid.UUID,
    ) -> None:
        """Soft-delete a group. Requires `delete_group` (channels.md 2.3, 2.22)."""
        org_id = await self._get_org_id(user_id)
        group = await self._repo.get_by_id(group_id)
        if group is None or group.organization_id != org_id:
            raise NotFoundError("Resource not found.")

        await self.require_group_permission(group_id, user_id, "delete_group")

        await self._repo.soft_delete(group_id)
        await self._audit.log(
            user_id=user_id,
            action="group.deleted",
            resource_type="group",
            resource_id=str(group_id),
            details={"name": group.name},
        )

    # ── Role Management & Hierarchy Rules ─────────────────────

    async def ensure_group_system_roles(self, group_id: uuid.UUID) -> None:
        """Ensure all four built-in system roles exist for the group without duplicates."""
        roles = await self._repo.list_roles_by_group(group_id)
        role_names = {r.name for r in roles}
        if "Group Owner" not in role_names:
            await self._repo.create_role(
                group_id=group_id,
                name="Group Owner",
                color="#F59E0B",
                description="Permanent group owner with absolute management authority",
                hierarchy_rank=0,
                is_system=True,
                is_default=False,
                permissions=default_owner_permissions(),
            )
        if "Group Admin" not in role_names:
            await self._repo.create_role(
                group_id=group_id,
                name="Group Admin",
                color="#8B5CF6",
                description="Group administrator with management authority",
                hierarchy_rank=10,
                is_system=True,
                is_default=False,
                permissions=default_admin_permissions(),
            )
        if "Group Member" not in role_names:
            await self._repo.create_role(
                group_id=group_id,
                name="Group Member",
                color="#64748B",
                description="Standard group member",
                hierarchy_rank=100,
                is_system=True,
                is_default=True,
                permissions=default_member_permissions(),
            )
        if "Group Viewer" not in role_names:
            await self._repo.create_role(
                group_id=group_id,
                name="Group Viewer",
                color="#94A3B8",
                description="View-only participant with no posting or management rights",
                hierarchy_rank=200,
                is_system=True,
                is_default=False,
                permissions=default_viewer_permissions(),
            )

    async def list_roles(
        self, user_id: uuid.UUID, group_id: uuid.UUID,
    ) -> list[GroupRoleResponse]:
        """List roles for a group in hierarchy order with member counts."""
        await self.require_group_permission(group_id, user_id, "view_roles")
        await self.ensure_group_system_roles(group_id)
        roles = await self._repo.list_roles_by_group(group_id)

        responses = []
        for r in roles:
            mcount = await self._repo.count_members_by_role(r.id)
            responses.append(_role_to_response(r, mcount))
        return responses

    async def create_role(
        self, user_id: uuid.UUID, group_id: uuid.UUID, data: GroupRoleCreate,
    ) -> GroupRoleResponse:
        """Create a custom role.

        Enforces:
        - `create_roles` permission
        - Hierarchy rank strictly below caller's rank
        - Permission ceiling: cannot grant permissions exceeding caller's authority (channels.md 2.11)
        """
        await self.require_group_permission(group_id, user_id, "create_roles")
        caller_role, is_owner = await self.get_user_effective_role(group_id, user_id)
        caller_rank = 0 if is_owner else (caller_role.hierarchy_rank if caller_role else 1000)

        # Existing role check
        if await self._repo.get_role_by_name(group_id, data.name):
            raise ConflictError(f"Role '{data.name}' already exists in this group.")

        # Permission ceiling check (channels.md 2.11)
        sanitized_perms = data.permissions or default_member_permissions()
        if not is_owner:
            caller_perms = caller_role.permissions if caller_role else {}
            for perm_key, enabled in sanitized_perms.items():
                if enabled and not caller_perms.get(perm_key, False):
                    raise ForbiddenError(
                        f"Cannot grant permission '{perm_key}' because your role does not possess it."
                    )

        # Place new role in hierarchy below caller
        existing_roles = await self._repo.list_roles_by_group(group_id)
        max_rank = max([r.hierarchy_rank for r in existing_roles] + [0])
        new_rank = max(caller_rank + 10, max_rank + 1)

        role = await self._repo.create_role(
            group_id=group_id,
            name=data.name,
            color=data.color or "#64748B",
            description=data.description,
            hierarchy_rank=new_rank,
            is_system=False,
            is_default=data.is_default,
            permissions=sanitized_perms,
        )

        await self._audit.log(
            user_id=user_id,
            action="group.role.created",
            resource_type="group_role",
            resource_id=str(role.id),
            details={"name": data.name, "rank": new_rank},
        )
        return _role_to_response(role, 0)

    async def update_role(
        self,
        user_id: uuid.UUID,
        group_id: uuid.UUID,
        role_id: uuid.UUID,
        data: GroupRoleUpdate,
    ) -> GroupRoleResponse:
        """Update a role.

        Enforces:
        - `edit_roles` permission
        - Cannot modify Group Owner (channels.md 2.3)
        - Cannot modify roles at or above caller's hierarchy rank (channels.md 2.8, 2.9)
        - Cannot grant permissions exceeding caller's own permissions (channels.md 2.11)
        """
        await self.require_group_permission(group_id, user_id, "edit_roles")
        role = await self._repo.get_role_by_id(role_id)
        if role is None or role.group_id != group_id:
            raise NotFoundError("Role not found.")

        caller_role, is_owner = await self.get_user_effective_role(group_id, user_id)
        caller_rank = 0 if is_owner else (caller_role.hierarchy_rank if caller_role else 1000)

        # 1. Owner Protection (channels.md 2.3)
        if role.is_system or role.hierarchy_rank == 0:
            if not is_owner:
                raise ForbiddenError("Group Owner role is protected and cannot be modified.")

        # 2. Hierarchy Rank Boundary (channels.md 2.8)
        if not is_owner and role.hierarchy_rank <= caller_rank:
            raise ForbiddenError("Cannot edit a role with equal or higher hierarchy authority.")

        # 3. Permission Ceiling (channels.md 2.11)
        update_dict = data.model_dump(exclude_unset=True)
        if "permissions" in update_dict and not is_owner:
            caller_perms = caller_role.permissions if caller_role else {}
            new_perms = update_dict["permissions"]
            for perm_key, enabled in new_perms.items():
                if enabled and not caller_perms.get(perm_key, False):
                    raise ForbiddenError(
                        f"Cannot grant permission '{perm_key}' because your role does not possess it."
                    )

        # Owner cannot be default role
        if (role.hierarchy_rank == 0 or role.name == "Group Owner") and update_dict.get("is_default") is True:
            update_dict["is_default"] = False

        updated = await self._repo.update_role(role, **update_dict)
        mcount = await self._repo.count_members_by_role(role.id)

        await self._audit.log(
            user_id=user_id,
            action="group.role.updated",
            resource_type="group_role",
            resource_id=str(role.id),
            details={"name": updated.name},
        )
        return _role_to_response(updated, mcount)

    async def reorder_roles(
        self, user_id: uuid.UUID, group_id: uuid.UUID, data: GroupRoleReorderRequest,
    ) -> list[GroupRoleResponse]:
        """Reorder role hierarchy.

        Enforces:
        - `manage_role_hierarchy` permission
        - Cannot move any role above Group Owner (rank 0)
        - Cannot move any role above caller's own rank
        - Cannot alter roles at or above caller's rank (channels.md 2.10)
        """
        await self.require_group_permission(group_id, user_id, "manage_role_hierarchy")
        caller_role, is_owner = await self.get_user_effective_role(group_id, user_id)
        caller_rank = 0 if is_owner else (caller_role.hierarchy_rank if caller_role else 1000)

        existing_roles = {r.id: r for r in await self._repo.list_roles_by_group(group_id)}

        for item in data.roles:
            if item.role_id not in existing_roles:
                raise NotFoundError(f"Role {item.role_id} not found.")

            target_role = existing_roles[item.role_id]
            if target_role.is_system or target_role.hierarchy_rank == 0:
                # Group owner is fixed at rank 0
                if item.hierarchy_rank != 0:
                    raise ForbiddenError("Group Owner rank cannot be changed.")
                continue

            if not is_owner:
                # Cannot touch roles above caller
                if target_role.hierarchy_rank <= caller_rank:
                    raise ForbiddenError(f"Cannot reorder role '{target_role.name}' above your hierarchy level.")
                # Cannot move role above caller's rank
                if item.hierarchy_rank <= caller_rank:
                    raise ForbiddenError(f"Cannot move role '{target_role.name}' above your hierarchy level.")

            target_role.hierarchy_rank = item.hierarchy_rank

        await self._session.flush()
        return await self.list_roles(user_id, group_id)

    async def delete_role(
        self,
        user_id: uuid.UUID,
        group_id: uuid.UUID,
        role_id: uuid.UUID,
        fallback_role_id: uuid.UUID | None = None,
    ) -> None:
        """Delete a custom role and reassign affected members.

        Enforces:
        - `delete_roles` permission
        - Protected roles (Owner, default) cannot be deleted (channels.md 2.16)
        - Cannot delete roles above caller's rank
        """
        await self.require_group_permission(group_id, user_id, "delete_roles")
        role = await self._repo.get_role_by_id(role_id)
        if role is None or role.group_id != group_id:
            raise NotFoundError("Role not found.")

        # Protected role checks
        if role.is_system or role.hierarchy_rank == 0 or role.name in ("Group Owner", "Group Admin", "Group Member", "Group Viewer"):
            raise ForbiddenError(f"'{role.name}' is a built-in system role and cannot be deleted.")
        if role.is_default:
            raise ForbiddenError("The active default role cannot be deleted. Set another default role first.")

        caller_role, is_owner = await self.get_user_effective_role(group_id, user_id)
        caller_rank = 0 if is_owner else (caller_role.hierarchy_rank if caller_role else 1000)
        if not is_owner and role.hierarchy_rank <= caller_rank:
            raise ForbiddenError("Cannot delete a role with equal or higher hierarchy authority.")

        # Determine fallback role
        if fallback_role_id:
            target_fallback = await self._repo.get_role_by_id(fallback_role_id)
            if target_fallback is None or target_fallback.group_id != group_id:
                raise NotFoundError("Fallback role not found.")
        else:
            target_fallback = await self._repo.get_default_role(group_id)

        fallback_id = target_fallback.id if target_fallback else None
        await self._repo.reassign_members_role(group_id, role_id, fallback_id)
        await self._repo.delete_role(role_id)

        await self._audit.log(
            user_id=user_id,
            action="group.role.deleted",
            resource_type="group_role",
            resource_id=str(role_id),
            details={"name": role.name, "reassigned_to": str(fallback_id)},
        )

    # ── Member Management ─────────────────────

    async def list_members(
        self, user_id: uuid.UUID, group_id: uuid.UUID,
    ) -> GroupMemberListResponse:
        """List group members with user profiles and assigned roles."""
        await self.require_group_permission(group_id, user_id, "view_members")
        member_pairs = await self._repo.list_members_with_roles(group_id)

        items = []
        for mem, u in member_pairs:
            if not u:
                continue
            role_resp = _role_to_response(mem.role) if mem.role else None
            items.append(
                GroupMemberDetailResponse(
                    id=mem.id,
                    group_id=mem.group_id,
                    user_id=mem.user_id,
                    username=u.username or "user",
                    display_name=u.display_name or u.username or "Member",
                    email=u.email or "",
                    role_id=mem.role_id,
                    role=role_resp,
                    added_by=mem.added_by,
                    created_at=mem.created_at,
                )
            )
        return GroupMemberListResponse(items=items, total=len(items))

    async def add_members(
        self,
        user_id: uuid.UUID,
        group_id: uuid.UUID,
        member_ids: list[uuid.UUID],
        role_id: uuid.UUID | None = None,
    ) -> GroupResponse:
        """Add members to a group with default role assignment (channels.md 2.4, 2.12)."""
        await self.require_group_permission(group_id, user_id, "add_members")
        group = await self._repo.get_by_id(group_id)
        if group is None:
            raise NotFoundError("Group not found.")

        # Determine role to assign
        target_role = None
        if role_id:
            target_role = await self._repo.get_role_by_id(role_id)
            if target_role is None or target_role.group_id != group_id:
                raise NotFoundError("Role not found.")
            # Check hierarchy rank
            caller_role, is_owner = await self.get_user_effective_role(group_id, user_id)
            caller_rank = 0 if is_owner else (caller_role.hierarchy_rank if caller_role else 1000)
            if not is_owner and target_role.hierarchy_rank <= caller_rank:
                raise ForbiddenError("Cannot assign a role at or above your hierarchy level.")
        else:
            target_role = await self._repo.get_default_role(group_id)

        assigned_role_id = target_role.id if target_role else None

        for mid in member_ids:
            if not await self._repo.is_member(group_id, mid):
                await self._repo.add_member(
                    group_id=group_id,
                    user_id=mid,
                    role_id=assigned_role_id,
                    added_by=user_id,
                )

        # Sync conversation participants
        try:
            from connecthub.modules.messaging.models import Conversation, ConversationParticipant, ConversationType
            from sqlalchemy import and_, select

            stmt = select(Conversation).where(
                and_(
                    Conversation.organization_id == group.organization_id,
                    Conversation.conversation_type == ConversationType.GROUP,
                    Conversation.target_id == group_id,
                )
            )
            conv = (await self._session.execute(stmt)).scalar_one_or_none()
            if conv is not None:
                for mid in member_ids:
                    part_check = select(ConversationParticipant).where(
                        and_(
                            ConversationParticipant.conversation_id == conv.id,
                            ConversationParticipant.user_id == mid,
                        )
                    )
                    if (await self._session.execute(part_check)).scalar_one_or_none() is None:
                        self._session.add(ConversationParticipant(conversation_id=conv.id, user_id=mid))
                await self._session.flush()
        except Exception as sync_err:
            logger.warning("Failed to sync conversation participants on add_members: %s", sync_err)

        await self._audit.log(
            user_id=user_id,
            action="group.members.added",
            resource_type="group",
            resource_id=str(group_id),
            details={"added": [str(m) for m in member_ids], "role_id": str(assigned_role_id)},
        )

        sa_inspect(group).session.expire(group, ["members"])
        group = await self._repo.get_by_id(group_id)
        role, is_owner = await self.get_user_effective_role(group_id, user_id)
        role_resp = _role_to_response(role) if role else None
        perms = default_owner_permissions() if is_owner else (role.permissions if role else None)
        return _to_response(group, role_resp, perms)

    async def assign_member_role(
        self,
        user_id: uuid.UUID,
        group_id: uuid.UUID,
        target_user_id: uuid.UUID,
        role_id: uuid.UUID,
    ) -> GroupMemberDetailResponse:
        """Assign a role to a group member (channels.md 2.15).

        Enforces:
        - `assign_roles` permission
        - Cannot modify Group Owner (channels.md 2.3)
        - Cannot assign a role at or above caller's hierarchy rank
        - Cannot modify role of a member who has equal or higher rank than caller
        """
        await self.require_group_permission(group_id, user_id, "assign_roles")
        group = await self._repo.get_by_id(group_id)
        if group is None:
            raise NotFoundError("Group not found.")

        # 1. Owner protection (channels.md 2.3)
        if target_user_id == group.created_by:
            raise ForbiddenError("Group Owner cannot be assigned a different role or demoted.")

        caller_role, is_owner = await self.get_user_effective_role(group_id, user_id)
        caller_rank = 0 if is_owner else (caller_role.hierarchy_rank if caller_role else 1000)

        target_member = await self._repo.get_member(group_id, target_user_id)
        if target_member is None:
            raise NotFoundError("Member not found in this group.")

        # Check target member's current rank
        if not is_owner and target_member.role and target_member.role.hierarchy_rank <= caller_rank:
            raise ForbiddenError("Cannot modify the role of a member with equal or higher rank.")

        # Check new role's rank
        new_role = await self._repo.get_role_by_id(role_id)
        if new_role is None or new_role.group_id != group_id:
            raise NotFoundError("Role not found.")

        if not is_owner and new_role.hierarchy_rank <= caller_rank:
            raise ForbiddenError("Cannot assign a role at or above your hierarchy level.")

        updated_mem = await self._repo.assign_member_role(group_id, target_user_id, role_id)
        u = await self._auth_repo.get_user_by_id(target_user_id)

        await self._audit.log(
            user_id=user_id,
            action="group.member.role_assigned",
            resource_type="group_member",
            resource_id=str(target_user_id),
            details={"role_id": str(role_id), "role_name": new_role.name},
        )

        return GroupMemberDetailResponse(
            id=updated_mem.id,
            group_id=updated_mem.group_id,
            user_id=updated_mem.user_id,
            username=u.username if u else None,
            display_name=u.display_name if u else None,
            email=u.email if u else None,
            role_id=new_role.id,
            role=_role_to_response(new_role),
            added_by=updated_mem.added_by,
            created_at=updated_mem.created_at,
        )

    async def remove_member(
        self, user_id: uuid.UUID, group_id: uuid.UUID, target_user_id: uuid.UUID,
    ) -> None:
        """Remove a member from a group (channels.md 2.4).

        Enforces:
        - `remove_members` permission (or user removing themselves)
        - Owner cannot be removed (channels.md 2.3)
        - Cannot remove member with equal or higher hierarchy rank
        """
        group = await self._repo.get_by_id(group_id)
        if group is None:
            raise NotFoundError("Group not found.")

        # 1. Owner protection (channels.md 2.3)
        if target_user_id == group.created_by:
            raise ForbiddenError("Group Owner cannot be removed from the Group.")

        is_self = user_id == target_user_id
        if not is_self:
            await self.require_group_permission(group_id, user_id, "remove_members")
            caller_role, is_owner = await self.get_user_effective_role(group_id, user_id)
            caller_rank = 0 if is_owner else (caller_role.hierarchy_rank if caller_role else 1000)

            target_mem = await self._repo.get_member(group_id, target_user_id)
            if target_mem and target_mem.role and not is_owner:
                if target_mem.role.hierarchy_rank <= caller_rank:
                    raise ForbiddenError("Cannot remove a member with equal or higher hierarchy rank.")

        await self._repo.remove_member(group_id, target_user_id)

        # Remove from conversation participants
        try:
            from connecthub.modules.messaging.models import Conversation, ConversationParticipant, ConversationType

            stmt = select(Conversation).where(
                and_(
                    Conversation.organization_id == group.organization_id,
                    Conversation.conversation_type == ConversationType.GROUP,
                    Conversation.target_id == group_id,
                )
            )
            conv = (await self._session.execute(stmt)).scalar_one_or_none()
            if conv is not None:
                part_check = select(ConversationParticipant).where(
                    and_(
                        ConversationParticipant.conversation_id == conv.id,
                        ConversationParticipant.user_id == target_user_id,
                    )
                )
                part = (await self._session.execute(part_check)).scalar_one_or_none()
                if part:
                    await self._session.delete(part)
                    await self._session.flush()
        except Exception as rem_err:
            logger.warning("Failed to remove conversation participant: %s", rem_err)

        await self._audit.log(
            user_id=user_id,
            action="group.member.removed",
            resource_type="group",
            resource_id=str(group_id),
            details={"removed_user_id": str(target_user_id)},
        )

    async def remove_members(
        self, user_id: uuid.UUID, group_id: uuid.UUID, user_ids: list[uuid.UUID],
    ) -> GroupResponse:
        """Bulk remove members."""
        for mid in user_ids:
            await self.remove_member(user_id, group_id, mid)

        group = await self._repo.get_by_id(group_id)
        if group:
            sa_inspect(group).session.expire(group, ["members"])
            group = await self._repo.get_by_id(group_id)
        role, is_owner = await self.get_user_effective_role(group_id, user_id)
        role_resp = _role_to_response(role) if role else None
        perms = default_owner_permissions() if is_owner else (role.permissions if role else None)
        return _to_response(group, role_resp, perms)

    # ── Group Invites & Direct User Invitations ───────

    async def create_invite_link(
        self,
        group_id: uuid.UUID,
        user_id: uuid.UUID,
        expires_hours: int = 24,
    ) -> GroupInviteResponse:
        """Generate a single-use expiring invite link."""
        group = await self._repo.get_by_id(group_id)
        if group is None:
            raise NotFoundError("Group not found.")

        caller_role, is_owner = await self.get_user_effective_role(group_id, user_id)
        is_sa = await self._is_super_admin(user_id)
        is_admin_or_owner = is_owner or is_sa or (caller_role is not None and (caller_role.name == "Group Admin" or caller_role.hierarchy_rank <= 10))

        if getattr(group, "only_admin_invites", True):
            if not is_admin_or_owner:
                raise ForbiddenError("Only group owner and administrators are allowed to create invite links.")
        else:
            await self.require_group_permission(group_id, user_id, "add_members")

        token = secrets.token_urlsafe(24)
        expires_at = datetime.now(timezone.utc) + timedelta(hours=expires_hours)
        invite = await self._repo.create_invite(
            group_id=group_id,
            token=token,
            created_by=user_id,
            expires_at=expires_at,
            max_uses=1,
        )

        creator = await self._auth_repo.get_user_by_id(user_id)
        creator_name = creator.display_name if creator else "Admin"

        await self._audit.log(
            user_id=user_id,
            action="group.invite.created",
            resource_type="group_invite",
            resource_id=str(invite.id),
            details={"group_id": str(group_id), "token": token},
        )

        return GroupInviteResponse(
            id=invite.id,
            group_id=group.id,
            group_name=group.name,
            token=invite.token,
            invite_url=f"/join/{invite.token}",
            created_by=user_id,
            created_by_name=creator_name,
            max_uses=invite.max_uses,
            uses_count=invite.uses_count,
            is_expired=False,
            is_used=False,
            expires_at=invite.expires_at,
            created_at=invite.created_at,
        )

    async def get_invite_info(self, token: str) -> GroupInviteResponse:
        """Inspect invite link info."""
        invite = await self._repo.get_invite_by_token(token)
        if invite is None:
            raise NotFoundError("Invite link is invalid or has been deleted.")

        now = datetime.now(timezone.utc)
        is_expired = invite.is_revoked or (invite.expires_at.replace(tzinfo=timezone.utc) if invite.expires_at.tzinfo is None else invite.expires_at) < now
        is_used = invite.uses_count >= invite.max_uses

        creator = await self._auth_repo.get_user_by_id(invite.created_by)
        creator_name = creator.display_name if creator else "Admin"

        return GroupInviteResponse(
            id=invite.id,
            group_id=invite.group_id,
            group_name=invite.group.name if invite.group else "Group",
            token=invite.token,
            invite_url=f"/join/{invite.token}",
            created_by=invite.created_by,
            created_by_name=creator_name,
            max_uses=invite.max_uses,
            uses_count=invite.uses_count,
            is_expired=is_expired,
            is_used=is_used,
            expires_at=invite.expires_at,
            created_at=invite.created_at,
        )

    async def accept_invite_link(
        self, token: str, user_id: uuid.UUID,
    ) -> GroupInviteAcceptResponse:
        """Join a group using a single-use expiring invite token."""
        invite = await self._repo.get_invite_by_token(token)
        if invite is None:
            raise NotFoundError("Invite link is invalid or has expired.")

        now = datetime.now(timezone.utc)
        exp_at = invite.expires_at.replace(tzinfo=timezone.utc) if invite.expires_at.tzinfo is None else invite.expires_at
        if invite.is_revoked or exp_at < now:
            raise ForbiddenError("This invite link has expired.")

        if invite.uses_count >= invite.max_uses:
            raise ForbiddenError("This single-use invite link has already been used.")

        user_org = await self._get_org_id(user_id)
        if invite.group.organization_id != user_org:
            raise ForbiddenError("You cannot join a group from another organization.")

        group_id = invite.group_id
        group_name = invite.group.name if invite.group else "Group"

        # If already member, return success
        if not await self._repo.is_member(group_id, user_id):
            default_role = await self._repo.get_default_role(group_id)
            await self._repo.add_member(
                group_id=group_id,
                user_id=user_id,
                role_id=default_role.id if default_role else None,
                added_by=invite.created_by,
            )

            # Consume single-use invite
            await self._repo.increment_invite_use(invite)

            # Sync conversation participant
            try:
                from connecthub.modules.messaging.models import Conversation, ConversationParticipant, ConversationType

                stmt = select(Conversation).where(
                    and_(
                        Conversation.organization_id == user_org,
                        Conversation.conversation_type == ConversationType.GROUP,
                        Conversation.target_id == group_id,
                    )
                )
                conv = (await self._session.execute(stmt)).scalar_one_or_none()
                if conv is not None:
                    part_check = select(ConversationParticipant).where(
                        and_(
                            ConversationParticipant.conversation_id == conv.id,
                            ConversationParticipant.user_id == user_id,
                        )
                    )
                    if (await self._session.execute(part_check)).scalar_one_or_none() is None:
                        self._session.add(ConversationParticipant(conversation_id=conv.id, user_id=user_id))
                        await self._session.flush()
            except Exception as e:
                logger.warning("Conversation sync on invite accept: %s", e)

            await self._audit.log(
                user_id=user_id,
                action="group.invite.accepted",
                resource_type="group",
                resource_id=str(group_id),
                details={"token": token},
            )

        # Get conversation id for direct navigation
        conv_id = None
        try:
            from connecthub.modules.messaging.models import Conversation, ConversationType

            stmt = select(Conversation.id).where(
                and_(
                    Conversation.organization_id == user_org,
                    Conversation.conversation_type == ConversationType.GROUP,
                    Conversation.target_id == group_id,
                )
            )
            conv_id = (await self._session.execute(stmt)).scalar_one_or_none()
        except Exception:
            pass

        return GroupInviteAcceptResponse(
            message=f"Successfully joined {group_name}!",
            group_id=group_id,
            group_name=group_name,
            conversation_id=conv_id,
        )

    async def invite_user_by_handle_or_id(
        self,
        group_id: uuid.UUID,
        user_id: uuid.UUID,
        target_handle_or_id: str | uuid.UUID,
        role_id: uuid.UUID | None = None,
    ) -> UserInviteResponse:
        """Send an invitation notification directly to a user specified by handle (@username) or ID."""
        group = await self._repo.get_by_id(group_id)
        if group is None:
            raise NotFoundError("Group not found.")

        caller_role, is_owner = await self.get_user_effective_role(group_id, user_id)
        is_sa = await self._is_super_admin(user_id)
        is_admin_or_owner = is_owner or is_sa or (caller_role is not None and (caller_role.name == "Group Admin" or caller_role.hierarchy_rank <= 10))

        if getattr(group, "only_admin_invites", True):
            if not is_admin_or_owner:
                raise ForbiddenError("Only group owner and administrators are allowed to invite members.")
        else:
            await self.require_group_permission(group_id, user_id, "add_members")

        # Resolve target user
        target_user: User | None = None
        query_str = str(target_handle_or_id).strip()
        clean_handle = query_str.lstrip("@").lower()

        # Try by UUID first
        try:
            target_uuid = uuid.UUID(query_str)
            target_user = await self._auth_repo.get_user_by_id(target_uuid)
        except ValueError:
            target_user = None

        if target_user is None:
            target_user = await self._auth_repo.get_user_by_email(clean_handle)

        if target_user is None or target_user.organization_id != group.organization_id:
            raise NotFoundError(f"User '@{clean_handle}' was not found or is not available in your organization.")

        if await self._repo.is_member(group_id, target_user.id):
            raise ConflictError(f"@{target_user.username} is already a member of this group.")

        sender = await self._auth_repo.get_user_by_id(user_id)
        sender_name = sender.display_name if sender else "Group Admin"
        sender_handle = sender.username if sender else "admin"

        # Find group conversation if exists
        conv_id = None
        try:
            from connecthub.modules.messaging.models import Conversation, ConversationType
            c_stmt = select(Conversation.id).where(
                and_(
                    Conversation.organization_id == group.organization_id,
                    Conversation.conversation_type == ConversationType.GROUP,
                    Conversation.target_id == group_id,
                )
            )
            conv_id = (await self._session.execute(c_stmt)).scalar_one_or_none()
        except Exception:
            pass

        notif_service = NotificationService(self._session)
        notif = await notif_service.create_notification(
            user_id=target_user.id,
            notification_type=NotificationType.INVITATION,
            title=f"Group Invitation: {group.name}",
            body=f"{sender_name} (@{sender_handle}) invited you to join '{group.name}'.",
            resource_type="group_invite",
            resource_id=str(group.id),
            conversation_id=conv_id,
        )

        await self._audit.log(
            user_id=user_id,
            action="group.member.invited",
            resource_type="group",
            resource_id=str(group_id),
            details={"invited_user_id": str(target_user.id), "invited_username": target_user.username},
        )

        return UserInviteResponse(
            message=f"Invitation sent to @{target_user.username} successfully.",
            target_user_id=target_user.id,
            target_username=target_user.username,
            notification_id=notif.id if notif else None,
        )

    async def respond_to_invitation(
        self,
        group_id: uuid.UUID,
        user_id: uuid.UUID,
        action: str,
        notification_id: uuid.UUID | None = None,
    ) -> dict:
        """Accept or reject a group invitation."""
        group = await self._repo.get_by_id(group_id)
        if group is None:
            raise NotFoundError("Group not found.")

        if action == "accept":
            if not await self._repo.is_member(group_id, user_id):
                default_role = await self._repo.get_default_role(group_id)
                await self._repo.add_member(
                    group_id=group_id,
                    user_id=user_id,
                    role_id=default_role.id if default_role else None,
                    added_by=group.created_by,
                )

                # Sync conversation
                try:
                    from connecthub.modules.messaging.models import Conversation, ConversationParticipant, ConversationType

                    stmt = select(Conversation).where(
                        and_(
                            Conversation.organization_id == group.organization_id,
                            Conversation.conversation_type == ConversationType.GROUP,
                            Conversation.target_id == group_id,
                        )
                    )
                    conv = (await self._session.execute(stmt)).scalar_one_or_none()
                    if conv is not None:
                        part_check = select(ConversationParticipant).where(
                            and_(
                                ConversationParticipant.conversation_id == conv.id,
                                ConversationParticipant.user_id == user_id,
                            )
                        )
                        if (await self._session.execute(part_check)).scalar_one_or_none() is None:
                            self._session.add(ConversationParticipant(conversation_id=conv.id, user_id=user_id))
                            await self._session.flush()
                except Exception as e:
                    logger.warning("Conversation sync on invite response: %s", e)

            if notification_id:
                try:
                    notif_service = NotificationService(self._session)
                    await notif_service.mark_read(user_id, notification_id)
                except Exception:
                    pass

            await self._audit.log(
                user_id=user_id,
                action="group.invitation.accepted",
                resource_type="group",
                resource_id=str(group_id),
            )

            # Get conversation id for navigation
            conv_id = None
            try:
                from connecthub.modules.messaging.models import Conversation, ConversationType
                c_stmt = select(Conversation.id).where(
                    and_(
                        Conversation.organization_id == group.organization_id,
                        Conversation.conversation_type == ConversationType.GROUP,
                        Conversation.target_id == group_id,
                    )
                )
                conv_id = (await self._session.execute(c_stmt)).scalar_one_or_none()
            except Exception:
                pass

            return {
                "message": f"You have joined {group.name}!",
                "status": "accepted",
                "group_id": str(group_id),
                "conversation_id": str(conv_id) if conv_id else None,
            }

        else:
            if notification_id:
                try:
                    notif_service = NotificationService(self._session)
                    await notif_service.mark_read(user_id, notification_id)
                except Exception:
                    pass

            await self._audit.log(
                user_id=user_id,
                action="group.invitation.rejected",
                resource_type="group",
                resource_id=str(group_id),
            )

            return {
                "message": f"Invitation to {group.name} was declined.",
                "status": "rejected",
                "group_id": str(group_id),
            }
