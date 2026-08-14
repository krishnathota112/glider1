#!/usr/bin/env bash
#
# run_dashboard.sh — start the glider web dashboard.
#
#   ./run_dashboard.sh /path/to/Raw_Data
#
# The dashboard then lets you, from the browser:
#   - see every deployment folder found under Raw_Data
#   - run the pipeline on them one at a time
#   - ingest the resulting EGO products into ONE shared SQLite database
#
# Ingestion appends. `meta` is keyed on glider_id and every write is
# ON CONFLICT DO UPDATE, so ingesting a new deployment leaves the existing ones
# untouched, and re-ingesting one refreshes its rows instead of duplicating.
#
# SECURITY: the dashboard has NO AUTHENTICATION and it starts subprocesses on
# this machine. It therefore binds to 127.0.0.1 by default and you reach it
# over an SSH tunnel (printed below). Only pass --host 0.0.0.0 if you
# understand that it lets anyone who can reach the port run the pipeline here.

set -euo pipefail

# ── Args ────────────────────────────────────────────────────────────
RAW_DATA_DIR=""
HOST="127.0.0.1"
PORT="5000"
DB=""
DO_INGEST=0

usage() {
    cat <<'USAGE'
Usage: ./run_dashboard.sh <RAW_DATA_DIR> [options]

  <RAW_DATA_DIR>        Folder holding one subdirectory per deployment.

Options:
  --host HOST           Bind address (default 127.0.0.1; use an SSH tunnel).
                        0.0.0.0 exposes an unauthenticated app - see below.
  --port PORT           Bind port (default 5000).
  --db PATH             SQLite database (default <repo>/glider_rtqc.db).
  --ingest-now          Ingest every ready deployment on startup, then serve.
  -h, --help            This message.

Examples:
  ./run_dashboard.sh ~/Raw_Data
  ./run_dashboard.sh ~/Raw_Data --port 8080 --ingest-now
  ./run_dashboard.sh /data/Raw_Data --db /data/glider_rtqc.db
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --host)       HOST="$2"; shift 2 ;;
        --port)       PORT="$2"; shift 2 ;;
        --db)         DB="$2";   shift 2 ;;
        --ingest-now) DO_INGEST=1; shift ;;
        -h|--help)    usage; exit 0 ;;
        -*)           echo "Unknown option: $1" >&2; usage; exit 2 ;;
        *)
            if [[ -z "$RAW_DATA_DIR" ]]; then
                RAW_DATA_DIR="$1"; shift
            else
                echo "Unexpected argument: $1" >&2; usage; exit 2
            fi ;;
    esac
done

if [[ -z "$RAW_DATA_DIR" ]]; then
    echo "ERROR: RAW_DATA_DIR is required." >&2
    echo >&2
    usage
    exit 2
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve to an absolute path. The dashboard stores these paths in the
# database, and a relative one would break as soon as anything ran from a
# different working directory.
if [[ ! -d "$RAW_DATA_DIR" ]]; then
    echo "ERROR: not a directory: $RAW_DATA_DIR" >&2
    exit 1
fi
RAW_DATA_DIR="$(cd "$RAW_DATA_DIR" && pwd)"

[[ -z "$DB" ]] && DB="$REPO_ROOT/glider_rtqc.db"
mkdir -p "$(dirname "$DB")"

# ── Interpreter ─────────────────────────────────────────────────────
# Prefer a project virtualenv so the dashboard and the pipeline it spawns run
# against the same dependency set.
PYTHON="${GLIDER_PYTHON:-}"
if [[ -z "$PYTHON" ]]; then
    for c in "$REPO_ROOT/.venv/bin/python" "$REPO_ROOT/venv/bin/python"; do
        [[ -x "$c" ]] && PYTHON="$c" && break
    done
fi
if [[ -z "$PYTHON" ]]; then
    PYTHON="$(command -v python3 || command -v python || true)"
fi
if [[ -z "$PYTHON" ]]; then
    echo "ERROR: no python found. Install python3 or set GLIDER_PYTHON." >&2
    exit 1
fi

# ── Dependency check ────────────────────────────────────────────────
# Checked up front: without these the dashboard starts and then fails on the
# first request, which is far harder to diagnose than a message here.
MISSING="$("$PYTHON" - <<'PY'
mods = {
    "flask": "flask",
    "netCDF4": "netCDF4",
    "numpy": "numpy",
    "xarray": "xarray",
    "scipy": "scipy",
    "matplotlib": "matplotlib",
}
missing = []
for mod, pkg in mods.items():
    try:
        __import__(mod)
    except ImportError:
        missing.append(pkg)
print(" ".join(missing))
PY
)"
if [[ -n "${MISSING// /}" ]]; then
    echo "ERROR: missing Python packages: $MISSING" >&2
    echo "  $PYTHON -m pip install $MISSING" >&2
    exit 1
fi

# ── Sanity: does Raw_Data look like deployments? ────────────────────
N_SUBDIRS="$(find "$RAW_DATA_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
if [[ "$N_SUBDIRS" == "0" ]]; then
    echo "WARNING: $RAW_DATA_DIR has no subdirectories." >&2
    echo "         Expected one folder per deployment, e.g. Raw_Data/1126/" >&2
fi

export GLIDER_RAW_DATA_DIR="$RAW_DATA_DIR"
export GLIDER_DB="$DB"
export GLIDER_PYTHON="$PYTHON"
export GLIDER_REPO_ROOT="$REPO_ROOT"
export GLIDER_PIPELINE="$REPO_ROOT/pipeline/run_pipeline.py"
export GLIDER_DASHBOARD_HOST="$HOST"
export GLIDER_DASHBOARD_PORT="$PORT"
export PYTHONUNBUFFERED=1

echo "============================================================"
echo " GLIDER DASHBOARD"
echo "============================================================"
echo "  repo        : $REPO_ROOT"
echo "  raw data    : $RAW_DATA_DIR  ($N_SUBDIRS subdirectory/ies)"
echo "  database    : $DB"
echo "  python      : $PYTHON"
echo "  bind        : $HOST:$PORT"
echo

# ── Optional: ingest before serving ─────────────────────────────────
if [[ "$DO_INGEST" == "1" ]]; then
    echo "------------------------------------------------------------"
    echo " Ingesting every ready deployment"
    echo "------------------------------------------------------------"
    # Runs the same code path the dashboard's Ingest button uses, so a
    # startup ingest and a browser ingest cannot diverge.
    "$PYTHON" - <<'PY'
import os
import sys

# GLIDER_REPO_ROOT, not PWD: the `cd "$REPO_ROOT"` happens after this block,
# so PWD is still wherever the operator invoked the script from.
_root = os.environ["GLIDER_REPO_ROOT"]
sys.path.insert(0, _root)
sys.path.insert(0, os.path.join(_root, "web_dashboard"))

from app import ingestible_deployments          # noqa: E402
from db.load_deployment import load_deployment   # noqa: E402

db = os.environ["GLIDER_DB"]
targets = ingestible_deployments()
if not targets:
    print("  nothing ready to ingest yet - run the pipeline first")
    sys.exit(0)

ok = fail = 0
for t in targets:
    name = t["folder_name"]
    try:
        res = load_deployment(ego_l1_path=t.get("ego_l1"),
                              ego_l0_path=t.get("ego_l0"),
                              db_path=db, verbose=False)
        print(f"  ok   {name} -> glider {res['glider_id']}: "
              f"{res['rows']['observation']:,} observations "
              f"({res['elapsed_s']:.1f}s)")
        ok += 1
    except Exception as exc:
        print(f"  FAIL {name}: {type(exc).__name__}: {exc}")
        fail += 1
print(f"\n  {ok} ingested, {fail} failed -> {db}")
PY
    echo
fi

# ── Access instructions ─────────────────────────────────────────────
if [[ "$HOST" == "127.0.0.1" || "$HOST" == "localhost" ]]; then
    cat <<EOF
------------------------------------------------------------
 Bound to localhost. From your workstation, open a tunnel:

     ssh -N -L ${PORT}:localhost:${PORT} $(whoami)@$(hostname -f 2>/dev/null || hostname)

 then browse to:  http://localhost:${PORT}
------------------------------------------------------------
EOF
else
    cat <<EOF
------------------------------------------------------------
 WARNING: bound to ${HOST}, NOT localhost.

 This dashboard has no authentication and it launches processing
 subprocesses on this machine. Anyone able to reach ${HOST}:${PORT}
 can start a pipeline run and read the data.

 Prefer:  ./run_dashboard.sh "$RAW_DATA_DIR" --port ${PORT}
          plus  ssh -N -L ${PORT}:localhost:${PORT} ...
 If you must expose it, put it behind a reverse proxy that
 requires authentication and restrict the port with a firewall.
------------------------------------------------------------
EOF
fi

echo " Ctrl-C to stop."
echo

cd "$REPO_ROOT"
exec "$PYTHON" web_dashboard/app.py
