"""Guard the local Supabase hardening contract against schema drift."""

from pathlib import Path


MIGRATION = (
    Path(__file__).parents[2]
    / "supabase"
    / "migrations"
    / "20260905120000_security_hardening.sql"
)


def test_hardening_matches_the_live_mixed_key_schema() -> None:
    sql = MIGRATION.read_text(encoding="utf-8").lower()

    assert "users.role" not in sql
    assert "auth.uid()::text" in sql
    assert "same_kryintalk_key" in sql
    assert "public.same_kryintalk_key(c.id::text, p_conversation_id)" in sql
    assert "public.same_kryintalk_key(gm.group_id, g.id::text)" in sql
    assert "public.same_kryintalk_key(c.id::text, channel_members.channel_id)" in sql
    assert "public.same_kryintalk_key(r.id::text, user_roles.role_id)" in sql
    assert "public.same_kryintalk_key(user_id, auth.uid()::text)" in sql
    assert "v_friendship.id::text" in sql
    assert "from public.user_roles" in sql
    assert "join public.roles" in sql
    assert "create table if not exists public.friendships" in sql
    assert "invited_user_id" not in sql
    assert "r.deleted_at" not in sql
    assert "gm.group_role_id" not in sql
    assert "grant execute on function public.can_access_conversation(uuid) to authenticated" in sql
    assert "grant execute on function public.same_kryintalk_key(text, text) to authenticated" in sql


def test_messaging_rpcs_derive_actor_from_the_authenticated_session() -> None:
    sql = MIGRATION.read_text(encoding="utf-8").lower()

    for function in (
        "create_direct_conversation",
        "send_conversation_message",
        "mark_conversation_read",
        "get_conversation_state",
    ):
        assert f"function public.{function}" in sql

    assert "v_actor := auth.uid()" in sql
    assert "grant execute on function public.send_conversation_message" in sql
