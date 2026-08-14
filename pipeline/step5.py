#!/usr/bin/env python3
"""
step5.py - Generates TWO time-depth plots per deployment:

  1. L0_gridplot  — raw data from L0 NetCDF, all finite values, no QC masking.
                    Shows what came off the glider before any processing.

  2. L1_gridplot  — QC-filtered data from L1 NetCDF (grid), only ARGO flag 1
                    (good) and flag 2 (probably good) values included.
                    This is the science-ready product.

Large time gaps (> GAP_THRESHOLD_HOURS) are masked in both plots so
pcolormesh does not stretch a cell across a multi-week blank period.
"""
import os
import sys
import numpy as np
import xarray as xr
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.dates as mdates

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from config import OUTPUT_DIR, GLIDER_ID, PLOT_DEPTH_MAX, DEPTH_BIN

# Time bin width for gridplots (hours). Imported separately with fallback.
try:
    from config import GRID_TIME_BIN_H
except ImportError:
    GRID_TIME_BIN_H = 3.0

# Gaps longer than this (hours) are masked in pcolormesh
GAP_THRESHOLD_HOURS = 48

# Preferred variables to plot, in priority order.
# For each "slot", we try names in order until one is found in the dataset.
PLOT_SLOTS = [
    # (slot_label, [candidate_var_names], cmap)
    ("temperature",  ["temperature", "potential_temperature", "sci_water_temp"], "RdYlBu_r"),
    ("salinity",     ["salinity", "practical_salinity"], "viridis"),
    ("oxygen",       ["oxygen_concentration", "dissolved_oxygen", "sci_oxy4_oxygen"], "viridis"),
    ("chlorophyll",  ["chlorophyll", "chlorophyll_flntu", "sci_flbbcd_chlor_units"], "viridis"),
    ("cdom",         ["cdom", "sci_flbbcd_cdom_units"], "RdBu_r"),
]

VAR_LABELS = {
    "potential_temperature": "Potential Temperature [°C]",
    "temperature":           "Temperature [°C]",
    "salinity":              "Salinity [PSU]",
    "practical_salinity":    "Salinity [PSU]",
    "oxygen_concentration":  "Oxygen [µmol/L]",
    "dissolved_oxygen":      "Oxygen [µmol/L]",
    "sci_oxy4_oxygen":       "Oxygen [µmol/L]",
    "chlorophyll":           "Chlorophyll [mg/m³]",
    "chlorophyll_flntu":     "Chlorophyll FLNTU [mg/m³]",
    "sci_flbbcd_chlor_units": "Chlorophyll [mg/m³]",
    "cdom":                  "CDOM [ppb]",
    "sci_flbbcd_cdom_units": "CDOM [ppb]",
    "backscatter_700":       "Backscatter 700nm [m⁻¹]",
}

# Physical plausibility ranges for plot variables.
# Values outside these are sentinel/corrupted — NaN them before colorscaling.
# These are wider than QC ranges to avoid clipping real extremes while still
# catching -9999 fill values and wildly wrong sensor outputs.
_PLOT_PHYS_RANGE = {
    "temperature":           (-3.0,   40.0),
    "potential_temperature": (-3.0,   40.0),
    "sci_water_temp":        (-3.0,   40.0),
    "salinity":              ( 0.0,   45.0),
    "practical_salinity":    ( 0.0,   45.0),
    "oxygen_concentration":  (-5.0,  700.0),
    "dissolved_oxygen":      (-5.0,  700.0),
    "sci_oxy4_oxygen":       (-5.0,  700.0),
    "chlorophyll":           (-1.0,  200.0),
    "chlorophyll_flntu":     (-1.0,  200.0),
    "sci_flbbcd_chlor_units":(-1.0,  200.0),
    "cdom":                  (-1.0,  500.0),
    "sci_flbbcd_cdom_units": (-1.0,  500.0),
    "backscatter_700":       (-0.01,   1.0),
}


def _slot_lookup(name, table, default=None):
    """
    Look `name` up in a variable-keyed table, tolerating slot labels.

    Panels are titled by *slot* label ("oxygen") while the lookup tables are
    keyed by *variable* name ("oxygen_concentration"). A direct .get() on the
    slot label therefore missed: the oxygen panel silently fell back to the
    (-inf, inf) physical range, so -9999 fill values reached the colour scale,
    and its colourbar read a bare "oxygen" instead of "Oxygen [µmol/L]".

    Falls back through every candidate name registered for the slot.
    """
    if name in table:
        return table[name]
    for slot_label, candidates, _cmap in PLOT_SLOTS:
        if name == slot_label or name in candidates:
            for cand in candidates:
                if cand in table:
                    return table[cand]
            break
    return default


def _apply_phys_range(V, var_name):
    """
    NaN out values outside physical plausibility range before colorscaling.
    Operates on a copy — never mutates the input array.
    Returns the cleaned copy and the number of cells nulled.
    """
    Vc = V.copy()
    lo, hi = _slot_lookup(var_name, _PLOT_PHYS_RANGE, (-np.inf, np.inf))
    bad = np.isfinite(Vc) & ((Vc < lo) | (Vc > hi))
    n_bad = int(np.sum(bad))
    if n_bad > 0:
        Vc[bad] = np.nan
    return Vc, n_bad


def _detect_plot_vars(ds):
    """
    Auto-detect which variables to plot from what's actually in the dataset.
    Returns list of (slot_label, actual_var_name, cmap) for variables that exist
    and have finite data.
    """
    result = []
    for slot_label, candidates, cmap in PLOT_SLOTS:
        for var in candidates:
            if var in ds:
                # Check it actually has some finite data
                v = ds[var].values
                if np.sum(np.isfinite(v)) > 10:
                    result.append((slot_label, var, cmap))
                    break
    return result


# Backward-compat: VARS_TO_PLOT used by grid functions (first candidate per slot)
VARS_TO_PLOT = [candidates[0] for _, candidates, _ in PLOT_SLOTS]


def _resolve_var(ds, var_name):
    """Resolve a variable name using PLOT_SLOTS candidates."""
    if var_name in ds:
        return var_name
    # Find this var in PLOT_SLOTS and try its alternatives
    for _, candidates, _ in PLOT_SLOTS:
        if var_name in candidates:
            for alt in candidates:
                if alt in ds:
                    return alt
            break
    return None


# ----------------------------------------------------------------
# Shared helpers
# ----------------------------------------------------------------


def _pcolormesh_edges(centers):
    """Compute cell edges from center values (handles datetime64)."""
    c = np.asarray(centers)
    if len(c) < 2:
        # Can't compute edges from a single point — create a tiny range
        if np.issubdtype(c.dtype, np.datetime64):
            c_num = mdates.date2num(c)
            return np.array([c_num[0] - 0.5, c_num[0] + 0.5])
        return np.array([c[0] - 0.5, c[0] + 0.5])
    if np.issubdtype(c.dtype, np.datetime64):
        c_num = mdates.date2num(c)
        edges = np.empty(len(c) + 1)
        edges[1:-1] = (c_num[1:] + c_num[:-1]) / 2.0
        edges[0]    = c_num[0]  - (c_num[1]  - c_num[0])  / 2.0
        edges[-1]   = c_num[-1] + (c_num[-1] - c_num[-2]) / 2.0
        return edges
    edges = np.empty(len(c) + 1)
    edges[1:-1] = (c[1:] + c[:-1]) / 2.0
    edges[0]    = c[0]  - (c[1]  - c[0])  / 2.0
    edges[-1]   = c[-1] + (c[-1] - c[-2]) / 2.0
    return edges


def _qc_retention(ds, var_name):
    """
    Return (pct_good, pct_removed) for a variable, or None if unknown.

    Two sources, because the L1 plot is fed from either product:
      * timeseries — the <var>_QC flag array is present, count it directly;
      * grid       — binning destroys per-cell flags, so step4.make_grid stores
                     the retention figures as variable attributes instead.
        Reading only the flag array meant the annotation never rendered on the
        grid path, which is the default path.
    """
    qc_var = f"{var_name}_QC"
    if qc_var in ds:
        qc = ds[qc_var].values.astype(float)
        total = float(np.sum(np.isfinite(qc) & (qc > 0)))
        if total > 0:
            good = float(np.sum((qc == 1) | (qc == 2)))
            gone = float(np.sum((qc == 3) | (qc == 4) | (qc == 9)))
            return 100 * good / total, 100 * gone / total

    if var_name in ds:
        attrs = ds[var_name].attrs
        if "qc_pct_good" in attrs:
            try:
                good = float(attrs["qc_pct_good"])
                gone = (float(attrs.get("qc_pct_removed", 0.0))
                        + float(attrs.get("qc_pct_missing", 0.0)))
                return good, gone
            except (TypeError, ValueError):
                pass
    return None


def _add_qc_annotation(ax, ds, var_name, slot_label):
    """Add a QC retention annotation to a plot panel."""
    retention = _qc_retention(ds, var_name)
    if retention is None:
        return
    pct_good, pct_removed = retention

    text = f"QC: {pct_good:.1f}% good"
    if pct_removed > 0.1:
        text += f" | {pct_removed:.1f}% removed"
    ax.text(0.99, 0.97, text, transform=ax.transAxes,
            fontsize=9, ha='right', va='top',
            bbox=dict(boxstyle='round,pad=0.3', facecolor='white',
                      alpha=0.8, edgecolor='gray'))


def _mask_time_gaps(data, time_values, gap_hours=GAP_THRESHOLD_HOURS):
    """NaN out the first profile after each large time gap."""
    if len(time_values) < 2:
        return data
    t_h = time_values.astype("datetime64[h]").astype(float)
    dt  = np.diff(t_h)
    gap_starts = np.where(dt > gap_hours)[0] + 1
    if len(gap_starts) == 0:
        return data
    masked = data.copy()
    for idx in gap_starts:
        masked[idx, :] = np.nan
    return masked


def _report_gaps(t_vals):
    if len(t_vals) < 2:
        return
    dt_h = np.diff(t_vals.astype("datetime64[h]").astype(float))
    big  = np.where(dt_h > GAP_THRESHOLD_HOURS)[0]
    if len(big):
        print(f"  Time gaps > {GAP_THRESHOLD_HOURS}h: {len(big)}")
        for gi in big:
            print(f"    {str(t_vals[gi])[:19]} -> {str(t_vals[gi+1])[:19]}"
                  f"  ({dt_h[gi]:.0f}h)")


def _draw_pcolormesh(ax, t_vals, depth_vals, V, cmap, label, max_depth):
    """Draw one pcolormesh panel. Returns True if data was plotted."""
    # Guard: V must be exactly 2D (n_time × n_depth)
    if V.ndim != 2 or V.shape != (len(t_vals), len(depth_vals)):
        ax.set_title(f"{label} (not 2D)", fontsize=13)
        ax.set_ylim(max_depth, 0)
        ax.set_ylabel("Depth (m)", fontsize=11)
        return False

    # Guard: need at least 2 time points for pcolormesh
    if len(t_vals) < 2:
        ax.set_title(f"{label} (insufficient time points: {len(t_vals)})", fontsize=13)
        ax.set_ylim(max_depth, 0)
        ax.set_ylabel("Depth (m)", fontsize=11)
        return False

    depth_mask = depth_vals <= max_depth
    V_trim = V[:, depth_mask].copy()
    d_trim = depth_vals[depth_mask]

    # --- Bug 3 fix: clamp physically impossible values before percentile ---
    # Resolve the actual variable name from the slot label so we can look up
    # the physical range. Fall back to the label itself if not in the table.
    var_key = label  # label is the slot label, also the actual var name in most paths
    V_trim, n_phys_bad = _apply_phys_range(V_trim, var_key)
    if n_phys_bad > 0:
        print(f"    {label}: nulled {n_phys_bad} physically-impossible values before colorscale")

    # Suppress isolated depth artefacts: NaN out depth bins where fewer than
    # 10% of profiles have data (removes interpolation artefacts and pressure
    # spike horizontal lines)
    n_profiles = V_trim.shape[0]
    if n_profiles > 5:
        col_counts = np.sum(np.isfinite(V_trim), axis=0).astype(float)
        sparse_bins = col_counts < max(n_profiles * 0.10, 3)
        V_trim[:, sparse_bins] = np.nan

    V_trim = _mask_time_gaps(V_trim, t_vals, GAP_THRESHOLD_HOURS)

    valid = np.isfinite(V_trim)
    if np.all(~valid):
        ax.set_title(f"{label} (ALL NaN)", fontsize=13)
        ax.set_ylim(max_depth, 0)
        ax.set_ylabel("Depth (m)", fontsize=11)
        return False

    n_valid = int(np.sum(valid))
    print(f"    {label}: {n_valid}/{V_trim.size} filled cells")

    v_min = np.nanpercentile(V_trim[valid], 2)
    v_max = np.nanpercentile(V_trim[valid], 98)

    t_edges = _pcolormesh_edges(t_vals)
    d_edges = _pcolormesh_edges(d_trim)
        # Ensure NaN/missing/gaps render as white, not black
    cmap_obj = plt.get_cmap(cmap).copy()
    cmap_obj.set_bad(color="white")
    cmap_obj.set_under(color="white")
    cmap_obj.set_over(color="white")


    mesh = ax.pcolormesh(t_edges, d_edges, V_trim.T,
                         cmap=cmap_obj, vmin=v_min, vmax=v_max, shading="flat")

    # Add contour lines for structure (matching team's plot style)
    try:
        import numpy.ma as ma
        V_ma = ma.masked_invalid(V_trim)
        X, Y = np.meshgrid(mdates.date2num(t_vals), d_trim)
        n_contours = 10
        levels = np.linspace(v_min, v_max, n_contours)
        ax.contour(X, Y, V_ma.T, levels=levels,
                   colors="k", linewidths=0.4, alpha=0.5)
    except Exception:
        pass

    ax.set_ylim(max_depth, 0)
    ax.set_title(label, fontsize=13, fontweight="bold")
    ax.set_ylabel("Depth (m)", fontsize=11)
    cbar = plt.colorbar(mesh, ax=ax, pad=0.02)
    cbar.set_label(_slot_lookup(label, VAR_LABELS, label), fontsize=11)
    return True


def _finalise_fig(fig, axes, plot_path):
    axes[-1].xaxis.set_major_locator(mdates.AutoDateLocator())
    axes[-1].xaxis.set_major_formatter(mdates.DateFormatter("%Y-%m-%d"))
    plt.xticks(rotation=45, fontsize=11)
    plt.tight_layout()
    plt.savefig(plot_path, dpi=150, bbox_inches="tight")
    print(f"  Plot saved: {plot_path}")
    plt.close(fig)


# ----------------------------------------------------------------
# L0 plot  — raw data, no QC masking
# ----------------------------------------------------------------

def _make_l1_grid_from_ts(l1_ds, depth_bin=None, time_bin_h=None):
    """
    Build a 2D grid from L1 timeseries using UNIFORM TIME BINS.
    Each grid column covers a fixed time interval (default 3h), aggregating
    all observations in that window regardless of profile boundaries.
    This eliminates the picket-fence pattern from irregular profile spacing.
    Returns (grid_data dict, time_arr, depth_centers) or (None, None, None).
    """
    if depth_bin is None:
        depth_bin = DEPTH_BIN
    if time_bin_h is None:
        time_bin_h = GRID_TIME_BIN_H

    depth_raw = l1_ds["depth"].values if "depth" in l1_ds else None
    if depth_raw is None:
        return None, None, None

    finite_depths = depth_raw[np.isfinite(depth_raw)]
    if len(finite_depths) == 0:
        return None, None, None
    max_depth = float(np.percentile(finite_depths, 99.5))
    if max_depth < 10:
        max_depth = PLOT_DEPTH_MAX or 1000.0
    depth_centers = np.arange(depth_bin / 2.0, max_depth + depth_bin / 2.0, depth_bin)
    n_depth = len(depth_centers)

    # Build uniform time axis
    time_vals = l1_ds.time.values
    t_float = time_vals.astype("datetime64[s]").astype(float)
    finite_mask = np.isfinite(t_float)
    if np.sum(finite_mask) == 0:
        return None, None, None
    t_start = time_vals[finite_mask][0]
    t_end = time_vals[finite_mask][-1]

    # Adaptive time bin: ensure at least 5 time columns
    duration_s = (t_end - t_start) / np.timedelta64(1, 's')
    min_bins = 5
    max_bin_s = max(duration_s / min_bins, 60)  # at least 60s per bin
    bin_s = min(time_bin_h * 3600, max_bin_s)
    time_bin_td = np.timedelta64(int(bin_s), 's')

    time_edges = np.arange(t_start, t_end + time_bin_td, time_bin_td)
    time_centers = time_edges[:-1] + time_bin_td // 2
    n_time = len(time_centers)

    if n_time == 0:
        return None, None, None

    # Digitize time and depth for fast bin-aggregation
    t_edge_float = time_edges.astype("datetime64[s]").astype(float)
    t_bin_idx = np.clip(np.digitize(t_float, t_edge_float) - 1, 0, n_time - 1)

    d_edge = np.arange(0, max_depth + depth_bin, depth_bin)
    d_bin_idx = np.clip(np.digitize(depth_raw, d_edge) - 1, 0, n_depth - 1)

    grid_2d = {}
    for var in VARS_TO_PLOT:
        actual_var = _resolve_var(l1_ds, var)
        if actual_var is None:
            continue
        v_arr = l1_ds[actual_var].values

        # Apply QC mask
        qc_var = f"{actual_var}_QC"
        if qc_var not in l1_ds:
            # Try the canonical name QC var too
            qc_var = f"{var}_QC"
        if qc_var in l1_ds:
            qc = l1_ds[qc_var].values.astype(float)
            qc_ok = (qc == 1) | (qc == 2)
        else:
            qc_ok = np.ones(len(v_arr), dtype=bool)

        valid = np.isfinite(depth_raw) & np.isfinite(v_arr) & qc_ok
        if np.sum(valid) == 0:
            continue

        # Aggregate into grid
        sums = np.zeros((n_time, n_depth))
        counts = np.zeros((n_time, n_depth))
        vi = np.where(valid)[0]
        np.add.at(sums, (t_bin_idx[vi], d_bin_idx[vi]), v_arr[vi])
        np.add.at(counts, (t_bin_idx[vi], d_bin_idx[vi]), 1)
        # Store under actual var name
        grid_2d[actual_var] = np.where(counts > 0, sums / counts, np.nan)

    return grid_2d, time_centers, depth_centers


def _make_l0_grid(l0_ds, depth_bin=None, time_bin_h=None):
    """
    Build a 2D grid from L0 timeseries using UNIFORM TIME BINS.
    All finite values included, no QC masking.
    Returns (grid_data dict, time_arr, depth_centers).
    """
    if depth_bin is None:
        depth_bin = DEPTH_BIN
    if time_bin_h is None:
        time_bin_h = GRID_TIME_BIN_H

    depth_raw = l0_ds["depth"].values if "depth" in l0_ds else None
    if depth_raw is None and "pressure" in l0_ds:
        # Fallback: approximate depth from pressure (1 dbar ≈ 1 m)
        depth_raw = l0_ds["pressure"].values
    if depth_raw is None:
        print("  WARNING: no 'depth' or 'pressure' variable in L0")
        return None, None, None

    finite_depths = depth_raw[np.isfinite(depth_raw)]
    if len(finite_depths) == 0:
        return None, None, None
    max_depth = float(np.percentile(finite_depths, 99.5))
    if max_depth < 10:
        max_depth = PLOT_DEPTH_MAX or 1000.0
    depth_centers = np.arange(depth_bin / 2.0, max_depth + depth_bin / 2.0, depth_bin)
    n_depth = len(depth_centers)

    # Build uniform time axis
    time_vals = l0_ds.time.values
    t_float = time_vals.astype("datetime64[s]").astype(float)
    finite_mask = np.isfinite(t_float)
    if np.sum(finite_mask) == 0:
        return None, None, None
    t_start = time_vals[finite_mask][0]
    t_end = time_vals[finite_mask][-1]

    # Adaptive time bin: ensure at least 5 time columns
    duration_s = (t_end - t_start) / np.timedelta64(1, 's')
    min_bins = 5
    max_bin_s = max(duration_s / min_bins, 60)  # at least 60s per bin
    bin_s = min(time_bin_h * 3600, max_bin_s)
    time_bin_td = np.timedelta64(int(bin_s), 's')

    time_edges = np.arange(t_start, t_end + time_bin_td, time_bin_td)
    time_centers = time_edges[:-1] + time_bin_td // 2
    n_time = len(time_centers)

    if n_time == 0:
        return None, None, None

    # Digitize time and depth
    t_edge_float = time_edges.astype("datetime64[s]").astype(float)
    t_bin_idx = np.clip(np.digitize(t_float, t_edge_float) - 1, 0, n_time - 1)

    d_edge = np.arange(0, max_depth + depth_bin, depth_bin)
    d_bin_idx = np.clip(np.digitize(depth_raw, d_edge) - 1, 0, n_depth - 1)

    grid_2d = {}
    for var in VARS_TO_PLOT:
        actual_var = _resolve_var(l0_ds, var)
        if actual_var is None:
            continue
        v_arr = l0_ds[actual_var].values
        valid = np.isfinite(depth_raw) & np.isfinite(v_arr)
        if np.sum(valid) == 0:
            continue

        sums = np.zeros((n_time, n_depth))
        counts = np.zeros((n_time, n_depth))
        vi = np.where(valid)[0]
        np.add.at(sums, (t_bin_idx[vi], d_bin_idx[vi]), v_arr[vi])
        np.add.at(counts, (t_bin_idx[vi], d_bin_idx[vi]), 1)
        # Store under actual var name so plot functions can find it
        grid_2d[actual_var] = np.where(counts > 0, sums / counts, np.nan)
        n_filled = int(np.sum(counts > 0))
        print(f"    {actual_var}: {n_filled}/{n_time*n_depth} grid cells filled")

    return grid_2d, time_centers, depth_centers


def plot_l0(l0_path, plot_path=None, l0_grid_path=None):
    """Generate the L0 raw gridplot. Uses pre-built L0 grid if available."""
    print("  Generating L0 plot (raw, no QC)...")

    if plot_path is None:
        plots_dir = os.path.join(OUTPUT_DIR, "plots")
        os.makedirs(plots_dir, exist_ok=True)
        plot_path = os.path.join(plots_dir,
                                 f"incois_glider_{GLIDER_ID}_L0_gridplot.png")

    # Try to use pre-built L0 grid (from step4/step1c) — much more reliable
    if l0_grid_path is None:
        candidates = [
            os.path.join(OUTPUT_DIR, "L0-gridfiles",
                         f"incois_glider_{GLIDER_ID}_L0_grid.nc"),
            os.path.join(OUTPUT_DIR, "gridfiles",
                         f"incois_glider_{GLIDER_ID}_L0_grid.nc"),
        ]
        for c in candidates:
            if os.path.exists(c):
                l0_grid_path = c
                break

    if l0_grid_path and os.path.exists(l0_grid_path):
        print(f"  Using pre-built L0 grid: {l0_grid_path}")
        ds = xr.open_dataset(l0_grid_path)
        t_arr = ds.time.values
        depth_centers = ds.depth.values

        _report_gaps(t_arr)

        # Determine max plot depth and build grid_2d from detected vars
        n_time = len(t_arr)
        detected = _detect_plot_vars(ds)
        if not detected:
            print("  WARNING: no plottable variables found in L0 grid")
            ds.close()
            return None

        max_depth = 0.0
        grid_2d = {}
        plot_vars = []  # (label, var_name, cmap)
        for slot_label, actual_var, cmap in detected:
            V = ds[actual_var].values
            if V.ndim == 2 and V.shape == (n_time, len(depth_centers)):
                grid_2d[slot_label] = V
                plot_vars.append((slot_label, actual_var, cmap))
                col_counts = np.sum(np.isfinite(V), axis=0).astype(float)
                frac = col_counts / max(n_time, 1)
                bins_ok = np.where(frac >= 0.10)[0]
                if len(bins_ok) > 0:
                    max_depth = max(max_depth, float(depth_centers[bins_ok[-1]]))

        if max_depth < 10:
            max_depth = float(depth_centers.max()) if len(depth_centers) > 0 else 1000.0

        print(f"  L0 plot depth: {max_depth:.0f} m")

        if len(t_arr) < 2 or not plot_vars:
            print("  WARNING: L0 grid has insufficient data — skipping plot")
            ds.close()
            return None

        n_panels = len(plot_vars)
        fig, axes = plt.subplots(n_panels, 1,
                                 figsize=(14, 4 * n_panels), sharex=True)
        if n_panels == 1:
            axes = [axes]
        fig.suptitle(f"Glider {GLIDER_ID}  —  L0 Raw Data (no QC)",
                     fontsize=14, fontweight="bold", y=1.01)

        for i, (slot_label, actual_var, cmap) in enumerate(plot_vars):
            ax = axes[i]
            _draw_pcolormesh(ax, t_arr, depth_centers, grid_2d[slot_label],
                             cmap, slot_label, max_depth)

        _finalise_fig(fig, axes, plot_path)
        ds.close()
        return plot_path

    # Fallback: build grid from L0 timeseries
    if not os.path.exists(l0_path):
        print(f"  WARNING: L0 file not found: {l0_path}")
        return None

    ds = xr.open_dataset(l0_path)

    grid_2d, t_arr, depth_centers = _make_l0_grid(ds)
    if grid_2d is None:
        print("  WARNING: could not build L0 grid (no profile_index or depth)")
        ds.close()
        return None

    _report_gaps(t_arr)

    # Determine max plot depth from whatever variables were gridded
    n_profiles = len(t_arr)
    max_depth = 0.0
    plot_vars = []
    for slot_label, candidates, cmap in PLOT_SLOTS:
        # Check which var name ended up in grid_2d (grid function uses VARS_TO_PLOT keys)
        found_key = None
        for cand in candidates:
            if cand in grid_2d:
                found_key = cand
                break
        # Also check the slot's primary name (VARS_TO_PLOT[i])
        primary = candidates[0]
        if primary in grid_2d:
            found_key = primary
        if found_key is None:
            continue
        v = grid_2d[found_key]
        col_counts = np.sum(np.isfinite(v), axis=0).astype(float)
        frac = col_counts / max(n_profiles, 1)
        bins_ok = np.where(frac >= 0.10)[0]
        if len(bins_ok) > 0:
            max_depth = max(max_depth, float(depth_centers[bins_ok[-1]]))
        plot_vars.append((slot_label, found_key, cmap))

    if max_depth < 10:
        max_depth = float(depth_centers.max())
    else:
        padding = max(10.0, max_depth * 0.05)
        max_depth = min(max_depth + padding, float(depth_centers.max()))

    if not plot_vars:
        print("  WARNING: no plottable variables found in L0 grid")
        ds.close()
        return None

    print(f"  L0 plot depth: {max_depth:.0f} m")

    n_panels = len(plot_vars)
    fig, axes = plt.subplots(n_panels, 1,
                             figsize=(14, 4 * n_panels), sharex=True)
    if n_panels == 1:
        axes = [axes]
    fig.suptitle(f"Glider {GLIDER_ID}  —  L0 Raw Data (ALL measurements, no QC applied)",
                 fontsize=13, fontweight="bold", y=1.01)

    for i, (slot_label, var_key, cmap) in enumerate(plot_vars):
        ax = axes[i]
        _draw_pcolormesh(ax, t_arr, depth_centers, grid_2d[var_key],
                         cmap, slot_label, max_depth)

    _finalise_fig(fig, axes, plot_path)
    ds.close()
    return plot_path


# ----------------------------------------------------------------
# L1 plot  — QC-filtered grid (flags 1 & 2 only)
# ----------------------------------------------------------------

def plot_l1(grid_path, plot_path=None, l1_path=None):
    """Generate the L1 QC-filtered gridplot."""
    print("  Generating L1 plot (QC flags 1 & 2 only)...")

    plots_dir = os.path.join(OUTPUT_DIR, "plots")
    os.makedirs(plots_dir, exist_ok=True)

    # Try to find the grid file (multiple naming conventions)
    if grid_path is None or not os.path.exists(grid_path):
        # Search common grid file patterns
        candidates = [
            grid_path,
            os.path.join(OUTPUT_DIR, "L1-gridfiles",
                         f"incois_glider_{GLIDER_ID}_L1_grid.nc"),
            os.path.join(OUTPUT_DIR, "gridfiles",
                         f"incois_glider_{GLIDER_ID}_L1_grid.nc"),
            os.path.join(OUTPUT_DIR, "gridfiles",
                         f"incois_glider_{GLIDER_ID}_grid.nc"),
        ]
        grid_path = None
        for c in candidates:
            if c and os.path.exists(c):
                grid_path = c
                break

    ds = None
    is_1d = False

    # Prefer the pre-built grid file (step4 output) — it has proper time coords
    # and works reliably (step7 uses it successfully).
    if grid_path and os.path.exists(grid_path):
        print(f"  Loading L1 grid: {grid_path}")
        ds = xr.open_dataset(grid_path)
        # Verify it has 2D variables
        has_2d = any(_resolve_var(ds, v) is not None and
                     ds[_resolve_var(ds, v)].ndim == 2
                     for v in VARS_TO_PLOT if _resolve_var(ds, v) is not None)
        if not has_2d:
            print(f"  WARNING: grid has no 2D plot variables — trying timeseries")
            ds.close()
            ds = None

    # Fallback: build from L1 timeseries with uniform time bins
    if ds is None and l1_path is not None and os.path.exists(l1_path):
        print(f"  Building L1 plot grid from timeseries (uniform time bins)...")
        l1_ds = xr.open_dataset(l1_path)
        if "depth" in l1_ds:
            grid_2d, t_arr, depth_centers = _make_l1_grid_from_ts(l1_ds)
            if grid_2d is not None:
                l1_ds.close()
                ds = xr.Dataset(coords={"time": t_arr, "depth": depth_centers})
                for var in VARS_TO_PLOT:
                    if var in grid_2d:
                        ds[var] = xr.DataArray(grid_2d[var],
                                               dims=["time", "depth"])
                is_1d = False
            else:
                l1_ds.close()

    # Last fallback: use grid file even if variable check failed earlier
    if ds is None and grid_path and os.path.exists(grid_path):
        print(f"  Loading grid (last resort): {grid_path}")
        ds = xr.open_dataset(grid_path)
        if "depth" in ds and "time" in ds:
            has_2d = False
            for var in VARS_TO_PLOT:
                if var in ds and ds[var].ndim == 2:
                    has_2d = True
                    break
            if not has_2d:
                print(f"  WARNING: grid file has no 2D variables — "
                      f"falling back to L1 timeseries")
                ds.close()
                ds = None

    if ds is None and l1_path is not None and os.path.exists(l1_path):
        print(f"  Loading L1 timeseries (grid not usable): {l1_path}")
        ds = xr.open_dataset(l1_path)
        # Build uniform-time-bin grid on-the-fly from timeseries
        if "depth" in ds:
            print(f"  Building L1 grid on-the-fly (uniform time bins)...")
            grid_2d, t_arr, depth_centers = _make_l1_grid_from_ts(ds)
            if grid_2d is not None:
                ds.close()
                gds = xr.Dataset(coords={"time": t_arr, "depth": depth_centers})
                for var in VARS_TO_PLOT:
                    if var in grid_2d:
                        gds[var] = xr.DataArray(grid_2d[var],
                                                dims=["time", "depth"])
                ds = gds
                is_1d = False
            else:
                is_1d = ("depth" in ds and ds["depth"].ndim == 1
                         and ds.depth.dims[0] == "time")
        else:
            is_1d = ("depth" in ds and ds["depth"].ndim == 1
                     and ds.depth.dims[0] == "time")

    if ds is None:
        print(f"  WARNING: no grid or L1 file found for L1 plot")
        return None

    if "potential_density" not in ds and "density" in ds:
        ds["potential_density"] = ds["density"]

    ds = ds.sortby("time")

    # Diagnostic: show what's in the loaded dataset
    if not is_1d:
        # Support both 'depth' and 'DEPTH' dimension names
        depth_dim = 'depth' if 'depth' in ds.dims else 'DEPTH' if 'DEPTH' in ds.dims else None
        if depth_dim:
            print(f"  Grid dims: time={len(ds.time)} {depth_dim}={len(ds[depth_dim])}")
        else:
            print(f"  Grid dims: time={len(ds.time)} (no depth dimension found)")
        for var in VARS_TO_PLOT:
            if var in ds:
                print(f"    {var}: shape={ds[var].shape} dims={ds[var].dims}")

    if plot_path is None:
        plot_path = os.path.join(plots_dir,
                                 f"incois_glider_{GLIDER_ID}_L1_gridplot.png")

    t_vals     = ds.time.values
    # Support both 'depth' and 'DEPTH' dimension names
    depth_dim = 'depth' if 'depth' in ds else 'DEPTH' if 'DEPTH' in ds else None
    depth_vals = ds[depth_dim].values if not is_1d and depth_dim else None

    _report_gaps(t_vals)

    # Detect available variables
    detected = _detect_plot_vars(ds)
    if not detected:
        print("  WARNING: no plottable variables found in L1 dataset")
        ds.close()
        return None

    if not is_1d:
        # Compute max_depth from detected vars
        max_depth = 0.0
        for _, actual_var, _ in detected:
            V = ds[actual_var].values
            if V.ndim == 2:
                col_counts = np.sum(np.isfinite(V), axis=0).astype(float)
                frac = col_counts / max(V.shape[0], 1)
                bins_ok = np.where(frac >= 0.10)[0]
                if len(bins_ok) > 0:
                    max_depth = max(max_depth, float(depth_vals[bins_ok[-1]]))
        if max_depth < 10:
            max_depth = float(depth_vals.max()) if depth_vals is not None and len(depth_vals) > 0 else 1000.0
        else:
            padding = max(10.0, max_depth * 0.05)
            max_depth = min(max_depth + padding, float(depth_vals.max()))
    else:
        max_depth = float(np.nanmax(ds.depth.values))
        if np.isnan(max_depth) or max_depth < 10:
            max_depth = PLOT_DEPTH_MAX or 1000.0

    print(f"  L1 plot depth: {max_depth:.0f} m")

    n_panels = len(detected)
    fig, axes = plt.subplots(n_panels, 1,
                             figsize=(14, 4 * n_panels), sharex=True)
    if n_panels == 1:
        axes = [axes]
    # NaN cells render white (cmap.set_bad below), so the legend says white —
    # it previously promised grey, which nothing in the figure ever draws.
    fig.suptitle(f"Glider {GLIDER_ID}  —  L1 QC-Filtered (only good data, flags 1 & 2)\n"
                 f"White = no data, or removed by QC",
                 fontsize=13, fontweight="bold", y=1.02)

    for i, (slot_label, var, cmap) in enumerate(detected):
        ax = axes[i]
        V = ds[var].values

        # Handle variables that might have different dimension names
        if not is_1d:
            if V.ndim != 2:
                # Try to reshape if it's a 1D variable in a grid dataset
                # (shouldn't happen with make_grid output, but be defensive)
                ax.set_title(f"{var} (NOT 2D: ndim={V.ndim})", fontsize=13)
                ax.set_ylim(max_depth, 0)
                ax.set_ylabel("Depth (m)", fontsize=11)
                continue
            # Accept any 2D variable — use its actual shape for depth axis
            if V.shape[0] == len(t_vals) and V.shape[1] == len(depth_vals):
                pass  # perfect match
            elif V.shape[0] == len(t_vals):
                # Depth dimension might differ — use variable's actual depth
                # This handles cases where depth coord length doesn't match
                print(f"    {var}: shape {V.shape} (depth_vals={len(depth_vals)})")
                depth_vals_eff = np.arange(V.shape[1]) * DEPTH_BIN
                _draw_pcolormesh(ax, t_vals, depth_vals_eff, V,
                                 cmap, slot_label, max_depth)
                _add_qc_annotation(ax, ds, var, slot_label)
                continue
            else:
                ax.set_title(f"{var} (shape mismatch: {V.shape})", fontsize=13)
                ax.set_ylim(max_depth, 0)
                ax.set_ylabel("Depth (m)", fontsize=11)
                continue

        if is_1d:
            depth_1d = ds.depth.values
            valid = np.isfinite(V) & np.isfinite(depth_1d)
            qc_var = f"{var}_QC"
            if qc_var in ds:
                qc    = ds[qc_var].values.astype(int)
                valid = valid & ((qc == 1) | (qc == 2))
            n_valid = int(np.sum(valid))
            print(f"    {var}: {n_valid} points (scatter)")
            if n_valid == 0:
                ax.set_title(f"{var} (NO DATA)", fontsize=13)
                ax.set_ylim(max_depth, 0)
                ax.set_ylabel("Depth (m)", fontsize=11)
                continue
            v_min = np.nanpercentile(V[valid], 2)
            v_max = np.nanpercentile(V[valid], 98)
            sc = ax.scatter(t_vals[valid], depth_1d[valid],
                            c=V[valid], cmap=cmap,
                            vmin=v_min, vmax=v_max,
                            s=15, marker="o", alpha=0.8)
            ax.set_ylim(max_depth, 0)
            ax.set_title(slot_label, fontsize=13, fontweight="bold")
            ax.set_ylabel("Depth (m)", fontsize=11)
            cbar = plt.colorbar(sc, ax=ax, pad=0.02)
            cbar.set_label(_slot_lookup(var, VAR_LABELS, var), fontsize=11)
            # QC retention annotation
            _add_qc_annotation(ax, ds, var, slot_label)
        else:
            _draw_pcolormesh(ax, t_vals, depth_vals, V, cmap, slot_label, max_depth)
            # QC retention annotation
            _add_qc_annotation(ax, ds, var, slot_label)

    _finalise_fig(fig, axes, plot_path)
    ds.close()
    return plot_path

# ----------------------------------------------------------------
# Individual variable plots (pyglider-style: per-profile, auto-depth)
# ----------------------------------------------------------------

def plot_individual_variables(l0_path, l1_path=None):
    """
    Generate individual single-variable section plots, one PNG per variable.

    Uses uniform TIME-BIN gridding (same as the overview section) so the
    plots render as dense filled panels rather than sparse per-profile columns.
    The existing L0/L1 grid NetCDFs are used when available; otherwise the
    grid is built on the fly from the timeseries.
    """
    plots_dir = os.path.join(OUTPUT_DIR, "plots")
    os.makedirs(plots_dir, exist_ok=True)

    var_configs = [
        # (var_name,          label,            cmap,        units,    max_depth_override)
        ("temperature",       "temperature",    "RdYlBu_r",  "°C",     None),
        ("salinity",          "salinity",       "viridis",   "PSU",    None),
        ("oxygen_concentration", "oxygen",      "viridis",   "µmol/L", None),
        ("chlorophyll",       "chlorophyll",    "YlGn",      "mg m⁻³", 200),
        ("cdom",              "CDOM",           "BuPu",      "ppb",    200),
        ("backscatter_700",   "backscatter_700","inferno",   "m⁻¹",    200),
    ]

    # Paths to pre-built grid files
    l0_grid_path = os.path.join(OUTPUT_DIR, "L0-gridfiles",
                                f"incois_glider_{GLIDER_ID}_L0_grid.nc")
    l1_grid_path = os.path.join(OUTPUT_DIR, "L1-gridfiles",
                                f"incois_glider_{GLIDER_ID}_L1_grid.nc")

    sources = []
    if l0_path and os.path.exists(l0_path):
        g = l0_grid_path if os.path.exists(l0_grid_path) else None
        sources.append(("L0", l0_path, g, False))
    if l1_path and os.path.exists(l1_path):
        g = l1_grid_path if os.path.exists(l1_grid_path) else None
        sources.append(("L1", l1_path, g, True))

    for label_prefix, ts_path, grid_path, apply_qc in sources:

        # ── Build or load the time-bin grid ──────────────────────────────
        if grid_path and os.path.exists(grid_path):
            gds = xr.open_dataset(grid_path)
            t_arr      = gds.time.values
            depth_vals = gds.depth.values
            grid_data  = {}
            for var_name, _, _, _, _ in var_configs:
                actual = _resolve_var(gds, var_name)
                if actual and actual in gds:
                    grid_data[var_name] = gds[actual].values  # (time, depth)
            gds.close()
        else:
            # Fall back: build from timeseries using uniform time bins
            ds = xr.open_dataset(ts_path)
            if apply_qc:
                grid_data_raw, t_arr, depth_vals = _make_l1_grid_from_ts(ds)
            else:
                grid_data_raw, t_arr, depth_vals = _make_l0_grid(ds)
            if grid_data_raw is None:
                ds.close()
                continue
            # Remap by var_name key — resolve against the already-open ds,
            # not a second open() call
            grid_data = {}
            for var_name, _, _, _, _ in var_configs:
                actual = _resolve_var(ds, var_name) or var_name
                if actual in grid_data_raw:
                    grid_data[var_name] = grid_data_raw[actual]
            ds.close()

        if t_arr is None or len(t_arr) < 2:
            continue

        # ── One plot per variable ─────────────────────────────────────────
        for var_name, var_label, cmap, units, max_depth_override in var_configs:
            if var_name not in grid_data:
                continue

            V = grid_data[var_name].copy()          # (n_time, n_depth)
            if V.ndim != 2:
                continue

            # Physical range guard — same table used in _draw_pcolormesh
            V, n_phys = _apply_phys_range(V, var_name)
            if n_phys > 0:
                print(f"    {var_name}: nulled {n_phys} physically-impossible values")

            # Determine plot depth
            if max_depth_override is not None:
                max_d = float(max_depth_override)
            else:
                col_counts = np.sum(np.isfinite(V), axis=0).astype(float)
                n_t = V.shape[0]
                bins_ok = np.where(col_counts >= max(n_t * 0.05, 2))[0]
                max_d = float(depth_vals[bins_ok[-1]]) if len(bins_ok) > 0 \
                        else float(depth_vals[-1])
                max_d = min(max_d * 1.05, float(depth_vals[-1]))

            depth_mask = depth_vals <= max_d
            V_trim   = V[:, depth_mask]
            d_trim   = depth_vals[depth_mask]

            # Suppress depth bins with < 5% coverage (artefacts)
            col_cov = np.sum(np.isfinite(V_trim), axis=0).astype(float)
            V_trim[:, col_cov < max(V_trim.shape[0] * 0.05, 2)] = np.nan

            V_trim = _mask_time_gaps(V_trim, t_arr, GAP_THRESHOLD_HOURS)

            finite = np.isfinite(V_trim)
            if np.sum(finite) < 10:
                print(f"  SKIP {label_prefix} {var_name}: no finite data after masking")
                continue

            # Robust colorscale — 2/98 percentile after physical clamp
            v_min = float(np.nanpercentile(V_trim[finite], 2))
            v_max = float(np.nanpercentile(V_trim[finite], 98))
            if v_min >= v_max:
                v_max = v_min + 1.0

            fig, ax = plt.subplots(1, 1, figsize=(14, 5))

            t_edges = _pcolormesh_edges(t_arr)
            d_edges = _pcolormesh_edges(d_trim)
            cmap_obj = plt.get_cmap(cmap).copy()
            cmap_obj.set_bad(color="white")
            cmap_obj.set_under(color="white")
            cmap_obj.set_over(color="white")

            mesh = ax.pcolormesh(t_edges, d_edges, V_trim.T,
                                 cmap=cmap_obj, vmin=v_min, vmax=v_max,
                                 shading="flat")

            ax.set_ylim(max_d, 0)
            ax.set_ylabel("Depth [m]", fontsize=12)
            ax.set_xlabel("", fontsize=12)
            ax.xaxis.set_major_formatter(mdates.DateFormatter("%b\n%Y"))
            ax.xaxis.set_major_locator(mdates.AutoDateLocator())

            cbar = plt.colorbar(mesh, ax=ax, pad=0.02)
            cbar.set_label(f"{var_label} [{units}]", fontsize=11)

            qc_note = " (QC good only)" if apply_qc else " (all values)"
            ax.set_title(
                f"Glider {GLIDER_ID}  —  {label_prefix} {var_label}{qc_note}",
                fontsize=13, fontweight="bold")

            plt.tight_layout()
            fname = f"incois_glider_{GLIDER_ID}_{label_prefix}_{var_name}.png"
            fpath = os.path.join(plots_dir, fname)
            plt.savefig(fpath, dpi=150, bbox_inches="tight")
            plt.close(fig)
            print(f"  Saved: {fname}")

    print("  Individual variable plots done.")

# ----------------------------------------------------------------
# Main entry point — generates both plots
# ----------------------------------------------------------------

def run_step5(grid_path=None, plot_path=None, l1_path=None, l0_path=None):
    print("=" * 60)
    print("  STEP 5: Time-Depth Grid Plots (L0 + L1)")
    print("=" * 60)

    plots_dir = os.path.join(OUTPUT_DIR, "plots")
    os.makedirs(plots_dir, exist_ok=True)

    # --- L0 plot ---
    if l0_path is None:
        l0_path = os.path.join(OUTPUT_DIR,
                               f"incois_glider_{GLIDER_ID}_L0.nc")
    l0_out = plot_l0(l0_path)

    print()

    # --- L1 plot ---
    l1_out = plot_l1(grid_path, plot_path, l1_path)

    print()
    if l0_out:
        print(f"  L0 plot: {l0_out}")
    if l1_out:
        print(f"  L1 plot: {l1_out}")
        # --- Individual per-variable plots (pyglider style) ---
    print()
    print("  Generating individual variable plots (pyglider style)...")
    plot_individual_variables(l0_path, l1_path)

    # Return L1 path for backward compatibility
    return l1_out


if __name__ == "__main__":
    import argparse
    p = argparse.ArgumentParser()
    p.add_argument("--grid",  default=None)
    p.add_argument("--l0",    default=None)
    p.add_argument("--l1",    default=None)
    p.add_argument("--out",   default=None)
    args = p.parse_args()
    run_step5(grid_path=args.grid, plot_path=args.out,
              l1_path=args.l1, l0_path=args.l0)
