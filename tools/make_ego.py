#!/usr/bin/env python3
"""
make_ego.py — regenerate EGO 1.5 files for a deployment, then validate them.

Wraps step_ego.run_ego_conversion so the EGO products can be rebuilt without
re-running the whole pipeline, and runs tools/ego_checker.py on the result.

Usage:
    python tools/make_ego.py <deployment_dir> [--no-check]
    python tools/make_ego.py <deployment_dir> --time-valid-max physical
"""
from __future__ import annotations

import argparse
import glob
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "pipeline"))
sys.path.insert(0, HERE)


def _find_l0(dep_dir: str) -> str | None:
    """L0 timeseries: prefer the pipeline output dir, then the data root."""
    for pat in (os.path.join(dep_dir, "output", "L0-timeseries", "*.nc"),
                os.path.join(dep_dir, "L0-timeseries", "*.nc")):
        hits = [h for h in glob.glob(pat) if "_EGO" not in os.path.basename(h)]
        if hits:
            return max(hits, key=os.path.getsize)
    return None


def _find_l1(dep_dir: str) -> str | None:
    pat = os.path.join(dep_dir, "output", "L1-timeseries", "*.nc")
    hits = [h for h in glob.glob(pat) if "_EGO" not in os.path.basename(h)]
    return max(hits, key=os.path.getsize) if hits else None


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Rebuild + validate EGO files")
    ap.add_argument("deployment_dir")
    ap.add_argument("--no-check", action="store_true")
    ap.add_argument("--time-valid-max", default="spec",
                    choices=["spec", "physical"])
    args = ap.parse_args(argv)

    dep = os.path.abspath(args.deployment_dir)
    if not os.path.isdir(dep):
        print(f"ERROR: not a directory: {dep}", file=sys.stderr)
        return 2

    import step_ego
    step_ego.EGO_TIME_VALID_MAX_MODE = args.time_valid_max

    l0 = _find_l0(dep)
    l1 = _find_l1(dep)
    yml = os.path.join(dep, "deployment.yml")
    out_dir = os.path.join(dep, "output")

    print(f"  deployment : {dep}")
    print(f"  L0         : {l0 or '(none)'}")
    print(f"  L1         : {l1 or '(none)'}")
    print(f"  valid_max  : {args.time_valid_max}")
    print()

    if not l0 and not l1:
        print("ERROR: no L0 or L1 timeseries found", file=sys.stderr)
        return 2

    results = step_ego.run_ego_conversion(
        l0_path=l0, l1_path=l1,
        deploy_yaml=yml if os.path.exists(yml) else None,
        output_dir=out_dir,
    )

    if args.no_check:
        return 0

    print()
    from ego_checker import check_file, print_report
    worst = 0
    for key in ("ego_l0", "ego_l1"):
        path = results.get(key)
        if not path:
            continue
        rep = check_file(path)
        print_report(path, rep)
        if not rep.compliant:
            worst = 1
    return worst


if __name__ == "__main__":
    sys.exit(main())
