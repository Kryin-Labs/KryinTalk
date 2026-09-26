"""Static contract for the UUID-safe Supabase group boundary."""

from pathlib import Path


MIGRATION = Path(__file__).parents[2] / "supabase" / "migrations" / "20260906140000_group_core_rpc.sql"


def test_group_core_uses_authenticated_rpcs_and_enforces_messages() -> None:
    sql = MIGRATION.read_text(encoding="utf-8")
    for name in (
        "create_kryintalk_group",
        "update_kryintalk_group",
        "create_kryintalk_group_role",
        "assign_kryintalk_group_member_role",
        "find_or_create_kryintalk_group_conversation",
        "kryintalk_enforce_group_message_permission",
    ):
        assert name in sql
    assert "p_member_ids uuid[]" in sql
    assert "p_user_ids uuid[]" in sql
    assert "kryintalk_can_message_action(p_message_id text" in sql
    assert "kryintalk_can_message_action(id::text" in sql
    assert "auth.uid()" in sql
    assert "BEFORE INSERT OR UPDATE ON public.messages" in sql
    assert "GRANT EXECUTE ON FUNCTION public.create_kryintalk_group" in sql
    assert "WITH CHECK (sender_id = OLD.sender_id)" not in sql


def test_group_deletion_soft_deletes_and_revokes_chat_access() -> None:
    sql = (MIGRATION.parent / "20260906141000_group_delete_rpc.sql").read_text(
        encoding="utf-8"
    )
    assert "delete_kryintalk_group" in sql
    assert "deleted_at = now()" in sql
    assert "DELETE FROM public.conversation_participants" in sql
    assert "GRANT EXECUTE ON FUNCTION public.delete_kryintalk_group" in sql


def test_group_invites_expire_limit_and_lock_before_accepting() -> None:
    sql = (MIGRATION.parent / "20260906142000_group_invites_rpc.sql").read_text(
        encoding="utf-8"
    )
    assert "p_max_uses integer" in sql
    assert "p_expires_hours integer" in sql
    assert "FOR UPDATE" in sql
    assert "uses_count < max_uses" in sql
    assert "group_user_invitations" in sql
    assert "notification_items" in sql
    assert "created_by_username" in sql
    assert "GRANT EXECUTE ON FUNCTION public.get_kryintalk_group_invite(text) TO anon, authenticated" in sql
