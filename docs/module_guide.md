# ConnectHub — Module Creation Guide

## Overview

ConnectHub uses a **convention-based module system**. Every business feature is a self-contained module under `src/connecthub/modules/`. Modules are automatically discovered and registered at application startup — no manual wiring required.

---

## Module Structure

Create a new directory under `src/connecthub/modules/` with this structure:

```
modules/<module_name>/
├── __init__.py          # Module registration
├── router.py            # FastAPI APIRouter
├── service.py           # Business logic
├── repository.py        # Data access (SQLAlchemy)
├── models.py            # ORM models
├── schemas.py           # Pydantic request/response schemas
├── events.py            # Event types this module publishes
├── config.py            # Module-specific config (optional)
├── exceptions.py        # Module-specific exceptions (optional)
├── tests/
│   ├── __init__.py
│   ├── test_router.py
│   ├── test_service.py
│   └── test_repository.py
└── README.md            # Module documentation
```

---

## Step-by-Step

### 1. Create the Module Directory

```bash
mkdir -p src/connecthub/modules/my_feature
mkdir -p src/connecthub/modules/my_feature/tests
```

### 2. Create `__init__.py` with `register()`

The module registry looks for a `register(app: FastAPI)` function in each module's `__init__.py`:

```python
"""MyFeature module — short description."""

from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from fastapi import FastAPI


def register(app: FastAPI) -> None:
    """Register the MyFeature module with the application."""
    from connecthub.modules.my_feature.router import router

    app.include_router(router, prefix="/my-feature", tags=["my-feature"])
```

### 3. Create `models.py`

```python
"""MyFeature — ORM Models."""

from __future__ import annotations

from sqlalchemy import String
from sqlalchemy.orm import Mapped, mapped_column

from connecthub.core.database.base import Base, IDMixin, TimestampMixin, SoftDeleteMixin


class MyFeature(Base, IDMixin, TimestampMixin, SoftDeleteMixin):
    __tablename__ = "my_features"

    name: Mapped[str] = mapped_column(String(255), nullable=False)
    description: Mapped[str | None] = mapped_column(String(1000), nullable=True)
```

### 4. Create `schemas.py`

```python
"""MyFeature — Request/Response Schemas."""

from __future__ import annotations

import uuid
from datetime import datetime

from pydantic import BaseModel, Field


class MyFeatureCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=255)
    description: str | None = None


class MyFeatureResponse(BaseModel):
    id: uuid.UUID
    name: str
    description: str | None
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}
```

### 5. Create `repository.py`

```python
"""MyFeature — Data Access Layer."""

from __future__ import annotations

import uuid

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from connecthub.modules.my_feature.models import MyFeature


class MyFeatureRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def create(self, name: str, description: str | None = None) -> MyFeature:
        feature = MyFeature(name=name, description=description)
        self._session.add(feature)
        await self._session.flush()
        return feature

    async def get_by_id(self, feature_id: uuid.UUID) -> MyFeature | None:
        stmt = select(MyFeature).where(
            MyFeature.id == feature_id,
            MyFeature.deleted_at.is_(None),  # Respect soft-delete
        )
        result = await self._session.execute(stmt)
        return result.scalar_one_or_none()
```

### 6. Create `service.py`

```python
"""MyFeature — Business Logic Layer."""

from __future__ import annotations

import uuid

from sqlalchemy.ext.asyncio import AsyncSession

from connecthub.core.exceptions import NotFoundError
from connecthub.modules.my_feature.models import MyFeature
from connecthub.modules.my_feature.repository import MyFeatureRepository


class MyFeatureService:
    def __init__(self, session: AsyncSession) -> None:
        self._repo = MyFeatureRepository(session)

    async def create_feature(self, name: str, description: str | None = None) -> MyFeature:
        # TODO: Check permissions via permission engine
        return await self._repo.create(name=name, description=description)

    async def get_feature(self, feature_id: uuid.UUID) -> MyFeature:
        # TODO: Check permissions via permission engine
        feature = await self._repo.get_by_id(feature_id)
        if feature is None:
            raise NotFoundError("Resource not found.")  # No info leakage
        return feature
```

### 7. Create `router.py`

```python
"""MyFeature — HTTP Endpoints."""

from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from connecthub.core.dependencies import get_db_session
from connecthub.modules.my_feature.schemas import MyFeatureCreate, MyFeatureResponse
from connecthub.modules.my_feature.service import MyFeatureService

router = APIRouter()


@router.post("/", response_model=MyFeatureResponse, status_code=201)
async def create_feature(
    data: MyFeatureCreate,
    db: AsyncSession = Depends(get_db_session),
) -> MyFeatureResponse:
    service = MyFeatureService(db)
    feature = await service.create_feature(name=data.name, description=data.description)
    return MyFeatureResponse.model_validate(feature)


@router.get("/{feature_id}", response_model=MyFeatureResponse)
async def get_feature(
    feature_id: uuid.UUID,
    db: AsyncSession = Depends(get_db_session),
) -> MyFeatureResponse:
    service = MyFeatureService(db)
    feature = await service.get_feature(feature_id)
    return MyFeatureResponse.model_validate(feature)
```

### 8. Create `README.md`

Document the module's purpose, public interface, and internal implementation:

```markdown
# MyFeature Module

## Purpose
Brief description of what this module does.

## Public Interface
- `POST /my-feature/` — Create a new feature
- `GET /my-feature/{id}` — Get a feature by ID

## Internal (Private)
- Repository methods are internal — other modules must not call them directly
- Use events for inter-module communication

## Events Published
- `my_feature.created` — When a new feature is created
```

### 9. Generate Migration

```bash
uv run alembic revision --autogenerate -m "add my_feature table"
uv run alembic upgrade head
```

### 10. Write Tests

Follow the same pattern as the core tests in `tests/core/`.

---

## Rules

1. **Never import from another module** — use events or core interfaces
2. **Always check permissions** via the permission engine (Phase 2+)
3. **Use `NotFoundError`** for both missing and unauthorized resources (no info leakage)
4. **Register events** in `events.py` — document what the module publishes
5. **Write tests** for router, service, and repository layers
6. **Document** the module's public interface in `README.md`
