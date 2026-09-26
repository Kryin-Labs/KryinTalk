"""
ConnectHub — Permission System Constants.

String constants for referencing system roles and common actions in code.
These are NOT hardcoded logic — the actual permissions are stored in the database.
These constants exist only to avoid magic strings when code needs to reference
well-known system entities (e.g., checking if a user is Super Admin).

IMPORTANT: Business logic must NEVER use `if role == SUPER_ADMIN` to gate features.
Use PolicyService.check_permission() for all access decisions. The Super Admin
bypass is handled inside PolicyService, not in module code.
"""

from __future__ import annotations


# ── System Role Codes ────────────────────────
# These roles are seeded at migration time and marked is_system=True.
SUPER_ADMIN_ROLE = "super_admin"
ADMIN_ROLE = "admin"
MEMBER_ROLE = "member"

# ── Common Action Codes ─────────────────────
# Modules may define additional action codes beyond these.
ACTION_CREATE = "create"
ACTION_READ = "read"
ACTION_UPDATE = "update"
ACTION_DELETE = "delete"
ACTION_MANAGE = "manage"  # Full management access to a domain
ACTION_EXPORT = "export"
ACTION_IMPORT = "import"

# ── Common Permission Domains ────────────────
# Modules register their own domains; these are the core/system domains.
DOMAIN_PERMISSIONS = "permission_management"
DOMAIN_ROLES = "role_management"
DOMAIN_AUDIT = "audit_logs"
DOMAIN_SYSTEM = "system_configuration"
