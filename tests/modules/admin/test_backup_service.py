"""
ConnectHub — Backup Service Tests.

Create backup, list backups, restore from backup, delete backup, and verify operations are audited.
"""

from __future__ import annotations

import pytest

from connecthub.core.exceptions import NotFoundError


@pytest.mark.asyncio
async def test_create_backup(
    backup_service, super_admin_user, db_session,
):
    """Creating backup exports data to file and records audit log."""
    await db_session.commit()
    backup = await backup_service.create_backup(super_admin_user.id)
    await db_session.commit()

    assert backup.id.startswith("backup_")
    assert backup.size_bytes > 0
    assert "users" in backup.tables_backed_up
    assert "organizations" in backup.tables_backed_up


@pytest.mark.asyncio
async def test_list_backups(
    backup_service, super_admin_user, db_session,
):
    """List returns created backups."""
    await db_session.commit()
    b1 = await backup_service.create_backup(super_admin_user.id)
    await db_session.commit()

    listing = await backup_service.list_backups()
    assert listing.total >= 1
    ids = [b.id for b in listing.items]
    assert b1.id in ids


@pytest.mark.asyncio
async def test_restore_backup(
    backup_service, super_admin_user, db_session,
):
    """Restore repopulates database tables from backup file."""
    await db_session.commit()
    b1 = await backup_service.create_backup(super_admin_user.id)
    await db_session.commit()

    restore_res = await backup_service.restore_backup(super_admin_user.id, b1.id)
    await db_session.commit()

    assert restore_res.backup_id == b1.id
    assert len(restore_res.restored_tables) >= 1
    assert restore_res.total_records_restored > 0


@pytest.mark.asyncio
async def test_delete_backup(
    backup_service, super_admin_user, db_session,
):
    """Delete backup removes file."""
    await db_session.commit()
    b1 = await backup_service.create_backup(super_admin_user.id)
    await db_session.commit()

    await backup_service.delete_backup(super_admin_user.id, b1.id)
    await db_session.commit()

    listing = await backup_service.list_backups()
    ids = [b.id for b in listing.items]
    assert b1.id not in ids


@pytest.mark.asyncio
async def test_restore_nonexistent_backup_fails(
    backup_service, super_admin_user, db_session,
):
    """Restoring nonexistent backup raises 404."""
    await db_session.commit()
    with pytest.raises(NotFoundError):
        await backup_service.restore_backup(super_admin_user.id, "backup_nonexistent_123")


@pytest.mark.asyncio
async def test_backup_operations_audited(
    backup_service, audit_service, super_admin_user, db_session,
):
    """Backup, restore, and delete operations are audited."""
    await db_session.commit()
    b1 = await backup_service.create_backup(super_admin_user.id)
    await db_session.commit()

    await backup_service.restore_backup(super_admin_user.id, b1.id)
    await db_session.commit()

    await backup_service.delete_backup(super_admin_user.id, b1.id)
    await db_session.commit()

    logs = await audit_service.query(user_id=super_admin_user.id)
    actions = [l.action for l in logs]
    assert "admin.backup.created" in actions
    assert "admin.backup.restored" in actions
    assert "admin.backup.deleted" in actions
