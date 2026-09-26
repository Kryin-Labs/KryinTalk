"""
ConnectHub — Module Registry.

Provides auto-discovery and registration of business modules.
Each module exposes a `register(app)` function that mounts its
router and registers its permissions with the permission engine.

Phase 1: This is a skeleton — no modules are registered yet.
Phase 2+: Modules will be added here as they are implemented.

Design:
    - Modules are self-contained packages under `src/connecthub/modules/`
    - Each module has a `router.py` with an APIRouter and a `register()` function
    - The registry discovers modules and calls their register() on app startup
    - New modules plug in without modifying this file (convention-based discovery)
"""

from __future__ import annotations

import importlib
import logging
import pkgutil
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from fastapi import FastAPI

logger = logging.getLogger(__name__)

# List of registered module names (populated at startup)
_registered_modules: list[str] = []


def discover_and_register_modules(app: FastAPI) -> list[str]:
    """Discover all modules under `connecthub.modules` and register them.

    Each module package must expose a `register(app: FastAPI) -> None` function.
    Modules without this function are skipped with a warning.

    Returns:
        List of successfully registered module names.
    """
    import connecthub.modules as modules_pkg

    for _importer, module_name, is_pkg in pkgutil.iter_modules(modules_pkg.__path__):
        if not is_pkg:
            continue  # Only packages (directories) are modules

        full_module_name = f"connecthub.modules.{module_name}"
        try:
            module = importlib.import_module(full_module_name)
            register_fn = getattr(module, "register", None)

            if register_fn is None:
                logger.warning(
                    "Module '%s' has no register() function — skipped.", module_name
                )
                continue

            register_fn(app)
            _registered_modules.append(module_name)
            logger.info("Module '%s' registered successfully.", module_name)

        except Exception:
            logger.exception("Failed to register module '%s'.", module_name)

    logger.info(
        "Module discovery complete: %d modules registered: %s",
        len(_registered_modules),
        _registered_modules,
    )
    return _registered_modules


def get_registered_modules() -> list[str]:
    """Return the list of currently registered module names."""
    return list(_registered_modules)
