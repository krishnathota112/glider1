import os
import re
import sys
import glob
import subprocess
from flask import Flask, jsonify, render_template, send_from_directory, abort, request

app = Flask(__name__, template_folder='templates')

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

RAW_DATA_DIR = os.path.abspath(os.environ.get(
    "GLIDER_RAW_DATA_DIR",
    os.path.join(os.path.dirname(_REPO_ROOT), "Raw_Data")))

PIPELINE_SCRIPT = os.path.abspath(os.environ.get(
    "GLIDER_PIPELINE",
    os.path.join(_REPO_ROOT, "pipeline", "run_pipeline.py")))

PYTHON = os.environ.get("GLIDER_PYTHON", sys.executable)

# Active processes tracker: glider_id -> { "process": Popen, "status": str,
#                                          "log_path": str, "log_file": handle }
active_processes = {}

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

@app.route('/api/transects')
def get_transects():
    transects = []
    if not os.path.exists(RAW_DATA_DIR):
        return jsonify([])
        
    for name in os.listdir(RAW_DATA_DIR):
        folder_path = os.path.join(RAW_DATA_DIR, name)
        if not os.path.isdir(folder_path):
            continue
            
        plots_dir = os.path.join(folder_path, 'output', 'plots')
        reports_dir = os.path.join(folder_path, 'output', 'reports')
        
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
            
        transects.append({
            'folder_name': name,
            'status': status,
            'metadata': summary_data,
            'plots': sorted(plot_files)
        })
        
    return jsonify(sorted(transects, key=lambda x: x['folder_name']))

@app.route('/plots/<transect>/<filename>')
def serve_plot(transect, filename):
    safe_transect = os.path.basename(transect)
    safe_filename = os.path.basename(filename)
    plots_dir = os.path.join(RAW_DATA_DIR, safe_transect, 'output', 'plots')
    if not os.path.exists(os.path.join(plots_dir, safe_filename)):
        abort(404)
    return send_from_directory(plots_dir, safe_filename)

@app.route('/api/process/<glider_id>', methods=['POST'])
def process_transect(glider_id):
    safe_glider_id = os.path.basename(glider_id)
    folder_path = os.path.join(RAW_DATA_DIR, safe_glider_id)
    if not os.path.exists(folder_path):
        return jsonify({"error": "Transect directory not found"}), 404
        
    if safe_glider_id in active_processes and active_processes[safe_glider_id]["status"] == "running":
        return jsonify({"status": "running", "message": "Already running"})
        
    log_dir = os.path.join(app.root_path, 'logs')
    os.makedirs(log_dir, exist_ok=True)
    log_path = os.path.join(log_dir, f"{safe_glider_id}.log")
    
    # Initialize log file
    with open(log_path, 'w', encoding='utf-8') as f:
        f.write(f"============================================================\n")
        f.write(f" STARTING PIPELINE PROCESSING FOR GLIDER {safe_glider_id}\n")
        f.write(f"============================================================\n\n")
        
    if not os.path.exists(PIPELINE_SCRIPT):
        return jsonify({
            "error": f"pipeline script not found: {PIPELINE_SCRIPT}. "
                     f"Set GLIDER_PIPELINE to its location."
        }), 500

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
        return jsonify({"error": f"could not start pipeline: {exc}"}), 500

    # Keep the handle so process_status can close it once the run ends —
    # previously it was left open for the lifetime of the server, leaking one
    # file descriptor per launch.
    active_processes[safe_glider_id] = {
        "process": proc,
        "status": "running",
        "log_path": log_path,
        "log_file": log_file,
    }

    return jsonify({"status": "running", "message": "Processing started"})

@app.route('/api/status/<glider_id>')
def process_status(glider_id):
    safe_glider_id = os.path.basename(glider_id)
    
    if safe_glider_id not in active_processes:
        # Check if already processed (plots exist)
        plots_dir = os.path.join(RAW_DATA_DIR, safe_glider_id, 'output', 'plots')
        if os.path.exists(plots_dir) and any(f.endswith('.png') for f in os.listdir(plots_dir)):
            return jsonify({"status": "processed", "progress": 100, "log": "Already processed."})
        return jsonify({"status": "unprocessed", "progress": 0, "log": "Idle."})
        
    info = active_processes[safe_glider_id]
    proc = info["process"]
    
    poll = proc.poll()
    if poll is not None:
        info["status"] = "completed" if poll == 0 else "failed"
        # The child has exited; release our end of the log file.
        log_file = info.pop("log_file", None)
        if log_file is not None and not log_file.closed:
            log_file.close()


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
    if not os.path.isdir(RAW_DATA_DIR):
        print(f"  WARNING: raw data dir does not exist — "
              f"set GLIDER_RAW_DATA_DIR")

    app.run(host=host, port=port, debug=debug)
