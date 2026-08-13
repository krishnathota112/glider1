#!/usr/bin/env python3
"""
ego_api.py — Flask blueprint serving the EGO NetCDF metadata and the SQLite
database behind the dashboard.

Kept separate from app.py, which owns deployment discovery, plot serving and the
pipeline runner. This module is read-only: it never writes to the database or
the NetCDF files.

Endpoints
---------
  GET /api/db/deployments                     rows from `meta`
  GET /api/db/<gid>/qc                        core + bgc QC summary
  GET /api/db/<gid>/track                     GPS-fix track points
  GET /api/db/<gid>/profiles                  profile index with depth range
  GET /api/db/<gid>/profile/<n>               one profile, all parameters
  GET /api/db/<gid>/timeseries?var=TEMP       downsampled series
  GET /api/ego/<gid>/metadata                 platform/sensor/param/history block
  GET /api/ego/<gid>/compliance               EGO 1.5 checker verdict
"""
from __future__ import annotations

import os
import sqlite3
import sys

from flask import Blueprint, jsonify, request

_REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if _REPO_ROOT not in sys.path:
    sys.path.insert(0, _REPO_ROOT)

ego_api = Blueprint("ego_api", __name__)

# Parameters stored as fixed columns in `core`; everything else lives in `bgc`.
CORE_PARAMS = ("PRES", "TEMP", "PSAL", "CNDC")

# EGO reference table 9.2 and 10.2, for turning stored codes into labels.
PHASE_LABELS = {
    0: "surface_drift", 1: "descent", 2: "subsurface_drift",
    3: "inflexion", 4: "ascent", 5: "grounded", 6: "inconsistent",
}
POSITIONING_LABELS = {0: "GPS", 1: "Argos", 2: "interpolated"}
QC_LABELS = {
    0: "no_qc_performed", 1: "good_data", 2: "probably_good_data",
    3: "bad_data_potentially_correctable", 4: "bad_data",
    5: "value_changed", 8: "interpolated_value", 9: "missing_value",
}


def db_path() -> str:
    """Database location, overridable with GLIDER_DB."""
    return os.path.abspath(os.environ.get(
        "GLIDER_DB", os.path.join(_REPO_ROOT, "glider_ego.db")))


def _connect() -> sqlite3.Connection | None:
    p = db_path()
    if not os.path.exists(p):
        return None
    # read-only: the dashboard must never mutate the product database, and this
    # also lets it open a file another process holds for writing.
    conn = sqlite3.connect(f"file:{p}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    return conn


def _table_params(conn, table: str) -> list[str]:
    """
    Parameter names carried by a wide table, read from its columns.

    Both core and bgc are wide with a <VAR>/<VAR>_QC/<VAR>_ADJUSTED/
    <VAR>_ADJUSTED_QC group per parameter, and the column list is generated per
    deployment at load time. Deriving the names from the table keeps the API
    working for a deployment with sensors this code has never seen.
    """
    cols = [r[1] for r in conn.execute(f'PRAGMA table_info("{table}")')]
    return [c for c in cols
            if c != "observation_id"
            and not c.endswith(("_QC", "_ADJUSTED", "_ADJUSTED_QC"))]


def _no_db():
    return jsonify({
        "error": "database not found",
        "expected": db_path(),
        "hint": "Build it with: python tools/load_db.py <deployment_dir> --fresh",
    }), 503


# ── Database endpoints ───────────────────────────────────────────────────────

@ego_api.route("/api/db/deployments")
def db_deployments():
    conn = _connect()
    if conn is None:
        return _no_db()
    try:
        rows = [dict(r) for r in conn.execute(
            "SELECT * FROM meta ORDER BY glider_id")]
        for r in rows:
            # Surface whether the referenced EGO files still exist, so a moved
            # or deleted product shows up in the UI instead of 500ing later.
            r["ego_l1_exists"] = bool(r.get("ego_l1_path")
                                      and os.path.exists(r["ego_l1_path"]))
            r["ego_l0_exists"] = bool(r.get("ego_l0_path")
                                      and os.path.exists(r["ego_l0_path"]))
        return jsonify({"db": db_path(), "deployments": rows})
    finally:
        conn.close()


@ego_api.route("/api/db/<gid>/qc")
def db_qc(gid):
    conn = _connect()
    if conn is None:
        return _no_db()
    try:
        out = []
        for view, family in (("core_qc_summary", "core"),
                             ("bgc_qc_summary", "bgc")):
            for r in conn.execute(
                    f"SELECT * FROM {view} WHERE glider_id = ? "
                    f"ORDER BY variable_name", (gid,)):
                d = dict(r)
                d["family"] = family
                out.append(d)
        if not out:
            return jsonify({"error": f"no data for glider {gid}"}), 404
        return jsonify({"glider_id": gid, "variables": out,
                        "qc_labels": QC_LABELS})
    finally:
        conn.close()


@ego_api.route("/api/db/<gid>/track")
def db_track(gid):
    """
    Real GPS-fix positions only (has_gps_fix = 1).

    Interpolated positions are excluded deliberately: plotting all 184k
    dead-reckoned points draws a track the glider did not measure, and it was an
    inflated point-to-point sum over exactly those points that produced the
    earlier impossible distance figures.
    """
    conn = _connect()
    if conn is None:
        return _no_db()
    try:
        rows = [dict(r) for r in conn.execute(
            "SELECT timestamp, latitude, longitude, phase_number "
            "  FROM observation "
            " WHERE glider_id = ? AND has_gps_fix = 1 "
            "   AND latitude IS NOT NULL AND longitude IS NOT NULL "
            " ORDER BY timestamp", (gid,))]
        meta = conn.execute(
            "SELECT distance_over_ground_km, n_gps_fixes FROM meta "
            " WHERE glider_id = ?", (gid,)).fetchone()
        return jsonify({
            "glider_id": gid,
            "n_points": len(rows),
            "distance_km": (meta["distance_over_ground_km"] if meta else None),
            "note": "GPS surface fixes only; interpolated positions excluded",
            "points": rows,
        })
    finally:
        conn.close()


@ego_api.route("/api/db/<gid>/profiles")
def db_profiles(gid):
    conn = _connect()
    if conn is None:
        return _no_db()
    try:
        rows = [dict(r) for r in conn.execute(
            "SELECT o.phase_number                AS profile,"
            "       COUNT(*)                      AS n_samples,"
            "       MIN(o.timestamp)              AS t_start,"
            "       MAX(o.timestamp)              AS t_end,"
            "       MIN(c.PRES)                   AS pres_min,"
            "       MAX(c.PRES)                   AS pres_max,"
            "       MAX(o.phase)                  AS phase"
            "  FROM observation o"
            "  LEFT JOIN core c ON c.observation_id = o.observation_id"
            " WHERE o.glider_id = ? AND o.phase_number IS NOT NULL"
            " GROUP BY o.phase_number"
            " ORDER BY o.phase_number", (gid,))]
        for r in rows:
            r["phase_label"] = PHASE_LABELS.get(r.get("phase"), "unknown")
        return jsonify({"glider_id": gid, "n_profiles": len(rows),
                        "profiles": rows})
    finally:
        conn.close()


@ego_api.route("/api/db/<gid>/profile/<int:n>")
def db_profile(gid, n):
    """One profile with every parameter, suitable for a depth plot."""
    conn = _connect()
    if conn is None:
        return _no_db()
    try:
        core_rows = [dict(r) for r in conn.execute(
            "SELECT o.timestamp, o.phase, c.*"
            "  FROM observation o"
            "  JOIN core c ON c.observation_id = o.observation_id"
            " WHERE o.glider_id = ? AND o.phase_number = ?"
            " ORDER BY c.PRES", (gid, n))]
        if not core_rows:
            return jsonify({"error": f"profile {n} not found for {gid}"}), 404

        # bgc is wide, so read its columns and group them per parameter for the
        # response. Parameter names are discovered from the table itself.
        bgc_params = _table_params(conn, "bgc")
        bgc: dict[str, list] = {}
        if bgc_params:
            sel = ", ".join(f'b."{c}"' for p in bgc_params
                            for c in (p, f"{p}_QC", f"{p}_ADJUSTED",
                                      f"{p}_ADJUSTED_QC"))
            rows = conn.execute(
                f"SELECT c.PRES, {sel}"
                f"  FROM observation o"
                f"  JOIN bgc  b ON b.observation_id = o.observation_id"
                f"  LEFT JOIN core c ON c.observation_id = o.observation_id"
                f" WHERE o.glider_id = ? AND o.phase_number = ?"
                f" ORDER BY c.PRES", (gid, n)).fetchall()
            for p in bgc_params:
                series = []
                for r in rows:
                    if r[p] is None and r[f"{p}_QC"] is None:
                        continue
                    series.append({
                        "PRES": r["PRES"], "value": r[p], "qc": r[f"{p}_QC"],
                        "value_adjusted": r[f"{p}_ADJUSTED"],
                        "adjusted_qc": r[f"{p}_ADJUSTED_QC"],
                    })
                bgc[p] = series

        for r in core_rows:
            r.pop("observation_id", None)
            r["phase_label"] = PHASE_LABELS.get(r.get("phase"), "unknown")

        return jsonify({"glider_id": gid, "profile": n,
                        "n_samples": len(core_rows),
                        "core": core_rows, "bgc": bgc})
    finally:
        conn.close()


@ego_api.route("/api/db/<gid>/timeseries")
def db_timeseries(gid):
    """
    Downsampled series for one parameter.

    `good_only=1` restricts to QC flags 1/2. Downsampling uses a deterministic
    modulo stride rather than random sampling so repeated requests return the
    same series and the chart does not shimmer between reloads.
    """
    var = (request.args.get("var") or "TEMP").upper()
    limit = max(100, min(int(request.args.get("limit", 5000)), 50000))
    good_only = request.args.get("good_only") == "1"

    if not var.replace("_", "").isalnum():
        return jsonify({"error": "invalid variable name"}), 400

    conn = _connect()
    if conn is None:
        return _no_db()
    try:
        if var in CORE_PARAMS:
            qc_clause = f' AND c."{var}_QC" IN (1,2)' if good_only else ""
            total = conn.execute(
                f"SELECT COUNT(*) FROM observation o "
                f"  JOIN core c ON c.observation_id = o.observation_id "
                f" WHERE o.glider_id = ? AND c.{var} IS NOT NULL{qc_clause}",
                (gid,)).fetchone()[0]
            stride = max(1, total // limit)
            rows = [dict(r) for r in conn.execute(
                f"SELECT o.timestamp, c.PRES, c.{var} AS value,"
                f"       c.{var}_QC AS qc, c.{var}_ADJUSTED AS value_adjusted"
                f"  FROM observation o"
                f"  JOIN core c ON c.observation_id = o.observation_id"
                f" WHERE o.glider_id = ? AND c.{var} IS NOT NULL{qc_clause}"
                f"   AND (o.rowid % ?) = 0"
                f" ORDER BY o.timestamp LIMIT ?", (gid, stride, limit))]
        else:
            # bgc is wide too, so the parameter is a column. Validate the name
            # against the table's real columns before interpolating it.
            if var not in _table_params(conn, "bgc"):
                return jsonify({
                    "error": f"unknown variable {var}",
                    "available": sorted(_table_params(conn, "core")
                                        + _table_params(conn, "bgc")),
                }), 404
            qc_clause = f' AND b."{var}_QC" IN (1,2)' if good_only else ""
            total = conn.execute(
                f'SELECT COUNT(*) FROM observation o '
                f'  JOIN bgc b ON b.observation_id = o.observation_id '
                f' WHERE o.glider_id = ? AND b."{var}" IS NOT NULL{qc_clause}',
                (gid,)).fetchone()[0]
            if total == 0:
                return jsonify({"error": f"no data for variable {var}"}), 404
            stride = max(1, total // limit)
            rows = [dict(r) for r in conn.execute(
                f'SELECT o.timestamp, c.PRES, b."{var}" AS value,'
                f'       b."{var}_QC" AS qc,'
                f'       b."{var}_ADJUSTED" AS value_adjusted'
                f'  FROM observation o'
                f'  JOIN bgc  b ON b.observation_id = o.observation_id'
                f'  LEFT JOIN core c ON c.observation_id = o.observation_id'
                f' WHERE o.glider_id = ? AND b."{var}" IS NOT NULL{qc_clause}'
                f'   AND (o.rowid % ?) = 0'
                f' ORDER BY o.timestamp LIMIT ?', (gid, stride, limit))]

        return jsonify({
            "glider_id": gid, "variable": var,
            "n_total": total, "n_returned": len(rows),
            "stride": stride, "good_only": good_only,
            "points": rows,
        })
    finally:
        conn.close()


# ── EGO NetCDF endpoints ─────────────────────────────────────────────────────

def _ego_path_for(gid: str, level: str = "l1") -> str | None:
    """Resolve the EGO file for a glider from the meta table."""
    conn = _connect()
    if conn is None:
        return None
    try:
        row = conn.execute(
            f"SELECT ego_{level}_path FROM meta WHERE glider_id = ?",
            (gid,)).fetchone()
    finally:
        conn.close()
    if not row:
        return None
    p = row[0]
    return p if p and os.path.exists(p) else None


def _char_rows(nc, name: str) -> list[str]:
    """Read an (N, STRINGnn) char variable as a list of trimmed strings."""
    if name not in nc.variables:
        return []
    arr = nc.variables[name][:]
    out = []
    for i in range(arr.shape[0]):
        out.append("".join(str(c) for c in arr[i]).strip())
    return out


def _scalar_str(nc, name: str) -> str | None:
    if name not in nc.variables:
        return None
    v = nc.variables[name][:]
    try:
        return "".join(str(c) for c in v.flatten().tolist()).strip()
    except Exception:
        return str(v).strip()


@ego_api.route("/api/ego/<gid>/metadata")
def ego_metadata(gid):
    """
    The EGO metadata blocks read straight from the NetCDF: global attributes,
    platform characteristics, deployment, sensors, parameters and history.

    Read from the file rather than the database on purpose — this is the view
    that shows what was actually published, independent of what was ingested.
    """
    import netCDF4

    path = _ego_path_for(gid, "l1") or _ego_path_for(gid, "l0")
    if not path:
        return jsonify({"error": f"no EGO file on record for glider {gid}"}), 404

    nc = netCDF4.Dataset(path)
    # TIME.valid_max is 90000 per the EGO spec while TIME holds epoch seconds,
    # so default auto-masking would blank the time axis. Read raw.
    nc.set_auto_mask(False)
    try:
        globals_ = {k: str(nc.getncattr(k)) for k in nc.ncattrs()}

        platform = {k: _scalar_str(nc, k) for k in (
            "PLATFORM_FAMILY", "PLATFORM_TYPE", "PLATFORM_MAKER",
            "GLIDER_SERIAL_NO", "GLIDER_OWNER", "OPERATING_INSTITUTION",
            "WMO_INST_TYPE", "BATTERY_TYPE", "BATTERY_PACKS",
            "FIRMWARE_VERSION_NAVIGATION", "FIRMWARE_VERSION_SCIENCE",
            "GLIDER_MANUAL_VERSION", "DAC_FORMAT_ID", "ANOMALY",
        ) if k in nc.variables}
        platform["POSITIONING_SYSTEM"] = _char_rows(nc, "POSITIONING_SYSTEM")
        platform["TRANS_SYSTEM"] = _char_rows(nc, "TRANS_SYSTEM")

        def _num(name):
            if name not in nc.variables:
                return None
            try:
                val = float(nc.variables[name][...])
            except Exception:
                return None
            return None if abs(val) >= 99999 - 1 else val

        deployment = {
            "DEPLOYMENT_START_DATE": _scalar_str(nc, "DEPLOYMENT_START_DATE"),
            "DEPLOYMENT_START_LATITUDE": _num("DEPLOYMENT_START_LATITUDE"),
            "DEPLOYMENT_START_LONGITUDE": _num("DEPLOYMENT_START_LONGITUDE"),
            "DEPLOYMENT_END_DATE": _scalar_str(nc, "DEPLOYMENT_END_DATE"),
            "DEPLOYMENT_END_LATITUDE": _num("DEPLOYMENT_END_LATITUDE"),
            "DEPLOYMENT_END_LONGITUDE": _num("DEPLOYMENT_END_LONGITUDE"),
            "DEPLOYMENT_END_STATUS": _scalar_str(nc, "DEPLOYMENT_END_STATUS"),
            "DEPLOYMENT_OPERATOR": _scalar_str(nc, "DEPLOYMENT_OPERATOR"),
            "DEPLOYMENT_PLATFORM": _scalar_str(nc, "DEPLOYMENT_PLATFORM"),
            "DEPLOYMENT_CRUISE_ID": _scalar_str(nc, "DEPLOYMENT_CRUISE_ID"),
        }

        names = _char_rows(nc, "SENSOR")
        sensors = [{
            "SENSOR": names[i],
            "SENSOR_MAKER": _char_rows(nc, "SENSOR_MAKER")[i:i + 1] and
                            _char_rows(nc, "SENSOR_MAKER")[i],
            "SENSOR_MODEL": _char_rows(nc, "SENSOR_MODEL")[i],
            "SENSOR_SERIAL_NO": _char_rows(nc, "SENSOR_SERIAL_NO")[i],
            "SENSOR_MOUNT": (_char_rows(nc, "SENSOR_MOUNT") or [""] * len(names))[i],
            "SENSOR_ORIENTATION": (_char_rows(nc, "SENSOR_ORIENTATION")
                                   or [""] * len(names))[i],
        } for i in range(len(names))]

        pnames = _char_rows(nc, "PARAMETER")
        psensor = _char_rows(nc, "PARAMETER_SENSOR")
        punits = _char_rows(nc, "PARAMETER_UNITS") or [""] * len(pnames)
        pacc = _char_rows(nc, "PARAMETER_ACCURACY") or [""] * len(pnames)
        pres_ = _char_rows(nc, "PARAMETER_RESOLUTION") or [""] * len(pnames)
        dm = nc.variables["PARAMETER_DATA_MODE"][:] \
            if "PARAMETER_DATA_MODE" in nc.variables else []
        parameters = [{
            "PARAMETER": pnames[i],
            "PARAMETER_SENSOR": psensor[i] if i < len(psensor) else "",
            "PARAMETER_UNITS": punits[i],
            "PARAMETER_ACCURACY": pacc[i],
            "PARAMETER_RESOLUTION": pres_[i],
            "PARAMETER_DATA_MODE": (str(dm[i]).strip() if i < len(dm) else ""),
        } for i in range(len(pnames))]

        h_action = _char_rows(nc, "HISTORY_ACTION")
        history = [{
            "HISTORY_INSTITUTION": (_char_rows(nc, "HISTORY_INSTITUTION") or [""])[i],
            "HISTORY_STEP": (_char_rows(nc, "HISTORY_STEP") or [""])[i],
            "HISTORY_SOFTWARE": (_char_rows(nc, "HISTORY_SOFTWARE") or [""])[i],
            "HISTORY_SOFTWARE_RELEASE": (_char_rows(nc, "HISTORY_SOFTWARE_RELEASE") or [""])[i],
            "HISTORY_DATE": (_char_rows(nc, "HISTORY_DATE") or [""])[i],
            "HISTORY_ACTION": h_action[i],
            "HISTORY_PARAMETER": (_char_rows(nc, "HISTORY_PARAMETER") or [""])[i],
            "HISTORY_QCTEST": (_char_rows(nc, "HISTORY_QCTEST") or [""])[i],
        } for i in range(len(h_action))]

        dims = {k: len(v) for k, v in nc.dimensions.items()}

        return jsonify({
            "glider_id": gid,
            "file": os.path.basename(path),
            "path": path,
            "dimensions": dims,
            "global_attributes": globals_,
            "platform": platform,
            "deployment": deployment,
            "sensors": sensors,
            "parameters": parameters,
            "history": history,
        })
    finally:
        nc.close()


@ego_api.route("/api/ego/<gid>/compliance")
def ego_compliance(gid):
    """
    Run the EGO 1.5 checker against this deployment's files, live.

    The verdict comes from tools/ego_checker.py parsing the official rules XML,
    so the dashboard reports real validation rather than a cached claim.
    """
    try:
        from tools.ego_checker import DEFAULT_RULES, check_file
    except ImportError:
        sys.path.insert(0, os.path.join(_REPO_ROOT, "tools"))
        from ego_checker import DEFAULT_RULES, check_file  # type: ignore

    if not os.path.exists(DEFAULT_RULES):
        return jsonify({"error": "EGO rules XML not found",
                        "expected": DEFAULT_RULES}), 503

    results = {}
    for level in ("l0", "l1"):
        path = _ego_path_for(gid, level)
        if not path:
            continue
        rep = check_file(path)
        results[level] = {
            "file": os.path.basename(path),
            "compliant": rep.compliant,
            "checks_passed": rep.passes,
            "failures": rep.failures,
            "warnings": rep.warnings,
        }

    if not results:
        return jsonify({"error": f"no EGO files on record for {gid}"}), 404

    return jsonify({
        "glider_id": gid,
        "spec": "EGO 1.5",
        "rules_file": os.path.basename(DEFAULT_RULES),
        "results": results,
        "overall_compliant": all(r["compliant"] for r in results.values()),
    })
