#!/usr/bin/env python3
"""
verify_db.py — confirm the SQLite contents match the EGO NetCDF exactly.

Compares per-parameter non-fill counts in the file against non-NULL counts in
the database. A silent NULL where real data exists is the failure mode this
guards against.
"""
from __future__ import annotations

import argparse
import os
import sqlite3
import sys

import netCDF4
import numpy as np

FILL = 99999.0
CORE = ("PRES", "TEMP", "PSAL", "CNDC")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("ego_l1")
    ap.add_argument("--db", default="glider_ego.db")
    args = ap.parse_args(argv)

    nc = netCDF4.Dataset(args.ego_l1)
    nc.set_auto_mask(False)          # required: TIME.valid_max=90000 per spec
    conn = sqlite3.connect(args.db)

    def nc_count(var):
        if var not in nc.variables:
            return None
        a = np.asarray(nc.variables[var][:], dtype=np.float64)
        return int(np.sum(np.isfinite(a) & (np.abs(a) < FILL - 1)))

    params = ["".join(str(c) for c in row).strip()
              for row in nc.variables["PARAMETER"][:]]

    print("=" * 72)
    print("  DB vs NetCDF — non-fill / non-NULL counts")
    print("=" * 72)
    print(f"  {'param':<10} {'table':<6} {'NetCDF':>10} {'DB':>10} "
          f"{'NetCDF adj':>11} {'DB adj':>10}  match")
    print("  " + "-" * 68)

    all_ok = True
    for p in params:  # noqa: PLR1702
        # core and bgc are both wide: the parameter is a real column in one of
        # them. Find which table holds it rather than assuming.
        table = "core" if p in CORE else "bgc"
        cols = [r[1] for r in conn.execute(f'PRAGMA table_info("{table}")')]
        if p not in cols:
            print(f"  {p:<10} {table:<6} {'-':>10} {'MISSING COLUMN':>10}")
            all_ok = False
            continue
        db_val = conn.execute(f'SELECT COUNT("{p}") FROM "{table}"').fetchone()[0]
        db_adj = conn.execute(
            f'SELECT COUNT("{p}_ADJUSTED") FROM "{table}"').fetchone()[0]

        f_val = nc_count(p)
        f_adj = nc_count(f"{p}_ADJUSTED") or 0
        ok = (f_val == db_val) and (f_adj == db_adj)
        all_ok &= ok
        print(f"  {p:<10} {table:<6} {f_val:>10,} {db_val:>10,} "
              f"{f_adj:>11,} {db_adj:>10,}  {'OK' if ok else 'MISMATCH'}")

    # Timestamp integrity: the valid_max=90000 trap would show up here.
    n_time = len(nc.dimensions["TIME"])
    n_obs = conn.execute("SELECT COUNT(*) FROM observation").fetchone()[0]
    n_null_ts = conn.execute(
        "SELECT COUNT(*) FROM observation WHERE timestamp IS NULL").fetchone()[0]
    print(f"\n  TIME in file : {n_time:,}")
    print(f"  observations : {n_obs:,}")
    print(f"  NULL timestamps: {n_null_ts}  (must be 0)")
    ts_ok = (n_obs == n_time) and n_null_ts == 0
    all_ok &= ts_ok

    dist = conn.execute(
        "SELECT distance_over_ground_km FROM meta").fetchone()[0]
    print(f"  distance     : {dist:.1f} km" if dist else "  distance: NULL")
    plausible = dist is not None and 10 <= dist <= 20000
    all_ok &= plausible
    print(f"  physically plausible (10-20000 km): {plausible}")

    conn.close()
    nc.close()

    print()
    print(f"  VERDICT: {'ALL CHECKS PASS' if all_ok else 'MISMATCHES FOUND'}")
    print("=" * 72)
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
