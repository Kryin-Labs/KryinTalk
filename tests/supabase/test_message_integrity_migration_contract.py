"""Guard the message-integrity migration against policy regressions."""

from pathlib import Path


MIGRATION = (
    Path(__file__).parents[2]
    / "supabase"
    / "migrations"
    / "20260906130000_harden_message_integrity.sql"
)


def test_message_integrity_is_enforced_server_side() -> None:
    sql = MIGRATION.read_text(encoding="utf-8").lower()

    assert "kryintalk_validate_message_mutation" in sql
    assert "message content is too long" in sql
    assert "new.conversation_id is distinct from old.conversation_id" in sql
    assert "new.sender_id is distinct from old.sender_id" in sql
    assert "new.parent_id is distinct from old.parent_id" in sql
    assert "drop policy if exists kt_reactions_write" in sql
    assert "public.can_access_conversation(m.conversation_id)" in sql
