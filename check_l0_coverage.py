#!/usr/bin/env python3
"""
check_l0_coverage.py — Verify Miss values in L1 are inherited from L0,
not manufactured by the pipeline.

Usage:
    python3 check_l0_coverage.py /path/to/data_dir

It will auto-find the L0 timeseries and L1 timeseries under that directory.
"""
import sys
import os
import glob
import numpy as np

try:
    import xarray as xr
except ImportError:
    sys.exit("ERROR: xarray not installed. Run: pip install xarray netCDF4")

def find_nc(data_dir, subdir, pattern):
    path = os.path.join(data_dir, "output", subdir)
    if os.path.isdir(path):
        hits = glob.glob(os.path.join(path, pattern))
        if hits:
            return sorted(hits)[-1]
    return None


def step2_l0_coverage(l0_path):
    """Step 2: raw NaN count straight from L0 — before pipeline touches anything."""
    print("\n" + "="*60)
    print("STEP 2 — L0 raw coverage (before any QC)")
    print(f"File: {os.path.basename(l0_path)}")
    print("="*60)
    ds = xr.open_dataset(l0_path)
    check_vars = [
        "temperature", "salinity", "pressure", "depth",
        "chlorophyll", "cdom", "backscatter_700",
        "oxygen_concentration",
    ]
    for var in check_vars:
        if var not in ds:
            print(f"  {var:<25}  not present in L0")
            continue
        n_total = int(ds[var].size)
        n_nan   = int(ds[var].isnull().sum())
        n_valid = n_total - n_nan
        pct     = 100.0 * n_valid / n_total if n_total > 0 else 0.0
        print(f"  {var:<25}  {n_valid:>8,} / {n_total:>8,} present  "
              f"({pct:5.1f}%)   NaN at L0 = {n_nan:,}")
    ds.close()


def step3_sample_cadence(l0_path):
    """Step 3: compare sample cadence of optics vs CTD."""
    print("\n" + "="*60)
    print("STEP 3 — Sample cadence (optics vs CTD)")
    print("="*60)
    ds = xr.open_dataset(l0_path)
    t = ds["time"].values

    all_gaps = np.diff(t).astype("timedelta64[s]").astype(float)
    all_gaps = all_gaps[all_gaps > 0]
    print(f"  All timestamps:  median gap = {np.median(all_gaps):.1f} s")

    for var in ["temperature", "chlorophyll", "cdom", "backscatter_700"]:
        if var not in ds:
            continue
        vals = ds[var].values
        valid_times = t[np.isfinite(vals)]
        if len(valid_times) < 2:
            print(f"  {var:<20}  too few points to compute gap")
            continue
        gaps = np.diff(valid_times).astype("timedelta64[s]").astype(float)
        gaps = gaps[gaps > 0]
        print(f"  {var:<20}  median gap = {np.median(gaps):.1f} s  "
              f"(ratio vs CTD: {np.median(gaps)/max(np.median(all_gaps),1):.1f}x)")
    ds.close()


def step2_l1_vs_l0(l0_path, l1_path):
    """
    Cross-check: compare L0 NaN count with L1 Miss count.
    If L1 Miss >> L0 NaN for the same variable → pipeline is manufacturing Miss.
    If L1 Miss ≈ L0 NaN (after accounting for logged removals) → inherited, not lost.
    """
    print("\n" + "="*60)
    print("CROSS-CHECK — L0 NaN vs L1 Miss count")
    print(f"L0: {os.path.basename(l0_path)}")
    print(f"L1: {os.path.basename(l1_path)}")
    print("="*60)
    l0 = xr.open_dataset(l0_path)
    l1 = xr.open_dataset(l1_path)

    check_vars = [
        "temperature", "salinity", "chlorophyll",
        "cdom", "backscatter_700", "oxygen_concentration",
    ]

    print(f"\n  {'Variable':<25}  {'L0 NaN':>10}  {'L1 Miss (flag9)':>16}  "
          f"{'L1 total':>10}  {'Verdict'}")
    print("  " + "-"*80)

    for var in check_vars:
        if var not in l0:
            continue

        l0_nan = int(l0[var].isnull().sum())
        l0_total = int(l0[var].size)

        if var not in l1:
            print(f"  {var:<25}  {l0_nan:>10,}  {'(not in L1)':>16}  "
                  f"{l0_total:>10,}")
            continue

        l1_total = int(l1[var].size)

        # Miss = flag 9 in QC array, or NaN in the data variable itself
        qc_var = f"{var}_QC"
        if qc_var in l1:
            qc = l1[qc_var].values.astype(float)
            l1_miss  = int(np.sum(qc == 9))
            l1_good  = int(np.sum(qc == 1))
            l1_pgood = int(np.sum(qc == 2))
            l1_bad   = int(np.sum((qc == 3) | (qc == 4)))
        else:
            # No QC array — count NaN in the data variable as proxy for Miss
            l1_miss  = int(l1[var].isnull().sum())
            l1_good  = l1_total - l1_miss
            l1_pgood = 0
            l1_bad   = 0

        # Verdict: are L0 NaN and L1 Miss consistent?
        # Allow up to 10% additional Miss in L1 vs L0 due to QC removals
        delta = l1_miss - l0_nan
        if l1_total != l0_total:
            verdict = f"SIZE MISMATCH (L0={l0_total:,} L1={l1_total:,})"
        elif abs(delta) <= max(500, 0.05 * l0_total):
            verdict = "OK — consistent (inherited from L0)"
        elif delta > 0:
            verdict = f"⚠ PIPELINE ADDED {delta:,} Miss (possible data loss)"
        else:
            verdict = f"L1 has {-delta:,} fewer Miss than L0 (QC recovered?)"

        print(f"  {var:<25}  {l0_nan:>10,}  {l1_miss:>16,}  "
              f"{l1_total:>10,}  {verdict}")
        print(f"  {'':25}  L1 breakdown: good={l1_good:,}  "
              f"prob_good={l1_pgood:,}  bad={l1_bad:,}  miss={l1_miss:,}")

    l0.close()
    l1.close()


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 check_l0_coverage.py /path/to/data_dir")
        sys.exit(1)

    data_dir = sys.argv[1]

    # Auto-find L0 timeseries
    l0_path = find_nc(data_dir, "L0-timeseries", "*.nc")
    if not l0_path:
        # Try old path
        l0_path = find_nc(data_dir, ".", "incois_glider_*_L0.nc")
    if not l0_path:
        sys.exit(f"ERROR: No L0 timeseries found under {data_dir}/output/")

    # Auto-find L1 timeseries
    l1_path = find_nc(data_dir, "L1-timeseries", "*.nc")

    print(f"\nData dir: {data_dir}")
    print(f"L0 path:  {l0_path}")
    print(f"L1 path:  {l1_path or '(not found)'}")

    step2_l0_coverage(l0_path)
    step3_sample_cadence(l0_path)

    if l1_path:
        step2_l1_vs_l0(l0_path, l1_path)
    else:
        print("\nNo L1 timeseries found — skipping cross-check.")
        print("Run the pipeline first, then re-run this script.")
