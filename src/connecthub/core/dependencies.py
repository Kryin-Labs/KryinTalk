"""
ConnectHub — Shared FastAPI Dependencies.

Common dependencies used across all modules.
Module-specific dependencies live in their own module directories.
"""

from __future__ import annotations

from connecthub.core.database.session import get_db_session

# Re-export for convenient imports
__all__ = ["get_db_session"]
