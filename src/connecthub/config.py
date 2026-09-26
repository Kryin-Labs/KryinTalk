"""
ConnectHub — Centralized Configuration.

All application settings are loaded from environment variables (or a .env file)
via Pydantic Settings. No secrets are ever hardcoded.

Usage:
    from connecthub.config import settings
    print(settings.POSTGRES_HOST)
"""

from __future__ import annotations

import os
from functools import lru_cache
from typing import Literal

from pydantic import computed_field, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Application-wide settings loaded from environment variables."""

    model_config = SettingsConfigDict(
        env_file=os.environ.get("CONNECTHUB_ENV_FILE", ".env"),
        env_file_encoding="utf-8",
        case_sensitive=True,
        extra="ignore",
    )

    # ── Application ──────────────────────────────
    APP_NAME: str = "ConnectHub"
    APP_ENV: Literal["development", "staging", "production"] = "development"
    APP_DEBUG: bool = True
    APP_HOST: str = "127.0.0.1"
    APP_PORT: int = 8000
    APP_LOG_LEVEL: Literal["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"] = "INFO"

    # ── PostgreSQL ───────────────────────────────
    POSTGRES_HOST: str = "localhost"
    POSTGRES_PORT: int = 5432
    POSTGRES_USER: str = "connecthub"
    POSTGRES_PASSWORD: str = ""
    POSTGRES_DB: str = "connecthub"

    # ── Custom DB URL Override (Optional) ────────
    DATABASE_URL_OVERRIDE: str | None = None

    @computed_field  # type: ignore[prop-decorator]
    @property
    def DATABASE_URL(self) -> str:
        """Async PostgreSQL or SQLite connection string for SQLAlchemy."""
        if self.DATABASE_URL_OVERRIDE:
            return self.DATABASE_URL_OVERRIDE
        return (
            f"postgresql+asyncpg://{self.POSTGRES_USER}:{self.POSTGRES_PASSWORD}"
            f"@{self.POSTGRES_HOST}:{self.POSTGRES_PORT}/{self.POSTGRES_DB}"
        )

    @computed_field  # type: ignore[prop-decorator]
    @property
    def DATABASE_URL_SYNC(self) -> str:
        """Synchronous connection string (for Alembic migrations)."""
        if self.DATABASE_URL_OVERRIDE:
            return self.DATABASE_URL_OVERRIDE.replace(
                "sqlite+aiosqlite", "sqlite"
            ).replace("postgresql+asyncpg", "postgresql")
        return (
            f"postgresql://{self.POSTGRES_USER}:{self.POSTGRES_PASSWORD}"
            f"@{self.POSTGRES_HOST}:{self.POSTGRES_PORT}/{self.POSTGRES_DB}"
        )

    # ── Redis ────────────────────────────────────
    REDIS_HOST: str = "localhost"
    REDIS_PORT: int = 6379
    REDIS_PASSWORD: str = ""
    REDIS_DB: int = 0

    @computed_field  # type: ignore[prop-decorator]
    @property
    def REDIS_URL(self) -> str:
        """Redis connection string."""
        auth = f":{self.REDIS_PASSWORD}@" if self.REDIS_PASSWORD else ""
        return f"redis://{auth}{self.REDIS_HOST}:{self.REDIS_PORT}/{self.REDIS_DB}"

    # ── NATS ─────────────────────────────────────
    NATS_URL: str = "nats://localhost:4222"
    NATS_CLUSTER_NAME: str = "connecthub"

    # ── Security ─────────────────────────────────
    SECRET_KEY: str = ""
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    REFRESH_TOKEN_EXPIRE_DAYS: int = 365

    # ── CORS ─────────────────────────────────────
    CORS_ORIGINS: list[str] = [
        "http://localhost:3000",
        "http://127.0.0.1:3000",
        "http://localhost:8000",
        "http://127.0.0.1:8000",
        "http://localhost:8080",
        "http://127.0.0.1:8080",
        "http://localhost:5173",
        "http://127.0.0.1:5173",
    ]
    CORS_ORIGIN_REGEX: str = (
        r"^https?://(localhost|127\.0\.0\.1|0\.0\.0\.0|"
        r"192\.168\.\d+\.\d+|10\.\d+\.\d+\.\d+|172\.(1[6-9]|2\d|3[0-1])\.\d+\.\d+)(:\d+)?$"
    )

    # ── Domain ───────────────────────────────────
    DOMAIN: str = "connecthub.local"

    @computed_field  # type: ignore[prop-decorator]
    @property
    def is_production(self) -> bool:
        """Check if the application is running in production."""
        return self.APP_ENV == "production"

    @model_validator(mode="after")
    def validate_production_security(self) -> Settings:
        """Fail closed when production is configured with development defaults."""
        if not self.is_production:
            return self

        errors: list[str] = []
        if self.APP_DEBUG:
            errors.append("APP_DEBUG must be false in production")
        if len(self.SECRET_KEY) < 32 or self.SECRET_KEY.startswith("changeme"):
            errors.append("SECRET_KEY must be a generated value at least 32 characters long")
        if self.DATABASE_URL.lower().startswith("sqlite"):
            errors.append("DATABASE_URL must use PostgreSQL in production")
        if (
            (not self.POSTGRES_PASSWORD or self.POSTGRES_PASSWORD.startswith("changeme"))
            and not self.DATABASE_URL_OVERRIDE
        ):
            errors.append("POSTGRES_PASSWORD must be set in production")
        if errors:
            raise ValueError("Invalid production security configuration: " + "; ".join(errors))
        return self


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    """Return cached settings instance (singleton per process)."""
    return Settings()


# Convenience alias — import `settings` directly.
settings: Settings = get_settings()
