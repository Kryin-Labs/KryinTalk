"""Keep the visible application identity on KryinTalk."""

from pathlib import Path


ROOT = Path(__file__).parents[2] / "clients" / "web"


def test_primary_brand_surfaces_use_kryintalk() -> None:
    app = (ROOT / "lib" / "main.dart").read_text(encoding="utf-8")
    logo = (ROOT / "lib" / "shared" / "widgets" / "connect_hub_logo.dart").read_text(
        encoding="utf-8"
    )
    web = (ROOT / "web" / "index.html").read_text(encoding="utf-8")

    assert "KryinTalkApp" in app
    assert "title: 'KryinTalk'" in app
    assert "class KryinTalkLogo" in logo
    assert "'KryinTalk'" in logo
    assert "Theme.of(context).colorScheme" in logo
    assert "<title>KryinTalk</title>" in web
