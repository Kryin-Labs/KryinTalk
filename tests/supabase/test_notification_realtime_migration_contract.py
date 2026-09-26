"""Static contract for event-driven notification delivery."""

from pathlib import Path


def test_notification_items_are_in_the_realtime_publication() -> None:
    source = (
        Path(__file__).parents[2]
        / "supabase"
        / "migrations"
        / "20260906144000_enable_notification_realtime.sql"
    ).read_text(encoding="utf-8")
    assert "pg_publication_tables" in source
    assert "supabase_realtime" in source
    assert "notification_items" in source
