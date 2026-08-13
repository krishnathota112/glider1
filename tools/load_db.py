#!/usr/bin/env python3
"""
load_db.py — rebuild the SQLite database from a deployment's EGO files.

Thin driver around db.load_deployment so the reload is a single command and the
PowerShell quoting of long Windows paths stays in one place.

Usage:
    python tools/load_db.py <deployment_dir> [--db glider_ego.db] [--fresh]
"""
from __future__ import annotations

import argparse
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Load EGO files into SQLite")
    ap.add_argument("deployment_dir")
    ap.add_argument("--db", default=os.path.join(ROOT, "glider_ego.db"))
    ap.add_argument("--fresh", action="store_true",
                    help="Delete the database first for a clean rebuild")
    args = ap.parse_args(argv)

    ego_dir = os.path.join(os.path.abspath(args.deployment_dir),
                           "output", "EGO-timeseries")
    if not os.path.isdir(ego_dir):
        print(f"ERROR: no EGO-timeseries dir at {ego_dir}", file=sys.stderr)
        return 2

    if args.fresh:
        for suffix in ("", "-wal", "-shm"):
            p = args.db + suffix
            if os.path.exists(p):
                try:
                    os.remove(p)
                except OSError as e:
                    print(f"ERROR: cannot remove {p}: {e}\n"
                          f"  Close the database in DB Browser and retry.",
                          file=sys.stderr)
                    return 2

    from db.load_deployment import load_deployment
    load_deployment(ego_dir=ego_dir, db_path=args.db, verbose=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
