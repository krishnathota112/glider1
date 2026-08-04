"""SQLite ingestion for glider RTQC pipeline outputs.

    from db import load_deployment
    load_deployment("/data/glider/890_2023/output")

Imports are lazy (PEP 562). Importing the submodule eagerly here would make
`python -m db.load_deployment` load and execute the module twice, which
runpy reports as a RuntimeWarning.
"""

from importlib import import_module

__all__ = ["load_deployment", "sanity_check"]


def __getattr__(name):
    if name in __all__:
        # import_module, not `from . import ...` — the submodule and the
        # function share the name `load_deployment`, so a fromlist import
        # would re-enter this __getattr__ and recurse forever.
        return getattr(import_module(f"{__name__}.load_deployment"), name)
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
