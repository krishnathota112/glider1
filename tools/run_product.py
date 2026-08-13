#!/usr/bin/env python3
"""
run_product.py — build a complete data product end to end and report it.

Chains the whole pipeline for one deployment and verifies each stage:

  1. run_pipeline.py      raw binaries -> L0/L1/grids/profiles/plots/reports/EGO
  2. ego_checker          validate both EGO files against the official rules
  3. load_deployment      EGO -> SQLite (wide core + wide bgc)
  4. verify_db            DB counts vs NetCDF non-fill counts
  5. inventory            list every artefact the run produced

Usage:
    python tools/run_product.py <deployment_dir> [--skip-pipeline] [--db PATH]
"""
from __future__ import annotations

import argparse
import glob
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, ROOT)
sys.path.insert(0, HERE)


def _ensure_utf8_console():
    """
    Make this script's own stdout tolerate the pipeline's non-ASCII output.

    The pipeline prints em dashes and arrows; on a default Windows console (or
    when redirected to a file) that is cp1252 and raises UnicodeEncodeError,
    killing the wrapper mid-run. pipeline/config.py guards its own streams the
    same way, but a subprocess's output is re-encoded by *this* process.
    """
    for stream in (sys.stdout, sys.stderr):
        reconfigure = getattr(stream, "reconfigure", None)
        if reconfigure is not None:
            try:
                reconfigure(encoding="utf-8", errors="replace")
            except (ValueError, OSError):
                pass


_ensure_utf8_console()


def hdr(n, title):
    print()
    print("=" * 78)
    print(f"  STAGE {n}: {title}")
    print("=" * 78)


def mb(path):
    try:
        return os.path.getsize(path) / 1024 / 1024
    except OSError:
        return 0.0


def stage_pipeline(dep: str) -> bool:
    hdr(1, "PIPELINE — raw binaries to L0/L1/grids/profiles/plots/EGO")
    script = os.path.join(ROOT, "pipeline", "run_pipeline.py")
    cmd = [sys.executable, "-u", script, "--data-dir", dep,
           "--l0-source", "auto"]
    print(f"  $ {' '.join(cmd)}")
    print("  (this takes several minutes; step markers below)\n")

    t0 = time.time()
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True,
                            encoding="utf-8", errors="replace", bufsize=1)
    keep = ("STEP", "PIPELINE COMPLETE", "ERROR", "WARNING", "Traceback",
            "Grid saved", "Split", "Created", "EGO file written",
            "Parameters:", "NOTE:", "POSITIONING_METHOD", "PLATFORM_TYPE",
            "DOXY umol", "_ADJUSTED:", "Observations:", "Pre-clean")
    for line in proc.stdout:
        if any(k in line for k in keep):
            print("   ", line.rstrip())
    proc.wait()
    print(f"\n  pipeline exit={proc.returncode} in {time.time() - t0:.0f}s")
    return proc.returncode == 0


def stage_compliance(dep: str) -> bool:
    hdr(2, "EGO 1.5 COMPLIANCE — validated against the official checker rules")
    from ego_checker import check_file, print_report

    ego_dir = os.path.join(dep, "output", "EGO-timeseries")
    files = sorted(glob.glob(os.path.join(ego_dir, "*.nc")))
    if not files:
        print("  ERROR: no EGO files produced")
        return False

    all_ok = True
    for f in files:
        rep = check_file(f)
        print_report(f, rep)
        all_ok &= rep.compliant
    return all_ok


def stage_database(dep: str, db: str) -> bool:
    hdr(3, "DATABASE — EGO NetCDF into SQLite (wide core + wide bgc)")
    from db.load_deployment import load_deployment

    for suffix in ("", "-wal", "-shm"):
        p = db + suffix
        if os.path.exists(p):
            try:
                os.remove(p)
            except OSError as e:
                print(f"  NOTE: could not remove {p} ({e}); loading in place. "
                      f"Close it in DB Browser for a clean rebuild.")

    ego_dir = os.path.join(dep, "output", "EGO-timeseries")
    res = load_deployment(ego_dir=ego_dir, db_path=db, verbose=True)
    return res["rows"]["observation"] > 0


def stage_verify(dep: str, db: str) -> bool:
    hdr(4, "VERIFY — database contents against the NetCDF")
    from db.load_deployment import find_ego_files
    from verify_db import main as verify_main

    ego_dir = os.path.join(dep, "output", "EGO-timeseries")
    l1 = find_ego_files(ego_dir, verbose=False).get("ego_l1")
    if not l1:
        print("  ERROR: no EGO L1 file to verify against")
        return False
    return verify_main([l1, "--db", db]) == 0


def stage_inventory(dep: str, db: str) -> None:
    hdr(5, "DATA PRODUCT INVENTORY")
    out = os.path.join(dep, "output")

    # L0 timeseries can live at the deployment root (pyglider-produced) rather
    # than under output/, so it is globbed from both.
    l0_ts = sorted(
        glob.glob(os.path.join(out, "L0-timeseries", "*.nc"))
        + glob.glob(os.path.join(dep, "L0-timeseries", "*.nc")))

    groups = [
        ("L0 timeseries", "L0-timeseries/*.nc"),
        ("L0 profiles", "L0-profiles/*.nc"),
        ("L0 grid", "L0-gridfiles/*.nc"),
        ("L1 timeseries", "L1-timeseries/*.nc"),
        ("L1 profiles", "L1-profiles/*.nc"),
        ("L1 grid", "L1-gridfiles/*.nc"),
        ("EGO 1.5", "EGO-timeseries/*.nc"),
        ("Plots (PNG)", "plots/*.png"),
        ("Reports", "reports/*.txt"),
    ]

    total_files = total_mb = 0
    print(f"  {'Product':<18} {'Files':>6} {'Size':>11}   Detail")
    print("  " + "-" * 74)
    for label, pat in groups:
        hits = (l0_ts if label == "L0 timeseries"
                else sorted(glob.glob(os.path.join(out, pat))))
        size = sum(mb(h) for h in hits)
        total_files += len(hits)
        total_mb += size
        if not hits:
            print(f"  {label:<18} {0:>6} {'-':>11}")
            continue
        if len(hits) <= 4:
            detail = ", ".join(os.path.basename(h) for h in hits)
        else:
            detail = (f"{os.path.basename(hits[0])} … "
                      f"{os.path.basename(hits[-1])}")
        print(f"  {label:<18} {len(hits):>6} {size:>9.1f} MB   {detail[:60]}")
    print("  " + "-" * 74)
    print(f"  {'TOTAL':<18} {total_files:>6} {total_mb:>9.1f} MB")

    # EGO files get their own listing: they are the publishable product.
    print("\n  EGO 1.5 files (the publishable product):")
    for f in sorted(glob.glob(os.path.join(out, "EGO-timeseries", "*.nc"))):
        print(f"    {mb(f):7.1f} MB  {f}")

    # Database summary straight from the tables.
    print(f"\n  Database: {db}")
    if os.path.exists(db):
        import sqlite3
        conn = sqlite3.connect(f"file:{os.path.abspath(db)}?mode=ro", uri=True)
        conn.row_factory = sqlite3.Row
        try:
            print(f"    size: {mb(db):.1f} MB")
            for t in ("meta", "observation", "core", "bgc"):
                n = conn.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0]
                cols = len(list(conn.execute(f'PRAGMA table_info("{t}")')))
                print(f"    {t:<12} {n:>10,} rows   {cols:>3} columns")
            for t in ("core", "bgc"):
                cols = [r[1] for r in conn.execute(f'PRAGMA table_info("{t}")')
                        if r[1] != "observation_id"]
                print(f"\n    {t} columns:")
                print(f"      {', '.join(cols)}")
            print("\n    QC summary (Good% is a share of FLAGGED points):")
            print(f"      {'variable':<9} {'table':<5} {'values':>9} "
                  f"{'good%':>7} {'bad':>8} {'missing':>9} {'no_qc':>9} "
                  f"{'adjusted':>9}")
            for view, fam in (("core_qc_summary", "core"),
                              ("bgc_qc_summary", "bgc")):
                for r in conn.execute(f"SELECT * FROM {view} "
                                      f"ORDER BY variable_name"):
                    d = dict(r)
                    pg = d["pct_good"]
                    print(f"      {d['variable_name']:<9} {fam:<5} "
                          f"{d['n_values']:>9,} "
                          f"{(f'{pg:.1f}' if pg is not None else '-'):>7} "
                          f"{d['n_bad'] or 0:>8,} {d['n_missing'] or 0:>9,} "
                          f"{d['n_no_qc'] or 0:>9,} {d['n_adjusted'] or 0:>9,}")
        finally:
            conn.close()
    else:
        print("    (not created)")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Build a full data product")
    ap.add_argument("deployment_dir")
    ap.add_argument("--db", default=os.path.join(ROOT, "glider_ego.db"))
    ap.add_argument("--skip-pipeline", action="store_true",
                    help="Reuse existing L0/L1 and rebuild from EGO onward")
    args = ap.parse_args(argv)

    dep = os.path.abspath(args.deployment_dir)
    if not os.path.isdir(dep):
        print(f"ERROR: not a directory: {dep}", file=sys.stderr)
        return 2

    t0 = time.time()
    print("=" * 78)
    print("  GLIDER DATA PRODUCT BUILD")
    print("=" * 78)
    print(f"  deployment : {dep}")
    print(f"  database   : {args.db}")

    results = {}
    if args.skip_pipeline:
        print("\n  (skipping pipeline; reusing existing L0/L1)")
    else:
        results["pipeline"] = stage_pipeline(dep)
        if not results["pipeline"]:
            print("\n  Pipeline failed — stopping before the later stages.")
            return 1

    results["compliance"] = stage_compliance(dep)
    results["database"] = stage_database(dep, args.db)
    results["verify"] = stage_verify(dep, args.db)
    stage_inventory(dep, args.db)

    print()
    print("=" * 78)
    print("  BUILD SUMMARY")
    print("=" * 78)
    for k, v in results.items():
        print(f"  {k:<12} {'OK' if v else 'FAILED'}")
    print(f"\n  Completed in {time.time() - t0:.0f}s")
    print("=" * 78)
    return 0 if all(results.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
