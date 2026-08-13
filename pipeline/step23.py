#!/usr/bin/env python3
"""
step23.py - L0 to L1 processing with GliderTools QC + ARGO flags.

Combines pre-cleaning, optics correction, physics QC, oxygen lag correction,
and complete ARGO RTQC flagging.
"""
import os
import sys
import time
import numpy as np
import xarray as xr
from scipy.signal import savgol_filter
from scipy.ndimage import median_filter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from config import (
    OUTPUT_DIR, GLIDER_ID, MAX_DEPTH_DBAR, OXYGEN_TAU,
    CLEAN_FACTORY_TESTS, FACTORY_LAT_MIN, FACTORY_LAT_MAX,
    FACTORY_LON_MIN, FACTORY_LON_MAX, CLEAN_ZERO_GPS,
    CLEAN_HEMISPHERE, CLEAN_MODE_YEAR,
    DEPLOY_TIME_START, DEPLOY_TIME_END,
)

try:
    import gsw
    HAS_GSW = True
except ImportError:
    HAS_GSW = False

try:
    import pandas as pd
    HAS_PANDAS = True
except ImportError:
    HAS_PANDAS = False


# ============================================================
# PRE-CLEANING: Remove factory/lab tests before QC
# ============================================================

def pre_clean(ds):
    """Remove pre-deployment factory tests, zero GPS, and cross-hemisphere data."""
    n_orig = len(ds.time)

    # ------------------------------------------------------------------
    # 0. Time crop: if deployment start/end are known, cut everything
    #    outside that window. This is the most reliable filter — it removes
    #    factory test data, transit, ballasting, and post-recovery noise
    #    in one clean cut.
    # ------------------------------------------------------------------
    if DEPLOY_TIME_START is not None or DEPLOY_TIME_END is not None:
        time_mask = np.ones(len(ds.time), dtype=bool)
        if DEPLOY_TIME_START is not None:
            time_mask &= (ds.time.values >= DEPLOY_TIME_START)
        if DEPLOY_TIME_END is not None:
            time_mask &= (ds.time.values <= DEPLOY_TIME_END)
        n_time_drop = int(np.sum(~time_mask))
        if n_time_drop > 0:
            ds = ds.isel(time=time_mask)
            print(f"  Pre-clean: time crop [{DEPLOY_TIME_START} to {DEPLOY_TIME_END}] "
                  f"removed {n_time_drop} observations")

    if "latitude" in ds and "longitude" in ds:
        if CLEAN_FACTORY_TESTS:
            mask = ~((ds.latitude > FACTORY_LAT_MIN) & (ds.latitude < FACTORY_LAT_MAX)
                     & (ds.longitude > FACTORY_LON_MIN) & (ds.longitude < FACTORY_LON_MAX))
            n_factory = int(np.sum(~mask.values))
            if n_factory > 0:
                ds = ds.where(mask, drop=True)
                print(f"  Pre-clean: factory test filter removed {n_factory} observations")

        if CLEAN_ZERO_GPS:
            # NaN out zero-GPS coordinates instead of dropping observations.
            # Subsurface data is still valid even without a GPS fix.
            zero_gps = (ds.latitude.values == 0) & (ds.longitude.values == 0)
            n_zero = int(np.sum(zero_gps))
            if n_zero > 0:
                lat_vals = ds.latitude.values.copy().astype(float)
                lon_vals = ds.longitude.values.copy().astype(float)
                lat_vals[zero_gps] = np.nan
                lon_vals[zero_gps] = np.nan
                ds["latitude"].values = lat_vals
                ds["longitude"].values = lon_vals
                print(f"  Pre-clean: NaN'd {n_zero} zero-GPS positions")

    if "waypoint_latitude" in ds and "waypoint_longitude" in ds:
        if CLEAN_FACTORY_TESTS:
            wp_mask = ~((ds["waypoint_latitude"] > FACTORY_LAT_MIN)
                        & (ds["waypoint_latitude"] < FACTORY_LAT_MAX)
                        & (ds["waypoint_longitude"] > FACTORY_LON_MIN)
                        & (ds["waypoint_longitude"] < FACTORY_LON_MAX))
            ds["waypoint_latitude"] = ds["waypoint_latitude"].where(wp_mask)
            ds["waypoint_longitude"] = ds["waypoint_longitude"].where(wp_mask)

    ds = ds.sortby("time")

    # Physical plausibility pre-filter: catch factory test values and
    # truly absurd readings BEFORE any other cleaning
    if "temperature" in ds:
        temp_vals = ds["temperature"].values.copy()
        bad_temp = np.isfinite(temp_vals) & ((temp_vals < -2.5) | (temp_vals > 35.0))
        n_preclean_temp = int(np.sum(bad_temp))
        if n_preclean_temp > 0:
            temp_vals[bad_temp] = np.nan
            ds["temperature"].values = temp_vals
            print(f"  Pre-clean: removed {n_preclean_temp} temperature values outside [-2.5, 35.0]°C")

    if CLEAN_MODE_YEAR and HAS_PANDAS:
        n_before_year = len(ds.time)
        t_dt = pd.Series(ds.time.values)
        if len(t_dt) > 0:
            mode_year = t_dt.dt.year.mode()[0]
            ds = ds.sel(time=((ds.time.dt.year == mode_year) | (ds.time.dt.year == mode_year - 1)))
        n_year_drop = n_before_year - len(ds.time)
        if n_year_drop > 0:
            print(f"  Pre-clean: mode year filter (keep {mode_year-1}-{mode_year}) "
                  f"removed {n_year_drop} observations")

    if CLEAN_HEMISPHERE and "latitude" in ds:
        n_before_hemi = len(ds.time)
        lat_vals = ds.latitude.values
        median_lat = float(np.nanmedian(lat_vals))
        # Only apply hemisphere filter if deployment is clearly in one hemisphere.
        # Near-equatorial deployments (|median_lat| < 10°) should NOT be filtered
        # because the glider may legitimately cross the equator.
        if abs(median_lat) < 10.0:
            pass  # skip — too close to equator for hemisphere filter
        else:
            # Only drop points with FINITE latitude in the wrong hemisphere.
            if median_lat < 0:
                wrong_hemi = np.isfinite(lat_vals) & (lat_vals > 0)
            else:
                wrong_hemi = np.isfinite(lat_vals) & (lat_vals < 0)
            if np.any(wrong_hemi):
                ds = ds.isel(time=~wrong_hemi)
            n_hemi_drop = n_before_hemi - len(ds.time)
            if n_hemi_drop > 0:
                print(f"  Pre-clean: hemisphere filter (median_lat={median_lat:.2f}) "
                      f"removed {n_hemi_drop} observations")

    n_clean = len(ds.time)
    print(f"  Pre-cleaning: {n_orig} -> {n_clean} observations (removed {n_orig - n_clean})")

    # ------------------------------------------------------------------
    # Bug 1 fix: Auto-segmentation — strip shallow test-dive data by
    # looking at actual signal (max depth per profile), not date heuristics.
    # ------------------------------------------------------------------
    if "profile_index" in ds:
        ds = _strip_shallow_test_dives(ds)

    return ds


def _strip_shallow_test_dives(ds):
    """
    Remove pre-deployment shallow test dives that appear before the real
    deployment segment. Detection is purely signal-based — no hardcoded dates.

    Algorithm
    ---------
    1. Compute max depth per profile.
    2. Find the "real deployment depth" as the 75th percentile of all profile
       max-depths. Test dives are typically < 20% of this value.
    3. Identify a contiguous block of shallow profiles at the START of the
       timeseries (before the first deep profile that exceeds the threshold).
       Only the leading shallow block is removed — shallow profiles elsewhere
       (e.g. end-of-deployment recovery) are preserved.
    4. If no clear shallow/deep separation exists (all profiles are similar
       depth), nothing is removed.

    This generalises across deployments: it works for a 150 m deployment with
    20 m test dives, a 1000 m deployment with 50 m test dives, etc.
    """
    pi_vals = ds.profile_index.values
    depth_var = "depth" if "depth" in ds else "pressure"
    if depth_var not in ds:
        return ds

    d_vals = ds[depth_var].values
    unique_profiles = np.unique(pi_vals[np.isfinite(pi_vals)])
    if len(unique_profiles) < 5:
        return ds  # not enough profiles to make a reliable decision

    # Max depth per profile
    max_depths = {}
    for p in unique_profiles:
        mask = pi_vals == p
        d_p = d_vals[mask]
        finite_d = d_p[np.isfinite(d_p)]
        max_depths[p] = float(np.max(finite_d)) if len(finite_d) > 0 else 0.0

    all_max = np.array([max_depths[p] for p in unique_profiles])

    # Real deployment depth: 75th percentile of all profile max depths.
    # Using 75th (not median) makes it robust when many profiles are shallow.
    real_depth = float(np.percentile(all_max, 75))
    if real_depth < 20:
        return ds  # deployment is inherently shallow — nothing to strip

    # Test-dive threshold: profiles shallower than 20% of real deployment depth
    # and at least 10 m shallower than real_depth are considered test dives.
    shallow_thresh = max(min(real_depth * 0.20, real_depth - 10.0), 5.0)

    # Find the first profile that clearly reaches deployment depth
    first_deep_idx = None
    for i, p in enumerate(unique_profiles):
        if max_depths[p] >= real_depth * 0.50:
            first_deep_idx = i
            break

    if first_deep_idx is None or first_deep_idx == 0:
        return ds  # first profile is already deep — nothing to strip

    # Check that the leading profiles really are shallow (test dives)
    leading = unique_profiles[:first_deep_idx]
    n_shallow_leading = sum(1 for p in leading if max_depths[p] < shallow_thresh)
    frac_shallow = n_shallow_leading / len(leading)

    if frac_shallow < 0.70:
        # Leading block is not clearly all-shallow — be conservative, don't strip
        return ds

    # Strip the leading test-dive profiles
    strip_profiles = set(leading)
    keep_mask = np.ones(len(ds.time), dtype=bool)
    for p in strip_profiles:
        keep_mask[pi_vals == p] = False

    n_stripped = int(np.sum(~keep_mask))
    if n_stripped > 0:
        ds = ds.isel(time=keep_mask)
        print(f"  Pre-clean: depth-based segmentation removed {n_stripped} observations "
              f"from {len(strip_profiles)} shallow test-dive profiles "
              f"(max depth < {shallow_thresh:.0f} m, real deployment depth ~{real_depth:.0f} m)")

    return ds


def detect_variable_corruption(ds):
    """
    Detect and null-out variables that are LITERALLY IDENTICAL to pressure
    — a sign of a data mapping bug in the L0 (wrong sensor mapped to wrong
    variable name).

    Detection rule: values must be near-identical in both NUMERIC VALUE and
    SCALE, not just correlated. High Pearson correlation alone is NOT
    sufficient — depth-varying ocean variables (chlorophyll, CDOM, backscatter)
    naturally correlate with pressure because they all track depth. We require:

      1. Near-identical numeric values: >50% of points within 1e-3 of pressure
         (absolute), OR median |chl - pres| < 1.0 (scale match)
      2. Variable's own physical range is pressure-like (span > 50 dbar)

    This catches the genuine bug pattern (chlorophyll array contains pressure
    values) while leaving real optical data alone even if it correlates with
    depth.
    """
    if "pressure" not in ds:
        return ds

    pres = ds["pressure"].values.astype(float)

    for var in ["chlorophyll", "cdom", "backscatter_700"]:
        if var not in ds:
            continue
        v = ds[var].values.astype(float)
        both = np.isfinite(v) & np.isfinite(pres)
        if np.sum(both) < 100:
            continue

        v_valid   = v[both]
        p_valid   = pres[both]
        v_range   = float(np.nanmax(v_valid) - np.nanmin(v_valid))
        v_min     = float(np.nanmin(v_valid))
        v_max     = float(np.nanmax(v_valid))
        p_range   = float(np.nanmax(p_valid) - np.nanmin(p_valid))

        # Test 1: are the numeric values actually the same as pressure?
        # "Same" means >50% of points are within 1e-3 of pressure value
        frac_identical = float(np.mean(np.abs(v_valid - p_valid) < 1e-3))

        # Test 2: does the variable's value range overlap pressure's range?
        # Real chlorophyll is 0–50 mg/m³, real pressure is 0–2000 dbar —
        # they won't overlap in value even if they correlate structurally
        range_overlap = (v_max > 10.0) and (v_min >= -2.0) and (v_range > 50.0)

        is_corrupted = (frac_identical > 0.50) or (frac_identical > 0.10 and range_overlap)

        if is_corrupted:
            print(f"  WARNING: '{var}' values are NUMERICALLY IDENTICAL to 'pressure' "
                  f"(frac_identical={frac_identical:.3f}, "
                  f"{var} range=[{v_min:.2f},{v_max:.2f}], "
                  f"pressure range=[{np.nanmin(p_valid):.1f},{np.nanmax(p_valid):.1f}]) "
                  f"— nulling (data mapping bug in L0)")
            nulled = ds[var].values.copy()
            nulled[:] = np.nan
            ds[var].values = nulled
        else:
            # Log what we found so the user can see the test passed cleanly
            corr = float(np.corrcoef(v_valid, p_valid)[0, 1])
            print(f"  Corruption check '{var}': range=[{v_min:.4f},{v_max:.4f}], "
                  f"corr_with_pressure={corr:.4f}, frac_identical={frac_identical:.6f} "
                  f"— OK (real data)")

    return ds


# ============================================================
# GLIDERTOOLS-STYLE QC FUNCTIONS
# ============================================================

def outlier_bounds_iqr(data, multiplier=1.5):
    """Global IQR outlier removal. Use only for optical variables, NOT for T/S/O2."""
    out = data.copy()
    valid = out[np.isfinite(out)]
    if len(valid) < 10:
        return out, 0
    q1, q3 = np.percentile(valid, [25, 75])
    iqr = q3 - q1
    lo, hi = q1 - multiplier * iqr, q3 + multiplier * iqr
    bad = (out < lo) | (out > hi)
    n_bad = int(np.sum(bad))
    out[bad] = np.nan
    return out, n_bad


def despike_median(data, window=5):
    baseline = data.copy()
    valid = np.isfinite(baseline)
    if np.sum(valid) < window:
        return baseline, np.zeros_like(data)
    filled = baseline.copy()
    if np.any(~valid):
        filled[~valid] = np.interp(
            np.flatnonzero(~valid), np.flatnonzero(valid),
            baseline[valid], left=np.nan, right=np.nan)
    med = median_filter(filled, size=window)
    spikes = data - med
    baseline = np.where(valid, med, np.nan)
    return baseline, spikes


def smooth_savgol_per_profile(data, profile_index, window=11, order=2):
    out = data.copy()
    valid_mask = np.isfinite(data) & np.isfinite(profile_index)
    if np.sum(valid_mask) < window:
        return out
    profiles = np.unique(profile_index[valid_mask])
    for p in profiles:
        p_mask = valid_mask & (profile_index == p)
        p_vals = data[p_mask]
        if len(p_vals) < window:
            continue
        filled = p_vals.copy()
        p_valid = np.isfinite(filled)
        if np.any(~p_valid):
            filled[~p_valid] = np.interp(
                np.flatnonzero(~p_valid), np.flatnonzero(p_valid),
                p_vals[p_valid], left=np.nan, right=np.nan)
        if len(filled) >= window:
            smoothed = savgol_filter(filled, window, order)
            out[p_mask] = np.where(p_valid, smoothed, np.nan)
    return out


def backscatter_zhang_correction(beta, temperature, salinity,
                                  theta_deg=124, wavelength=700, chi_factor=1.076):
    out = np.full_like(beta, np.nan)
    valid = np.isfinite(beta) & np.isfinite(temperature) & np.isfinite(salinity)
    if np.sum(valid) < 2:
        return out
    T = temperature[valid]
    S = salinity[valid]
    lam = wavelength
    lam_ref = 500.0
    beta_sw_ref = 1.38e-4 * (lam_ref / lam) ** 4.32
    beta_sw = beta_sw_ref * (1 + 0.3 * S / 37.0) * (1 + (T - 20) * 0.002)
    beta_p = beta[valid] - beta_sw
    bbp = 2 * np.pi * chi_factor * beta_p
    out[valid] = bbp
    return out


def insitu_dark_count(data, depth, deep_min=None, deep_max=None, percentile=5):
    """
    Subtract in-situ dark count (noise floor) from optical data.

    Uses the 5th percentile of deep measurements as the dark offset
    (standard practice per GliderTools / Briggs et al. 2011).

    Depth range is adaptive: uses 70th-90th percentile of deployment depth
    so it works for shallow coastal (100m) and deep (1000m+) deployments.
    """
    valid = np.isfinite(data) & np.isfinite(depth)
    if np.sum(valid) < 10:
        return data, False

    # Adaptive depth range based on deployment depth
    if deep_min is None or deep_max is None:
        deep_min = max(50, np.nanpercentile(depth[valid], 70))
        deep_max = np.nanpercentile(depth[valid], 90)

    deep = valid & (depth >= deep_min) & (depth <= deep_max)
    used_fallback = False
    if np.sum(deep) < 5:
        depth_thresh = np.percentile(depth[valid], 90)
        deep = valid & (depth >= depth_thresh)
        used_fallback = True
    if np.sum(deep) < 3:
        return data, False
    dark = np.percentile(data[deep], percentile)
    out = data.copy()
    out[valid] = data[valid] - dark
    return out, used_fallback


def find_bad_profiles(data, depth, profile_index, depth_threshold=None, multiplier=2.0):
    """
    Find profiles with anomalously high deep values (biofouling, sensor drift).

    depth_threshold is adaptive: defaults to 60th percentile of deployment depth,
    with a minimum of 100m. This scales to the deployment depth automatically.
    """
    mask = np.zeros(len(data), dtype=bool)
    valid = np.isfinite(data) & np.isfinite(depth) & np.isfinite(profile_index)
    if np.sum(valid) < 10:
        return mask, 0

    # Adaptive depth threshold based on deployment depth
    if depth_threshold is None:
        finite_depth = depth[np.isfinite(depth)]
        if len(finite_depth) > 0:
            depth_threshold = max(100, np.nanpercentile(finite_depth, 60))
        else:
            depth_threshold = 100

    profiles = np.unique(profile_index[valid])
    deep_means = {}
    for p in profiles:
        in_prof = valid & (profile_index == p) & (depth > depth_threshold)
        if np.sum(in_prof) >= 3:
            deep_means[p] = np.nanmean(data[in_prof])
    if len(deep_means) < 5:
        return mask, 0
    means = np.array(list(deep_means.values()))
    med = np.median(means)
    std = np.std(means)
    threshold = med + multiplier * std
    n_flagged = 0
    for p, m in deep_means.items():
        if m > threshold:
            prof_mask = (profile_index == p)
            mask[prof_mask] = True
            n_flagged += int(np.sum(prof_mask))
    return mask, n_flagged


def horizontal_diff_outliers(data, depth, profile_index, depth_bins=None,
                              max_frac=0.1, multiplier=3.0):
    mask = np.zeros(len(data), dtype=bool)
    valid = np.isfinite(data) & np.isfinite(depth) & np.isfinite(profile_index)
    if np.sum(valid) < 20:
        return mask, 0
    if depth_bins is None:
        depth_bins = np.arange(0, np.nanmax(depth[valid]) + 10, 10)
    profiles = np.sort(np.unique(profile_index[valid]))
    if len(profiles) < 5:
        return mask, 0
    n_prof = len(profiles)
    n_bins = len(depth_bins) - 1
    vi = np.where(valid)[0]
    pi_arr = np.searchsorted(profiles, profile_index[vi])
    di_arr = np.clip(np.searchsorted(depth_bins, depth[vi]) - 1, 0, n_bins - 1)
    sums = np.zeros((n_prof, n_bins))
    counts = np.zeros((n_prof, n_bins))
    np.add.at(sums, (pi_arr, di_arr), data[vi])
    np.add.at(counts, (pi_arr, di_arr), 1)
    grid = np.where(counts > 0, sums / counts, np.nan)
    hdiff = np.abs(np.diff(grid, axis=0))
    all_diffs = hdiff[np.isfinite(hdiff)]
    if len(all_diffs) < 10:
        return mask, 0
    med_diff = np.median(all_diffs)
    mad = np.median(np.abs(all_diffs - med_diff))
    threshold = med_diff + multiplier * 1.4826 * mad
    n_flagged = 0
    for i in range(hdiff.shape[0]):
        row = hdiff[i]
        n_valid_bins = np.sum(np.isfinite(row))
        if n_valid_bins < 3:
            continue
        frac = np.sum(row > threshold) / n_valid_bins
        if frac > max_frac:
            for pi in [i, i + 1]:
                p = profiles[pi]
                prof_mask = (profile_index == p)
                mask[prof_mask] = True
                n_flagged += int(np.sum(prof_mask))
    return mask, n_flagged


def quenching_correction(chl, bbp, depth, time_vals, latitude, longitude, profile_index):
    chl_corr = chl.copy()
    valid = (np.isfinite(chl) & np.isfinite(bbp) & np.isfinite(depth)
             & np.isfinite(profile_index))
    if np.sum(valid) < 50:
        return chl_corr, 0
    try:
        time_ns = time_vals.astype("datetime64[ns]")
        day_start = time_ns.astype("datetime64[D]")
        hour_utc = (time_ns - day_start) / np.timedelta64(1, "h")
    except Exception:
        return chl_corr, 0
    mean_lon = float(np.nanmean(longitude)) if np.any(np.isfinite(longitude)) else 75.0
    solar_hour = (hour_utc + mean_lon / 15.0) % 24.0
    is_day = (solar_hour > 6) & (solar_hour < 18)
    profiles = np.unique(profile_index[valid])
    night_ratios = []
    for p in profiles:
        in_prof = valid & (profile_index == p)
        if np.sum(in_prof) < 5 or np.mean(is_day[in_prof]) > 0.5:
            continue
        subsurface = in_prof & (depth >= 20) & (depth <= 200) & (bbp > 1e-5)
        if np.sum(subsurface) < 3:
            continue
        ratio = np.nanmedian(chl[subsurface] / bbp[subsurface])
        if np.isfinite(ratio) and ratio > 0:
            night_ratios.append(ratio)
    if len(night_ratios) < 3:
        return chl_corr, 0
    ref_ratio = np.median(night_ratios)
    n_corrected = 0
    for p in profiles:
        in_prof = valid & (profile_index == p)
        if np.sum(in_prof) < 5 or np.mean(is_day[in_prof]) <= 0.5:
            continue
        prof_depth = depth[in_prof]
        prof_chl = chl[in_prof]
        prof_bbp = bbp[in_prof]
        prof_ratio = np.where(prof_bbp > 1e-5, prof_chl / prof_bbp, np.nan)
        quench_candidates = (prof_depth < 200) & np.isfinite(prof_ratio) & (prof_ratio < 0.5 * ref_ratio)
        if not np.any(quench_candidates):
            continue
        quench_depth = np.max(prof_depth[quench_candidates])
        indices = np.where(in_prof)[0]
        for idx in indices:
            if depth[idx] < quench_depth and bbp[idx] > 1e-5:
                corrected = bbp[idx] * ref_ratio
                if corrected > chl[idx]:
                    chl_corr[idx] = corrected
                    n_corrected += 1
    return chl_corr, n_corrected


# ============================================================
# PROCESSING PIPELINES
# ============================================================

def apply_optics_correction(ds):
    """
    Apply optics corrections (IQR, dark count, despiking, Zhang, quenching).

    NON-DESTRUCTIVE: Original chlorophyll/cdom/backscatter_700 values are
    preserved. Corrected versions are written as separate variables:
      chlorophyll_corrected, cdom_corrected, backscatter_700_corrected

    Points identified as bad (IQR outliers, bad profiles) are NaN'd in the
    original to inform QC flags, but no calibration/smoothing is applied
    to the surviving good points in the original array.
    """
    print("  Optics Processing (GliderTools-style)...")
    depth = ds["depth"].values if "depth" in ds else ds["pressure"].values
    profile_index = ds["profile_index"].values if "profile_index" in ds else np.zeros(len(ds.time))

    if "chlorophyll" in ds:
        chl_orig = ds["chlorophyll"].values.copy()
        chl = chl_orig.copy()
        chl, n_iqr = outlier_bounds_iqr(chl, multiplier=3.0)
        # Track which points were removed by IQR
        iqr_bad = np.isfinite(chl_orig) & ~np.isfinite(chl)

        # Corrected version: dark count + clip + despike
        chl_corr = chl.copy()
        chl_corr, fb = insitu_dark_count(chl_corr, depth)
        if fb:
            print("    WARNING: chlorophyll dark count - no deep data, using fallback")
        chl_corr = np.where(np.isfinite(chl_corr), np.maximum(chl_corr, 0.0), np.nan)
        chl_corr, chl_spikes = despike_median(chl_corr, window=7)

        # Write corrected as separate variable
        ds["chlorophyll_corrected"] = xr.DataArray(chl_corr, dims=["time"],
            attrs={"long_name": "chlorophyll (corrected)", "units": "mg m-3",
                   "comment": "IQR(3x), dark count corrected, clipped to 0, despiked. "
                              "Original values in 'chlorophyll'."})

        # NaN the IQR-bad points in original (for QC flags) but don't alter good values
        orig_masked = chl_orig.copy()
        orig_masked[iqr_bad] = np.nan
        ds["chlorophyll"].values = orig_masked
        print(f"    chlorophyll: IQR removed {n_iqr}, dark count corrected, despiked")

    if "cdom" in ds:
        cdom_orig = ds["cdom"].values.copy()
        cdom = cdom_orig.copy()
        cdom, n_iqr = outlier_bounds_iqr(cdom, multiplier=3.0)
        iqr_bad = np.isfinite(cdom_orig) & ~np.isfinite(cdom)

        cdom_corr = cdom.copy()
        cdom_corr, fb = insitu_dark_count(cdom_corr, depth)
        if fb:
            print("    WARNING: cdom dark count - no deep data, using fallback")
        cdom_corr = np.where(np.isfinite(cdom_corr), np.maximum(cdom_corr, 0.0), np.nan)
        cdom_corr, _ = despike_median(cdom_corr, window=7)

        ds["cdom_corrected"] = xr.DataArray(cdom_corr, dims=["time"],
            attrs={"long_name": "CDOM (corrected)", "units": "ppb",
                   "comment": "IQR(3x), dark count corrected, clipped to 0, despiked. "
                              "Original values in 'cdom'."})

        orig_masked = cdom_orig.copy()
        orig_masked[iqr_bad] = np.nan
        ds["cdom"].values = orig_masked
        print(f"    cdom: IQR removed {n_iqr}, processed")

    if "backscatter_700" in ds:
        bb_orig = ds["backscatter_700"].values.copy()
        bb = bb_orig.copy()
        bb, n_iqr = outlier_bounds_iqr(bb, multiplier=3.0)
        iqr_bad = np.isfinite(bb_orig) & ~np.isfinite(bb)

        temp = ds["temperature"].values if "temperature" in ds else None
        sal = ds["salinity"].values if "salinity" in ds else None
        if temp is not None and sal is not None:
            bbp = backscatter_zhang_correction(bb, temp, sal)
            bbp, fb = insitu_dark_count(bbp, depth)
            if fb:
                print("    WARNING: backscatter dark count - no deep data, using fallback")
            bbp_corr, bbp_spikes = despike_median(bbp, window=7)
            ds["backscatter_700_corrected"] = xr.DataArray(bbp_corr, dims=["time"],
                attrs={"long_name": "particulate backscatter 700nm (corrected)", "units": "m-1",
                       "comment": "Zhang corrected, dark count removed, despiked. "
                                  "Original values in 'backscatter_700'."})
            print(f"    backscatter: IQR removed {n_iqr}, Zhang corrected, dark count, despiked")
        else:
            bb_corr, _ = despike_median(bb, window=7)
            ds["backscatter_700_corrected"] = xr.DataArray(bb_corr, dims=["time"],
                attrs={"long_name": "backscatter 700nm (corrected)", "units": "1",
                       "comment": "Despiked only (no T/S for Zhang correction). "
                                  "Original values in 'backscatter_700'."})
            print("    backscatter: despiked only (no T/S available)")

        # NaN the IQR-bad points in original
        orig_masked = bb_orig.copy()
        orig_masked[iqr_bad] = np.nan
        ds["backscatter_700"].values = orig_masked

    # Bad profile detection — NaN in originals (for QC) and corrected
    if "profile_index" in ds:
        prof_idx = ds["profile_index"].values
        for var in ["backscatter_700", "chlorophyll"]:
            if var not in ds:
                continue
            corr_var = f"{var}_corrected"
            source = ds[corr_var].values if corr_var in ds else ds[var].values
            bad_mask, n_bad = find_bad_profiles(
                source, depth, prof_idx,
                depth_threshold=None, multiplier=2.0)
            if n_bad > 0:
                # NaN in original
                vals = ds[var].values.copy()
                vals[bad_mask] = np.nan
                ds[var].values = vals
                # NaN in corrected
                if corr_var in ds:
                    cv = ds[corr_var].values.copy()
                    cv[bad_mask] = np.nan
                    ds[corr_var].values = cv
                print(f"    {var}: flagged {n_bad} pts in bad profiles")

    # Quenching correction — applied to corrected version only
    if all(v in ds for v in ["chlorophyll_corrected", "backscatter_700_corrected", "profile_index"]):
        lat = ds["latitude"].values if "latitude" in ds else np.full(len(ds.time), 12.0)
        lon = ds["longitude"].values if "longitude" in ds else np.full(len(ds.time), 75.0)
        chl_corr, n_corr = quenching_correction(
            ds["chlorophyll_corrected"].values, ds["backscatter_700_corrected"].values,
            depth, ds.time.values, lat, lon, ds["profile_index"].values)
        if n_corr > 0:
            ds["chlorophyll_corrected"].values = chl_corr
            ds["chlorophyll_corrected"].attrs["comment"] = (
                ds["chlorophyll_corrected"].attrs.get("comment", "") +
                " Quenching corrected (Thomalla et al. 2017).")
            print(f"    chlorophyll: quenching corrected {n_corr} points")

    return ds


def apply_physics_qc(ds):
    print("  Physics QC (GliderTools-style)...")
    profile_index = ds["profile_index"].values if "profile_index" in ds else np.zeros(len(ds.time))

    # For glider T/S/O2 we do NOT use IQR — it is fundamentally wrong for full-depth
    # profiles where cold deep water dominates the distribution and would flag warm
    # surface water as outliers. Instead we use:
    #   1. Physical range limits (removes truly impossible values)
    #   2. Median despike (removes point-to-point spikes within a profile)
    #   3. Savitzky-Golay smoothing per profile (reduces sensor noise)
    # IQR is reserved for optical variables (chlorophyll, backscatter) where the
    # distribution is more uniform and global outliers are meaningful.

    phys_limits = {
        "temperature":          (-2.5, 35.0),
        "salinity":             (2.0,  41.0),
        "oxygen_concentration": (-5.0, 600.0),
    }

    for var, sg_win in [
        ("temperature",          11),
        ("salinity",             11),
        ("oxygen_concentration", 11),
    ]:
        if var not in ds:
            continue
        vals = ds[var].values.copy()
        n_orig = int(np.sum(np.isfinite(vals)))

        # Step 1: physical range guard — NaN out-of-range values
        # These NaNs inform the QC flags but we track which points are bad
        bad_mask = np.zeros(len(vals), dtype=bool)
        if var in phys_limits:
            lo_phys, hi_phys = phys_limits[var]
            out_of_range = np.isfinite(vals) & ((vals < lo_phys) | (vals > hi_phys))
            n_phys = int(np.sum(out_of_range))
            bad_mask |= out_of_range
            if n_phys > 0:
                print(f"    {var}: physical range removed {n_phys}")

        # Step 2: median despike — identify spikes
        vals_work = vals.copy()
        vals_work[bad_mask] = np.nan
        _, spikes = despike_median(vals_work, window=5)
        # Spikes are the difference from median — flag as bad where |spike| > 3*MAD
        spike_vals = np.abs(spikes)
        finite_spikes = spike_vals[np.isfinite(spike_vals) & (spike_vals > 0)]
        if len(finite_spikes) > 10:
            mad = np.median(finite_spikes)
            spike_threshold = 3.0 * 1.4826 * mad
            spike_mask = np.isfinite(spike_vals) & (spike_vals > spike_threshold)
        else:
            spike_mask = np.zeros(len(vals), dtype=bool)
        bad_mask |= spike_mask

        # Step 3: Savitzky-Golay smoothing per profile → write as SEPARATE variable
        vals_smoothed = smooth_savgol_per_profile(vals_work, profile_index, window=sg_win, order=2)

        # Clip oxygen to physically meaningful minimum
        if var == "oxygen_concentration":
            vals_smoothed = np.where(np.isfinite(vals_smoothed), np.maximum(vals_smoothed, 0.0), np.nan)

        # Write smoothed/corrected version as a new variable (NOT overwriting original)
        smoothed_name = f"{var}_processed"
        attrs_proc = dict(ds[var].attrs) if var in ds else {}
        attrs_proc["comment"] = (
            f"Processed: physical range check, median despiked (w=5), "
            f"SG smoothed per-profile (w={sg_win}). "
            f"Original values preserved in '{var}'."
        )
        attrs_proc["long_name"] = attrs_proc.get("long_name", var) + " (processed)"
        ds[smoothed_name] = xr.DataArray(vals_smoothed, dims=["time"], attrs=attrs_proc)

        # Mark bad points as NaN in the ORIGINAL variable for QC flag purposes
        # but DO NOT smooth or alter the good values
        orig_vals = ds[var].values.copy()
        orig_vals[bad_mask] = np.nan
        ds[var].values = orig_vals

        n_final = int(np.sum(np.isfinite(orig_vals)))
        print(f"    {var}: {n_orig} -> {n_final} valid")

    if "salinity" in ds and "profile_index" in ds:
        sal_depth = ds["depth"].values if "depth" in ds else ds["pressure"].values
        sal_mask, n_hdiff = horizontal_diff_outliers(
            ds["salinity"].values, sal_depth, ds["profile_index"].values,
            max_frac=0.3, multiplier=8.0)
        if n_hdiff > 0:
            # Depth guard: only apply horizontal_diff_outliers below 100m.
            # Surface salinity naturally has large horizontal gradients near
            # coasts, river outflows, and fronts — don't flag those.
            depth_guard = sal_depth > 100.0
            sal_mask_guarded = sal_mask & depth_guard
            n_applied = int(np.sum(sal_mask_guarded))
            if n_applied > 0:
                # NaN the flagged points in the original (marks them for QC flags)
                # but do NOT smooth or alter good values
                sal_vals = ds["salinity"].values.copy()
                sal_vals[sal_mask_guarded] = np.nan
                ds["salinity"].values = sal_vals
                # Also update the processed version
                if "salinity_processed" in ds:
                    sp = ds["salinity_processed"].values.copy()
                    sp[sal_mask_guarded] = np.nan
                    ds["salinity_processed"].values = sp
            print(f"    salinity: horizontal diff flagged {n_hdiff} pts, "
                  f"applied {n_applied} (depth>100m guard)")

    return ds


def oxygen_lag_correction(ds):
    print("  Applying Oxygen Lag Correction...")
    if "oxygen_concentration" not in ds:
        print("   Oxygen variable not found.")
        return ds

    tau = OXYGEN_TAU
    t = ds.time.values.astype("datetime64[s]").astype(float)
    dt = np.diff(t)
    dt = np.insert(dt, 0, 0.0)
    oxy = ds["oxygen_concentration"].values
    doxy = np.diff(oxy)
    doxy = np.insert(doxy, 0, 0.0)

    with np.errstate(invalid="ignore", divide="ignore"):
        oxy_rate = doxy / dt
    oxy_rate[dt <= 0] = 0
    oxy_rate[dt > 60] = 0
    oxy_rate[np.isnan(oxy_rate)] = 0
    oxy_rate[np.isinf(oxy_rate)] = 0

    if "profile_index" in ds:
        pi = ds["profile_index"].values
        dpi = np.diff(pi)
        dpi = np.insert(dpi, 0, 0)
        oxy_rate[dpi != 0] = 0

    oxy_corrected = oxy + (tau * oxy_rate)
    oxy_corrected[oxy_corrected < 0] = 0.0
    oxy_corrected[~np.isfinite(oxy)] = np.nan

    ds["oxygen_concentration_lag_corrected"] = xr.DataArray(
        oxy_corrected, dims=["time"],
        attrs={"long_name": "lag corrected oxygen concentration",
               "units": "umol l-1",
               "comment": f"First-order lag correction, tau={tau}s, profile-aware"})
    print(f"   Added oxygen_concentration_lag_corrected (tau={tau}s)")
    return ds


# ============================================================
# ARGO RTQC TESTS
# ============================================================

# Severity ranking used to resolve competing verdicts. Flag 9 (missing) is
# deliberately absent: it is not a verdict about a value, it is the statement
# that there is no value, so it neither wins nor loses a comparison.
_FLAG_SEVERITY = {1: 0, 2: 1, 3: 2, 4: 3}

# Lookup table for the same ranking, indexed by flag value, so the comparison
# vectorises. Size 10 covers every flag in ARGO Reference Table 2; entries the
# pipeline never emits (0, 5-8) stay at -1 and therefore always lose, which is
# the safe direction — an unknown flag gets replaced by a real verdict.
_SEVERITY_LUT = np.full(10, -1, dtype=np.int8)
for _flag, _rank in _FLAG_SEVERITY.items():
    _SEVERITY_LUT[_flag] = _rank


def _raise_flag(qc, mask, flag):
    """
    Apply `flag` where `mask` is True, keeping whichever verdict is worse.

    The RTQC tests run in sequence and several of them judge the same variable.
    A plain ``qc[mask] = flag`` lets a later, milder test erase an earlier,
    harsher one. That is not cosmetic: test 19 (deepest pressure, flag 3) runs
    after test 6 (global range, flag 4), so a pressure of 2500 dbar was being
    downgraded 4 -> 3, after which pressure_cascade no longer recognised it as
    bad and the temperature and salinity measured at that impossible pressure
    kept flag 1 (good).

    Positions already flagged 9 (missing) are left untouched — a test cannot
    return a verdict on a value that is not there.

    Returns the number of positions actually changed.
    """
    if flag not in _FLAG_SEVERITY:
        raise ValueError(
            f"_raise_flag handles verdict flags {sorted(_FLAG_SEVERITY)}, "
            f"got {flag}. Flag 9 (missing) is set once at initialisation "
            f"from the L0 NaN mask and must not be re-derived here."
        )
    mask = np.asarray(mask, dtype=bool)
    upgrade = mask & (qc != 9) & (_SEVERITY_LUT[qc] < _FLAG_SEVERITY[flag])
    n_changed = int(np.count_nonzero(upgrade))
    qc[upgrade] = flag
    return n_changed


def test_impossible_date(ds, qc_dict):
    flagged = 0
    try:
        time_ns = ds.time.values.astype("datetime64[ns]")
        juld_ref = np.datetime64("1997-01-01", "ns")
        now = np.datetime64("now", "ns")
        bad = (time_ns < juld_ref) | (time_ns > now)
        if np.any(bad):
            for var in qc_dict:
                _raise_flag(qc_dict[var], bad, 4)
            flagged = int(np.sum(bad))
    except Exception:
        pass
    return flagged


def test_impossible_location(ds, qc_dict):
    """
    Flag positions outside the valid lat/lon domain.

    Only finite-but-impossible values are judged here. A non-finite position is
    absent, not wrong, and is already carried as flag 9 from the L0 NaN mask.
    """
    flagged = 0
    lat = ds["latitude"].values if "latitude" in ds else None
    lon = ds["longitude"].values if "longitude" in ds else None
    if lat is not None and "latitude" in qc_dict:
        bad_lat = np.isfinite(lat) & (np.abs(lat) > 90)
        flagged += _raise_flag(qc_dict["latitude"], bad_lat, 4)
    if lon is not None and "longitude" in qc_dict:
        bad_lon = np.isfinite(lon) & (np.abs(lon) > 180)
        flagged += _raise_flag(qc_dict["longitude"], bad_lon, 4)
    return flagged


def test_impossible_speed(ds, qc_dict, max_speed_ms=3.0):
    """
    Flag both endpoints of any GPS leg implying an impossible speed.

    Judged as 'probably bad' (3): one bad fix in a pair makes the leg suspect
    but does not identify which of the two positions is at fault.
    """
    lat = ds["latitude"].values if "latitude" in ds else None
    lon = ds["longitude"].values if "longitude" in ds else None
    if lat is None or lon is None:
        return 0
    time_s = ds.time.values.astype("datetime64[s]").astype(float)
    valid = np.isfinite(lat) & np.isfinite(lon) & np.isfinite(time_s)
    if np.sum(valid) < 2:
        return 0
    lat_v = lat[valid]
    lon_v = lon[valid]
    t_v = time_s[valid]
    dlat = np.diff(lat_v) * 111320
    dlon = np.diff(lon_v) * 111320 * np.cos(np.radians(float(np.mean(lat_v))))
    dist = np.sqrt(dlat**2 + dlon**2)
    dt = np.diff(t_v)
    dt[dt <= 0] = 1.0
    speed = dist / dt
    bad_speed = speed > max_speed_ms
    if not np.any(bad_speed):
        return 0

    # Mark both endpoints of every offending leg. Building one mask instead of
    # assigning per pair keeps consecutive bad legs from being counted twice.
    valid_idx = np.where(valid)[0]
    leg = np.where(bad_speed)[0]
    bad = np.zeros(len(qc_dict[next(iter(qc_dict))]), dtype=bool)
    bad[valid_idx[leg]] = True
    bad[valid_idx[leg + 1]] = True

    for var in qc_dict:
        _raise_flag(qc_dict[var], bad, 3)
    return int(np.count_nonzero(bad))


def test_global_range(ds, qc_dict):
    ranges = {
        "temperature": (-2.5, 40.0),
        "salinity": (2.0, 41.0),
        "pressure": (-5.0, 2000.0),
        "oxygen_concentration": (-5.0, 500.0),
        "chlorophyll": (-0.5, 50.0),
        "cdom": (-5.0, 375.0),
        "backscatter_700": (-0.01, 0.1),
        "density": (1000.0, 1060.0),
    }
    flagged = 0
    for var, (vmin, vmax) in ranges.items():
        if var not in ds:
            continue
        vals = ds[var].values
        bad = (vals < vmin) | (vals > vmax)
        n_bad = int(np.sum(bad))
        if var in qc_dict:
            _raise_flag(qc_dict[var], bad, 4)
        if var == "pressure" and n_bad > 0:
            pres_bad = vals < -5.0
            for v2 in ["temperature", "salinity"]:
                if v2 in qc_dict:
                    _raise_flag(qc_dict[v2], pres_bad, 4)
        flagged += n_bad
    return flagged


def test_pressure_increasing(ds, qc_dict, reversal_threshold=50.0):
    """
    Flag genuine pressure reversals within profiles.

    Threshold increased to 50 dbar (from 20) because small jitter during
    profile inflection is normal for Slocum gliders and doesn't invalidate
    measurements. Only flag genuine reversals.

    Flags pressure as "probably bad" (3) — NOT bad (4) — since the T/S
    readings at these points may still be valid. The cascade step handles
    propagation only for truly impossible pressure values.
    """
    if "pressure" not in ds:
        return 0
    p = ds["pressure"].values.copy()
    valid = np.isfinite(p)
    if np.sum(valid) < 10:
        return 0
    profile_index = ds["profile_index"].values if "profile_index" in ds else np.zeros(len(p))
    profiles = np.unique(profile_index[valid])
    bad = np.zeros(len(p), dtype=bool)
    for prof in profiles:
        prof_mask = (profile_index == prof) & valid
        prof_idx = np.where(prof_mask)[0]
        if len(prof_idx) < 4:
            continue
        mid = len(prof_idx) // 2
        segment = prof_idx[:mid][::-1]
        if len(segment) > 1:
            p_seg = p[segment]
            running_min = p_seg[0]
            for i in range(1, len(segment)):
                if p_seg[i] >= running_min + reversal_threshold:
                    bad[segment[i]] = True
                running_min = min(running_min, p_seg[i])
        segment = prof_idx[mid:]
        if len(segment) > 1:
            p_seg = p[segment]
            running_max = p_seg[0]
            for i in range(1, len(segment)):
                if p_seg[i] <= running_max - reversal_threshold:
                    bad[segment[i]] = True
                running_max = max(running_max, p_seg[i])
    n_bad = int(np.sum(bad))
    if "pressure" in qc_dict:
        # Flag as "probably bad" (3), not "bad" (4) — pressure jitter
        # doesn't invalidate the measurement, just the depth assignment.
        # _raise_flag keeps any harsher verdict already set by test 6.
        _raise_flag(qc_dict["pressure"], bad, 3)
    return n_bad


def test_spike(ds, qc_dict):
    spike_thresholds = {
        "temperature": {"shallow": 2.0, "deep": 1.0},
        "salinity": {"shallow": 0.3, "deep": 0.1},
        "pressure": {"shallow": 20.0, "deep": 20.0},
        "oxygen_concentration": {"shallow": 50.0, "deep": 50.0},
    }
    pvals = ds["pressure"].values if "pressure" in ds else None
    profile_index = ds["profile_index"].values if "profile_index" in ds else np.zeros(len(ds.time))
    total_flagged = 0
    for var, thresh in spike_thresholds.items():
        if var not in ds:
            continue
        vals = ds[var].values
        bad = np.zeros(len(vals), dtype=bool)
        profiles = np.unique(profile_index[np.isfinite(profile_index)])
        for prof in profiles:
            prof_mask = (profile_index == prof)
            prof_idx = np.where(prof_mask)[0]
            if len(prof_idx) < 3:
                continue
            for i in range(1, len(prof_idx) - 1):
                idx_prev = prof_idx[i - 1]
                idx_curr = prof_idx[i]
                idx_next = prof_idx[i + 1]
                v1 = vals[idx_prev]
                v2 = vals[idx_curr]
                v3 = vals[idx_next]
                if not (np.isfinite(v1) and np.isfinite(v2) and np.isfinite(v3)):
                    continue
                spike = abs(v2 - (v3 + v1) / 2.0) - abs((v3 - v1) / 2.0)
                if pvals is not None:
                    th = thresh["shallow"] if pvals[idx_curr] < 500 else thresh["deep"]
                else:
                    th = thresh["shallow"]
                if spike > th:
                    bad[idx_curr] = True
        n_bad = int(np.sum(bad))
        if var in qc_dict:
            _raise_flag(qc_dict[var], bad, 4)
        total_flagged += n_bad
    return total_flagged


def test_stuck_value(ds, qc_dict, run_length=10):
    stuck_exempt = {"chlorophyll", "cdom", "backscatter_700"}
    total_flagged = 0
    for var in ["temperature", "salinity", "pressure", "oxygen_concentration", "density"]:
        if var not in ds or var in stuck_exempt:
            continue
        vals = ds[var].values
        n = len(vals)
        if n < run_length + 1:
            continue
        diffs = np.diff(vals)
        zero_diffs = np.concatenate([[False], diffs == 0])
        kernel = np.ones(run_length)
        runs = np.convolve(zero_diffs.astype(float), kernel, mode="same")
        bad = runs >= run_length
        bad[:run_length] = False
        bad[-run_length:] = False
        n_bad = int(np.sum(bad))
        if var in qc_dict:
            _raise_flag(qc_dict[var], bad, 4)
        total_flagged += n_bad
    return total_flagged


def test_density_inversion(ds, qc_dict, threshold=0.03):
    if not HAS_GSW:
        return 0
    if not all(v in ds for v in ["temperature", "salinity", "pressure"]):
        return 0
    T = ds["temperature"].values
    SP = ds["salinity"].values
    P = ds["pressure"].values
    profile_index = ds["profile_index"].values if "profile_index" in ds else np.zeros_like(T)
    lat_m = float(np.nanmean(ds["latitude"].values)) if "latitude" in ds else 12.0
    lon_m = float(np.nanmean(ds["longitude"].values)) if "longitude" in ds else 75.0
    with np.errstate(invalid="ignore"):
        SA = gsw.SA_from_SP(SP, P, lon_m, lat_m)
        CT = gsw.CT_from_t(SA, T, P)
        sigma0 = gsw.sigma0(SA, CT)
    inv_mask = np.zeros(len(sigma0), dtype=bool)
    profiles = np.unique(profile_index[np.isfinite(profile_index)])
    for prof in profiles:
        prof_mask = (profile_index == prof)
        prof_idx = np.where(prof_mask)[0]
        if len(prof_idx) < 2:
            continue
        for i in range(len(prof_idx) - 1):
            idx_curr = prof_idx[i]
            idx_next = prof_idx[i + 1]
            dp = P[idx_next] - P[idx_curr]
            dsig = sigma0[idx_next] - sigma0[idx_curr]
            if np.isfinite(dp) and np.isfinite(dsig):
                if dp > 1 and dsig < -threshold:
                    inv_mask[idx_curr] = True
                if dp < -1 and dsig > threshold:
                    inv_mask[idx_curr] = True
    n_bad = int(np.sum(inv_mask))
    for v in ["temperature", "salinity", "density"]:
        if v in qc_dict:
            _raise_flag(qc_dict[v], inv_mask, 4)
    return n_bad


def test_gross_sensor_drift(ds, qc_dict):
    """
    Detect gross sensor drift by comparing deep-water means between consecutive
    profiles. Uses a sliding window of 5 profiles to compute running baseline,
    making it robust to real horizontal gradients (eddies, fronts).

    Thresholds raised and flags set to "probably bad" (3) instead of "bad" (4)
    because gliders traverse real ocean variability. Only flag when the jump
    is clearly beyond natural variability.
    """
    if "profile_index" not in ds:
        return 0
    profile_index = ds["profile_index"].values
    depth = ds["depth"].values if "depth" in ds else ds["pressure"].values
    profiles = np.sort(np.unique(profile_index[np.isfinite(profile_index)]))
    if len(profiles) < 2:
        return 0
    flagged = 0
    deep_means_s = {}
    deep_means_t = {}
    for p in profiles:
        p_mask = (profile_index == p)
        p_depth = depth[p_mask]
        p_valid = np.isfinite(p_depth)
        if "salinity" in ds:
            p_sal = ds["salinity"].values[p_mask]
            deep_mask = p_valid & np.isfinite(p_sal) & (p_depth > np.nanmax(p_depth) - 100)
            if np.sum(deep_mask) >= 3:
                deep_means_s[p] = np.nanmean(p_sal[deep_mask])
        if "temperature" in ds:
            p_temp = ds["temperature"].values[p_mask]
            deep_mask = p_valid & np.isfinite(p_temp) & (p_depth > np.nanmax(p_depth) - 100)
            if np.sum(deep_mask) >= 3:
                deep_means_t[p] = np.nanmean(p_temp[deep_mask])

    # Use sliding window of 5 profiles to compute running baseline
    # This prevents flagging due to real gradual environmental changes
    window_size = 5

    prof_list = sorted(deep_means_s.keys())
    means_s_arr = np.array([deep_means_s[p] for p in prof_list])
    for i in range(window_size, len(prof_list)):
        p_curr = prof_list[i]
        # Compare against median of previous window_size profiles
        window_med = np.median(means_s_arr[max(0, i - window_size):i])
        delta_s = abs(means_s_arr[i] - window_med)
        if delta_s > 1.5:  # raised threshold — real ocean has gradients
            p_mask = (profile_index == p_curr)
            if "salinity" in qc_dict:
                _raise_flag(qc_dict["salinity"], p_mask, 3)
            flagged += int(np.sum(p_mask))

    prof_list_t = sorted(deep_means_t.keys())
    means_t_arr = np.array([deep_means_t[p] for p in prof_list_t])
    for i in range(window_size, len(prof_list_t)):
        p_curr = prof_list_t[i]
        window_med = np.median(means_t_arr[max(0, i - window_size):i])
        delta_t = abs(means_t_arr[i] - window_med)
        if delta_t > 4.0:  # raised threshold — gliders cross thermal fronts
            p_mask = (profile_index == p_curr)
            if "temperature" in qc_dict:
                _raise_flag(qc_dict["temperature"], p_mask, 3)
            flagged += int(np.sum(p_mask))
    return flagged


def test_deepest_pressure(ds, qc_dict, config_pressure_dbar=1000.0):
    if "pressure" not in ds:
        return 0
    p = ds["pressure"].values
    if config_pressure_dbar <= 10:
        tolerance_pct = 150.0
    elif config_pressure_dbar <= 1000:
        tolerance_pct = 150.0 - (config_pressure_dbar - 10) * (140.0 / 990.0)
    else:
        tolerance_pct = 10.0
    if config_pressure_dbar > 1000:
        tolerance = 100.0
    else:
        tolerance = config_pressure_dbar * tolerance_pct / 100.0
    threshold = config_pressure_dbar + tolerance
    bad = p > threshold
    n_bad = int(np.sum(bad))
    if n_bad > 0:
        for var in ("pressure", "temperature", "salinity"):
            if var in qc_dict:
                _raise_flag(qc_dict[var], bad, 3)
    return n_bad


def pressure_cascade(ds, qc_dict):
    """
    Cascade ONLY truly impossible pressure values (QC=4 from global range test)
    to other variables. Do NOT cascade pressure-increasing flags (QC=3) — a
    small pressure jitter during profile inflection doesn't invalidate the
    temperature or oxygen readings at that point.

    Only pressure Bad (4) and Missing (9) propagate to T/S/O2.
    """
    if "pressure" not in qc_dict:
        return 0
    # Only cascade Bad (4) from global_range, not probably_bad (3) from
    # pressure_increasing. Missing (9) also cascades.
    pres_bad = (qc_dict["pressure"] == 4) | (qc_dict["pressure"] == 9)
    n_casc = 0
    # Only cascade to physical variables that depend on pressure for context
    cascade_vars = ["temperature", "salinity", "oxygen_concentration", "density",
                    "chlorophyll", "cdom", "backscatter_700"]
    for var in cascade_vars:
        if var not in qc_dict:
            continue
        # _raise_flag skips positions already at 4 (no change) and at 9
        # (missing stays missing), which is exactly the old guard.
        n_casc += _raise_flag(qc_dict[var], pres_bad, 4)
    return n_casc


def apply_argo_qc(ds, config_pressure_dbar=1000.0, l0_nan_mask=None):
    """
    Apply ARGO QC flags.

    l0_nan_mask : dict {var: boolean array} of NaN positions in the original
                  L0 data, captured BEFORE physics QC ran. Used to distinguish
                  "originally missing" (flag 9) from "nulled by QC tests"
                  (flag 4). If None, falls back to current NaN positions
                  (legacy behaviour — may incorrectly flag QC-nulled values
                  as Miss instead of Bad).
    """
    print("  Applying ARGO QC Flags (Manual v3.9)...")
    vars_to_qc = [
        "temperature", "salinity", "pressure", "oxygen_concentration",
        "chlorophyll", "cdom", "backscatter_700", "density",
        "latitude", "longitude",
    ]
    qc_dict = {}
    n = len(ds.time)
    for var in vars_to_qc:
        if var not in ds:
            continue
        qc = np.ones(n, dtype=np.int8)

        current_nan = np.isnan(ds[var].values)

        if l0_nan_mask is not None and var in l0_nan_mask:
            # Points that were NaN in the original L0 → truly missing (flag 9)
            orig_missing = l0_nan_mask[var]
            # Points that are NaN now but were NOT NaN in L0 → nulled by QC → flag 4
            qc_nulled = current_nan & ~orig_missing
            qc[orig_missing] = 9
            qc[qc_nulled]    = 4
        else:
            # Fallback: treat all current NaNs as missing
            qc[current_nan] = 9

        qc_dict[var] = qc

    n2 = test_impossible_date(ds, qc_dict)
    if n2 > 0:
        print(f"   Test 2  (Impossible date):    flagged {n2}")
    n3 = test_impossible_location(ds, qc_dict)
    if n3 > 0:
        print(f"   Test 3  (Impossible location): flagged {n3}")
    n5 = test_impossible_speed(ds, qc_dict)
    if n5 > 0:
        print(f"   Test 5  (Impossible speed):    flagged {n5}")
    n6 = test_global_range(ds, qc_dict)
    print(f"   Test 6  (Global range):          flagged {n6}")
    n8 = test_pressure_increasing(ds, qc_dict)
    if n8 > 0:
        print(f"   Test 8  (Pressure increasing): flagged {n8}")
    n9 = test_spike(ds, qc_dict)
    print(f"   Test 9  (Spike test):            flagged {n9}")
    n13 = test_stuck_value(ds, qc_dict)
    if n13 > 0:
        print(f"   Test 13 (Stuck value):         flagged {n13}")
    n14 = test_density_inversion(ds, qc_dict)
    if n14 > 0:
        print(f"   Test 14 (Density inversion):   flagged {n14}")
    n16 = test_gross_sensor_drift(ds, qc_dict)
    if n16 > 0:
        print(f"   Test 16 (Gross sensor drift):  flagged {n16}")
    n19 = test_deepest_pressure(ds, qc_dict, config_pressure_dbar)
    if n19 > 0:
        print(f"   Test 19 (Deepest pressure):    flagged {n19}")
    nc = pressure_cascade(ds, qc_dict)
    if nc > 0:
        print(f"   Cascade (PRES_QC=4 -> T/S/O2/optics): flagged {nc}")

    if "temperature" in qc_dict and "salinity" in qc_dict:
        # ARGO 2.1.4b: salinity is derived from conductivity *and* temperature,
        # so a bad temperature invalidates the salinity computed with it, and a
        # missing temperature makes that salinity unobtainable.
        t_qc = qc_dict["temperature"]
        n_tc = _raise_flag(qc_dict["salinity"], t_qc == 4, 4)
        m_cascade = (t_qc == 9) & (qc_dict["salinity"] != 9)
        n_tm = int(np.sum(m_cascade))
        qc_dict["salinity"][m_cascade] = 9
        if n_tc + n_tm > 0:
            print(f"   Cascade (TEMP_QC -> SAL_QC):   flagged {n_tc + n_tm} (bad:{n_tc}, miss:{n_tm})")

    for var, qc in qc_dict.items():
        ds[f"{var}_QC"] = xr.DataArray(qc, dims=["time"])

    qc_attrs = {
        "long_name": "Quality flag",
        "standard_name": "status_flag",
        "flag_values": np.array([1, 2, 3, 4, 9], dtype=np.int8),
        "flag_meanings": "good probably_good probably_bad bad missing",
        "conventions": "ARGO Reference Table 2",
    }
    for var in list(ds.data_vars):
        if var.endswith("_QC"):
            ds[var].attrs.update(qc_attrs)

    return ds


# ============================================================
# MAIN ENTRY POINT
# ============================================================

def run_step23(l0_path=None, out_dir=None):
    """
    Apply QC and ARGO RTQC flags, writing the L1 timeseries.

    out_dir : directory to write the L1 into. Defaults to config.OUTPUT_DIR.
              Passed explicitly rather than read from a module global that the
              caller mutates after import — see run_step1 for the same reason.
    """
    print("=" * 60)
    print("  STEP 2/3: L0 -> L1 (QC + ARGO flags)")
    print("=" * 60)
    t0 = time.time()

    if l0_path is None:
        l0_path = os.path.join(OUTPUT_DIR, f"incois_glider_{GLIDER_ID}_L0.nc")

    if not os.path.exists(l0_path):
        print(f"ERROR: L0 file not found: {l0_path}")
        sys.exit(1)

    print(f"  Loading L0: {l0_path}")
    ds = xr.open_dataset(l0_path)
    print(f"  Observations: {len(ds.time):,}")
    print(f"  Variables: {len(ds.data_vars)}")

    ds = pre_clean(ds)

    # Snapshot which positions are NaN RIGHT NOW — after pre-clean (time-crop,
    # depth-segmentation) but BEFORE detect_variable_corruption or any QC runs.
    # This is the ground truth for "originally missing" vs "removed by QC".
    # CRITICAL: must happen before detect_variable_corruption, which may null
    # entire variables if they're corrupted — we want those nulled points to
    # show as Bad (flag 4), not Miss (flag 9).
    l0_nan_mask = {}
    for var in ["temperature", "salinity", "pressure", "oxygen_concentration",
                "chlorophyll", "cdom", "backscatter_700", "density",
                "latitude", "longitude"]:
        if var in ds:
            l0_nan_mask[var] = np.isnan(ds[var].values).copy()

    ds = detect_variable_corruption(ds)
    ds = apply_optics_correction(ds)
    ds = apply_physics_qc(ds)
    ds = oxygen_lag_correction(ds)
    ds = apply_argo_qc(ds, config_pressure_dbar=MAX_DEPTH_DBAR,
                       l0_nan_mask=l0_nan_mask)

    # ── Build canonical-format L1 output ────────────────────────────────────
    import nc_format

    t_sec = ds["time"].values.astype("datetime64[s]").astype(np.float64)
    n = len(t_sec)

    # Science parameter values — use canonical names
    # The L0 already uses canonical names (TEMP, PSAL, etc.) since step1 now
    # writes them directly. Map back via nc_format.
    _canon = nc_format.params()
    _old_to_new = {
        "temperature": "TEMP", "salinity": "PSAL", "pressure": "PRES",
        "conductivity": "CNDC", "oxygen_concentration": "DOXY",
        "chlorophyll": "CHLA", "cdom": "CDOM", "backscatter_700": "BBP700",
        "turbidity": "TURBIDITY",
    }
    values = {}
    for old, new in _old_to_new.items():
        if new in ds:          # L0 already wrote canonical names
            values[new] = ds[new].values.astype(np.float32)
        elif old in ds:        # fallback for older L0 files
            values[new] = ds[old].values.astype(np.float32)

    # QC flags — map from internal QC var names to canonical names
    _qc_old_to_new = {
        "temperature_QC": "TEMP", "salinity_QC": "PSAL",
        "pressure_QC": "PRES", "conductivity_QC": "CNDC",
        "oxygen_concentration_QC": "DOXY",
        "chlorophyll_QC": "CHLA", "cdom_QC": "CDOM",
        "backscatter_700_QC": "BBP700",
    }
    qc = {}
    for old_qc, new in _qc_old_to_new.items():
        if old_qc in ds:
            qc[new] = ds[old_qc].values.astype(np.int8)
        elif new + "_QC" in ds:
            qc[new] = ds[new + "_QC"].values.astype(np.int8)

    # Adjusted (processed/corrected) values
    _adj_map = {
        "TEMP":   ("temperature_processed",),
        "PSAL":   ("salinity_processed",),
        "DOXY":   ("oxygen_concentration_lag_corrected",),
        "CHLA":   ("chlorophyll_corrected",),
        "CDOM":   ("cdom_corrected",),
        "BBP700": ("backscatter_700_corrected",),
    }
    adjusted = {}
    for canonical, candidates in _adj_map.items():
        for src in candidates:
            if src in ds:
                adjusted[canonical] = ds[src].values.astype(np.float32)
                break

    # Ancillary variables
    _anc_map = {
        "LATITUDE": ["LATITUDE", "latitude"],
        "LONGITUDE": ["LONGITUDE", "longitude"],
        "DEPTH": ["DEPTH", "depth"],
        "DENSITY": ["DENSITY", "density"],
        "POTENTIAL_TEMP": ["POTENTIAL_TEMP", "potential_temperature"],
        "POTENTIAL_DENSITY": ["POTENTIAL_DENSITY", "potential_density"],
        "HEADING": ["HEADING", "heading"],
        "PITCH": ["PITCH", "pitch"],
        "ROLL": ["ROLL", "roll"],
        "WAYPOINT_LATITUDE": ["WAYPOINT_LATITUDE", "waypoint_latitude"],
        "WAYPOINT_LONGITUDE": ["WAYPOINT_LONGITUDE", "waypoint_longitude"],
        "DISTANCE_OVER_GROUND": ["DISTANCE_OVER_GROUND", "distance_over_ground"],
    }
    anc = {}
    for canon_name, candidates in _anc_map.items():
        for src in candidates:
            if src in ds:
                anc[canon_name] = ds[src].values
                break

    # GPS surface fixes from the ancillary lat/lon + profile_index
    _pi = (ds["profile_index"].values if "profile_index" in ds
           else ds["PROFILE_NUMBER"].values if "PROFILE_NUMBER" in ds
           else None)
    _lat = anc.get("LATITUDE")
    _lon = anc.get("LONGITUDE")
    if _pi is not None and _lat is not None and _lon is not None:
        ft, flat, flon = [], [], []
        for p in np.unique(_pi[np.isfinite(_pi)]):
            m = (_pi == p) & np.isfinite(_lat) & np.isfinite(_lon)
            if m.any():
                i = np.flatnonzero(m)[0]
                ft.append(t_sec[i]); flat.append(_lat[i]); flon.append(_lon[i])
        gps = (np.array(ft), np.array(flat), np.array(flon))
    else:
        gps = (None, None, None)

    # Phase
    _pd = (ds["profile_direction"].values if "profile_direction" in ds
           else ds["PHASE"].values if "PHASE" in ds else None)
    phase = np.full(n, np.int8(6), dtype=np.int8)
    if _pd is not None:
        finite = np.isfinite(_pd)
        phase[finite & (_pd > 0)] = np.int8(1)
        phase[finite & (_pd < 0)] = np.int8(4)
        phase[finite & (_pd == 0)] = np.int8(2)
    _pi2 = _pi if _pi is not None else np.full(n, nc_format.FILL_INT)
    phase_number = np.where(np.isfinite(_pi2), _pi2, nc_format.FILL_INT).astype(np.int32)

    # Load deployment meta for global attrs
    meta_cfg = {}
    try:
        if os.path.exists(DEPLOY_YAML):
            import yaml as _yaml
            with open(DEPLOY_YAML) as _f:
                _yml = _yaml.safe_load(_f) or {}
            meta_cfg = _yml.get("metadata", {})
    except Exception:
        pass
    if not meta_cfg.get("glider_serial"):
        meta_cfg["glider_serial"] = GLIDER_ID

    ds_out, written = nc_format.build_dataset(
        time_sec=t_sec,
        values=values,
        ancillary_values=anc,
        gps=gps,
        phase=phase,
        phase_number=phase_number,
        meta=meta_cfg,
        level="L1",
        qc=qc,
        adjusted=adjusted,
        rtqc_tests="TEST002 TEST003 TEST005 TEST006 TEST008 TEST009 TEST013 TEST014 TEST016 TEST019",
    )

    if out_dir is None:
        out_dir = OUTPUT_DIR
    os.makedirs(out_dir, exist_ok=True)
    l1_path = os.path.join(out_dir, f"incois_glider_{GLIDER_ID}_L1.nc")
    print(f"\n  Saving L1: {l1_path}")
    nc_format.write(ds_out, l1_path)

    elapsed = time.time() - t0
    print(f"\n  L1 saved: {os.path.getsize(l1_path) / 1024 / 1024:.1f} MB")
    print(f"  Parameters: {', '.join(written)}")
    print(f"  QC Flag Summary:")
    for canonical in written:
        qc_var = f"{canonical}_QC"
        if qc_var in ds_out:
            q = ds_out[qc_var].values.astype(int)
            good     = int(np.sum(q == 1))
            prob_bad = int(np.sum(q == 3))
            bad      = int(np.sum(q == 4))
            missing  = int(np.sum(q == 9))
            pct_good = 100.0 * good / len(q) if len(q) > 0 else 0
            print(f"    {qc_var:40s} Good:{good:>8,} ({pct_good:5.1f}%)  "
                  f"PBad:{prob_bad:>6,}  Bad:{bad:>6,}  Miss:{missing:>6,}")

    ds.close()
    ds_out.close()
    print(f"\n  STEP 2/3 COMPLETE in {elapsed:.1f}s")
    return l1_path


if __name__ == "__main__":
    import argparse
    _p = argparse.ArgumentParser(description="L0 -> L1 QC + ARGO RTQC flags")
    _p.add_argument("l0_path", nargs="?", default=None,
                    help="L0 NetCDF (default: <OUTPUT_DIR>/incois_glider_<ID>_L0.nc)")
    _p.add_argument("--out-dir", default=None,
                    help="Directory for the L1 NetCDF "
                         "(default: config.OUTPUT_DIR)")
    _a = _p.parse_args()
    run_step23(_a.l0_path, out_dir=_a.out_dir)
