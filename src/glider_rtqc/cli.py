"""
cli.py — console entry point for glider-rtqc

Thin wrapper around pipeline/run_pipeline.py.
Keeps config.py's global-state pattern intact for now;
the Config-dataclass refactor is a post-demo task.
"""

import os
import sys


def _pipeline_dir():
    """
    Locate the pipeline/ package directory.

    Preferred route is the installed `pipeline` package — pyproject declares
    it alongside glider_rtqc, so `pip install .` puts it on sys.path and this
    resolves wherever the console script is invoked from.

    The path-based fallbacks below only matter for a source tree that was
    never installed (a bare `git clone`, or `python src/glider_rtqc/cli.py`).
    """
    try:
        import pipeline
    except ImportError:
        pass
    else:
        paths = list(getattr(pipeline, "__path__", []))
        if paths:
            return paths[0]

    here = os.path.dirname(os.path.abspath(__file__))
    for candidate in (
        # repo root, from src/glider_rtqc/cli.py
        os.path.join(os.path.dirname(os.path.dirname(here)), "pipeline"),
        # invoked from the repo root
        os.path.join(os.getcwd(), "pipeline"),
    ):
        if os.path.isdir(candidate):
            return candidate
    return None


def main():
    pipeline_dir = _pipeline_dir()

    if pipeline_dir is None:
        print("ERROR: could not locate the pipeline/ package.")
        print("       Install the project with `pip install -e .`, "
              "or run from the repo root.")
        sys.exit(1)

    # Put pipeline/ on sys.path so its flat intra-package imports
    # (`import config`, `from step1 import ...`) resolve unchanged.
    if pipeline_dir not in sys.path:
        sys.path.insert(0, pipeline_dir)

    # Import and run the existing entry point — all argparse logic lives there
    from run_pipeline import main as run_pipeline_main
    run_pipeline_main()


if __name__ == "__main__":
    main()
