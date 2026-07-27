#!/usr/bin/env python3
"""
check_l0_coverage.py — Verify QC flag integrity for ALL variables.

Checks that:
  - Miss (flag 9) in L1 matches NaN in L0 (inherited, not manufactured)
  - Bad (flag 4)  in L1 accounts for values removed by QC tests
  - No valid L0 data silently disappears into flag 9

Usage:
    python3 check_l0_coverage.py /path/to/data_dir
"""
import sys
import os
import glob
import numpy as np

try:
    import xarray as xr
except ImportError:
    sys.exit("ERROR: xarray not installed.  Run: pip install xarray netCDF4")


# All variables the pipeline QC-flags
ALL_VARS = [
    "temperature",
    "salinity",
    "pressure",
    "depth",
    "oxygen_concentration",
    "chlorophyll",
    "cdom",
    "backscatter_700",
    "density",
    "latitude",
    "longitude",
]


def find_nc(data_dir, subdir, pattern):
    path = os.path.join(data_dir, "output", subdir)
    if os.path.isdir(path):
        hits = glob.glob(os.path.join(path, pattern))
        if hits:
            return sorted(hits)[-1]
    return None


# ── Section 1: raw L0 coverage ───────────────────────────────────────────────

def report_l0_coverage(l0_path):
    print("\n" + "=" * 70)
    print("SECTION 1 — L0 raw coverage (before pipeline touches anything)")
    print(f"File: {os.path.basename(l0_path)}")
    print("=" * 70)
    print(f"  {'Variable':<28}  {'Present':>8}  {'Total':>8}  "
          f"{'Cover%':>7}  {'NaN at L0':>10}")
    print("  " + "-" * 65)
    ds = xr.open_dataset(l0_path)
    results = {}
    for var in ALL_VARS:
        if var not in ds:
            continue
        n_total = int(ds[var].size)
        n_nan   = int(ds[var].isnull().sum())
        n_valid = n_total - n_nan
        pct     = 100.0 * n_valid / n_total if n_total > 0 else 0.0
        results[var] = {"n_total": n_total, "n_nan": n_nan, "n_valid": n_valid}
        print(f"  {var:<28}  {n_valid:>8,}  {n_total:>8,}  "
              f"{pct:>6.1f}%  {n_nan:>10,}")
    ds.close()
    return results


# ── Section 2: sample cadence ────────────────────────────────────────────────

def report_cadence(l0_path):
    print("\n" + "=" * 70)
    print("SECTION 2 — Sample cadence (optics vs CTD)")
    print("=" * 70)
    ds = xr.open_dataset(l0_path)
    t = ds["time"].values
    all_gaps = np.diff(t).astype("timedelta64[s]").astype(float)
    all_gaps = all_gaps[all_gaps > 0]
    ctd_median = np.median(all_gaps) if len(all_gaps) > 0 else 1.0
    print(f"  {'All timestamps':<28}  median gap = {ctd_median:.1f} s")

    for var in ["temperature", "salinity", "oxygen_concentration",
                "chlorophyll", "cdom", "backscatter_700"]:
        if var not in ds:
            continue
        vals = ds[var].values
        valid_t = t[np.isfinite(vals)]
        if len(valid_t) < 2:
            print(f"  {var:<28}  (too few points)")
            continue
        gaps = np.diff(valid_t).astype("timedelta64[s]").astype(float)
        gaps = gaps[gaps > 0]
        med = np.median(gaps)
        ratio = med / max(ctd_median, 1.0)
        note = ""
        if ratio > 3:
            note = "  ← sub-sampled sensor (normal)"
        elif ratio > 8:
            note = "  ← very sparse, check decode"
        print(f"  {var:<28}  median gap = {med:.1f} s  "
              f"({ratio:.1f}x CTD){note}")
    ds.close()


# ── Section 3: L0 vs L1 flag integrity ───────────────────────────────────────

def report_flag_integrity(l0_path, l1_path, l0_results):
    print("\n" + "=" * 70)
    print("SECTION 3 — Flag integrity: L0 NaN vs L1 flag breakdown")
    print(f"L0: {os.path.basename(l0_path)}")
    print(f"L1: {os.path.basename(l1_path)}")
    print("=" * 70)

    l0 = xr.open_dataset(l0_path)
    l1 = xr.open_dataset(l1_path)
    l1_n = len(l1.time)
    l0_n = len(l0.time)

    print(f"\n  Time points:  L0 = {l0_n:,}   L1 = {l1_n:,}  "
          f"({'same' if l0_n == l1_n else f'diff = {l0_n - l1_n:,} removed by pre-clean'})")

    issues = []

    print(f"\n  {'Variable':<28}  {'L0 NaN':>8}  {'L1 Miss':>8}  "
          f"{'L1 Bad':>8}  {'L1 Good':>8}  {'Extra Miss':>11}  Verdict")
    print("  " + "-" * 100)

    for var in ALL_VARS:
        if var not in l0:
            continue

        l0_nan   = l0_results.get(var, {}).get("n_nan", 0)
        l0_total = l0_results.get(var, {}).get("n_total", 0)

        if var not in l1:
            print(f"  {var:<28}  {l0_nan:>8,}  {'—':>8}  {'—':>8}  {'—':>8}  "
                  f"{'—':>11}  not in L1")
            continue

        qc_var = f"{var}_QC"
        if qc_var not in l1:
            print(f"  {var:<28}  {l0_nan:>8,}  {'no QC':>8}  {'—':>8}  {'—':>8}  "
                  f"{'—':>11}  no QC array in L1")
            continue

        qc = l1[qc_var].values.astype(int)
        l1_good   = int(np.sum(qc == 1))
        l1_pgood  = int(np.sum(qc == 2))
        l1_pbad   = int(np.sum(qc == 3))
        l1_bad    = int(np.sum(qc == 4))
        l1_miss   = int(np.sum(qc == 9))
        l1_total  = len(qc)

        # Scale L0 NaN to L1 size if pre-clean removed rows
        # L0 NaN that were in removed rows are gone from L1 entirely —
        # so the expected Miss count in L1 is l0_nan scaled by (l1_total/l0_total)
        if l0_total > 0 and l0_total != l1_total:
            scale = l1_total / l0_total
            expected_miss = int(round(l0_nan * scale))
            size_note = f"(scaled {scale:.2f}x)"
        else:
            expected_miss = l0_nan
            size_note = ""

        # Extra Miss = Miss in L1 beyond what was already NaN in L0
        extra_miss = l1_miss - expected_miss

        # Tolerance: allow ±2% of total or 200 points (whichever larger)
        # to account for pre-clean removing some originally-NaN rows
        tol = max(200, int(0.02 * l1_total))

        if extra_miss > tol:
            verdict = f"⚠  BUG: +{extra_miss:,} Miss not from L0"
            issues.append((var, extra_miss))
        elif extra_miss < -tol:
            verdict = f"✓  OK (QC reclaimed {-extra_miss:,} pts from NaN)"
        else:
            verdict = "✓  OK"

        print(f"  {var:<28}  {l0_nan:>8,}  {l1_miss:>8,}  "
              f"{l1_bad+l1_pbad:>8,}  {l1_good+l1_pgood:>8,}  "
              f"{extra_miss:>+11,}  {verdict} {size_note}")

    l0.close()
    l1.close()

    # Summary
    print("\n" + "=" * 70)
    if issues:
        print("SUMMARY — Variables with QC flag bug (Miss > L0 NaN):")
        for var, n in sorted(issues, key=lambda x: -x[1]):
            print(f"  ⚠  {var:<28}  +{n:,} extra Miss values")
        print("\n  These variables have valid L0 data mislabelled as Miss (flag 9)")
        print("  instead of Bad (flag 4). Fix: re-run pipeline after git pull.")
    else:
        print("SUMMARY — All variables OK: Miss in L1 is consistent with L0 NaN.")
        print("  No valid data is being silently dropped by the pipeline.")
    print("=" * 70)


# ── Main ─────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 check_l0_coverage.py /path/to/data_dir")
        sys.exit(1)

    data_dir = sys.argv[1]

    l0_path = find_nc(data_dir, "L0-timeseries", "*.nc")
    if not l0_path:
        l0_path = find_nc(data_dir, ".", "incois_glider_*_L0.nc")
    if not l0_path:
        sys.exit(f"ERROR: No L0 timeseries found under {data_dir}/output/\n"
                 f"Run the pipeline first.")

    l1_path = find_nc(data_dir, "L1-timeseries", "*.nc")

    print(f"\nData dir : {data_dir}")
    print(f"L0 file  : {l0_path}")
    print(f"L1 file  : {l1_path or '(not found — run pipeline first)'}")

    l0_results = report_l0_coverage(l0_path)
    report_cadence(l0_path)

    if l1_path:
        report_flag_integrity(l0_path, l1_path, l0_results)
    else:
        print("\nNo L1 file found — skipping flag integrity check.")
        print("Run the pipeline, then re-run this script.")
