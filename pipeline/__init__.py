"""
pipeline — the INCOIS glider RTQC processing steps.

The modules in here import each other flatly (`import config`,
`from step1 import run_step1`) and each prepends this directory to sys.path at
import time, so they run identically as scripts and as package members.

This file exists so the directory is a real package: `pip install` then ships
it, and glider_rtqc.cli can locate it via `pipeline.__path__` instead of
guessing at relative paths from the installed location.

Nothing is imported eagerly here — pulling in step5/step6/step7 would drag
matplotlib into every `import pipeline`, which the SQLite loader and the tests
have no use for.
"""

__all__ = [
    "config",
    "run_pipeline",
    "step1", "step23", "step4", "step5", "step6", "step7",
    "verify",
]
