"""Static contract for the authenticated profile settings boundary."""

from pathlib import Path


def test_profile_updates_are_identity_bound_and_validated() -> None:
    source = (
        Path(__file__).parents[2]
        / "supabase"
        / "migrations"
        / "20260906143000_profile_settings_rpc.sql"
    ).read_text(encoding="utf-8")
    assert "update_kryintalk_profile" in source
    assert "auth.uid()" in source
    assert "FOR UPDATE" in source
    assert "^[a-z0-9_]{3,100}$" in source
    assert "GRANT EXECUTE ON FUNCTION public.update_kryintalk_profile" in source
