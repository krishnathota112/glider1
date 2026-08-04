#!/usr/bin/env python3
"""
load_deployment.py — ingest a glider deployment's output/ folder into SQLite.

Reads the L0 and L1 NetCDF timeseries produced by the RTQC pipeline and loads
them into the four-table schema in db/schema.sql:

    meta         one row per deployment
    observation  one row per (glider_id, timestamp)
    core         one row per (observation_id, variable_name), physical
    bgc          one row per (observation_id, variable_name), biogeochemical

Value semantics
---------------
    value             raw L0 value at that timestamp
    qc_flag           L1 <var>_QC  (ARGO ref table 2: 1 good … 4 bad, 9 missing)
    value_adjusted    L1 corrected value, NULL when no correction was computed
    adjusted_qc_flag  QC flag on the adjusted value, NULL when none exists

The pipeline is non-destructive: it never overwrites a raw value, it writes
corrections alongside as separate variables (see ADJUSTED_SUFFIXES). Those
suffixed variables are what land in value_adjusted.

Idempotency
-----------
observation_id is a deterministic 63-bit hash of (glider_id, timestamp), so
re-running the pipeline and re-ingesting the same deployment updates rows in
place instead of duplicating them. Every write is an ON CONFLICT DO UPDATE
upsert — never INSERT OR REPLACE, which would cascade-delete child rows.

Usage
-----
    python -m db.load_deployment <output_dir> [--db glider_rtqc.db]

    from db.load_deployment import load_deployment
    load_deployment("/data/glider/890_2023/output")
"""

from __future__ import annotations

import argparse
import hashlib
import os
import re
import sqlite3
import sys
import time
from datetime import datetime, timezone
from itertools import repeat

import numpy as np
import pandas as pd
import xarray as xr


# ============================================================
#  Name mapping — pipeline internal name -> ARGO short name
#
#  Plain dicts on purpose: extend them when a new sensor shows up.
#  A variable that isn't listed here is NOT dropped — it is inserted
#  under its internal name and reported at the end of the run.
# ============================================================

ARGO_NAME_MAP = {
    # --- core / physical ---
    "temperature":           "TEMP",
    "salinity":              "PSAL",
    "pressure":              "PRES",
    "conductivity":          "CNDC",
    "density":               "DENS",
    # --- bgc ---
    "oxygen_concentration":  "DOXY",
    "chlorophyll":           "CHLA",
    "cdom":                  "CDOM",
    "backscatter_700":       "BBP700",
    # Room to grow — uncomment/extend as sensors appear:
    # "backscatter_470":     "BBP470",
    # "backscatter_532":     "BBP532",
    # "nitrate":             "NITRATE",
    # "ph":                  "PH_IN_SITU_TOTAL",
    # "par":                 "DOWNWELLING_PAR",
}

# Which family a variable belongs to. Anything measured but unlisted defaults
# to `core` with a warning, so a new sensor is never silently discarded.
CORE_VARS = {
    "temperature", "salinity", "pressure", "conductivity", "density",
    "potential_temperature", "potential_density",
}

BGC_VARS = {
    "oxygen_concentration", "chlorophyll", "cdom", "backscatter_700",
    "backscatter_470", "backscatter_532", "nitrate", "ph", "par",
    "downwelling_par",
}

# Columns of `observation`, mapped to the NetCDF variable that fills them.
# These are sample *context*, not measurements — they never go to core/bgc.
OBSERVATION_FIELDS = {
    "depth_m":              "depth",
    "pressure":             "pressure",
    "latitude":             "latitude",
    "longitude":            "longitude",
    "profile_id":           "profile_index",
    "profile_direction":    "profile_direction",
    "heading":              "heading",
    "pitch":                "pitch",
    "roll":                 "roll",
    "waypoint_latitude":    "waypoint_latitude",
    "waypoint_longitude":   "waypoint_longitude",
    "distance_over_ground": "distance_over_ground",
}

# NetCDF variables that are neither measurements nor observation context.
NON_MEASUREMENT_VARS = {
    "latitude", "longitude", "depth", "profile_index", "profile_direction",
    "heading", "pitch", "roll", "waypoint_latitude", "waypoint_longitude",
    "distance_over_ground", "time",
}

# How the pipeline names a corrected value, in priority order. The first
# suffix that resolves to a real L1 variable wins.
#
#   oxygen_concentration_lag_corrected   step23.oxygen_lag_correction
#   chlorophyll_corrected                step23.apply_optics_correction
#   temperature_processed                step23.apply_physics_qc
#
# oxygen has both `_lag_corrected` and `_processed`; the lag correction is the
# scientifically meaningful adjustment, so it is listed first.
ADJUSTED_SUFFIXES = ("_lag_corrected", "_corrected", "_processed", "_adjusted")

# Explicit overrides, if a variable's adjusted counterpart is named oddly.
#   internal_var -> exact L1 variable name
ADJUSTED_OVERRIDES: dict[str, str] = {}

QC_SUFFIX = "_QC"

# Identifiers safe to interpolate into generated view SQL.
_SAFE_IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")

SCHEMA_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                           "schema.sql")

BATCH_SIZE = 100_000


# ============================================================
#  Deterministic IDs
# ============================================================

def make_observation_id(glider_id: str, timestamp_iso: str) -> int:
    """
    Deterministic 63-bit observation id from (glider_id, timestamp).

    SHA-256 of "glider_id|timestamp", first 8 bytes, masked to 63 bits so it
    is always positive and fits SQLite's signed 64-bit INTEGER (which, as the
    declared INTEGER PRIMARY KEY, is the table's rowid).

    Same deployment ingested twice -> same ids -> upsert, not duplicate.
    """
    digest = hashlib.sha256(f"{glider_id}|{timestamp_iso}".encode("utf-8")).digest()
    return int.from_bytes(digest[:8], "big") & 0x7FFF_FFFF_FFFF_FFFF


# ============================================================
#  File discovery
# ============================================================

def _first_existing_nc(*candidate_dirs, must_match=None, must_not_match=None):
    """Return the largest .nc under the first candidate dir that has one."""
    for d in candidate_dirs:
        if not os.path.isdir(d):
            continue
        hits = []
        for fn in os.listdir(d):
            if not fn.endswith(".nc"):
                continue
            low = fn.lower()
            if must_match and must_match not in low:
                continue
            if must_not_match and must_not_match in low:
                continue
            path = os.path.join(d, fn)
            hits.append((os.path.getsize(path), path))
        if hits:
            hits.sort(reverse=True)
            return hits[0][1]
    return None


def find_deployment_files(output_dir: str) -> dict:
    """
    Locate the L0 NetCDF, L1 NetCDF and summary report inside an output/ dir.

    Handles both layouts this pipeline has produced:
      output/L0-timeseries/*.nc  +  output/L1-timeseries/*.nc   (current)
      output/*_L0.nc             +  output/l1/*_L1.nc           (older)
    """
    output_dir = os.path.abspath(output_dir)

    l0 = (_first_existing_nc(os.path.join(output_dir, "L0-timeseries"))
          or _first_existing_nc(output_dir, must_match="l0", must_not_match="l1"))

    l1 = (_first_existing_nc(os.path.join(output_dir, "L1-timeseries"))
          or _first_existing_nc(os.path.join(output_dir, "l1"))
          or _first_existing_nc(output_dir, must_match="l1"))

    summary = None
    reports_dir = os.path.join(output_dir, "reports")
    for d in (reports_dir, output_dir):
        if not os.path.isdir(d):
            continue
        hits = [os.path.join(d, f) for f in os.listdir(d)
                if f.lower().endswith(".txt") and "summary" in f.lower()]
        if hits:
            summary = sorted(hits)[0]
            break

    return {"output_dir": output_dir, "l0": l0, "l1": l1, "summary": summary}


# ============================================================
#  Metadata extraction
# ============================================================

def _parse_summary_report(path: str) -> dict:
    """
    Pull deployment facts out of reports/*_summary.txt.

    Used as a fallback when the NetCDF global attributes are missing or
    malformed. The report is written by pipeline/step6.py and has
    'L0 PRODUCT' / 'L1 PRODUCT' sections, each with 'Profiles:' and
    'Time range:' lines.
    """
    out: dict = {}
    if not path or not os.path.exists(path):
        return out

    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            text = fh.read()
    except OSError:
        return out

    # Split into the L0 and L1 halves so 'Profiles:' is unambiguous.
    l1_at = text.find("L1 PRODUCT")
    l0_text = text[:l1_at] if l1_at > 0 else text
    l1_text = text[l1_at:] if l1_at > 0 else ""

    def _profiles(chunk):
        m = re.search(r"Profiles:\s+([\d,]+)", chunk)
        return int(m.group(1).replace(",", "")) if m else None

    def _time_range(chunk):
        m = re.search(r"Time range:\s+(\S+)\s+\S+\s+(\S+)", chunk)
        return (m.group(1), m.group(2)) if m else (None, None)

    out["n_profiles_l0"] = _profiles(l0_text)
    out["n_profiles_l1"] = _profiles(l1_text)

    start, end = _time_range(l0_text)
    if start:
        out["deployment_start"] = start
    if end:
        out["deployment_end"] = end

    m = re.search(r"Max depth:\s+([\d.]+)", l0_text)
    if m:
        out["max_depth_m"] = float(m.group(1))

    return out


def _valid_iso(value) -> str | None:
    """
    Accept a timestamp string only if it actually parses.

    Guards against truncated attributes — real deployments in this repo carry
    deployment_start='2023-12-13T04:11:1', which is not a usable timestamp.
    """
    if value is None:
        return None
    s = str(value).strip()
    if not s:
        return None
    try:
        ts = pd.Timestamp(s)
    except (ValueError, TypeError):
        return None
    if pd.isna(ts):
        return None
    return ts.isoformat()


def _count_profiles(ds) -> int | None:
    """Number of distinct profiles in a timeseries, from profile_index."""
    if ds is None or "profile_index" not in ds:
        return None
    vals = ds["profile_index"].values
    vals = vals[np.isfinite(vals)]
    if vals.size == 0:
        return 0
    return int(np.unique(vals).size)


def _derive_glider_id(ds0, ds1, l0_path: str, override: str | None) -> str:
    """glider_serial attr -> deployment_name attr -> filename -> 'unknown'."""
    if override:
        return str(override)

    for ds in (ds0, ds1):
        if ds is None:
            continue
        serial = ds.attrs.get("glider_serial")
        if serial not in (None, "", " "):
            return str(serial).strip()

    if l0_path:
        base = os.path.basename(l0_path)
        m = re.match(r"incois_glider_(.+?)(?:_L[01])?\.nc$", base, re.IGNORECASE)
        if m:
            return m.group(1)
        return os.path.splitext(base)[0]

    return "unknown"


def build_meta_row(ds0, ds1, files: dict, glider_id: str,
                   n_observations: int) -> dict:
    """
    Assemble the `meta` row, checking NetCDF attrs *and* summary.txt.

    Precedence for the deployment window: time_coverage_* attrs (computed from
    the data), then deployment_start/end attrs, then the summary report. The
    deployment_* attrs are checked second because they have been observed
    truncated in real files.
    """
    attrs = {}
    if ds0 is not None:
        attrs.update(ds0.attrs)
    if ds1 is not None:
        attrs.update(ds1.attrs)   # L1 attrs win where both exist

    summary = _parse_summary_report(files.get("summary"))

    start = (_valid_iso(attrs.get("time_coverage_start"))
             or _valid_iso(attrs.get("deployment_start"))
             or _valid_iso(summary.get("deployment_start")))
    end = (_valid_iso(attrs.get("time_coverage_end"))
           or _valid_iso(attrs.get("deployment_end"))
           or _valid_iso(summary.get("deployment_end")))

    # Last resort: the time axis itself.
    base_ds = ds0 if ds0 is not None else ds1
    if (start is None or end is None) and base_ds is not None and "time" in base_ds:
        tvals = base_ds["time"].values
        if tvals.size:
            start = start or pd.Timestamp(tvals.min()).isoformat()
            end = end or pd.Timestamp(tvals.max()).isoformat()

    n_prof_l0 = _count_profiles(ds0)
    if n_prof_l0 is None:
        n_prof_l0 = summary.get("n_profiles_l0")
    n_prof_l1 = _count_profiles(ds1)
    if n_prof_l1 is None:
        n_prof_l1 = summary.get("n_profiles_l1")

    # Max depth in dbar — prefer measured pressure, fall back to the report's
    # depth in metres (~1 dbar per metre for these depths).
    max_depth = None
    for ds in (ds1, ds0):
        if ds is not None and "pressure" in ds:
            pvals = ds["pressure"].values
            pvals = pvals[np.isfinite(pvals)]
            if pvals.size:
                max_depth = float(np.max(pvals))
                break
    if max_depth is None:
        max_depth = summary.get("max_depth_m")

    pipeline_version = (attrs.get("processing_software")
                        or attrs.get("processing_level")
                        or attrs.get("history"))

    return {
        "glider_id":        glider_id,
        "deployment_name":  attrs.get("deployment_name") or attrs.get("title"),
        "deployment_start": start,
        "deployment_end":   end,
        "max_depth_dbar":   max_depth,
        "n_profiles_l0":    n_prof_l0,
        "n_profiles_l1":    n_prof_l1,
        "pipeline_version": str(pipeline_version) if pipeline_version else None,
        "processed_at":     datetime.now(timezone.utc)
                                    .replace(microsecond=0).isoformat(),
        "l0_path":          files.get("l0"),
        "l1_path":          files.get("l1"),
        "n_observations":   n_observations,
    }


# ============================================================
#  Dataset preparation
# ============================================================

def _dedupe_time(ds, label: str, warnings: list):
    """
    Drop duplicate timestamps, keeping the first occurrence.

    Required for correctness, not just tidiness: observation_id hashes
    (glider_id, timestamp), so duplicate timestamps would collide onto one
    row and the upsert would silently keep whichever landed last.
    """
    if ds is None:
        return None
    tvals = ds["time"].values
    _, first_idx = np.unique(tvals, return_index=True)
    if first_idx.size != tvals.size:
        n_dropped = tvals.size - first_idx.size
        warnings.append(
            f"{label}: {n_dropped:,} duplicate timestamps dropped "
            f"(kept first occurrence of each)"
        )
        ds = ds.isel(time=np.sort(first_idx))
    return ds


def _align_on_time(ds0, ds1, warnings: list):
    """
    Put L0 and L1 on one shared time axis.

    L1 is not a row-for-row copy of L0 — step23.pre_clean() crops the record to
    the deployment window and drops segments, so L1 is usually a subset.
    Aligning by position would silently pair L0 values with the wrong L1 flags.
    We align on the timestamps themselves and reindex both onto their union, so
    nothing from either file is lost.
    """
    if ds0 is None:
        return ds1, ds1, ds1["time"].values
    if ds1 is None:
        return ds0, None, ds0["time"].values

    t0 = ds0["time"].values
    t1 = ds1["time"].values

    if t0.size == t1.size and np.array_equal(t0, t1):
        return ds0, ds1, t0

    master = np.union1d(t0, t1)
    n_l1_only = int(np.setdiff1d(t1, t0).size)
    n_l0_only = int(np.setdiff1d(t0, t1).size)
    if n_l0_only:
        warnings.append(
            f"{n_l0_only:,} timestamps present in L0 but not L1 "
            f"(dropped by pre_clean) — loaded with NULL qc_flag"
        )
    if n_l1_only:
        warnings.append(
            f"{n_l1_only:,} timestamps present in L1 but not L0 "
            f"— loaded with NULL raw value"
        )

    return (ds0.reindex(time=master),
            ds1.reindex(time=master),
            master)


def _column(ds, name: str, n: int):
    """1-D float list for `name`, or a list of None if absent."""
    if ds is not None and name in ds:
        return np.asarray(ds[name].values, dtype="float64").tolist()
    return [None] * n


def _qc_column(ds, var: str, n: int):
    """
    Integer QC flags for `var`, or a list of None if the file has no <var>_QC.

    NaN is mapped to None rather than to flag 9 — 9 means the pipeline
    positively determined 'missing', while absent means 'not assessed'.
    """
    if ds is None or f"{var}{QC_SUFFIX}" not in ds:
        return [None] * n
    vals = np.asarray(ds[f"{var}{QC_SUFFIX}"].values, dtype="float64")
    return [int(v) if np.isfinite(v) else None for v in vals]


def _find_adjusted_var(ds1, var: str) -> str | None:
    """Name of the L1 variable holding `var`'s corrected values, if any."""
    if ds1 is None:
        return None
    override = ADJUSTED_OVERRIDES.get(var)
    if override:
        return override if override in ds1 else None
    for suffix in ADJUSTED_SUFFIXES:
        candidate = f"{var}{suffix}"
        if candidate in ds1:
            return candidate
    return None


def discover_measurement_vars(ds0, ds1) -> list[str]:
    """
    Every measured variable across both files, in a stable order.

    Nothing is hardcoded as required — different gliders carry different
    sensor suites. Derived variables (<var>_QC, <var>_corrected, ...) and
    observation-context variables are excluded.
    """
    derived_suffixes = ADJUSTED_SUFFIXES + (QC_SUFFIX,)
    seen: dict[str, None] = {}

    for ds in (ds0, ds1):
        if ds is None:
            continue
        for name in ds.data_vars:
            if name in NON_MEASUREMENT_VARS:
                continue
            if ds[name].dims != ("time",):
                continue
            if any(name.endswith(s) for s in derived_suffixes):
                continue
            seen.setdefault(name, None)

    return list(seen)


def classify(var: str) -> str:
    """'bgc' or 'core' for a measured variable."""
    if var in BGC_VARS:
        return "bgc"
    return "core"


def _measurement_rows(ds0, ds1, obs_ids, plan, table: str, n: int):
    """
    Yield (observation_id, variable_name, value, qc, adjusted, adjusted_qc)
    tuples for every variable assigned to `table`.

    A generator on purpose. Materialising these into a list first meant holding
    n_observations x n_variables six-tuples at once — for the ~1M-observation,
    10-variable deployments this pipeline routinely produces, several GB before
    a single row reached SQLite. Streaming keeps only one variable's columns
    resident, and _executemany_batched consumes it in fixed-size chunks.
    """
    for entry in plan:
        if entry["table"] != table:
            continue
        var = entry["internal"]
        adj_var = entry["adjusted"]
        values = _column(ds0, var, n)
        qc_flags = _qc_column(ds1, var, n)
        adj_values = _column(ds1, adj_var, n) if adj_var else [None] * n
        adj_qc = _qc_column(ds1, adj_var, n) if adj_var else [None] * n
        yield from zip(obs_ids, repeat(entry["argo"], n),
                       values, qc_flags, adj_values, adj_qc)


# ============================================================
#  Database
# ============================================================

def _connect(db_path: str) -> sqlite3.Connection:
    conn = sqlite3.connect(db_path)
    conn.execute("PRAGMA foreign_keys = ON")
    conn.execute("PRAGMA journal_mode = WAL")
    # synchronous=OFF trades crash-durability for load speed. It is a
    # per-connection setting, so it lapses when this connection closes — a
    # torn write only costs you a re-ingest, which is idempotent anyway.
    conn.execute("PRAGMA synchronous = OFF")
    conn.execute("PRAGMA temp_store = MEMORY")
    conn.execute("PRAGMA cache_size = -64000")    # 64 MB page cache
    return conn


def apply_schema(conn: sqlite3.Connection) -> None:
    if not os.path.exists(SCHEMA_PATH):
        raise FileNotFoundError(f"schema not found: {SCHEMA_PATH}")
    with open(SCHEMA_PATH, "r", encoding="utf-8") as fh:
        conn.executescript(fh.read())


META_UPSERT = """
INSERT INTO meta (glider_id, deployment_name, deployment_start, deployment_end,
                  max_depth_dbar, n_profiles_l0, n_profiles_l1,
                  pipeline_version, processed_at, l0_path, l1_path,
                  n_observations)
VALUES (:glider_id, :deployment_name, :deployment_start, :deployment_end,
        :max_depth_dbar, :n_profiles_l0, :n_profiles_l1,
        :pipeline_version, :processed_at, :l0_path, :l1_path,
        :n_observations)
ON CONFLICT(glider_id) DO UPDATE SET
    deployment_name  = excluded.deployment_name,
    deployment_start = excluded.deployment_start,
    deployment_end   = excluded.deployment_end,
    max_depth_dbar   = excluded.max_depth_dbar,
    n_profiles_l0    = excluded.n_profiles_l0,
    n_profiles_l1    = excluded.n_profiles_l1,
    pipeline_version = excluded.pipeline_version,
    processed_at     = excluded.processed_at,
    l0_path          = excluded.l0_path,
    l1_path          = excluded.l1_path,
    n_observations   = excluded.n_observations
"""

OBSERVATION_UPSERT = """
INSERT INTO observation (observation_id, glider_id, timestamp, depth_m,
                         pressure, latitude, longitude, profile_id,
                         profile_direction, heading, pitch, roll,
                         waypoint_latitude, waypoint_longitude,
                         distance_over_ground)
VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
ON CONFLICT(observation_id) DO UPDATE SET
    glider_id            = excluded.glider_id,
    timestamp            = excluded.timestamp,
    depth_m              = excluded.depth_m,
    pressure             = excluded.pressure,
    latitude             = excluded.latitude,
    longitude            = excluded.longitude,
    profile_id           = excluded.profile_id,
    profile_direction    = excluded.profile_direction,
    heading              = excluded.heading,
    pitch                = excluded.pitch,
    roll                 = excluded.roll,
    waypoint_latitude    = excluded.waypoint_latitude,
    waypoint_longitude   = excluded.waypoint_longitude,
    distance_over_ground = excluded.distance_over_ground
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
    Feed `rows` to executemany in fixed-size chunks.

    Accepts any iterable, not just a list: the measurement rows are produced
    per variable and streamed straight through, so a deployment with millions
    of observations never holds n_observations x n_variables tuples in memory
    at once.
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


def create_wide_views(conn: sqlite3.Connection,
                      core_names: list[str],
                      bgc_names: list[str]) -> None:
    """
    Build pivoted `wide_core` / `wide_bgc` views over the long tables.

    One column set per variable (TEMP, TEMP_ADJUSTED, TEMP_QC,
    TEMP_ADJUSTED_QC), so raw-vs-adjusted comparison reads as a single-table
    query with no join, while storage stays long and schema-stable.

    Regenerated on every load, since the column list depends on which
    variables the deployment carries.
    """
    for table, names in (("core", core_names), ("bgc", bgc_names)):
        view = f"wide_{table}"
        conn.execute(f"DROP VIEW IF EXISTS {view}")

        safe = [n for n in sorted(names) if _SAFE_IDENT.match(n)]
        skipped = [n for n in sorted(names) if not _SAFE_IDENT.match(n)]
        if skipped:
            print(f"    note: {view} omits {skipped} "
                  f"(name not a valid SQL identifier)")
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

        # Joined outside the f-string: a backslash inside an f-string
        # expression is a syntax error before Python 3.12.
        pivot_sql = ",\n".join(cols)
        conn.execute(f"""
CREATE VIEW {view} AS
SELECT
    o.observation_id,
    o.glider_id,
    o.timestamp,
    o.depth_m,
    o.pressure,
    o.latitude,
    o.longitude,
    o.profile_id,
{pivot_sql}
FROM observation o
LEFT JOIN {table} m ON m.observation_id = o.observation_id
GROUP BY o.observation_id
""")


# ============================================================
#  Main entry point
# ============================================================

def load_deployment(output_dir: str,
                    db_path: str = "glider_rtqc.db",
                    glider_id: str | None = None,
                    verbose: bool = True) -> dict:
    """
    Load one deployment's output/ folder into the SQLite database.

    Parameters
    ----------
    output_dir : path to the deployment's output/ directory
    db_path    : SQLite file; created and migrated if it doesn't exist
    glider_id  : override the auto-detected glider id
    verbose    : print progress and the end-of-run summary

    Returns a dict with row counts, warnings, and unmapped variable names.
    """
    t_start = time.time()
    warnings: list[str] = []
    unmapped: list[str] = []

    files = find_deployment_files(output_dir)
    if files["l0"] is None and files["l1"] is None:
        raise FileNotFoundError(
            f"no L0 or L1 NetCDF found under {output_dir}\n"
            f"  expected output/L0-timeseries/*.nc or output/L1-timeseries/*.nc"
        )

    if verbose:
        print("=" * 68)
        print("  GLIDER DEPLOYMENT -> SQLITE")
        print("=" * 68)
        print(f"  output dir : {files['output_dir']}")
        print(f"  L0         : {files['l0'] or '(missing)'}")
        print(f"  L1         : {files['l1'] or '(missing)'}")
        print(f"  summary    : {files['summary'] or '(missing)'}")
        print(f"  database   : {os.path.abspath(db_path)}")

    if files["l0"] is None:
        warnings.append("no L0 file — `value` will be NULL, only L1 loaded")
    if files["l1"] is None:
        warnings.append("no L1 file — qc_flag and value_adjusted will be NULL")

    ds0 = xr.open_dataset(files["l0"]) if files["l0"] else None
    ds1 = xr.open_dataset(files["l1"]) if files["l1"] else None

    try:
        ds0 = _dedupe_time(ds0, "L0", warnings)
        ds1 = _dedupe_time(ds1, "L1", warnings)
        ds0, ds1, master_time = _align_on_time(ds0, ds1, warnings)

        n = int(master_time.size)
        glider_id = _derive_glider_id(ds0, ds1, files["l0"] or files["l1"],
                                      glider_id)

        if verbose:
            print(f"\n  glider_id  : {glider_id}")
            print(f"  timestamps : {n:,}")

        # ---- timestamps and deterministic ids ----
        ts_strings = (pd.DatetimeIndex(master_time)
                        .strftime("%Y-%m-%dT%H:%M:%S.%f").tolist())
        obs_ids = [make_observation_id(glider_id, ts) for ts in ts_strings]

        if len(set(obs_ids)) != len(obs_ids):
            raise RuntimeError(
                "observation_id hash collision — refusing to load, "
                "this would silently merge distinct samples"
            )

        # ---- meta ----
        meta_row = build_meta_row(ds0, ds1, files, glider_id, n)

        # ---- observation rows ----
        obs_cols = {col: _column(ds0 if (ds0 is not None and src in ds0) else ds1,
                                 src, n)
                    for col, src in OBSERVATION_FIELDS.items()}
        missing_ctx = [src for col, src in OBSERVATION_FIELDS.items()
                       if (ds0 is None or src not in ds0)
                       and (ds1 is None or src not in ds1)]
        if missing_ctx and verbose:
            print(f"  observation: no {', '.join(missing_ctx)} in this "
                  f"deployment — those columns stay NULL")

        # A generator, not a list — _executemany_batched chunks it as it goes.
        observation_rows = zip(
            obs_ids,
            [glider_id] * n,
            ts_strings,
            obs_cols["depth_m"],
            obs_cols["pressure"],
            obs_cols["latitude"],
            obs_cols["longitude"],
            obs_cols["profile_id"],
            obs_cols["profile_direction"],
            obs_cols["heading"],
            obs_cols["pitch"],
            obs_cols["roll"],
            obs_cols["waypoint_latitude"],
            obs_cols["waypoint_longitude"],
            obs_cols["distance_over_ground"],
        )

        # ---- measurement rows ----
        measured = discover_measurement_vars(ds0, ds1)
        if verbose:
            print(f"  variables  : {len(measured)} measured "
                  f"({', '.join(measured)})")
            print()

        # Plan every variable up front — which table it lands in, its ARGO
        # name, where its adjusted values live. The plan is metadata only; the
        # data columns are read later, one variable at a time, by
        # _measurement_rows.
        names_by_table = {"core": [], "bgc": []}
        per_variable = []

        for var in measured:
            argo = ARGO_NAME_MAP.get(var)
            if argo is None:
                argo = var
                unmapped.append(var)

            table = classify(var)
            if var not in CORE_VARS and var not in BGC_VARS:
                warnings.append(
                    f"'{var}' is in neither CORE_VARS nor BGC_VARS — "
                    f"defaulted to `{table}`"
                )

            names_by_table[table].append(argo)
            has_qc = ds1 is not None and f"{var}{QC_SUFFIX}" in ds1
            per_variable.append({
                "internal": var,
                "argo": argo,
                "table": table,
                "qc": f"{var}{QC_SUFFIX}" if has_qc else None,
                "adjusted": _find_adjusted_var(ds1, var),
                "mapped": var in ARGO_NAME_MAP,
            })

        # ---- write ----
        conn = _connect(db_path)
        try:
            apply_schema(conn)
            with conn:
                conn.execute(META_UPSERT, meta_row)
                n_obs = _executemany_batched(conn, OBSERVATION_UPSERT,
                                             observation_rows)
                n_core = _executemany_batched(
                    conn, _measurement_upsert("core"),
                    _measurement_rows(ds0, ds1, obs_ids, per_variable,
                                      "core", n))
                n_bgc = _executemany_batched(
                    conn, _measurement_upsert("bgc"),
                    _measurement_rows(ds0, ds1, obs_ids, per_variable,
                                      "bgc", n))
                create_wide_views(conn, names_by_table["core"],
                                  names_by_table["bgc"])
            conn.execute("PRAGMA synchronous = NORMAL")
            conn.execute("PRAGMA optimize")
        finally:
            conn.close()

    finally:
        if ds0 is not None:
            ds0.close()
        if ds1 is not None:
            ds1.close()

    elapsed = time.time() - t_start
    result = {
        "glider_id": glider_id,
        "db_path": os.path.abspath(db_path),
        "rows": {"meta": 1, "observation": n_obs, "core": n_core, "bgc": n_bgc},
        "variables": per_variable,
        "unmapped": unmapped,
        "warnings": warnings,
        "elapsed_s": elapsed,
        "files": files,
        "meta": meta_row,
    }

    if verbose:
        _print_load_summary(result)
    return result


def _print_load_summary(result: dict) -> None:
    print("-" * 68)
    print("  LOAD SUMMARY")
    print("-" * 68)

    m = result["meta"]
    print(f"  deployment      : {m['deployment_name']}")
    print(f"  window          : {m['deployment_start']}  ->  "
          f"{m['deployment_end']}")
    print(f"  profiles        : L0={m['n_profiles_l0']}  L1={m['n_profiles_l1']}")
    depth = m["max_depth_dbar"]
    print(f"  max depth       : "
          f"{f'{depth:.1f} dbar' if depth is not None else 'unknown'}")
    print(f"  pipeline        : {m['pipeline_version']}")

    print("\n  Rows inserted / updated")
    for table, count in result["rows"].items():
        print(f"    {table:<14} {count:>12,}")
    total = sum(result["rows"].values())
    print(f"    {'TOTAL':<14} {total:>12,}")

    print("\n  Variables loaded")
    print(f"    {'internal':<24} {'-> ARGO':<26} {'table':<6} {'qc source':<26} "
          f"{'adjusted source':<36}")
    print("    " + "-" * 122)
    for v in result["variables"]:
        argo = v["argo"] if v["mapped"] else f"{v['argo']} (!)"
        print(f"    {v['internal']:<24} {argo:<26} {v['table']:<6} "
              f"{v['qc'] or '-':<26} {v['adjusted'] or '-':<36}")

    if result["unmapped"]:
        print("\n  (!) NOT IN ARGO_NAME_MAP — inserted under their internal "
              "names, nothing dropped:")
        for name in result["unmapped"]:
            print(f"      - {name}")
        print("      Add them to ARGO_NAME_MAP in db/load_deployment.py "
              "to store proper ARGO names.")

    if result["warnings"]:
        print("\n  Warnings")
        for w in result["warnings"]:
            print(f"      - {w}")

    print(f"\n  Completed in {result['elapsed_s']:.1f}s -> {result['db_path']}")
    print("=" * 68)


# ============================================================
#  Sanity check
# ============================================================

def sanity_check(db_path: str, glider_id: str | None = None) -> None:
    """
    Post-load verification: row counts per table, plus a real
    observation+core+bgc join for one timestamp, proving the keys line up.
    """
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
            "       deployment_end, n_profiles_l0, n_profiles_l1, "
            "       n_observations FROM meta ORDER BY glider_id"
        ):
            print(f"    {row['glider_id']:<12} {row['deployment_name']}")
            print(f"      {row['deployment_start']} -> {row['deployment_end']}")
            print(f"      profiles L0/L1: {row['n_profiles_l0']}/"
                  f"{row['n_profiles_l1']}   "
                  f"observations: {row['n_observations']:,}")

        # ---- per-variable QC breakdown (uses the qc_summary view) ----
        print("\n  QC breakdown by variable")
        print(f"    {'family':<6} {'variable':<22} {'n':>10} {'good%':>7} "
              f"{'bad':>9} {'missing':>9} {'adjusted':>10}")
        print("    " + "-" * 80)
        params = (glider_id,) if glider_id else ()
        where = "WHERE glider_id = ?" if glider_id else ""
        for row in conn.execute(
            f"SELECT * FROM qc_summary {where} "
            f"ORDER BY family DESC, variable_name", params
        ):
            pct = row["pct_good"]
            print(f"    {row['family']:<6} {row['variable_name']:<22} "
                  f"{row['n_total']:>10,} "
                  f"{(f'{pct:.1f}' if pct is not None else '-'):>7} "
                  f"{row['n_bad'] or 0:>9,} {row['n_missing'] or 0:>9,} "
                  f"{row['n_adjusted'] or 0:>10,}")

        # ---- the end-to-end join ----
        print("\n  Join test: observation + core + bgc at a single timestamp")

        # Pick the most informative sample we can find, in descending order of
        # usefulness. The first query prefers a row that actually exercises all
        # four measurement columns — otherwise the demo can land on a sample
        # that pre_clean dropped from L1, where every flag is NULL and the
        # join proves very little.
        candidates = (
            """SELECT o.observation_id
                 FROM observation o
                 JOIN core c ON c.observation_id = o.observation_id
                            AND c.qc_flag IS NOT NULL
                            AND c.value_adjusted IS NOT NULL
                 JOIN bgc  b ON b.observation_id = o.observation_id
                            AND b.qc_flag IS NOT NULL
                            AND b.value_adjusted IS NOT NULL
                LIMIT 1""",
            """SELECT o.observation_id
                 FROM observation o
                 JOIN core c ON c.observation_id = o.observation_id
                            AND c.qc_flag IS NOT NULL
                 JOIN bgc  b ON b.observation_id = o.observation_id
                            AND b.qc_flag IS NOT NULL
                LIMIT 1""",
            """SELECT o.observation_id
                 FROM observation o
                 JOIN core c ON c.observation_id = o.observation_id
                 JOIN bgc  b ON b.observation_id = o.observation_id
                WHERE c.value IS NOT NULL AND b.value IS NOT NULL
                LIMIT 1""",
        )

        pick = None
        for sql in candidates:
            pick = conn.execute(sql).fetchone()
            if pick is not None:
                break

        if pick is None:
            print("    no timestamp has both a core and a bgc reading — "
                  "join not exercised")
            return

        obs_id = pick["observation_id"]

        ctx = conn.execute("""
            SELECT glider_id, timestamp, depth_m, pressure, latitude,
                   longitude, profile_id
              FROM observation WHERE observation_id = ?
        """, (obs_id,)).fetchone()

        print(f"    observation_id : {obs_id}")
        print(f"    glider_id      : {ctx['glider_id']}")
        print(f"    timestamp      : {ctx['timestamp']}")
        print(f"    depth / pres   : "
              f"{_fmt(ctx['depth_m'])} m / {_fmt(ctx['pressure'])} dbar")
        print(f"    position       : "
              f"{_fmt(ctx['latitude'], 5)}, {_fmt(ctx['longitude'], 5)}")
        print(f"    profile_id     : {_fmt(ctx['profile_id'], 1)}")

        print(f"\n    {'family':<6} {'variable':<22} {'value':>12} {'qc':>4} "
              f"{'adjusted':>12} {'adj_qc':>7}")
        print("    " + "-" * 68)
        for row in conn.execute("""
            SELECT m.family, m.variable_name, m.value, m.qc_flag,
                   m.value_adjusted, m.adjusted_qc_flag
              FROM observation o
              JOIN measurement m ON m.observation_id = o.observation_id
             WHERE o.observation_id = ?
             ORDER BY m.family DESC, m.variable_name
        """, (obs_id,)):
            print(f"    {row['family']:<6} {row['variable_name']:<22} "
                  f"{_fmt(row['value'], 4):>12} "
                  f"{(row['qc_flag'] if row['qc_flag'] is not None else '-'):>4} "
                  f"{_fmt(row['value_adjusted'], 4):>12} "
                  f"{(row['adjusted_qc_flag'] if row['adjusted_qc_flag'] is not None else '-'):>7}")

        print("\n  Join OK — observation, core and bgc all resolve "
              "on observation_id.")
        print("=" * 68)
    finally:
        conn.close()


def _fmt(value, places: int = 2) -> str:
    if value is None:
        return "NULL"
    try:
        return f"{float(value):.{places}f}"
    except (TypeError, ValueError):
        return str(value)


# ============================================================
#  CLI
# ============================================================

def main(argv=None) -> int:
    parser = argparse.ArgumentParser(
        prog="python -m db.load_deployment",
        description="Load a glider deployment's output/ folder into SQLite.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""examples:
  python -m db.load_deployment /data/glider/890_2023/output
  python -m db.load_deployment ./output --db /srv/incois/glider_rtqc.db
  python -m db.load_deployment ./output --glider-id 1131 --no-check

Safe to re-run on the same deployment: observation_id is a deterministic
hash of (glider_id, timestamp), so a second ingest updates rows in place.
""")
    parser.add_argument("output_dir",
                        help="deployment output/ directory")
    parser.add_argument("--db", default="glider_rtqc.db",
                        help="SQLite database path (default: glider_rtqc.db)")
    parser.add_argument("--glider-id", default=None,
                        help="override the auto-detected glider id")
    parser.add_argument("--no-check", action="store_true",
                        help="skip the post-load sanity check")
    parser.add_argument("-q", "--quiet", action="store_true",
                        help="suppress progress output")
    args = parser.parse_args(argv)

    try:
        result = load_deployment(args.output_dir, args.db,
                                 glider_id=args.glider_id,
                                 verbose=not args.quiet)
    except FileNotFoundError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    if not args.no_check:
        sanity_check(args.db, result["glider_id"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
