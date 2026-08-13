#!/usr/bin/env python3
"""
load_deployment.py — ingest EGO 1.5 NetCDF files into SQLite.

Schema: Pattern A (wide core + tall bgc)
  core: one row per observation with fixed columns (TEMP, TEMP_QC, PSAL, ...)
  bgc:  one row per (observation_id, variable_name) for open-ended sensors

The EGO file is the SINGLE source of truth for variable names and values.
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


# ── Constants ────────────────────────────────────────────────────────────────
CORE_PARAMS = ("PRES", "TEMP", "PSAL", "CNDC")
FILL_FLOAT = 99999.0
FILL_TIME = 9999999999.0
BATCH_SIZE = 50_000
SCHEMA_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "schema.sql")


# ── Helpers ──────────────────────────────────────────────────────────────────

def make_observation_id(glider_id: str, timestamp_iso: str) -> int:
    digest = hashlib.sha256(f"{glider_id}|{timestamp_iso}".encode()).digest()
    return int.from_bytes(digest[:8], "big") & 0x7FFF_FFFF_FFFF_FFFF


def _haversine_km(lat1, lon1, lat2, lon2):
    R = 6371.0
    dlat = np.radians(lat2 - lat1)
    dlon = np.radians(lon2 - lon1)
    a = (np.sin(dlat / 2) ** 2
         + np.cos(np.radians(lat1)) * np.cos(np.radians(lat2))
         * np.sin(dlon / 2) ** 2)
    return R * 2 * np.arcsin(np.sqrt(np.clip(a, 0, 1)))


def _read_char_array(nc, var_name: str) -> list[str]:
    if var_name not in nc.variables:
        return []
    arr = nc.variables[var_name][:]
    return ["".join(str(c) for c in arr[i]).strip() for i in range(arr.shape[0])]


def _float_or_none(val) -> float | None:
    if np.isfinite(val) and abs(val) < FILL_FLOAT - 1:
        return float(val)
    return None


def _int_or_none(val, fill=-128) -> int | None:
    v = int(val)
    return v if v != fill else None


# ── GPS distance ─────────────────────────────────────────────────────────────

def compute_distance_from_gps(nc) -> float | None:
    if "TIME_GPS" not in nc.variables:
        return None
    t = np.asarray(nc.variables["TIME_GPS"][:], dtype=np.float64)
    lat = np.asarray(nc.variables["LATITUDE_GPS"][:], dtype=np.float64)
    lon = np.asarray(nc.variables["LONGITUDE_GPS"][:], dtype=np.float64)
    valid = np.isfinite(t) & np.isfinite(lat) & np.isfinite(lon) & (t < FILL_TIME - 1)
    if valid.sum() < 2:
        return None
    lat_v, lon_v, t_v = lat[valid], lon[valid], t[valid]
    order = np.argsort(t_v)
    lat_v, lon_v, t_v = lat_v[order], lon_v[order], t_v[order]
    dists = _haversine_km(lat_v[:-1], lon_v[:-1], lat_v[1:], lon_v[1:])
    dt_h = np.diff(t_v) / 3600.0
    speed = np.where(dt_h > 0.001, dists / dt_h, np.inf)
    good = speed <= 10.8  # 3 m/s max
    return float(dists[good].sum()) if good.any() else None


def _build_gps_fix_set(nc) -> set:
    if "TIME_GPS" not in nc.variables:
        return set()
    t = np.asarray(nc.variables["TIME_GPS"][:], dtype=np.float64)
    valid = np.isfinite(t) & (t < FILL_TIME - 1)
    return set(np.round(t[valid]).astype(np.int64))


# ── File discovery ───────────────────────────────────────────────────────────

def find_ego_files(ego_dir: str, verbose: bool = True) -> dict:
    """
    Locate the EGO L0 and L1 NetCDF in a directory.

    Classification is by the data the file actually carries, not by filename:
    an L1 has QC flags with at least one non-zero verdict and *_ADJUSTED
    variables, an L0 does not. Filenames in this pipeline have varied
    (`_L1_EGO.nc`, `_2024_EGO.nc`), so name-sniffing alone silently picked up a
    stale file from an earlier run once already.

    When several files classify the same way the most recently modified one
    wins and the others are reported, so a leftover never quietly becomes the
    source of truth.
    """
    import netCDF4

    ego_dir = os.path.abspath(ego_dir)
    result = {"ego_l0": None, "ego_l1": None}
    if not os.path.isdir(ego_dir):
        return result

    l0_cands, l1_cands = [], []
    for f in sorted(os.listdir(ego_dir)):
        if not f.endswith(".nc"):
            continue
        path = os.path.join(ego_dir, f)
        try:
            nc = netCDF4.Dataset(path)
            nc.set_auto_mask(False)
            try:
                has_adjusted = any(v.endswith("_ADJUSTED") for v in nc.variables)
            finally:
                nc.close()
        except OSError:
            continue
        (l1_cands if has_adjusted else l0_cands).append(path)

    for key, cands in (("ego_l1", l1_cands), ("ego_l0", l0_cands)):
        if not cands:
            continue
        cands.sort(key=os.path.getmtime, reverse=True)
        result[key] = cands[0]
        if len(cands) > 1 and verbose:
            print(f"  NOTE: {len(cands)} candidate {key} files in {ego_dir}; "
                  f"using the newest ({os.path.basename(cands[0])}). "
                  f"Ignored: {', '.join(os.path.basename(c) for c in cands[1:])}")
    return result


# ── Database ─────────────────────────────────────────────────────────────────

def _connect(db_path):
    conn = sqlite3.connect(db_path)
    conn.execute("PRAGMA foreign_keys = ON")
    conn.execute("PRAGMA journal_mode = WAL")
    conn.execute("PRAGMA synchronous = OFF")
    conn.execute("PRAGMA temp_store = MEMORY")
    conn.execute("PRAGMA cache_size = -64000")
    return conn


def _apply_schema(conn):
    with open(SCHEMA_PATH, "r", encoding="utf-8") as f:
        conn.executescript(f.read())


# ── Wide table generation ────────────────────────────────────────────────────
# Both core and bgc are wide: four real columns per parameter. The column list
# comes from the EGO PARAMETER array, so the tables are readable in a SQL
# browser without pivoting AND a deployment with a new sensor still loads.

def _col_names(param: str) -> tuple[str, str, str, str]:
    """The four column names for one EGO parameter."""
    return (param, f"{param}_QC", f"{param}_ADJUSTED", f"{param}_ADJUSTED_QC")


def _safe_param(param: str) -> bool:
    """Only accept identifiers safe to interpolate into DDL."""
    return bool(re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*", param))


def _create_wide_table(conn, table: str, params: list[str]) -> None:
    """CREATE TABLE <table> with one named column set per parameter."""
    cols = [
        "observation_id   INTEGER PRIMARY KEY "
        "REFERENCES observation(observation_id) ON DELETE CASCADE"
    ]
    for p in params:
        v, q, a, aq = _col_names(p)
        cols.append(f'"{v}"  REAL')
        cols.append(f'"{q}"  INTEGER')
        cols.append(f'"{a}"  REAL')
        cols.append(f'"{aq}" INTEGER')
    conn.execute(f'CREATE TABLE IF NOT EXISTS "{table}" (\n  '
                 + ",\n  ".join(cols) + "\n)")

    # One index per parameter's QC column: "all good TEMP" is the dominant
    # filter in the dashboard and in downstream analysis.
    for p in params:
        conn.execute(f'CREATE INDEX IF NOT EXISTS "idx_{table}_{p}_qc" '
                     f'ON "{table}" ("{p}_QC")')


def _wide_upsert(table: str, params: list[str]) -> str:
    """INSERT ... ON CONFLICT DO UPDATE across every generated column."""
    cols, sets = ["observation_id"], []
    for p in params:
        for c in _col_names(p):
            cols.append(c)
            sets.append(f'"{c}" = excluded."{c}"')
    placeholders = ",".join("?" * len(cols))
    quoted = ", ".join(f'"{c}"' for c in cols)
    return (f'INSERT INTO "{table}" ({quoted}) VALUES ({placeholders})\n'
            f'ON CONFLICT(observation_id) DO UPDATE SET\n  '
            + ",\n  ".join(sets))


def _create_views(conn, core_params: list[str], bgc_params: list[str]) -> None:
    """
    Rebuild the convenience views for whichever parameters this file carries.

    Dropped and recreated on every load because the column list is
    deployment-dependent; a view left over from a deployment with a different
    sensor suite would reference columns that no longer exist.
    """
    for name in ("core_full", "bgc_full", "core_qc_summary",
                 "bgc_qc_summary", "measurement_full"):
        conn.execute(f"DROP VIEW IF EXISTS {name}")

    for table, params in (("core", core_params), ("bgc", bgc_params)):
        if not params:
            continue
        sel = ", ".join(f't."{c}"' for p in params for c in _col_names(p))
        conn.execute(f"""
CREATE VIEW {table}_full AS
SELECT o.glider_id, o.timestamp, o.latitude, o.longitude,
       o.phase, o.phase_number, o.has_gps_fix, {sel}
  FROM observation o
  JOIN "{table}" t ON t.observation_id = o.observation_id""")

        # Per-parameter QC rollup. n_values (measurements) and n_flagged (QC
        # verdicts) are counted separately on purpose: a point flagged 4 or 9
        # has a verdict but no published value, so pct_good is a share of
        # FLAGGED points. Counting flags against n_values produced
        # good+bad+missing > n_values in an earlier version of this view.
        branches = []
        for p in params:
            v, q, a, _ = _col_names(p)
            branches.append(f"""
SELECT o.glider_id, '{p}' AS variable_name,
       COUNT(*)                    AS n_total,
       COUNT(t."{v}")              AS n_values,
       COUNT(t."{q}")              AS n_flagged,
       SUM(t."{q}" = 1)            AS n_good,
       SUM(t."{q}" = 2)            AS n_probably_good,
       SUM(t."{q}" = 3)            AS n_probably_bad,
       SUM(t."{q}" = 4)            AS n_bad,
       SUM(t."{q}" = 9)            AS n_missing,
       SUM(t."{q}" = 0)            AS n_no_qc,
       COUNT(t."{a}")              AS n_adjusted,
       CASE WHEN COUNT(t."{q}") > 0
            THEN ROUND(100.0 * SUM(t."{q}" IN (1,2)) / COUNT(t."{q}"), 2)
            END                    AS pct_good
  FROM observation o
  JOIN "{table}" t ON t.observation_id = o.observation_id
 GROUP BY o.glider_id""")
        conn.execute(f"CREATE VIEW {table}_qc_summary AS"
                     + "\nUNION ALL".join(branches))


# ── SQL statements ───────────────────────────────────────────────────────────

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
    deployment_name=excluded.deployment_name, deployment_start=excluded.deployment_start,
    deployment_end=excluded.deployment_end, max_depth_dbar=excluded.max_depth_dbar,
    n_profiles=excluded.n_profiles, n_observations=excluded.n_observations,
    n_gps_fixes=excluded.n_gps_fixes, distance_over_ground_km=excluded.distance_over_ground_km,
    pipeline_version=excluded.pipeline_version, ego_format_version=excluded.ego_format_version,
    data_mode=excluded.data_mode, institution=excluded.institution,
    rtqc_tests_applied=excluded.rtqc_tests_applied, processed_at=excluded.processed_at,
    ego_l0_path=excluded.ego_l0_path, ego_l1_path=excluded.ego_l1_path
"""

OBS_UPSERT = """
INSERT INTO observation (observation_id, glider_id, timestamp,
                         latitude, longitude, phase, phase_number,
                         position_qc, has_gps_fix)
VALUES (?,?,?,?,?,?,?,?,?)
ON CONFLICT(observation_id) DO UPDATE SET
    glider_id=excluded.glider_id, timestamp=excluded.timestamp,
    latitude=excluded.latitude, longitude=excluded.longitude,
    phase=excluded.phase, phase_number=excluded.phase_number,
    position_qc=excluded.position_qc, has_gps_fix=excluded.has_gps_fix
"""



# core/bgc upserts are generated per deployment by _wide_upsert(), since the
# column list depends on which parameters the EGO file carries.


# ── Main loader ──────────────────────────────────────────────────────────────

def load_deployment(ego_l1_path=None, ego_l0_path=None, ego_dir=None,
                    db_path="glider_rtqc.db", glider_id=None,
                    verbose=True) -> dict:
    import netCDF4

    t0 = _time.time()

    if ego_dir and not ego_l1_path:
        files = find_ego_files(ego_dir)
        ego_l1_path = files.get("ego_l1")
        ego_l0_path = ego_l0_path or files.get("ego_l0")

    primary = ego_l1_path or ego_l0_path
    if not primary:
        raise FileNotFoundError("No EGO NetCDF provided.")

    nc = netCDF4.Dataset(primary)
    # REQUIRED, not an optimisation. The EGO 1.5 spec pins TIME.valid_max to
    # 90000 while TIME is epoch seconds (~1.7e9), so netCDF4's default
    # valid_min/valid_max auto-masking would mask EVERY timestamp and the load
    # would silently produce zero rows. Fill values are handled explicitly in
    # _float_or_none / _int_or_none instead.
    nc.set_auto_mask(False)
    try:
        # ── Discover parameters ──────────────────────────────────────────
        params = _read_char_array(nc, "PARAMETER")
        bgc_params = [p for p in params if p not in CORE_PARAMS]

        def _attr(name, default=""):
            return str(nc.getncattr(name)) if name in nc.ncattrs() else default

        gid = glider_id or _attr("platform_code", "unknown")
        if gid == "unknown":
            base = os.path.basename(primary)
            m = re.match(r"incois_glider_(.+?)(?:_L[01])?_EGO\.nc$", base, re.I)
            if m:
                gid = m.group(1)

        # ── Read arrays ──────────────────────────────────────────────────
        t_raw = np.asarray(nc.variables["TIME"][:], dtype=np.float64)
        n = len(t_raw)

        # Timestamps
        ts_strings = []
        for t in t_raw:
            if np.isfinite(t) and t < FILL_TIME - 1:
                dt = datetime.fromtimestamp(float(t), tz=timezone.utc)
                ts_strings.append(dt.strftime("%Y-%m-%dT%H:%M:%S.%fZ"))
            else:
                ts_strings.append(None)

        # Observation IDs
        obs_ids = [make_observation_id(gid, ts) if ts else None for ts in ts_strings]

        # Position + phase
        def _arr(name):
            if name not in nc.variables:
                return np.full(n, np.nan)
            return np.asarray(nc.variables[name][:], dtype=np.float64)

        def _int_arr(name, fill):
            if name not in nc.variables:
                return np.full(n, fill, dtype=np.int32)
            return np.asarray(nc.variables[name][:], dtype=np.int32)

        lat = _arr("LATITUDE")
        lon = _arr("LONGITUDE")
        phase = _int_arr("PHASE", -128)
        phase_num = _int_arr("PHASE_NUMBER", 99999)
        pos_qc = _int_arr("POSITION_QC", -1)

        # GPS
        gps_fix_set = _build_gps_fix_set(nc)
        distance_km = compute_distance_from_gps(nc)
        t_round = np.round(t_raw).astype(np.int64)

        # Only keep parameters the file actually carries, and only names safe
        # to use as SQL identifiers.
        core_list = [p for p in CORE_PARAMS
                     if p in nc.variables and _safe_param(p)]
        bgc_list = [p for p in bgc_params
                    if p in nc.variables and _safe_param(p)]
        skipped = [p for p in (list(CORE_PARAMS) + bgc_params)
                   if p in nc.variables and not _safe_param(p)]
        if skipped:
            print(f"  WARNING: skipping parameter(s) whose names are not valid "
                  f"SQL identifiers: {', '.join(skipped)}")

        # Read every column once, up front; the row loop just indexes them.
        col_arrays = {}
        for p in core_list + bgc_list:
            col_arrays[p] = {
                "val": _arr(p),
                "qc": _int_arr(f"{p}_QC", -128),
                "adj": _arr(f"{p}_ADJUSTED"),
                "adj_qc": _int_arr(f"{p}_ADJUSTED_QC", -128),
            }

        # Counts
        pres = col_arrays["PRES"]["val"] if "PRES" in col_arrays \
            else np.full(n, np.nan)
        pres_valid = pres[np.isfinite(pres) & (pres < FILL_FLOAT - 1)]
        max_depth = float(pres_valid.max()) if pres_valid.size > 0 else None
        pn_valid = phase_num[phase_num != 99999]
        n_profiles = int(np.unique(pn_valid).size) if pn_valid.size > 0 else 0
        n_gps = len(gps_fix_set)

        if verbose:
            print("=" * 68)
            print("  GLIDER EGO -> SQLITE (wide core + wide bgc)")
            print("=" * 68)
            print(f"  source     : {os.path.basename(primary)}")
            print(f"  glider_id  : {gid}")
            print(f"  timestamps : {n:,}")
            print(f"  profiles   : {n_profiles}")
            print(f"  GPS fixes  : {n_gps}")
            print(f"  distance   : {distance_km:.1f} km" if distance_km else "  distance   : N/A")
            print(f"  max depth  : {max_depth:.1f} dbar" if max_depth else "  max depth  : N/A")
            print(f"  core cols  : {', '.join(core_list)}"
                  f"  ({len(core_list) * 4} columns)")
            print(f"  bgc cols   : {', '.join(bgc_list)}"
                  f"  ({len(bgc_list) * 4} columns)")

        # ── Write to DB ──────────────────────────────────────────────────
        meta_row = {
            "glider_id": gid,
            "deployment_name": _attr("deployment_code") or _attr("title") or _attr("id"),
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

        conn = _connect(db_path)
        try:
            _apply_schema(conn)
            _create_wide_table(conn, "core", core_list)
            _create_wide_table(conn, "bgc", bgc_list)
            core_sql = _wide_upsert("core", core_list) if core_list else None
            bgc_sql = _wide_upsert("bgc", bgc_list) if bgc_list else None

            def _row_for(params, i, oid):
                row = [oid]
                for p in params:
                    a = col_arrays[p]
                    qc, aqc = a["qc"][i], a["adj_qc"][i]
                    row.append(_float_or_none(a["val"][i]))
                    row.append(int(qc) if qc != -128 else None)
                    row.append(_float_or_none(a["adj"][i]))
                    row.append(int(aqc) if aqc != -128 else None)
                return tuple(row)

            with conn:
                conn.execute(META_UPSERT, meta_row)

                # observation, core and bgc all written in one pass, batched, so
                # nothing larger than BATCH_SIZE rows is resident at a time.
                obs_batch, core_batch, bgc_batch = [], [], []
                n_obs = 0

                def _flush():
                    nonlocal n_obs
                    if not obs_batch:
                        return
                    conn.executemany(OBS_UPSERT, obs_batch)
                    if core_sql:
                        conn.executemany(core_sql, core_batch)
                    if bgc_sql:
                        conn.executemany(bgc_sql, bgc_batch)
                    n_obs += len(obs_batch)
                    obs_batch.clear()
                    core_batch.clear()
                    bgc_batch.clear()

                for i in range(n):
                    oid = obs_ids[i]
                    if oid is None:
                        continue
                    ph, pn, pq = phase[i], phase_num[i], pos_qc[i]
                    obs_batch.append((
                        oid, gid, ts_strings[i],
                        _float_or_none(lat[i]), _float_or_none(lon[i]),
                        int(ph) if ph != -128 else None,
                        int(pn) if pn != 99999 else None,
                        int(pq) if pq >= 0 else None,
                        1 if t_round[i] in gps_fix_set else 0,
                    ))
                    if core_sql:
                        core_batch.append(_row_for(core_list, i, oid))
                    if bgc_sql:
                        bgc_batch.append(_row_for(bgc_list, i, oid))
                    if len(obs_batch) >= BATCH_SIZE:
                        _flush()
                _flush()

                _create_views(conn, core_list, bgc_list)

            conn.execute("PRAGMA synchronous = NORMAL")
            conn.execute("ANALYZE")
            conn.execute("PRAGMA optimize")
        finally:
            conn.close()

        n_core = n_obs if core_list else 0
        n_bgc = n_obs if bgc_list else 0

    finally:
        nc.close()

    elapsed = _time.time() - t0
    result = {
        "glider_id": gid,
        "db_path": os.path.abspath(db_path),
        "rows": {"meta": 1, "observation": n_obs, "core": n_core, "bgc": n_bgc},
        "core_params": core_list,
        "bgc_params": bgc_list,
        "elapsed_s": elapsed,
        "meta": meta_row,
    }

    if verbose:
        print(f"\n  Rows: observation={n_obs:,}  core={n_core:,}  bgc={n_bgc:,}")
        print(f"  Done in {elapsed:.1f}s -> {os.path.abspath(db_path)}")
        print("=" * 68)

    return result


# ── CLI ──────────────────────────────────────────────────────────────────────

def main(argv=None) -> int:
    parser = argparse.ArgumentParser(
        prog="python -m db.load_deployment",
        description="Load EGO 1.5 NetCDF into SQLite (wide core + tall bgc).")
    parser.add_argument("--ego-dir", default=None)
    parser.add_argument("--ego-l1", default=None)
    parser.add_argument("--ego-l0", default=None)
    parser.add_argument("--db", default="glider_rtqc.db")
    parser.add_argument("--glider-id", default=None)
    parser.add_argument("-q", "--quiet", action="store_true")
    args = parser.parse_args(argv)

    if not args.ego_dir and not args.ego_l1 and not args.ego_l0:
        parser.error("Provide --ego-dir, --ego-l1, or --ego-l0")

    try:
        load_deployment(
            ego_l1_path=args.ego_l1,
            ego_l0_path=args.ego_l0,
            ego_dir=args.ego_dir,
            db_path=args.db,
            glider_id=args.glider_id,
            verbose=not args.quiet,
        )
    except (FileNotFoundError, ValueError) as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
