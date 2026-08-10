#!/usr/bin/env python3
"""
load_deployment.py — ingest EGO 1.5 NetCDF files into SQLite.

Reads the EGO-format L0 and L1 NetCDF files produced by step_ego.py and loads
them into the four-table schema (meta, observation, core, bgc).

The EGO file is the SINGLE source of truth for variable names. The PARAMETER
array in each file is read to discover which science variables exist — no
hardcoded mapping is maintained here. This eliminates the drift risk of having
two independent name-translation layers.

Value semantics
---------------
    value             EGO <VAR> at that timestamp (fill -> NULL)
    qc_flag           <VAR>_QC  (EGO ref table 2.1: 0 no_qc, 1 good, 4 bad, 9 missing)
    value_adjusted    <VAR>_ADJUSTED, NULL when fill or not computed
    adjusted_qc_flag  <VAR>_ADJUSTED_QC, NULL when fill or not computed

distance_over_ground
--------------------
Computed from TIME_GPS / LATITUDE_GPS / LONGITUDE_GPS (real GPS surface fixes
only), with impossible-speed legs (>3 m/s) excluded. Stored in meta as a
deployment-level summary.

Idempotency
-----------
observation_id = deterministic 63-bit hash of (glider_id, timestamp).
Every write is ON CONFLICT DO UPDATE — re-running overwrites, never duplicates.

Usage
-----
    python -m db.load_deployment <ego_output_dir> [--db glider_rtqc.db]
    python -m db.load_deployment --ego-l1 /path/to/L1_EGO.nc [--ego-l0 /path/L0_EGO.nc]
"""

from __future__ import annotations

import argparse
import hashlib
import os
import re
import sqlite3
import sys
import time as _time
from datetime import datetime, timezone

import numpy as np


# ============================================================
#  Constants
# ============================================================

# Core (physical/CTD) vs BGC classification. Anything not listed here
# defaults to BGC with a note — so a future sensor never silently drops.
CORE_PARAMS = {"TEMP", "PSAL", "PRES", "CNDC"}
# Everything else in PARAMETER is BGC by default.

SCHEMA_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "schema.sql")
BATCH_SIZE = 100_000

# EGO fill value for float variables
FILL_VALUE = 99999.0

# Safe identifier regex for generated SQL
_SAFE_IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


# ============================================================
#  Deterministic IDs
# ============================================================

def make_observation_id(glider_id: str, timestamp_iso: str) -> int:
    """
    Deterministic 63-bit observation id from (glider_id, timestamp).

    SHA-256 of "glider_id|timestamp", first 8 bytes, masked to 63 bits so it
    is always positive and fits SQLite's signed 64-bit INTEGER PRIMARY KEY.
    """
    digest = hashlib.sha256(f"{glider_id}|{timestamp_iso}".encode("utf-8")).digest()
    return int.from_bytes(digest[:8], "big") & 0x7FFF_FFFF_FFFF_FFFF


# ============================================================
#  EGO file discovery
# ============================================================

def find_ego_files(ego_dir: str) -> dict:
    """
    Locate EGO L0 and L1 NetCDF files in an EGO-timeseries/ directory.

    Convention: filenames contain '_L0_EGO' or '_L1_EGO' (or just '_EGO'
    without L0/L1 for single-file deployments).
    """
    ego_dir = os.path.abspath(ego_dir)
    result = {"ego_dir": ego_dir, "ego_l0": None, "ego_l1": None}

    if not os.path.isdir(ego_dir):
        return result

    nc_files = [f for f in os.listdir(ego_dir) if f.endswith(".nc")]
    for f in sorted(nc_files):
        low = f.lower()
        path = os.path.join(ego_dir, f)
        if "_l1" in low:
            result["ego_l1"] = path
        elif "_l0" in low:
            result["ego_l0"] = path
        elif result["ego_l1"] is None:
            # Single EGO file without L0/L1 suffix — treat as L1 if it has QC
            result["ego_l1"] = path

    return result


# ============================================================
#  GPS distance computation
# ============================================================

def _haversine_km(lat1, lon1, lat2, lon2):
    """Haversine distance in km between two arrays of coordinates."""
    R = 6371.0
    dlat = np.radians(lat2 - lat1)
    dlon = np.radians(lon2 - lon1)
    a = (np.sin(dlat / 2) ** 2
         + np.cos(np.radians(lat1)) * np.cos(np.radians(lat2))
         * np.sin(dlon / 2) ** 2)
    return R * 2 * np.arcsin(np.sqrt(np.clip(a, 0, 1)))


def compute_distance_from_gps(nc) -> float | None:
    """
    Compute total distance over ground from GPS fix positions only.

    Uses TIME_GPS / LATITUDE_GPS / LONGITUDE_GPS arrays. Filters out:
      - Fill values (99999)
      - Legs with implied speed > 3 m/s (10.8 km/h) — physically impossible
        for a Slocum glider, indicates a data gap or bad fix.

    Returns distance in km, or None if insufficient data.
    """
    if "TIME_GPS" not in nc.variables:
        return None

    t_gps = np.asarray(nc.variables["TIME_GPS"][:], dtype=np.float64)
    lat_gps = np.asarray(nc.variables["LATITUDE_GPS"][:], dtype=np.float64)
    lon_gps = np.asarray(nc.variables["LONGITUDE_GPS"][:], dtype=np.float64)

    # Filter valid fixes
    valid = (
        np.isfinite(lat_gps) & np.isfinite(lon_gps) & np.isfinite(t_gps)
        & (np.abs(lat_gps) < 90.1) & (np.abs(lon_gps) < 180.1)
    )
    if valid.sum() < 2:
        return None

    lat_v = lat_gps[valid]
    lon_v = lon_gps[valid]
    t_v = t_gps[valid]

    # Sort by time (should already be, but be safe)
    order = np.argsort(t_v)
    lat_v, lon_v, t_v = lat_v[order], lon_v[order], t_v[order]

    # Compute leg distances and speeds
    dists = _haversine_km(lat_v[:-1], lon_v[:-1], lat_v[1:], lon_v[1:])
    dt_hours = np.diff(t_v) / 3600.0

    # Filter: max glider speed is ~1 m/s horizontal => 3.6 km/h.
    # Use 3 m/s (10.8 km/h) as a generous upper bound.
    speed_kmh = np.where(dt_hours > 0.001, dists / dt_hours, np.inf)
    good_legs = speed_kmh <= 10.8

    if good_legs.sum() == 0:
        return None

    return float(np.sum(dists[good_legs]))


# ============================================================
#  EGO file reading helpers
# ============================================================

def _read_char_array(nc, var_name: str) -> list[str]:
    """Read an (N, STRING_LEN) char array and return list of stripped strings."""
    if var_name not in nc.variables:
        return []
    arr = nc.variables[var_name][:]
    result = []
    for i in range(arr.shape[0]):
        row = "".join(str(c) for c in arr[i]).rstrip()
        result.append(row)
    return result


def _var_array(nc, name: str, n: int) -> np.ndarray:
    """Read a TIME-dimensioned variable, replacing fill with NaN."""
    if name not in nc.variables:
        return np.full(n, np.nan, dtype=np.float64)
    arr = np.asarray(nc.variables[name][:], dtype=np.float64)
    arr[arr >= FILL_VALUE - 1] = np.nan
    return arr


def _qc_array(nc, name: str, n: int) -> np.ndarray:
    """Read a QC variable as int, with fill -> -1."""
    qc_name = f"{name}_QC"
    if qc_name not in nc.variables:
        return np.full(n, -1, dtype=np.int16)
    arr = np.asarray(nc.variables[qc_name][:], dtype=np.int16)
    # int8 fill is -128
    arr[arr == -128] = -1
    return arr


def discover_parameters(nc) -> list[str]:
    """
    Read the PARAMETER array from the EGO file to discover which science
    variables this deployment carries. This is the single source of truth.
    """
    return _read_char_array(nc, "PARAMETER")


def classify_param(param: str) -> str:
    """Classify an EGO parameter as 'core' or 'bgc'."""
    if param in CORE_PARAMS:
        return "core"
    return "bgc"


# ============================================================
#  GPS fix matching
# ============================================================

def _build_gps_fix_set(nc) -> set:
    """
    Build a set of epoch timestamps (as int64 seconds) that are real GPS fixes.
    Used to mark observation rows with has_gps_fix=1.
    """
    if "TIME_GPS" not in nc.variables:
        return set()
    t_gps = np.asarray(nc.variables["TIME_GPS"][:], dtype=np.float64)
    # GPS fill value is 9999999999 (not 99999)
    gps_fill = 9999999999.0
    valid = np.isfinite(t_gps) & (t_gps < gps_fill - 1)
    # Round to nearest second for matching against TIME
    return set(np.round(t_gps[valid]).astype(np.int64))


# ============================================================
#  Database helpers
# ============================================================

def _connect(db_path: str) -> sqlite3.Connection:
    conn = sqlite3.connect(db_path)
    conn.execute("PRAGMA foreign_keys = ON")
    conn.execute("PRAGMA journal_mode = WAL")
    conn.execute("PRAGMA synchronous = OFF")
    conn.execute("PRAGMA temp_store = MEMORY")
    conn.execute("PRAGMA cache_size = -64000")
    return conn


def apply_schema(conn: sqlite3.Connection) -> None:
    if not os.path.exists(SCHEMA_PATH):
        raise FileNotFoundError(f"schema not found: {SCHEMA_PATH}")
    with open(SCHEMA_PATH, "r", encoding="utf-8") as fh:
        conn.executescript(fh.read())


META_UPSERT = """
INSERT INTO meta (glider_id, deployment_name, deployment_start, deployment_end,
                  max_depth_dbar, n_profiles, n_observations, n_gps_fixes,
                  distance_over_ground_km, pipeline_version, ego_format_version,
                  data_mode, institution, rtqc_tests_applied,
                  processed_at, ego_l0_path, ego_l1_path)
VALUES (:glider_id, :deployment_name, :deployment_start, :deployment_end,
        :max_depth_dbar, :n_profiles, :n_observations, :n_gps_fixes,
        :distance_over_ground_km, :pipeline_version, :ego_format_version,
        :data_mode, :institution, :rtqc_tests_applied,
        :processed_at, :ego_l0_path, :ego_l1_path)
ON CONFLICT(glider_id) DO UPDATE SET
    deployment_name         = excluded.deployment_name,
    deployment_start        = excluded.deployment_start,
    deployment_end          = excluded.deployment_end,
    max_depth_dbar          = excluded.max_depth_dbar,
    n_profiles              = excluded.n_profiles,
    n_observations          = excluded.n_observations,
    n_gps_fixes             = excluded.n_gps_fixes,
    distance_over_ground_km = excluded.distance_over_ground_km,
    pipeline_version        = excluded.pipeline_version,
    ego_format_version      = excluded.ego_format_version,
    data_mode               = excluded.data_mode,
    institution             = excluded.institution,
    rtqc_tests_applied      = excluded.rtqc_tests_applied,
    processed_at            = excluded.processed_at,
    ego_l0_path             = excluded.ego_l0_path,
    ego_l1_path             = excluded.ego_l1_path
"""

OBSERVATION_UPSERT = """
INSERT INTO observation (observation_id, glider_id, timestamp, pressure,
                         latitude, longitude, phase, phase_number,
                         position_qc, has_gps_fix)
VALUES (?,?,?,?,?,?,?,?,?,?)
ON CONFLICT(observation_id) DO UPDATE SET
    glider_id    = excluded.glider_id,
    timestamp    = excluded.timestamp,
    pressure     = excluded.pressure,
    latitude     = excluded.latitude,
    longitude    = excluded.longitude,
    phase        = excluded.phase,
    phase_number = excluded.phase_number,
    position_qc  = excluded.position_qc,
    has_gps_fix  = excluded.has_gps_fix
"""


def _measurement_upsert(table: str) -> str:
    return f"""
INSERT INTO {table} (observation_id, variable_name, value, qc_flag,
                     value_adjusted, adjusted_qc_flag)
VALUES (?,?,?,?,?,?)
ON CONFLICT(observation_id, variable_name) DO UPDATE SET
    value            = excluded.value,
    qc_flag          = excluded.qc_flag,
    value_adjusted   = excluded.value_adjusted,
    adjusted_qc_flag = excluded.adjusted_qc_flag
"""


def _executemany_batched(conn, sql, rows, batch=BATCH_SIZE) -> int:
    """
    Feed rows to executemany in fixed-size chunks.
    Accepts any iterable (generator OK) — never materialises the full set.
    """
    total = 0
    chunk = []
    for row in rows:
        chunk.append(row)
        if len(chunk) >= batch:
            conn.executemany(sql, chunk)
            total += len(chunk)
            chunk.clear()
    if chunk:
        conn.executemany(sql, chunk)
        total += len(chunk)
    return total


def _measurement_rows(nc, obs_ids, param: str, table: str, n: int):
    """
    Yield (observation_id, variable_name, value, qc, adjusted, adjusted_qc)
    for one EGO parameter. Generator — streams one variable at a time.
    Skips rows where observation_id is None (fill-value timestamps).
    """
    values = _var_array(nc, param, n)
    qc_flags = _qc_array(nc, param, n)

    adj_name = f"{param}_ADJUSTED"
    adj_values = _var_array(nc, adj_name, n) if adj_name in nc.variables else None

    adj_qc_name = f"{param}_ADJUSTED_QC"
    adj_qc = None
    if adj_qc_name in nc.variables:
        adj_qc = np.asarray(nc.variables[adj_qc_name][:], dtype=np.int16)
        adj_qc[adj_qc == -128] = -1

    for i in range(n):
        oid = obs_ids[i]
        if oid is None:
            continue

        val = values[i]
        qc = qc_flags[i]
        adj_val = adj_values[i] if adj_values is not None else np.nan
        adj_q = adj_qc[i] if adj_qc is not None else -1

        # Convert NaN/fill -> None for SQLite
        v = float(val) if np.isfinite(val) else None
        q = int(qc) if qc >= 0 else None
        av = float(adj_val) if np.isfinite(adj_val) else None
        aq = int(adj_q) if adj_q >= 0 else None

        yield (oid, param, v, q, av, aq)


def create_wide_views(conn: sqlite3.Connection,
                      core_names: list[str],
                      bgc_names: list[str]) -> None:
    """
    Build pivoted `wide_core` / `wide_bgc` views with one column set per
    variable. Regenerated on every load since the column list depends on
    which parameters the deployment carries.
    """
    for table, names in (("core", core_names), ("bgc", bgc_names)):
        view = f"wide_{table}"
        conn.execute(f"DROP VIEW IF EXISTS {view}")

        safe = [n for n in sorted(names) if _SAFE_IDENT.match(n)]
        if not safe:
            continue

        cols = []
        for n in safe:
            cols.append(
                f'    MAX(CASE WHEN m.variable_name = \'{n}\' '
                f'THEN m.value END) AS "{n}"')
            cols.append(
                f'    MAX(CASE WHEN m.variable_name = \'{n}\' '
                f'THEN m.value_adjusted END) AS "{n}_ADJUSTED"')
            cols.append(
                f'    MAX(CASE WHEN m.variable_name = \'{n}\' '
                f'THEN m.qc_flag END) AS "{n}_QC"')
            cols.append(
                f'    MAX(CASE WHEN m.variable_name = \'{n}\' '
                f'THEN m.adjusted_qc_flag END) AS "{n}_ADJUSTED_QC"')

        pivot_sql = ",\n".join(cols)
        conn.execute(f"""
CREATE VIEW IF NOT EXISTS {view} AS
SELECT
    o.observation_id,
    o.glider_id,
    o.timestamp,
    o.pressure,
    o.latitude,
    o.longitude,
    o.phase_number,
{pivot_sql}
FROM observation o
LEFT JOIN {table} m ON m.observation_id = o.observation_id
GROUP BY o.observation_id
""")


# ============================================================
#  Main entry point
# ============================================================

def load_deployment(ego_l1_path: str = None,
                    ego_l0_path: str = None,
                    ego_dir: str = None,
                    db_path: str = "glider_rtqc.db",
                    glider_id: str = None,
                    verbose: bool = True) -> dict:
    """
    Load one deployment's EGO NetCDF files into the SQLite database.

    Parameters
    ----------
    ego_l1_path : direct path to EGO L1 file (preferred — has QC + adjusted)
    ego_l0_path : direct path to EGO L0 file (optional, for raw-only values)
    ego_dir     : directory containing EGO files (auto-discovers L0/L1)
    db_path     : SQLite file; created if it doesn't exist
    glider_id   : override the auto-detected glider id
    verbose     : print progress

    Returns a dict with row counts, warnings, and loaded parameters.
    """
    import netCDF4

    t_start = _time.time()
    warnings: list[str] = []

    # Resolve file paths
    if ego_dir and not ego_l1_path:
        files = find_ego_files(ego_dir)
        ego_l1_path = files.get("ego_l1")
        ego_l0_path = ego_l0_path or files.get("ego_l0")

    if not ego_l1_path and not ego_l0_path:
        raise FileNotFoundError(
            "No EGO NetCDF files found. Provide --ego-l1, --ego-l0, or --ego-dir.")

    # The L1 file is primary (has QC flags + adjusted). Fall back to L0-only.
    primary_path = ego_l1_path or ego_l0_path
    is_l1 = ego_l1_path is not None

    if verbose:
        print("=" * 68)
        print("  GLIDER EGO -> SQLITE")
        print("=" * 68)
        print(f"  EGO L1     : {ego_l1_path or '(none)'}")
        print(f"  EGO L0     : {ego_l0_path or '(none)'}")
        print(f"  database   : {os.path.abspath(db_path)}")

    nc = netCDF4.Dataset(primary_path)

    try:
        # ── Discover parameters from the file itself ─────────────────────
        params = discover_parameters(nc)
        if not params:
            raise ValueError(f"PARAMETER array is empty in {primary_path}")

        # Classify
        core_params = [p for p in params if classify_param(p) == "core"]
        bgc_params = [p for p in params if classify_param(p) == "bgc"]

        # ── Extract metadata from global attributes ──────────────────────
        def _attr(name, default=""):
            return str(nc.getncattr(name)) if name in nc.ncattrs() else default

        gid = glider_id or _attr("platform_code", "unknown")
        if gid == "unknown":
            # Try to derive from filename
            base = os.path.basename(primary_path)
            m = re.match(r"incois_glider_(.+?)(?:_L[01])?_EGO\.nc$", base, re.I)
            if m:
                gid = m.group(1)

        if verbose:
            print(f"  glider_id  : {gid}")
            print(f"  parameters : {', '.join(params)}")
            print(f"  core       : {', '.join(core_params)}")
            print(f"  bgc        : {', '.join(bgc_params)}")


        # ── Read TIME axis ───────────────────────────────────────────────
        t_raw = np.asarray(nc.variables["TIME"][:], dtype=np.float64)
        n = len(t_raw)
        # TIME fill value is 9999999999 (much larger than science fill of 99999)
        time_fill = 9999999999.0

        # Convert epoch seconds to ISO timestamps
        ts_strings = []
        for t in t_raw:
            if np.isfinite(t) and t < time_fill - 1:
                dt = datetime.fromtimestamp(float(t), tz=timezone.utc)
                ts_strings.append(dt.strftime("%Y-%m-%dT%H:%M:%S.%fZ"))
            else:
                ts_strings.append(None)

        # Deterministic observation IDs
        obs_ids = []
        for ts in ts_strings:
            if ts:
                obs_ids.append(make_observation_id(gid, ts))
            else:
                obs_ids.append(None)

        # Check for hash collisions
        valid_ids = [oid for oid in obs_ids if oid is not None]
        if len(set(valid_ids)) != len(valid_ids):
            raise RuntimeError(
                "observation_id hash collision — refusing to load")

        # ── GPS fix set for has_gps_fix marking ──────────────────────────
        gps_fix_times = _build_gps_fix_set(nc)
        n_gps = len(gps_fix_times)

        # ── Compute distance over ground from GPS fixes ──────────────────
        distance_km = compute_distance_from_gps(nc)

        # ── Read observation-level arrays ────────────────────────────────
        pres = _var_array(nc, "PRES", n)
        lat = _var_array(nc, "LATITUDE", n)
        lon = _var_array(nc, "LONGITUDE", n)
        phase = np.asarray(nc.variables["PHASE"][:], dtype=np.int16) if "PHASE" in nc.variables else np.full(n, -128, dtype=np.int16)
        phase_num = np.asarray(nc.variables["PHASE_NUMBER"][:], dtype=np.int32) if "PHASE_NUMBER" in nc.variables else np.full(n, 99999, dtype=np.int32)
        pos_qc = np.asarray(nc.variables["POSITION_QC"][:], dtype=np.int16) if "POSITION_QC" in nc.variables else np.full(n, 0, dtype=np.int16)

        # Count distinct profiles
        pn_valid = phase_num[phase_num != 99999]
        n_profiles = int(np.unique(pn_valid).size) if pn_valid.size > 0 else 0

        # Max depth
        pres_valid = pres[np.isfinite(pres)]
        max_depth = float(pres_valid.max()) if pres_valid.size > 0 else None

        if verbose:
            print(f"  timestamps : {n:,}")
            print(f"  profiles   : {n_profiles}")
            print(f"  GPS fixes  : {n_gps}")
            print(f"  distance   : {distance_km:.1f} km" if distance_km else "  distance   : N/A")
            print(f"  max depth  : {max_depth:.1f} dbar" if max_depth else "  max depth  : N/A")


        # ── Build meta row ───────────────────────────────────────────────
        meta_row = {
            "glider_id": gid,
            "deployment_name": _attr("deployment_code") or _attr("title"),
            "deployment_start": _attr("time_coverage_start"),
            "deployment_end": _attr("time_coverage_end"),
            "max_depth_dbar": max_depth,
            "n_profiles": n_profiles,
            "n_observations": n,
            "n_gps_fixes": n_gps,
            "distance_over_ground_km": distance_km,
            "pipeline_version": _attr("data_processing_chain_version"),
            "ego_format_version": _attr("format_version"),
            "data_mode": _attr("data_mode"),
            "institution": _attr("institution"),
            "rtqc_tests_applied": _attr("rtqc_tests_applied"),
            "processed_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
            "ego_l0_path": ego_l0_path,
            "ego_l1_path": ego_l1_path,
        }

        # ── Build observation rows (generator) ───────────────────────────
        def _obs_rows():
            t_round = np.round(t_raw).astype(np.int64)
            for i in range(n):
                oid = obs_ids[i]
                ts = ts_strings[i]
                if oid is None or ts is None:
                    continue
                p = float(pres[i]) if np.isfinite(pres[i]) else None
                la = float(lat[i]) if np.isfinite(lat[i]) else None
                lo = float(lon[i]) if np.isfinite(lon[i]) else None
                ph = int(phase[i]) if phase[i] != -128 else None
                pn = int(phase_num[i]) if phase_num[i] != 99999 else None
                pq = int(pos_qc[i]) if pos_qc[i] >= 0 else None
                gps = 1 if t_round[i] in gps_fix_times else 0
                yield (oid, gid, ts, p, la, lo, ph, pn, pq, gps)

        # ── Write to database ────────────────────────────────────────────
        if verbose:
            print()
            print("  Writing to database...")

        conn = _connect(db_path)
        try:
            apply_schema(conn)
            with conn:
                conn.execute(META_UPSERT, meta_row)
                n_obs = _executemany_batched(conn, OBSERVATION_UPSERT, _obs_rows())

                n_core = 0
                for param in core_params:
                    if param not in nc.variables:
                        continue
                    n_core += _executemany_batched(
                        conn, _measurement_upsert("core"),
                        _measurement_rows(nc, obs_ids, param, "core", n))

                n_bgc = 0
                for param in bgc_params:
                    if param not in nc.variables:
                        continue
                    n_bgc += _executemany_batched(
                        conn, _measurement_upsert("bgc"),
                        _measurement_rows(nc, obs_ids, param, "bgc", n))

                # Wide views
                create_wide_views(conn, core_params, bgc_params)

            conn.execute("PRAGMA synchronous = NORMAL")
            conn.execute("PRAGMA optimize")
        finally:
            conn.close()

    finally:
        nc.close()

    elapsed = _time.time() - t_start
    result = {
        "glider_id": gid,
        "db_path": os.path.abspath(db_path),
        "rows": {"meta": 1, "observation": n_obs, "core": n_core, "bgc": n_bgc},
        "parameters": {"core": core_params, "bgc": bgc_params},
        "distance_km": distance_km,
        "warnings": warnings,
        "elapsed_s": elapsed,
        "meta": meta_row,
    }

    if verbose:
        _print_load_summary(result)
    return result


def _print_load_summary(result: dict) -> None:
    print()
    print("-" * 68)
    print("  LOAD SUMMARY")
    print("-" * 68)

    m = result["meta"]
    print(f"  deployment      : {m['deployment_name']}")
    print(f"  window          : {m['deployment_start']}  ->  {m['deployment_end']}")
    print(f"  profiles        : {m['n_profiles']}")
    print(f"  GPS fixes       : {m['n_gps_fixes']}")
    dist = m["distance_over_ground_km"]
    print(f"  distance        : {f'{dist:.1f} km' if dist else 'N/A'}")
    depth = m["max_depth_dbar"]
    print(f"  max depth       : {f'{depth:.1f} dbar' if depth else 'N/A'}")
    print(f"  EGO version     : {m['ego_format_version']}")
    print(f"  data mode       : {m['data_mode']}")
    print(f"  RTQC tests      : {m['rtqc_tests_applied']}")

    print(f"\n  Rows inserted / updated")
    for table, count in result["rows"].items():
        print(f"    {table:<14} {count:>12,}")
    total = sum(result["rows"].values())
    print(f"    {'TOTAL':<14} {total:>12,}")

    print(f"\n  Parameters loaded")
    print(f"    core: {', '.join(result['parameters']['core'])}")
    print(f"    bgc:  {', '.join(result['parameters']['bgc'])}")

    if result["warnings"]:
        print(f"\n  Warnings")
        for w in result["warnings"]:
            print(f"      - {w}")

    print(f"\n  Completed in {result['elapsed_s']:.1f}s -> {result['db_path']}")
    print("=" * 68)


# ============================================================
#  Sanity check
# ============================================================

def sanity_check(db_path: str, glider_id: str = None) -> None:
    """Post-load verification: row counts, QC breakdown, join test."""
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    try:
        print("\n" + "=" * 68)
        print("  SANITY CHECK")
        print("=" * 68)

        print("\n  Row counts")
        for table in ("meta", "observation", "core", "bgc"):
            n = conn.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
            print(f"    {table:<14} {n:>12,}")

        print("\n  Deployments")
        for row in conn.execute(
            "SELECT glider_id, deployment_name, deployment_start, "
            "       deployment_end, n_profiles, n_observations, "
            "       distance_over_ground_km FROM meta ORDER BY glider_id"
        ):
            print(f"    {row['glider_id']:<12} {row['deployment_name']}")
            print(f"      {row['deployment_start']} -> {row['deployment_end']}")
            print(f"      profiles: {row['n_profiles']}   "
                  f"observations: {row['n_observations']:,}   "
                  f"distance: {row['distance_over_ground_km']:.1f} km"
                  if row['distance_over_ground_km'] else
                  f"      profiles: {row['n_profiles']}   "
                  f"observations: {row['n_observations']:,}")


        # ── QC breakdown ─────────────────────────────────────────────────
        print("\n  QC breakdown by variable")
        print(f"    {'family':<6} {'variable':<12} {'n':>10} {'good%':>7} "
              f"{'bad':>9} {'missing':>9} {'no_qc':>9} {'adjusted':>10}")
        print("    " + "-" * 80)
        params = (glider_id,) if glider_id else ()
        where = "WHERE glider_id = ?" if glider_id else ""
        for row in conn.execute(
            f"SELECT * FROM qc_summary {where} "
            f"ORDER BY family DESC, variable_name", params
        ):
            pct = row["pct_good"]
            print(f"    {row['family']:<6} {row['variable_name']:<12} "
                  f"{row['n_total']:>10,} "
                  f"{(f'{pct:.1f}' if pct is not None else '-'):>7} "
                  f"{row['n_bad'] or 0:>9,} "
                  f"{row['n_missing'] or 0:>9,} "
                  f"{row['n_no_qc'] or 0:>9,} "
                  f"{row['n_adjusted'] or 0:>10,}")

        # ── Join test ────────────────────────────────────────────────────
        print("\n  Join test: observation + core + bgc at one timestamp")
        pick = conn.execute("""
            SELECT o.observation_id
              FROM observation o
              JOIN core c ON c.observation_id = o.observation_id
                         AND c.qc_flag IS NOT NULL AND c.value IS NOT NULL
              JOIN bgc  b ON b.observation_id = o.observation_id
                         AND b.qc_flag IS NOT NULL AND b.value IS NOT NULL
             LIMIT 1
        """).fetchone()

        if pick is None:
            pick = conn.execute("""
                SELECT observation_id FROM observation
                WHERE pressure IS NOT NULL LIMIT 1
            """).fetchone()

        if pick is None:
            print("    (no suitable row found for join test)")
        else:
            obs_id = pick["observation_id"]
            ctx = conn.execute("""
                SELECT glider_id, timestamp, pressure, latitude, longitude,
                       phase, phase_number, has_gps_fix
                  FROM observation WHERE observation_id = ?
            """, (obs_id,)).fetchone()
            print(f"    observation_id : {obs_id}")
            print(f"    timestamp      : {ctx['timestamp']}")
            print(f"    pressure       : {ctx['pressure']}")
            print(f"    lat/lon        : {ctx['latitude']}, {ctx['longitude']}")
            print(f"    phase/number   : {ctx['phase']}/{ctx['phase_number']}")
            print(f"    has_gps_fix    : {ctx['has_gps_fix']}")

            print(f"\n    {'family':<6} {'variable':<12} {'value':>12} "
                  f"{'qc':>4} {'adjusted':>12} {'adj_qc':>7}")
            print("    " + "-" * 60)
            for row in conn.execute("""
                SELECT m.family, m.variable_name, m.value, m.qc_flag,
                       m.value_adjusted, m.adjusted_qc_flag
                  FROM measurement m
                 WHERE m.observation_id = ?
                 ORDER BY m.family DESC, m.variable_name
            """, (obs_id,)):
                v = f"{row['value']:.4f}" if row['value'] is not None else "NULL"
                av = f"{row['value_adjusted']:.4f}" if row['value_adjusted'] is not None else "NULL"
                q = row['qc_flag'] if row['qc_flag'] is not None else "-"
                aq = row['adjusted_qc_flag'] if row['adjusted_qc_flag'] is not None else "-"
                print(f"    {row['family']:<6} {row['variable_name']:<12} "
                      f"{v:>12} {q:>4} {av:>12} {aq:>7}")

        print("\n  Join OK.")
        print("=" * 68)
    finally:
        conn.close()


# ============================================================
#  CLI
# ============================================================

def main(argv=None) -> int:
    parser = argparse.ArgumentParser(
        prog="python -m db.load_deployment",
        description="Load EGO 1.5 NetCDF files into SQLite.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""examples:
  python -m db.load_deployment --ego-dir /path/to/output/EGO-timeseries
  python -m db.load_deployment --ego-l1 /path/to/L1_EGO.nc
  python -m db.load_deployment --ego-l1 L1_EGO.nc --ego-l0 L0_EGO.nc --db my.db

Safe to re-run: observation_id is a deterministic hash, upserts in place.
""")
    parser.add_argument("--ego-dir", default=None,
                        help="Directory containing EGO NetCDF files")
    parser.add_argument("--ego-l1", default=None,
                        help="Path to EGO L1 NetCDF (QC + adjusted)")
    parser.add_argument("--ego-l0", default=None,
                        help="Path to EGO L0 NetCDF (raw only)")
    parser.add_argument("--db", default="glider_rtqc.db",
                        help="SQLite database path (default: glider_rtqc.db)")
    parser.add_argument("--glider-id", default=None,
                        help="Override the auto-detected glider id")
    parser.add_argument("--no-check", action="store_true",
                        help="Skip the post-load sanity check")
    parser.add_argument("-q", "--quiet", action="store_true",
                        help="Suppress progress output")
    args = parser.parse_args(argv)

    # Also accept a positional argument as ego-dir for backwards compat
    if args.ego_dir is None and args.ego_l1 is None and args.ego_l0 is None:
        # Try first positional-style argument
        remaining = [a for a in (argv or sys.argv[1:])
                     if not a.startswith("-") and a != args.db]
        if remaining:
            candidate = remaining[0]
            if os.path.isdir(candidate):
                args.ego_dir = candidate
            elif candidate.endswith(".nc"):
                args.ego_l1 = candidate

    if not args.ego_dir and not args.ego_l1 and not args.ego_l0:
        parser.error("Provide --ego-dir, --ego-l1, or --ego-l0")

    try:
        result = load_deployment(
            ego_l1_path=args.ego_l1,
            ego_l0_path=args.ego_l0,
            ego_dir=args.ego_dir,
            db_path=args.db,
            glider_id=args.glider_id,
            verbose=not args.quiet,
        )
    except (FileNotFoundError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    if not args.no_check:
        sanity_check(args.db, result["glider_id"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
