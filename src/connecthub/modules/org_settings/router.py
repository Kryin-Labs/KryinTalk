"""
ConnectHub Org Settings Module — HTTP Endpoints.

Routes:
    GET  /organizations/me — Get current user's organization settings
    PUT  /organizations/me — Update organization settings
"""

from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, Request
from sqlalchemy.ext.asyncio import AsyncSession

from connecthub.core.database.session import get_db_session
from connecthub.modules.org_settings.schemas import OrgSettingsResponse, OrgSettingsUpdate
from connecthub.modules.org_settings.service import OrgSettingsService

router = APIRouter()


def _get_user_id(request: Request) -> uuid.UUID:
    return request.state.user_id


@router.get("/me", response_model=OrgSettingsResponse)
async def get_organization(
    request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> OrgSettingsResponse:
    """Get the current user's organization settings."""
    service = OrgSettingsService(db)
    return await service.get_organization(_get_user_id(request))


@router.put("/me", response_model=OrgSettingsResponse)
async def update_organization(
    data: OrgSettingsUpdate,
    request: Request,
    db: AsyncSession = Depends(get_db_session),
) -> OrgSettingsResponse:
    """Update organization settings."""
    service = OrgSettingsService(db)
    return await service.update_organization(_get_user_id(request), data)
