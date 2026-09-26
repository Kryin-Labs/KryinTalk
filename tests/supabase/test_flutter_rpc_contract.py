"""Keep production messaging writes on the Supabase RPC boundary."""

from pathlib import Path


SERVICE = (
    Path(__file__).parents[2]
    / "clients"
    / "web"
    / "lib"
    / "core"
    / "supabase"
    / "supabase_service.dart"
)


def _method_body(source: str, signature: str, next_signature: str) -> str:
    start = source.index(signature)
    end = source.index(next_signature, start)
    return source[start:end]


def test_message_send_uses_authenticated_rpc_not_client_identity() -> None:
    source = SERVICE.read_text(encoding="utf-8")
    body = _method_body(source, "Future<Map<String, dynamic>?> sendMessage", "/// Subscribe")

    assert "send_conversation_message" in body
    assert ".from('messages')" not in body
    assert "sender_id" not in body


def test_direct_conversation_and_read_receipts_use_rpcs() -> None:
    source = SERVICE.read_text(encoding="utf-8")
    body = _method_body(source, "Future<Map<String, dynamic>> createConversation", "/// Add emoji")

    assert "create_direct_conversation" in body
    assert ".from('conversations')" not in body
    assert "Future<Map<String, dynamic>> markConversationRead" in source
    assert "mark_conversation_read" in source
    assert "get_conversation_state" in source


def test_bridge_handles_read_and_notification_acknowledgements() -> None:
    source = (
        SERVICE.parents[1]
        / "api"
        / "api_client.dart"
    ).read_text(encoding="utf-8")

    assert "markConversationRead" in source
    assert "/notifications/conversation/" in source
    assert "/notifications/read-all" in source


def test_directory_uses_columns_declared_in_the_uuid_schema() -> None:
    source = SERVICE.read_text(encoding="utf-8")
    bridge = (SERVICE.parents[1] / "api" / "api_client.dart").read_text(
        encoding="utf-8"
    )

    assert "role, avatar_url" not in source
    assert "presence_text" not in bridge
    assert "getUserById" in bridge


def test_current_profile_role_is_derived_from_the_role_join() -> None:
    migration = (
        Path(__file__).parents[2]
        / "supabase"
        / "migrations"
        / "20260905123000_profile_role_rpc.sql"
    ).read_text(encoding="utf-8")
    source = SERVICE.read_text(encoding="utf-8")

    assert "get_current_user_profile" in migration
    assert "public.user_roles" in migration
    assert "public.roles" in migration
    assert "same_kryintalk_key(r.id::text, ur.role_id)" in migration
    assert "same_kryintalk_key(ur.user_id, auth.uid()::text)" in migration
    assert "r.deleted_at" not in migration
    assert "is_super_admin" in migration
    assert "get_current_user_profile" in source


def test_friendship_writes_use_authenticated_rpcs() -> None:
    service = SERVICE.read_text(encoding="utf-8")
    friends = (
        SERVICE.parents[2] / "features" / "friends" / "friends_screen.dart"
    ).read_text(encoding="utf-8")
    messages = (
        SERVICE.parents[2] / "features" / "messaging" / "messages_screen.dart"
    ).read_text(encoding="utf-8")
    migration = (
        Path(__file__).parents[2]
        / "supabase"
        / "migrations"
        / "20260906100000_friendship_controls.sql"
    ).read_text(encoding="utf-8")

    for rpc in ("request_friendship", "respond_to_friendship", "remove_friendship", "block_user"):
        assert rpc in service
    assert ".from('friendships').insert" not in friends
    assert ".from('friendships').update" not in friends
    assert ".from('friendships').delete" not in friends
    assert ".from('friendships').insert" not in messages
    assert "function public.remove_friendship" in migration.lower()
    assert "function public.block_user" in migration.lower()


def test_legacy_organizational_features_are_not_exposed() -> None:
    web = SERVICE.parents[2]
    router = (web / "core" / "router" / "app_router.dart").read_text(encoding="utf-8")
    endpoints = (web / "core" / "api" / "api_endpoints.dart").read_text(encoding="utf-8")

    assert "return '/groups';" in router
    for path in ("/departments", "/teams", "/channels"):
        assert path in router
        assert f"static const {path.removeprefix('/')}" not in endpoints
    for source in (
        "departments/dept_list_screen.dart",
        "teams/team_list_screen.dart",
        "channels/channel_list_screen.dart",
        "channels/widgets/channel_settings_dialog.dart",
    ):
        assert not (web / "features" / source).exists()
