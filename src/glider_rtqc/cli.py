"""
cli.py — console entry point for glider-rtqc

Thin wrapper around pipeline/run_pipeline.py.
Keeps config.py's global-state pattern intact for now;
the Config-dataclass refactor is a post-demo task.
"""

import os
import sys


def main():
    # Locate the pipeline directory relative to this file.
    # Works both as an installed package (src/glider_rtqc/cli.py)
    # and when run directly from the repo root.
    this_dir = os.path.dirname(os.path.abspath(__file__))

    # When installed as a package, pipeline/ is two levels up (repo root).
    # When running from src/glider_rtqc/ in dev mode (pip install -e .),
    # same relationship holds.
    repo_root = os.path.dirname(os.path.dirname(this_dir))
    pipeline_dir = os.path.join(repo_root, "pipeline")

    if not os.path.isdir(pipeline_dir):
        # Fallback: look relative to cwd (useful when running from repo root)
        pipeline_dir = os.path.join(os.getcwd(), "pipeline")

    if not os.path.isdir(pipeline_dir):
        print(f"ERROR: pipeline/ directory not found. Expected at {pipeline_dir}")
        print("       Run from the repo root or install with pip install -e .")
        sys.exit(1)

    # Add pipeline/ to sys.path so all the existing imports work unchanged
    if pipeline_dir not in sys.path:
        sys.path.insert(0, pipeline_dir)

    # Import and run the existing entry point — all argparse logic lives there
    from run_pipeline import main as run_pipeline_main
    run_pipeline_main()


if __name__ == "__main__":
    main()
