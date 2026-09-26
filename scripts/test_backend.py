"""Run offline backend tests with any compatible Python, including Codex's runtime.

Usage: python scripts/test_backend.py [pytest arguments]
If pytest is missing, reuse this checkout's installed .venv packages when its
Python major/minor version matches. No dependencies are downloaded or services started.
"""

from __future__ import annotations

import importlib.util
import os
import sys
from pathlib import Path


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    if importlib.util.find_spec("pytest") is None:
        config = root / ".venv" / "pyvenv.cfg"
        values = dict(
            line.split(" = ", 1)
            for line in config.read_text().splitlines()
            if " = " in line
        ) if config.exists() else {}
        version = values.get("version_info", values.get("version", ""))
        expected = f"{sys.version_info.major}.{sys.version_info.minor}"
        if not version.startswith(expected + "."):
            print("Install dev dependencies, or use Python matching .venv's version.", file=sys.stderr)
            return 2
        packages = root / ".venv" / (
            "Lib/site-packages" if os.name == "nt" else f"lib/python{expected}/site-packages"
        )
        sys.path.insert(0, str(packages))

    sys.path.insert(0, str(root / "src"))
    os.chdir(root)
    # Test conftest also enforces isolation for direct pytest invocations.
    os.environ["CONNECTHUB_ENV_FILE"] = ""
    import pytest

    return pytest.main(["-p", "no:cacheprovider", *sys.argv[1:]])


if __name__ == "__main__":
    raise SystemExit(main())
