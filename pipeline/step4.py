    #!/usr/bin/env python3
"""
step4.py - Profile splitting and 2D grid generation.

Exposes two reusable functions:

  split_profiles(nc_path, out_dir, base_name, apply_qc)
    → writes one NetCDF per profile, returns profile count

  make_grid(nc_path, out_dir, grid_filename, apply_qc)
    → writes 2D time×depth grid NetCDF, returns path

Both can be called with apply_qc=False (L0) or apply_qc=True (L1).
When apply_qc=True, only QC flags 1 & 2 (good / probably good) are
included in the depth-bin average.
"""
import os
import sys
import time
import numpy as np
import xarray as xr

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from config import OUTPUT_DIR, GLIDER_ID, DEPTH_BIN

# Variables excluded from gridding (not continuous physical quantities)
# "depth" MUST be excluded — it's used as the grid coordinate and must stay 1D
_SKIP_GRID_VARS = {
    "profile_index", "profile_direction", "distance_over_ground",
    "mission_number", "profile_time_start", "profile_time_end",
    "depth",
    # EGO equivalents (L1 uses uppercase names)
    "PHASE", "PHASE_NUMBER", "DISTANCE_OVER_GROUND",
    "DEPTH", "POSITIONING_METHOD",
    "HEADING", "PITCH", "ROLL",
    "WAYPOINT_LATITUDE", "WAYPOINT_LONGITUDE",
    "POSITION_QC", "TIME_QC",
}


def _get_vars_to_grid(ds):
    """Return all numeric time-dimension variables suitable for gridding."""
    # The time dimension is 'time' in L0 (IOOS) and 'TIME' in L1 (EGO).
    time_dim = "TIME" if "TIME" in ds.dims else "time"
    result = []
    for var in ds.data_vars:
        if var.endswith("_QC"):
            continue
        if var.endswith("_ADJUSTED") or var.endswith("_ADJUSTED_QC"):
            continue
        if var.endswith("_ADJUSTED_ERROR"):
            continue
        if var in _SKIP_GRID_VARS or var.upper() in _SKIP_GRID_VARS:
            continue
        da = ds[var]
        if da.dims == (time_dim,) and np.issubdtype(da.dtype, np.floating):
            result.append(var)
    return result


def _qc_mask(ds, var):
    """Return boolean mask: True where data is good (QC 1 or 2)."""
    qc_var = f"{var}_QC"
    if qc_var in ds:
        qc = ds[qc_var].values.astype(int)
        return (qc == 1) | (qc == 2)
    return np.ones(len(ds.time), dtype=bool)


def _qc_retention_attrs(ds, var):
    """
    Summarise a variable's QC outcome for storage on the gridded variable.

    A grid cell averages many source observations, so a per-cell flag array
    would be meaningless — but the deployment-level retention *is* real
    provenance, and without it the gridded product carries no record that QC
    was applied at all. Returns {} when the source has no flags.
    """
    qc_var = f"{var}_QC"
    if qc_var not in ds:
        return {}
    qc = ds[qc_var].values.astype(int)
    assessed = int(np.sum(qc > 0))
    if assessed == 0:
        return {}
    good    = int(np.sum((qc == 1) | (qc == 2)))
    removed = int(np.sum((qc == 3) | (qc == 4)))
    missing = int(np.sum(qc == 9))
    return {
        "qc_source_variable": qc_var,
        "qc_n_assessed":      str(assessed),
        "qc_pct_good":        f"{100.0 * good / assessed:.2f}",
        "qc_pct_removed":     f"{100.0 * removed / assessed:.2f}",
        "qc_pct_missing":     f"{100.0 * missing / assessed:.2f}",
    }


# ── Profile splitting ────────────────────────────────────────────

def split_profiles(nc_path, out_dir, base_name, apply_qc=False):
    """
    Split a timeseries NetCDF into one file per profile.

    Parameters
    ----------
    nc_path   : path to input timeseries NetCDF
    out_dir   : directory where profile NetCDFs are written
    base_name : filename prefix (e.g. "incois_glider_890_2023_L1")
    apply_qc  : if True, mask bad-flagged values in the output profiles

    Returns
    -------
    Number of profiles written.
    """
    os.makedirs(out_dir, exist_ok=True)
    if not os.path.exists(nc_path) or os.path.getsize(nc_path) < 1000:
        print(f"  ERROR: input file missing or empty: {nc_path}")
        return 0
    ds = xr.open_dataset(nc_path, engine="netcdf4")

    # Support both old internal name and new canonical name
    _pi_var = ("profile_index" if "profile_index" in ds
               else "PHASE_NUMBER" if "PHASE_NUMBER" in ds else None)
    if _pi_var is None:
        print("  WARNING: no profile_index — cannot split profiles")
        ds.close()
        return 0

    pi = ds[_pi_var].values
    unique = np.unique(pi[np.isfinite(pi)])
    n = len(unique)

    if apply_qc:
        # Pre-build QC masks
        qc_vars = [v for v in ds.data_vars if v.endswith("_QC")]
        # Mask bad values in a copy — flag 3 and 4 → NaN
        ds_masked = ds.copy(deep=True)
        for qv in qc_vars:
            base_v = qv.replace("_QC", "")
            # Skip dimension coordinates — they can't be overwritten in-place
            if base_v in ds_masked.dims:
                continue
            # Skip if base_v is a coordinate (index variable)
            if base_v in ds_masked.coords and base_v in ds_masked.dims:
                continue
            if base_v in ds_masked:
                qc = ds_masked[qv].values.astype(int)
                bad = (qc == 3) | (qc == 4)
                vals = ds_masked[base_v].values.copy().astype(float)
                vals[bad] = np.nan
                # Use assign to avoid IndexVariable error
                ds_masked = ds_masked.assign({base_v: (ds_masked[base_v].dims, vals, ds_masked[base_v].attrs)})
    else:
        ds_masked = ds

    # Resolve the time dimension name — support both 'time' and 'TIME'
    _time_dim = "TIME" if "TIME" in ds_masked.dims else "time"

    for p_num in unique:
        mask = (ds_masked[_pi_var].values == p_num)
        prof = ds_masked.isel({_time_dim: mask})
        prof.attrs["profile_id"] = int(p_num)
        _pd_var = ("profile_direction" if "profile_direction" in prof
                   else "PHASE" if "PHASE" in prof else None)
        if _pd_var:
            d = float(np.nanmean(prof[_pd_var].values))
            prof.attrs["direction"] = ("climb" if d > 0
                                       else "dive" if d < 0 else "unknown")
        out = os.path.join(out_dir, f"{base_name}_profile_{int(p_num):04d}.nc")
        prof.to_netcdf(out, mode="w")

    ds.close()
    if apply_qc:
        ds_masked.close()
    print(f"  Split {n} profiles → {out_dir}")
    return n


# ── Grid generation ─────────────────────────────────────────────

def _interp_profile_to_grid(d_arr, v_arr, depth_centers,
                            min_points=4, min_depth_coverage_frac=0.15):
    """
    Interpolate a single profile onto the regular depth grid.

    Uses linear interpolation between measurements — this is correct because
    glider data is essentially a continuous profile sampled every few meters.
    Only interpolates WITHIN the measured depth range (no extrapolation).

    Bug 2 fix: profiles with too few points or insufficient vertical coverage
    are skipped (return all-NaN) rather than interpolating across the full
    depth range, which creates thin jagged vine artefacts in section plots.

    min_points            : minimum number of valid measurement points required
                            to attempt interpolation (default 4)
    min_depth_coverage_frac : minimum fraction of the grid depth range that the
                            profile must span to be interpolated (default 0.15,
                            i.e. must cover at least 15% of the grid depth range)

    Returns array of length len(depth_centers) with NaN outside data range.
    """
    from scipy.interpolate import interp1d

    grid_depth_range = float(depth_centers[-1] - depth_centers[0]) if len(depth_centers) > 1 else 1.0

    # Sort by depth (profiles can be ascending or descending)
    order = np.argsort(d_arr)
    d_sorted = d_arr[order]
    v_sorted = v_arr[order]

    # Remove duplicate depths (average values at same depth)
    _, unique_idx = np.unique(d_sorted, return_index=True)
    if len(unique_idx) < len(d_sorted):
        # There are duplicates — use binned mean at each unique depth
        d_unique = d_sorted[unique_idx]
        v_unique = np.empty(len(d_unique))
        for j, idx in enumerate(unique_idx):
            next_idx = unique_idx[j + 1] if j + 1 < len(unique_idx) else len(d_sorted)
            v_unique[j] = np.nanmean(v_sorted[idx:next_idx])
        d_sorted = d_unique
        v_sorted = v_unique

    # --- Bug 2 fix: sparse/shallow profile guard ---
    n_pts = len(d_sorted)
    if n_pts < 2:
        result = np.full(len(depth_centers), np.nan)
        if n_pts == 1:
            # Place single point in nearest bin
            idx = np.argmin(np.abs(depth_centers - d_sorted[0]))
            result[idx] = v_sorted[0]
        return result

    if n_pts < min_points:
        # Too few points to produce a meaningful interpolation
        result = np.full(len(depth_centers), np.nan)
        for i in range(n_pts):
            idx = np.argmin(np.abs(depth_centers - d_sorted[i]))
            result[idx] = v_sorted[i]
        return result

    profile_depth_span = float(d_sorted[-1] - d_sorted[0])
    if grid_depth_range > 0 and (profile_depth_span / grid_depth_range) < min_depth_coverage_frac:
        # Profile covers less than min_depth_coverage_frac of the grid — don't
        # interpolate, just bin-place the raw points so they show as dots, not
        # a smeared column across the full grid depth.
        result = np.full(len(depth_centers), np.nan)
        for i in range(n_pts):
            idx = np.argmin(np.abs(depth_centers - d_sorted[i]))
            result[idx] = v_sorted[i]
        return result

    # Interpolate — only within the measured depth range (bounds_error=False
    # with fill_value=nan means no extrapolation beyond data)
    f = interp1d(d_sorted, v_sorted, kind='linear',
                 bounds_error=False, fill_value=np.nan)
    return f(depth_centers)


def make_grid(nc_path, out_dir, grid_filename, apply_qc=False):
    """
    Interpolate a timeseries NetCDF into a 2D time x depth grid.

    Each profile is linearly interpolated onto a regular 1m depth grid.
    This matches what pyglider does — glider measurements are continuous
    profiles sampled every few meters, so linear interpolation between
    points is physically correct.

    Parameters
    ----------
    nc_path        : path to input timeseries NetCDF
    out_dir        : directory where the grid is written
    grid_filename  : output filename (e.g. "incois_glider_890_2023_L1_grid.nc")
    apply_qc       : if True, only flag 1/2 values go into the grid

    Returns
    -------
    Path to the written grid NetCDF.
    """
    os.makedirs(out_dir, exist_ok=True)
    if not os.path.exists(nc_path) or os.path.getsize(nc_path) < 1000:
        print(f"  ERROR: input file missing or empty: {nc_path}")
        return None
    ds = xr.open_dataset(nc_path, engine="netcdf4")

    # Support both old internal name and new canonical name
    _pi_var = ("profile_index" if "profile_index" in ds
               else "PHASE_NUMBER" if "PHASE_NUMBER" in ds else None)
    if _pi_var is None:
        print(f"  WARNING: no profile_index in {nc_path} — cannot grid")
        ds.close()
        return None

    pi = ds[_pi_var].values
    unique = np.unique(pi[np.isfinite(pi)])
    n = len(unique)

    vars_to_grid = _get_vars_to_grid(ds)

    # Support DEPTH or depth
    _depth_var = "depth" if "depth" in ds else "DEPTH" if "DEPTH" in ds else None
    if _depth_var is None:
        print(f"  WARNING: no depth variable in {nc_path} — cannot grid")
        ds.close()
        return None
    max_depth = float(np.nanmax(ds[_depth_var].values))
    if np.isnan(max_depth) or max_depth < 10:
        max_depth = 1000.0
    depth_centers = np.arange(DEPTH_BIN / 2.0, max_depth + DEPTH_BIN / 2.0, DEPTH_BIN)
    label = "QC flags 1&2" if apply_qc else "all finite values"
    print(f"  Grid: {n} profiles x {len(depth_centers)} depth bins "
          f"(0-{max_depth:.0f} m, dz={DEPTH_BIN}m, {label})")

    # QC masks (built once over full dataset)
    qc_masks = {}
    if apply_qc:
        qc_masks = {var: _qc_mask(ds, var) for var in vars_to_grid}

    gridded  = {var: [] for var in vars_to_grid}
    p_times  = []

    # Resolve time dimension name
    _time_dim = "TIME" if "TIME" in ds.dims else "time"
    _time_coord = "time" if "time" in ds.coords else "TIME"

    for i, p_num in enumerate(unique):
        mask = (pi == p_num)
        t_arr = ds[_time_coord].values[mask].astype("datetime64[s]").astype(float)
        p_times.append(float(np.nanmean(t_arr)) if len(t_arr) > 0 else np.nan)

        d_arr = ds[_depth_var].values[mask]
        prof_idx = np.where(mask)[0]

        for var in vars_to_grid:
            if var not in ds:
                gridded[var].append(np.full(len(depth_centers), np.nan))
                continue
            v_arr = ds[var].values[mask]
            # Skip if not 1D float (e.g. string, structured, or wrong shape)
            if v_arr.ndim != 1 or not np.issubdtype(v_arr.dtype, np.floating):
                gridded[var].append(np.full(len(depth_centers), np.nan))
                continue
            if apply_qc and var in qc_masks:
                qc_ok = qc_masks[var][prof_idx]
            else:
                qc_ok = np.ones(len(v_arr), dtype=bool)
            good = np.isfinite(d_arr) & np.isfinite(v_arr) & qc_ok
            if good.sum() >= 2:
                # Interpolate profile onto regular depth grid
                gridded[var].append(
                    _interp_profile_to_grid(d_arr[good], v_arr[good],
                                            depth_centers))
            elif good.sum() == 1:
                row = np.full(len(depth_centers), np.nan)
                idx = np.argmin(np.abs(depth_centers - d_arr[good][0]))
                row[idx] = v_arr[good][0]
                gridded[var].append(row)
            else:
                gridded[var].append(np.full(len(depth_centers), np.nan))

        if (i + 1) % 200 == 0:
            print(f"    ... {i+1}/{n} profiles")

    # Assemble grid dataset
    grid_times = np.array(p_times).astype("datetime64[s]")
    gds = xr.Dataset(coords={"time": grid_times, "depth": depth_centers})

    for var in vars_to_grid:
        if var in ds:
            arr = np.vstack(gridded[var])
            attrs = ds[var].attrs.copy()
            if apply_qc:
                # Carry the QC outcome forward as provenance — the per-cell
                # flags cannot survive binning, but the retention figures are
                # what the plots and reports need to state what was filtered.
                attrs.update(_qc_retention_attrs(ds, var))
            gds[var] = xr.DataArray(arr, dims=["time", "depth"], attrs=attrs)

    # Carry all global attributes from source
    gds.attrs = ds.attrs.copy()
    if apply_qc:
        gds.attrs["processing_level"] = (
            ds.attrs.get("processing_level", "") +
            " | 2D Gridded (QC flags 1 & 2 only)")
        gds.attrs["qc_applied"] = "Only ARGO QC flags 1 (good) and 2 (probably good) included in depth bins"
    else:
        gds.attrs["processing_level"] = (
            ds.attrs.get("processing_level", "") +
            " | 2D Gridded (all finite values, no QC)")
    gds.attrs["depth_bin_m"] = str(DEPTH_BIN)
    gds.attrs["n_profiles"]  = str(n)

    out_path = os.path.join(out_dir, grid_filename)
    gds.to_netcdf(out_path, mode="w")
    print(f"  Grid saved: {out_path}")

    ds.close()
    return out_path


# ── Standalone entry point ──────────────────────────────────────

def main(argv=None):
    """Split profiles and build the grid for one timeseries NetCDF."""
    import argparse
    p = argparse.ArgumentParser(
        description="Split a timeseries NetCDF into profiles and grid it.")
    p.add_argument("nc_path", help="input timeseries NetCDF (L0 or L1)")
    p.add_argument("--out-dir", required=True,
                   help="directory for the profiles/ and grid outputs")
    p.add_argument("--base-name", default=None,
                   help="filename prefix (default: derived from nc_path)")
    p.add_argument("--apply-qc", action="store_true",
                   help="keep only ARGO QC flags 1 and 2 (use for L1)")
    args = p.parse_args(argv)

    if not os.path.exists(args.nc_path):
        print(f"ERROR: file not found: {args.nc_path}")
        return 1

    base = args.base_name or os.path.splitext(
        os.path.basename(args.nc_path))[0]

    t0 = time.time()
    split_profiles(args.nc_path, os.path.join(args.out_dir, "profiles"),
                   base, apply_qc=args.apply_qc)
    make_grid(args.nc_path, os.path.join(args.out_dir, "gridfiles"),
              f"{base}_grid.nc", apply_qc=args.apply_qc)
    print(f"\n  COMPLETE in {time.time() - t0:.1f}s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
