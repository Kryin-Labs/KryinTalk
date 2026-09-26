"""
ConnectHub — Password Hashing Utilities.

Uses bcrypt directly for secure password hashing.
This module provides utility functions only — no business logic.
"""

from __future__ import annotations

import bcrypt


def hash_password(plain_password: str) -> str:
    """Hash a plaintext password using bcrypt.

    Uses 12 rounds (OWASP recommended minimum).

    Args:
        plain_password: The plaintext password to hash.

    Returns:
        The bcrypt hash string.
    """
    password_bytes = plain_password.encode("utf-8")
    salt = bcrypt.gensalt(rounds=12)
    hashed = bcrypt.hashpw(password_bytes, salt)
    return hashed.decode("utf-8")


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Verify a plaintext password against a bcrypt hash.

    Args:
        plain_password: The plaintext password to verify.
        hashed_password: The stored bcrypt hash.

    Returns:
        True if the password matches, False otherwise.
    """
    return bcrypt.checkpw(
        plain_password.encode("utf-8"),
        hashed_password.encode("utf-8"),
    )

