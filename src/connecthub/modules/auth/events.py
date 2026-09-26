"""
ConnectHub Auth Module — Event Types.

Events published by the auth module for inter-module communication.
"""

from __future__ import annotations

# Event type constants for the auth module.
# These are published to the event bus when admin operations occur.
# Other modules can subscribe to react (e.g., notifications).

AUTH_LOGIN_SUCCESS = "auth.login_success"
AUTH_LOGIN_FAILED = "auth.login_failed"

ADMIN_CREATED = "admin.created"
ADMIN_SUSPENDED = "admin.suspended"
ADMIN_REACTIVATED = "admin.reactivated"
ADMIN_PERMISSIONS_GRANTED = "admin.permissions.granted"
ADMIN_PERMISSIONS_REVOKED = "admin.permissions.revoked"

SUPERADMIN_BOOTSTRAPPED = "superadmin.bootstrapped"
