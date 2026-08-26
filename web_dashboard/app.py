import os
import re
import sys
import glob
import time
import shutil
import threading
import subprocess
from datetime import datetime
from flask import Flask, jsonify, render_template, send_from_directory, abort, request

app = Flask(__name__, template_folder='templates')

# EGO NetCDF + SQLite endpoints live in their own read-only blueprint.
# Import works both as `python web_dashboard/app.py` and `python -m
# web_dashboard.app`, so the launch style cannot break the dashboard.
try:
    from ego_api import ego_api, db_path
except ImportError:  # pragma: no cover - depends on launch style
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from ego_api import ego_api, db_path
app.register_blueprint(ego_api)

# ------------------------------------------------------------------
# Configuration.
#
# Both of these were previously hardcoded absolute paths — and to two
# different machines at that (a Linux data root plus a Windows pipeline
# path), so the dashboard could not run anywhere as shipped. They are now
# environment-driven with defaults derived from this file's own location.
#
#   GLIDER_RAW_DATA_DIR  folder holding one subdirectory per deployment
#   GLIDER_PIPELINE      run_pipeline.py to invoke (default: ../pipeline/)
#   GLIDER_PYTHON        interpreter to run it with (default: this one)
# ------------------------------------------------------------------
_REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Needed for `from db.load_deployment import ...`. ego_api happens to insert
# this too, so this was working by accident; make it explicit rather than
# depending on another module's import side effect.
if _REPO_ROOT not in sys.path:
    sys.path.insert(0, _REPO_ROOT)
# pipeline/ holds layout.py, the single definition of the output directory
# structure. Importing it here keeps the dashboard from restating the layout.
_PIPELINE_DIR = os.path.join(_REPO_ROOT, "pipeline")
if _PIPELINE_DIR not in sys.path:
    sys.path.insert(0, _PIPELINE_DIR)

import layout as _layout  # noqa: E402


def _default_raw_data_dir() -> str:
    """
    Best guess at the deployments folder when GLIDER_RAW_DATA_DIR is unset.

    Checks the locations this project actually uses, in order, and only falls
    back to the historical 'Raw_Data' sibling if none exist — so the dashboard
    comes up pointing at real data instead of an empty list.
    """
    candidates = [
        os.path.join(os.path.dirname(_REPO_ROOT), "glider_data"),
        os.path.join(os.path.dirname(_REPO_ROOT), "glider"),
        os.path.join(os.path.dirname(_REPO_ROOT), "Raw_Data"),
    ]
    for c in candidates:
        if os.path.isdir(c):
            return c
    return candidates[-1]


RAW_DATA_DIR = os.path.abspath(os.environ.get(
    "GLIDER_RAW_DATA_DIR", _default_raw_data_dir()))

PIPELINE_SCRIPT = os.path.abspath(os.environ.get(
    "GLIDER_PIPELINE",
    os.path.join(_REPO_ROOT, "pipeline", "run_pipeline.py")))

PYTHON = os.environ.get("GLIDER_PYTHON", sys.executable)

# Active processes tracker: glider_id -> { "process": Popen, "status": str,
#                                          "log_path": str, "log_file": handle }
active_processes = {}

# Ingestion runs in a worker thread rather than a subprocess: db.load_deployment
# is an importable function, and running it in-process means the status dict
# below carries the real per-deployment result instead of scraped stdout.
# One lock, because every ingest appends to the same SQLite file.
_ingest_lock = threading.Lock()
ingest_state = {
    "running": False,
    "started_at": None,
    "finished_at": None,
    "current": None,
    "queue": [],
    "done": [],       # [{glider_id, rows, core_params, bgc_params, elapsed_s}]
    "errors": [],     # [{deployment, error}]
    "log": [],
}


def _ingest_log(msg):
    ingest_state["log"].append(
        f"{datetime.now().strftime('%H:%M:%S')}  {msg}")
    # Keep the tail bounded; the UI only ever renders the recent lines.
    if len(ingest_state["log"]) > 500:
        del ingest_state["log"][:-500]


def ingestible_deployments():
    """
    Deployment folders that hold a usable EGO product.

    Delegates the "is this file usable" judgement to db.load_deployment's own
    discovery, so the dashboard cannot disagree with the loader about which
    files count.
    """
    from db.load_deployment import find_ego_files

    out = []
    if not os.path.isdir(RAW_DATA_DIR):
        return out
    for name in sorted(os.listdir(RAW_DATA_DIR)):
        if not os.path.isdir(os.path.join(RAW_DATA_DIR, name)):
            continue
        root = deployment_root(name)
        found = find_ego_files(root, verbose=False)
        if found.get("ego_l1") or found.get("ego_l0"):
            out.append({
                "folder_name": name,
                "root": root,
                "ego_l1": found.get("ego_l1"),
                "ego_l0": found.get("ego_l0"),
            })
    return out


def _run_ingest(targets):
    """Worker: load each deployment into the shared database, in sequence."""
    from db.load_deployment import load_deployment

    db = db_path()
    ingest_state.update(running=True, started_at=datetime.now().isoformat(),
                        finished_at=None, current=None,
                        queue=[t["folder_name"] for t in targets],
                        done=[], errors=[], log=[])
    _ingest_log(f"database: {db}")
    _ingest_log(f"{len(targets)} deployment(s) queued")

    try:
        for t in targets:
            name = t["folder_name"]
            ingest_state["current"] = name
            if name in ingest_state["queue"]:
                ingest_state["queue"].remove(name)
            _ingest_log(f"ingesting {name} ...")
            try:
                # Appends: meta is keyed on glider_id and every write is
                # ON CONFLICT DO UPDATE, so re-ingesting a deployment refreshes
                # its rows instead of duplicating them.
                res = load_deployment(
                    ego_l1_path=t.get("ego_l1"),
                    ego_l0_path=t.get("ego_l0"),
                    db_path=db,
                    verbose=False,
                )
                ingest_state["done"].append({
                    "folder_name": name,
                    "glider_id": res["glider_id"],
                    "rows": res["rows"],
                    "core_params": res["core_params"],
                    "bgc_params": res["bgc_params"],
                    "elapsed_s": round(res["elapsed_s"], 1),
                })
                _ingest_log(
                    f"  {name} -> glider {res['glider_id']}: "
                    f"{res['rows']['observation']:,} observations, "
                    f"core={','.join(res['core_params'])}, "
                    f"bgc={','.join(res['bgc_params'])} "
                    f"({res['elapsed_s']:.1f}s)")
            except Exception as exc:
                ingest_state["errors"].append(
                    {"deployment": name, "error": f"{type(exc).__name__}: {exc}"})
                _ingest_log(f"  ERROR {name}: {type(exc).__name__}: {exc}")
        _ingest_log(f"complete: {len(ingest_state['done'])} ok, "
                    f"{len(ingest_state['errors'])} failed")
    finally:
        ingest_state["current"] = None
        ingest_state["running"] = False
        ingest_state["finished_at"] = datetime.now().isoformat()

def parse_summary_report(file_path):
    if not os.path.exists(file_path):
        return {}
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
    except Exception:
        return {}

    data = {}

    # Title. step6 writes an em dash here ("DEPLOYMENT SUMMARY — Glider X");
    # matching only an ASCII hyphen meant this never fired and every
    # deployment silently fell back to its folder name. Accept either.
    title_match = re.search(r"DEPLOYMENT SUMMARY\s*[-–—]\s*Glider\s+([\w_]+)",
                            content)
    if title_match:
        data['glider_id'] = title_match.group(1)
    
    # L0 Product Info
    l0_section = re.search(r"L0 PRODUCT\n\s*-+\n(.*?)(?=\n\n|\n[A-Z0-9\s]+PRODUCT|\Z)", content, re.DOTALL)
    if l0_section:
        l0_content = l0_section.group(1)
        data['l0'] = {
            'file': re.search(r"File:\s*([^\n]+)", l0_content).group(1).strip() if re.search(r"File:\s*", l0_content) else '',
            'size': re.search(r"Size:\s*([^\n]+)", l0_content).group(1).strip() if re.search(r"Size:\s*", l0_content) else '',
            'time_range': re.search(r"Time range:\s*([^\n]+)", l0_content).group(1).strip() if re.search(r"Time range:\s*", l0_content) else '',
            'duration': re.search(r"Duration:\s*([^\n]+)", l0_content).group(1).strip() if re.search(r"Duration:\s*", l0_content) else '',
            'observations': re.search(r"Observations:\s*([\d,]+)", l0_content).group(1).replace(',', '').strip() if re.search(r"Observations:\s*", l0_content) else '',
            'profiles': re.search(r"Profiles:\s*([\d,]+)", l0_content).group(1).replace(',', '').strip() if re.search(r"Profiles:\s*", l0_content) else '',
            'max_depth': re.search(r"Max depth:\s*([^\n]+)", l0_content).group(1).strip() if re.search(r"Max depth:\s*", l0_content) else '',
            'track_dist': re.search(r"Track dist:\s*([^\n]+)", l0_content).group(1).strip() if re.search(r"Track dist:\s*", l0_content) else '',
        }
        
    # L1 Product Info
    l1_section = re.search(r"L1 PRODUCT\n\s*-+\n(.*?)(?=\n\n|\n[A-Z0-9\s]+PRODUCT|\Z)", content, re.DOTALL)
    if l1_section:
        l1_content = l1_section.group(1)
        data['l1'] = {
            'file': re.search(r"File:\s*([^\n]+)", l1_content).group(1).strip() if re.search(r"File:\s*", l1_content) else '',
            'size': re.search(r"Size:\s*([^\n]+)", l1_content).group(1).strip() if re.search(r"Size:\s*", l1_content) else '',
            'time_range': re.search(r"Time range:\s*([^\n]+)", l1_content).group(1).strip() if re.search(r"Time range:\s*", l1_content) else '',
            'observations': re.search(r"Observations:\s*([\d,]+)", l1_content).group(1).replace(',', '').strip() if re.search(r"Observations:\s*", l1_content) else '',
            'profiles': re.search(r"Profiles:\s*([\d,]+)", l1_content).group(1).replace(',', '').strip() if re.search(r"Profiles:\s*", l1_content) else '',
            'profile_retention': re.search(r"Profile retention:\s*([^\n]+)", l1_content).group(1).strip() if re.search(r"Profile retention:\s*", l1_content) else '',
        }
        
        # Parse Variable QC Flag Summary Table
        qc_table = re.search(r"L1 QC flag summary \(per variable\):\n\s*Variable\s+Good%\s+PBad%\s+Bad%\s+Miss%\n\s*-+\n(.*?)(?=\n\n|\n[A-Z]|\Z)", content, re.DOTALL)
        if qc_table:
            qc_rows = []
            for line in qc_table.group(1).strip().split('\n'):
                parts = line.split()
                if len(parts) >= 5:
                    qc_rows.append({
                        'variable': parts[0],
                        'good': float(parts[1]),
                        'pbad': float(parts[2]),
                        'bad': float(parts[3]),
                        'miss': float(parts[4]),
                    })
            data['l1']['qc_flags'] = qc_rows
            
    # Grid Product Info
    grid_section = re.search(r"GRID PRODUCT\n\s*-+\n(.*?)(?=\n\n|\n[A-Z0-9\s]+PRODUCT|\Z)", content, re.DOTALL)
    if grid_section:
        grid_content = grid_section.group(1)
        data['grid'] = {
            'file': re.search(r"File:\s*([^\n]+)", grid_content).group(1).strip() if re.search(r"File:\s*", grid_content) else '',
            'size': re.search(r"Size:\s*([^\n]+)", grid_content).group(1).strip() if re.search(r"Size:\s*", grid_content) else '',
            'dims': re.search(r"Dims:\s*([^\n]+)", grid_content).group(1).strip() if re.search(r"Dims:\s*", grid_content) else '',
            'depth': re.search(r"Depth:\s*([^\n]+)", grid_content).group(1).strip() if re.search(r"Depth:\s*", grid_content) else '',
        }
        
    return data

@app.route('/')
def index():
    return render_template('index.html')

def deployment_root(name):
    """
    Resolve a deployment folder name to the directory that actually holds
    `output/`.

    Real deployment folders in this project are sometimes nested one level
    (glider_data/1131-Data(Dec-2024)/1131-Data(Dec-2024)/output), typically from
    unzipping an archive that contained its own top-level folder. Looking only
    at the top level marked those deployments 'unprocessed' even though the
    products existed, so one level of nesting is resolved here.
    """
    base = os.path.join(RAW_DATA_DIR, os.path.basename(name))
    if os.path.isdir(os.path.join(base, 'output')):
        return base
    if not os.path.isdir(base):
        return base

    for child in sorted(os.listdir(base)):
        nested = os.path.join(base, child)
        if os.path.isdir(os.path.join(nested, 'output')):
            return nested

    # No output/ anywhere — which is exactly the state a reset leaves behind,
    # and the state a fresh deployment arrives in. Resolving nesting purely by
    # looking for output/ breaks here: the folder would resolve to the outer
    # directory, and the re-run would then decode from the outer level and write
    # its products beside the real deployment instead of inside it. So fall back
    # to the markers of the raw inputs, which a reset never removes.
    if _has_raw_markers(base):
        return base
    for child in sorted(os.listdir(base)):
        nested = os.path.join(base, child)
        if _has_raw_markers(nested):
            return nested
    return base


# Raw glider binaries, per pipeline/config.py _BINARY_EXTS.
_BINARY_EXTS = ('.dcd', '.ecd', '.dbd', '.ebd')


def _has_raw_markers(path):
    """
    Whether a directory holds a deployment's raw inputs.

    Only the things a pipeline run consumes rather than produces, so this
    answer is stable across a delete-output-and-reprocess cycle.
    """
    if not os.path.isdir(path):
        return False
    if os.path.exists(os.path.join(path, 'deployment.yml')):
        return True
    if os.path.isdir(os.path.join(path, 'combined_binary')):
        return True
    try:
        for entry in os.scandir(path):
            if entry.is_file() and entry.name.lower().endswith(_BINARY_EXTS):
                return True
    except OSError:
        return False
    return False


def looks_like_deployment(name):
    """
    Whether a subdirectory of RAW_DATA_DIR is a deployment the pipeline can run.

    Raw_Data holds housekeeping folders alongside the real deployments
    (Calibration_details_glider, for one). A batch run must not launch the
    pipeline on those, so a folder has to show at least one marker of being
    glider data: a deployment.yml, a collected combined_binary/, an existing
    output/, or raw binaries / NetCDF sitting within two levels.
    """
    root = deployment_root(name)
    if not os.path.isdir(root):
        return False
    if os.path.isdir(os.path.join(root, 'output')) or _has_raw_markers(root):
        return True
    # Also accept a bare NetCDF, for deployments handed over as an L0 product
    # rather than as binaries. Shallow scan only: some deployment folders carry
    # thousands of files and this runs per folder on every /api/transects call.
    try:
        for entry in os.scandir(root):
            if entry.is_file() and entry.name.lower().endswith('.nc'):
                return True
            if entry.is_dir():
                try:
                    for sub in os.scandir(entry.path):
                        if sub.is_file() and sub.name.lower().endswith('.nc'):
                            return True
                except OSError:
                    continue
    except OSError:
        return False
    return False


def deployment_folders(only_deployments=True):
    """Subdirectory names of RAW_DATA_DIR, in sorted order."""
    if not os.path.isdir(RAW_DATA_DIR):
        return []
    names = sorted(n for n in os.listdir(RAW_DATA_DIR)
                   if os.path.isdir(os.path.join(RAW_DATA_DIR, n)))
    if only_deployments:
        names = [n for n in names if looks_like_deployment(n)]
    return names


@app.route('/api/transects')
def get_transects():
    transects = []
    if not os.path.exists(RAW_DATA_DIR):
        return jsonify([])
        
    for name in os.listdir(RAW_DATA_DIR):
        if not os.path.isdir(os.path.join(RAW_DATA_DIR, name)):
            continue
        folder_path = deployment_root(name)
            
        plots_dir = _layout.plots_dir(os.path.join(folder_path, 'output'))
        reports_dir = _layout.reports_dir(os.path.join(folder_path, 'output'))
        
        # Check if processed
        is_processed = False
        if os.path.exists(plots_dir) and any(f.endswith('.png') for f in os.listdir(plots_dir)):
            is_processed = True
            
        # Parse summary report
        summary_data = {}
        if is_processed:
            report_files = glob.glob(os.path.join(reports_dir, '*_summary.txt'))
            if report_files:
                summary_data = parse_summary_report(report_files[0])
            
        # Get all plots
        plot_files = []
        if is_processed and os.path.exists(plots_dir):
            plot_files = [f for f in os.listdir(plots_dir) if f.endswith('.png')]
            
        if not summary_data.get('glider_id'):
            summary_data['glider_id'] = name
            
        # Status check
        status = "processed" if is_processed else "unprocessed"
        if name in active_processes:
            status = active_processes[name]["status"]
            
        # EGO products, so the UI can link the deployment to its EGO files and
        # to its row in the database. Paths come from pipeline/layout.py, which
        # searches the current output/L{0,1}/L{0,1}_timeseries/ layout and the
        # legacy flat directories, so deployments processed before the layout
        # change still list their files.
        out_dir = os.path.join(folder_path, 'output')
        ego_files = sorted({
            os.path.basename(p)
            for lvl in ('L0', 'L1')
            for p in _layout.find_timeseries(out_dir, lvl)
        })

        # Per-deployment database, written into this deployment's own output/.
        dep_db = _layout.deployment_db(out_dir, name)

        transects.append({
            'folder_name': name,
            'status': status,
            'metadata': summary_data,
            # Whether there is anything for the reset button to delete. Only an
            # isdir() here on purpose: measuring the size means walking every
            # profile NetCDF of every deployment, and this endpoint is hit on
            # each page load. /api/batch/candidates reports the sizes.
            'has_output': os.path.isdir(out_dir),
            'runnable': looks_like_deployment(name),
            'deployment_db': dep_db if os.path.exists(dep_db) else None,
            'deployment_db_mb': (round(os.path.getsize(dep_db) / (1024 * 1024), 1)
                                 if os.path.exists(dep_db) else None),
            'legacy_dirs': [os.path.basename(p)
                            for p in _layout.legacy_dirs_present(out_dir)],
            'plots': sorted(plot_files),
            'ego_files': ego_files,
            'has_ego': bool(ego_files),
            'glider_id': summary_data.get('glider_id', name),
        })
        
    return jsonify(sorted(transects, key=lambda x: x['folder_name']))

@app.route('/plots/<transect>/<filename>')
def serve_plot(transect, filename):
    safe_filename = os.path.basename(filename)
    plots_dir = _layout.plots_dir(
        os.path.join(deployment_root(transect), 'output'))
    if not os.path.exists(os.path.join(plots_dir, safe_filename)):
        abort(404)
    return send_from_directory(plots_dir, safe_filename)

def _pipeline_log_path(safe_glider_id):
    log_dir = os.path.join(app.root_path, 'logs')
    os.makedirs(log_dir, exist_ok=True)
    return os.path.join(log_dir, f"{safe_glider_id}.log")


def _close_log(info):
    """Release our end of a run's log file, once."""
    log_file = info.pop("log_file", None)
    if log_file is not None and not log_file.closed:
        log_file.close()


def _launch_pipeline(safe_glider_id):
    """
    Start a pipeline run for one deployment and register it in
    active_processes.

    Returns (info, error). Shared by POST /api/process/<id> and the batch
    runner, so a batch run and a single click are the same code path: same log
    file, same progress markers, same /api/status/<id> behaviour. A batch that
    launched the pipeline its own way would eventually disagree with the
    single-deployment view about what a run looks like.
    """
    folder_path = deployment_root(safe_glider_id)
    if not os.path.isdir(folder_path):
        return None, "deployment directory not found"

    existing = active_processes.get(safe_glider_id)
    if existing and existing["status"] == "running" \
            and existing["process"].poll() is None:
        return None, "already running"

    if not os.path.exists(PIPELINE_SCRIPT):
        return None, (f"pipeline script not found: {PIPELINE_SCRIPT}. "
                      f"Set GLIDER_PIPELINE to its location.")

    log_path = _pipeline_log_path(safe_glider_id)
    with open(log_path, 'w', encoding='utf-8') as f:
        f.write("=" * 60 + "\n")
        f.write(f" STARTING PIPELINE PROCESSING FOR GLIDER {safe_glider_id}\n")
        f.write("=" * 60 + "\n\n")

    cmd = [PYTHON, PIPELINE_SCRIPT, "--data-dir", folder_path]

    log_file = open(log_path, 'a', encoding='utf-8', errors='ignore')
    try:
        proc = subprocess.Popen(
            cmd,
            stdout=log_file,
            stderr=subprocess.STDOUT,
            creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0
        )
    except OSError as exc:
        # Don't leak the handle when the process never starts.
        log_file.close()
        return None, f"could not start pipeline: {exc}"

    # Keep the handle so the status endpoint (or the batch worker) can close it
    # once the run ends — previously it was left open for the lifetime of the
    # server, leaking one file descriptor per launch.
    info = {
        "process": proc,
        "status": "running",
        "log_path": log_path,
        "log_file": log_file,
    }
    active_processes[safe_glider_id] = info
    return info, None


@app.route('/api/process/<glider_id>', methods=['POST'])
def process_transect(glider_id):
    safe_glider_id = os.path.basename(glider_id)

    if batch_state["running"]:
        return jsonify({"error": "a batch run is in progress",
                        "current": batch_state["current"]}), 409

    info, err = _launch_pipeline(safe_glider_id)
    if err == "already running":
        return jsonify({"status": "running", "message": "Already running"})
    if err == "deployment directory not found":
        return jsonify({"error": "Transect directory not found"}), 404
    if err:
        return jsonify({"error": err}), 500

    return jsonify({"status": "running", "message": "Processing started"})

@app.route('/api/status/<glider_id>')
def process_status(glider_id):
    safe_glider_id = os.path.basename(glider_id)
    
    if safe_glider_id not in active_processes:
        # Check if already processed (plots exist)
        plots_dir = _layout.plots_dir(
            os.path.join(deployment_root(safe_glider_id), 'output'))
        if os.path.exists(plots_dir) and any(f.endswith('.png') for f in os.listdir(plots_dir)):
            return jsonify({"status": "processed", "progress": 100, "log": "Already processed."})
        return jsonify({"status": "unprocessed", "progress": 0, "log": "Idle."})
        
    info = active_processes[safe_glider_id]
    proc = info["process"]
    
    poll = proc.poll()
    if poll is not None:
        info["status"] = "completed" if poll == 0 else "failed"
        # The child has exited; release our end of the log file.
        _close_log(info)


    log_content = ""
    if os.path.exists(info["log_path"]):
        try:
            with open(info["log_path"], 'r', encoding='utf-8', errors='ignore') as f:
                log_content = f.read()
        except Exception:
            pass
            
    # Estimate progress from the markers the pipeline actually prints.
    # "STEP 5 COMPLETE" was watched for here but is never emitted — step5 ends
    # with its plot paths — so the bar used to jump 65 -> 95 with nothing in
    # between. Anchored on real markers, checked in order.
    progress = 5
    for marker, pct in (
        ("STEP 1 COMPLETE",   20),
        ("STEP 2/3 COMPLETE", 50),
        ("STEP 3b",           60),
        ("Grid saved",        70),
        ("L1 plot:",          80),
        ("STEP 6 COMPLETE",   90),
        ("STEP 7 COMPLETE",   95),
        ("PIPELINE COMPLETE", 100),
    ):
        if marker in log_content:
            progress = pct
    
    if info["status"] == "completed":
        progress = 100
    elif info["status"] == "failed":
        if progress == 100: progress = 95
        
    return jsonify({
        "status": info["status"],
        "progress": progress,
        "log": log_content
    })


# ── Reset: delete a deployment's output/ ────────────────────────────
#
# Reprocessing from scratch has to start from an empty output/. Steps write
# with os.makedirs(exist_ok=True) and overwrite by name, so a re-run over a
# populated output/ leaves behind anything the new run does not happen to
# rewrite — plots for parameters no longer present, reports from the previous
# config, products in the legacy flat layout. Those stale files then show up in
# the dashboard and get ingested as if current.

def _dir_size(path):
    total = 0
    for root, _dirs, files in os.walk(path):
        for f in files:
            try:
                total += os.path.getsize(os.path.join(root, f))
            except OSError:
                pass
    return total


def _reset_output(folder_name):
    """
    Delete one deployment's output/ directory.

    Removed:
        <deployment>/output/            all L0/L1 products, plots, reports and
                                        the per-deployment .db inside it
        web_dashboard/logs/<name>.log   this dashboard's own run log

    Never touched: the raw binaries, deployment.yml, cache/, and the combined
    database — that one lives in Raw_Data beside the deployment folders rather
    than inside any of them, so a reset cannot take it along.

    Raises ValueError if the request is refused; the caller turns that into a
    409 or a batch error rather than deleting something unintended.
    """
    safe = os.path.basename(folder_name)
    root = deployment_root(safe)
    if not os.path.isdir(root):
        raise ValueError(f"deployment directory not found: {safe}")

    out_dir = os.path.join(root, 'output')
    real_out = os.path.realpath(out_dir)
    real_raw = os.path.realpath(RAW_DATA_DIR)

    # The folder name arrives from a URL and deployment_root() resolves one
    # level of nesting, so the path that is actually about to be removed is
    # checked, not the one that was asked for.
    if os.path.basename(real_out) != 'output':
        raise ValueError(f"refusing to delete non-output path: {real_out}")
    if not (real_out + os.sep).startswith(real_raw + os.sep):
        raise ValueError(
            f"refusing to delete outside the data root {real_raw}: {real_out}")
    if os.path.islink(out_dir):
        raise ValueError(f"refusing to follow a symlink: {out_dir}")

    info = active_processes.get(safe)
    if info and info["status"] == "running" and info["process"].poll() is None:
        raise ValueError("a pipeline run is still in progress for this "
                         "deployment — wait for it to finish")

    existed = os.path.isdir(real_out)
    freed = _dir_size(real_out) if existed else 0
    if existed:
        shutil.rmtree(real_out)

    # Drop our own bookkeeping too. Without this the deployment keeps the
    # 'completed' status of the run whose products just went away, so the UI
    # would offer 'Re-run' over an empty output/ and report it as finished.
    old = active_processes.pop(safe, None)
    if old:
        _close_log(old)
    log_path = _pipeline_log_path(safe)
    if os.path.exists(log_path):
        try:
            os.remove(log_path)
        except OSError:
            pass

    return {
        "folder_name": safe,
        "output_dir": real_out,
        "existed": existed,
        "freed_mb": round(freed / (1024 * 1024), 1),
    }


@app.route('/api/reset/<glider_id>', methods=['POST'])
def reset_transect(glider_id):
    """
    Delete a deployment's output/ so the pipeline can run clean.

    Destructive and irreversible from here, so it is POST-only and the caller
    must echo the folder name back:

        POST /api/reset/1126   {"confirm": "1126"}

    The products are regenerable from the raw binaries, but a run takes
    minutes, which is why a bare POST is not enough.
    """
    safe = os.path.basename(glider_id)
    body = request.get_json(silent=True) or {}
    if body.get("confirm") != safe:
        return jsonify({
            "error": "confirmation required",
            "hint": f'POST {{"confirm": "{safe}"}} to delete {safe}/output/',
        }), 400

    if batch_state["running"]:
        return jsonify({"error": "a batch run is in progress",
                        "current": batch_state["current"]}), 409

    try:
        res = _reset_output(safe)
    except ValueError as exc:
        return jsonify({"error": str(exc)}), 409
    except OSError as exc:
        return jsonify({"error": f"delete failed: {exc}"}), 500

    return jsonify({"status": "deleted", **res})


# ── Ingestion ───────────────────────────────────────────────────────
#
# Every ingest appends into ONE database (GLIDER_DB, default
# <repo>/glider_rtqc.db). meta is keyed on glider_id and all writes are
# ON CONFLICT DO UPDATE, so re-running a deployment refreshes its rows rather
# than duplicating them, and loading a new deployment leaves the others alone.

@app.route('/api/ingest/candidates')
def ingest_candidates():
    """Deployments that have a usable EGO product, and whether each is loaded."""
    import sqlite3

    cands = ingestible_deployments()

    loaded = {}
    db = db_path()
    if os.path.exists(db):
        try:
            conn = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
            try:
                loaded = {r[0]: {"n_observations": r[1], "processed_at": r[2]}
                          for r in conn.execute(
                              "SELECT glider_id, n_observations, processed_at "
                              "FROM meta")}
            finally:
                conn.close()
        except sqlite3.Error:
            pass

    for c in cands:
        # The loader takes glider_id from the EGO platform_code attribute; the
        # folder name is only a fallback, so match on both.
        gid = next((g for g in loaded
                    if g == c["folder_name"] or g in c["folder_name"]), None)
        c["glider_id"] = gid
        c["ingested"] = bool(gid)
        c["ingested_info"] = loaded.get(gid) if gid else None
        c["has_l1"] = bool(c.get("ego_l1"))
        c["has_l0"] = bool(c.get("ego_l0"))
        c["ego_l1"] = os.path.basename(c["ego_l1"]) if c.get("ego_l1") else None
        c["ego_l0"] = os.path.basename(c["ego_l0"]) if c.get("ego_l0") else None

    return jsonify({
        "database": db,
        "database_exists": os.path.exists(db),
        "n_loaded": len(loaded),
        "candidates": cands,
    })


@app.route('/api/ingest', methods=['POST'])
def ingest_start():
    """
    Start ingestion.

    Body: {"deployments": ["1126", ...]}  or  {"all": true}
    """
    if ingest_state["running"]:
        return jsonify({"error": "an ingestion is already running",
                        "current": ingest_state["current"]}), 409

    body = request.get_json(silent=True) or {}
    available = ingestible_deployments()

    if body.get("all"):
        targets = available
    else:
        wanted = body.get("deployments") or []
        if not wanted:
            return jsonify({"error": "provide 'deployments': [...] or 'all': true"}), 400
        names = {os.path.basename(w) for w in wanted}
        targets = [a for a in available if a["folder_name"] in names]
        missing = names - {t["folder_name"] for t in targets}
        if missing:
            return jsonify({
                "error": "no usable EGO product for: " + ", ".join(sorted(missing)),
                "hint": "run the pipeline for these deployments first",
            }), 404

    if not targets:
        return jsonify({"error": "nothing to ingest",
                        "hint": "no deployment has a usable EGO product yet"}), 404

    # Guard the lock rather than the flag: two POSTs arriving together could
    # both pass the check above before either sets running=True.
    if not _ingest_lock.acquire(blocking=False):
        return jsonify({"error": "an ingestion is already running"}), 409

    def _worker():
        try:
            _run_ingest(targets)
        finally:
            _ingest_lock.release()

    threading.Thread(target=_worker, daemon=True).start()

    return jsonify({
        "status": "started",
        "database": db_path(),
        "deployments": [t["folder_name"] for t in targets],
    })


@app.route('/api/ingest/status')
def ingest_status():
    st = {k: v for k, v in ingest_state.items()}
    st["log"] = "\n".join(ingest_state["log"])
    total = len(st["done"]) + len(st["errors"]) + len(st["queue"]) \
        + (1 if st["current"] else 0)
    st["progress"] = (
        100 if (not st["running"] and total and not st["queue"])
        else int(100 * len(st["done"]) / total) if total else 0
    )
    st["database"] = db_path()
    return jsonify(st)


# ── Batch run ───────────────────────────────────────────────────────
#
# Reprocessing every deployment one browser click at a time means watching for
# each run to finish before starting the next. This runs the whole set in one
# go, strictly sequentially: a pipeline run saturates a core and holds the
# NetCDF/plotting stack, and several at once on the same machine trade a
# throughput gain for memory pressure and interleaved logs.
#
# Each deployment goes through _launch_pipeline, the same path as a single
# click, so /api/status/<id> keeps working per deployment while the batch runs
# and the console shows the live log of whichever one is current.

_batch_lock = threading.Lock()
batch_state = {
    "running": False,
    "cancel": False,
    "started_at": None,
    "finished_at": None,
    "current": None,
    "queue": [],
    "reset": False,
    "ingest": False,
    "done": [],       # [{folder_name, status, elapsed_s, freed_mb}]
    "errors": [],     # [{folder_name, error}]
    "log": [],
}


def _batch_log(msg):
    batch_state["log"].append(
        f"{datetime.now().strftime('%H:%M:%S')}  {msg}")
    if len(batch_state["log"]) > 1000:
        del batch_state["log"][:-1000]


def _wait_with_cancel(proc):
    """
    Wait for a pipeline run, staying responsive to a cancel request.

    proc.wait() would block until the run ends, which for a full deployment is
    minutes — long enough that a cancel button that only took effect afterwards
    would be useless.
    """
    while proc.poll() is None:
        if batch_state["cancel"]:
            proc.terminate()
            try:
                proc.wait(timeout=15)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
            return proc.poll(), True
        time.sleep(1)
    return proc.poll(), False


def _run_batch(names, do_reset, do_ingest):
    """Worker: reset (optional) and run the pipeline for each deployment."""
    batch_state.update(running=True, cancel=False,
                       started_at=datetime.now().isoformat(),
                       finished_at=None, current=None, queue=list(names),
                       reset=bool(do_reset), ingest=bool(do_ingest),
                       done=[], errors=[], log=[])
    _batch_log(f"{len(names)} deployment(s) queued: {', '.join(names)}")
    if do_reset:
        _batch_log("each output/ will be deleted before its run")
    if do_ingest:
        _batch_log("the combined database will be refreshed at the end")

    try:
        for name in names:
            if batch_state["cancel"]:
                _batch_log("cancelled — remaining deployments skipped")
                break

            batch_state["current"] = name
            if name in batch_state["queue"]:
                batch_state["queue"].remove(name)

            t0 = time.time()
            freed_mb = None
            try:
                if do_reset:
                    r = _reset_output(name)
                    freed_mb = r["freed_mb"]
                    _batch_log(f"{name}: removed output/ ({r['freed_mb']} MB)"
                               if r["existed"]
                               else f"{name}: no output/ to remove")

                info, err = _launch_pipeline(name)
                if err:
                    raise RuntimeError(err)

                _batch_log(f"{name}: pipeline running (pid "
                           f"{info['process'].pid}) — live log in the console")
                rc, cancelled = _wait_with_cancel(info["process"])
                _close_log(info)

                if cancelled:
                    info["status"] = "failed"
                    batch_state["errors"].append(
                        {"folder_name": name, "error": "cancelled"})
                    _batch_log(f"{name}: terminated by cancel")
                    continue

                elapsed = time.time() - t0
                info["status"] = "completed" if rc == 0 else "failed"
                if rc == 0:
                    batch_state["done"].append({
                        "folder_name": name,
                        "status": "completed",
                        "elapsed_s": round(elapsed, 1),
                        "freed_mb": freed_mb,
                    })
                    _batch_log(f"{name}: COMPLETED in {elapsed:.0f}s")
                else:
                    batch_state["errors"].append({
                        "folder_name": name,
                        "error": f"pipeline exited {rc} after {elapsed:.0f}s "
                                 f"— see the console log for this deployment",
                    })
                    _batch_log(f"{name}: FAILED (exit {rc}) after "
                               f"{elapsed:.0f}s")
            except Exception as exc:
                batch_state["errors"].append(
                    {"folder_name": name,
                     "error": f"{type(exc).__name__}: {exc}"})
                _batch_log(f"{name}: ERROR {type(exc).__name__}: {exc}")

        _batch_log(f"batch complete: {len(batch_state['done'])} ok, "
                   f"{len(batch_state['errors'])} failed")

        # Ingest last, once, rather than after each deployment: the loader
        # upserts on glider_id, so a single pass at the end picks up everything
        # that just succeeded and costs one database write cycle instead of N.
        if do_ingest and not batch_state["cancel"]:
            if _ingest_lock.acquire(blocking=False):
                try:
                    _batch_log("ingesting every ready deployment ...")
                    _run_ingest(ingestible_deployments())
                    _batch_log(f"ingest: {len(ingest_state['done'])} ok, "
                               f"{len(ingest_state['errors'])} failed")
                finally:
                    _ingest_lock.release()
            else:
                _batch_log("skipped ingest: another ingestion is running")
    finally:
        batch_state["current"] = None
        batch_state["running"] = False
        batch_state["cancel"] = False
        batch_state["finished_at"] = datetime.now().isoformat()


@app.route('/api/batch/candidates')
def batch_candidates():
    """Every deployment folder the pipeline can be run on, and its state."""
    out = []
    for name in deployment_folders():
        root = deployment_root(name)
        out_dir = os.path.join(root, 'output')
        plots = _layout.plots_dir(out_dir)
        has_plots = os.path.isdir(plots) and any(
            f.endswith('.png') for f in os.listdir(plots))
        out.append({
            "folder_name": name,
            "processed": has_plots,
            "has_output": os.path.isdir(out_dir),
            "output_mb": (round(_dir_size(out_dir) / (1024 * 1024), 1)
                          if os.path.isdir(out_dir) else 0),
        })
    return jsonify({"data_dir": RAW_DATA_DIR, "candidates": out})


@app.route('/api/batch', methods=['POST'])
def batch_start():
    """
    Start a sequential batch run.

    Body:
      {"all": true}                       every deployment folder
      {"deployments": ["1126", ...]}      just these
      {"reset": true}                     delete each output/ first
      {"ingest": true}                    refresh the combined database after
    """
    if batch_state["running"]:
        return jsonify({"error": "a batch run is already in progress",
                        "current": batch_state["current"]}), 409

    running_single = [g for g, i in active_processes.items()
                      if i["status"] == "running" and i["process"].poll() is None]
    if running_single:
        return jsonify({
            "error": "a pipeline run is already in progress: "
                     + ", ".join(running_single),
            "hint": "wait for it to finish, or reload after it completes",
        }), 409

    body = request.get_json(silent=True) or {}
    available = deployment_folders()

    if body.get("all"):
        names = available
    else:
        wanted = [os.path.basename(w) for w in (body.get("deployments") or [])]
        if not wanted:
            return jsonify({
                "error": "provide 'deployments': [...] or 'all': true"}), 400
        names = [n for n in available if n in set(wanted)]
        missing = set(wanted) - set(names)
        if missing:
            return jsonify({
                "error": "not a runnable deployment folder: "
                         + ", ".join(sorted(missing)),
                "available": available,
            }), 404

    if not names:
        return jsonify({
            "error": "no deployment folders found",
            "hint": f"looked in {RAW_DATA_DIR}",
        }), 404

    if not os.path.exists(PIPELINE_SCRIPT):
        return jsonify({
            "error": f"pipeline script not found: {PIPELINE_SCRIPT}. "
                     f"Set GLIDER_PIPELINE to its location."}), 500

    # Guard the lock rather than the flag above: two POSTs arriving together
    # could both pass that check before either sets running=True.
    if not _batch_lock.acquire(blocking=False):
        return jsonify({"error": "a batch run is already in progress"}), 409

    do_reset = bool(body.get("reset"))
    do_ingest = bool(body.get("ingest"))

    def _worker():
        try:
            _run_batch(names, do_reset, do_ingest)
        finally:
            _batch_lock.release()

    threading.Thread(target=_worker, daemon=True).start()

    return jsonify({
        "status": "started",
        "deployments": names,
        "reset": do_reset,
        "ingest": do_ingest,
    })


@app.route('/api/batch/status')
def batch_status():
    st = {k: v for k, v in batch_state.items()}
    st["log"] = "\n".join(batch_state["log"])
    total = (len(st["done"]) + len(st["errors"]) + len(st["queue"])
             + (1 if st["current"] else 0))
    finished = len(st["done"]) + len(st["errors"])
    st["total"] = total
    st["progress"] = (
        100 if (not st["running"] and total and not st["queue"])
        else int(100 * finished / total) if total else 0
    )
    return jsonify(st)


@app.route('/api/batch/cancel', methods=['POST'])
def batch_cancel():
    """
    Stop the batch.

    The deployment currently running is terminated, which leaves its output/
    half-written — reset it before trusting anything in there. Queued
    deployments are simply skipped.
    """
    if not batch_state["running"]:
        return jsonify({"error": "no batch run in progress"}), 409
    batch_state["cancel"] = True
    _batch_log("cancel requested — stopping after the current deployment "
               "is terminated")
    return jsonify({"status": "cancelling", "current": batch_state["current"]})


@app.route('/api/db/summary')
def db_summary():
    """Compact rollup of the combined database, for the dashboard header."""
    import sqlite3

    db = db_path()
    if not os.path.exists(db):
        return jsonify({"exists": False, "database": db})

    conn = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    try:
        deps = [dict(r) for r in conn.execute(
            "SELECT glider_id, deployment_start, deployment_end, n_profiles,"
            "       n_observations, n_gps_fixes, distance_over_ground_km,"
            "       max_depth_dbar, ego_format_version, processed_at"
            "  FROM meta ORDER BY deployment_start")]
        n_obs = conn.execute("SELECT COUNT(*) FROM observation").fetchone()[0]
        core_cols = [r[1] for r in conn.execute("PRAGMA table_info(core)")
                     if r[1] != "observation_id"
                     and not r[1].endswith(("_QC", "_ADJUSTED",
                                            "_ADJUSTED_QC"))]
        bgc_cols = [r[1] for r in conn.execute("PRAGMA table_info(bgc)")
                    if r[1] != "observation_id"
                    and not r[1].endswith(("_QC", "_ADJUSTED",
                                           "_ADJUSTED_QC"))]
        return jsonify({
            "exists": True,
            "database": db,
            "size_mb": round(os.path.getsize(db) / (1024 * 1024), 1),
            "n_deployments": len(deps),
            "n_observations": n_obs,
            "core_params": core_cols,
            "bgc_params": bgc_cols,
            "deployments": deps,
        })
    finally:
        conn.close()


if __name__ == '__main__':
    # debug=True enables the Werkzeug interactive debugger, which is remote
    # code execution for anyone who can reach the port. This app also spawns
    # subprocesses, so it must not be exposed. Opt in explicitly, and only
    # for local development:  GLIDER_DASHBOARD_DEBUG=1
    debug = os.environ.get("GLIDER_DASHBOARD_DEBUG", "") == "1"
    host = os.environ.get("GLIDER_DASHBOARD_HOST", "127.0.0.1")
    port = int(os.environ.get("GLIDER_DASHBOARD_PORT", "5000"))

    if debug and host not in ("127.0.0.1", "localhost", "::1"):
        sys.exit("REFUSING TO START: debug mode is only safe on localhost. "
                 f"Got host={host!r}.")

    print(f"  raw data : {RAW_DATA_DIR}")
    print(f"  pipeline : {PIPELINE_SCRIPT}")
    print(f"  python   : {PYTHON}")
    print(f"  database : {db_path()}")
    if not os.path.isdir(RAW_DATA_DIR):
        print(f"  WARNING: raw data dir does not exist — "
              f"set GLIDER_RAW_DATA_DIR")
    if not os.path.exists(db_path()):
        print(f"  WARNING: database not found — build it with "
              f"`python tools/load_db.py <deployment_dir> --fresh` "
              f"or set GLIDER_DB")
    print(f"  serving on http://{host}:{port}")

    # threaded=True is not optional here. The dashboard fires several API
    # requests per page load, and the default single-threaded dev server
    # serialises them — on Windows that showed up as connections being reset
    # mid-body even though the handler had returned 200.
    app.run(host=host, port=port, debug=debug, threaded=True)
