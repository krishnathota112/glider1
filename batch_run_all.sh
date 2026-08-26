#!/usr/bin/env bash
# ============================================================
#  batch_run_all.sh — Process EVERY deployment in a Raw_Data
#  folder and produce a consolidated report.
#
#  USAGE:
#    bash batch_run_all.sh /path/to/Raw_Data
#    bash batch_run_all.sh /path/to/Raw_Data --ingest
#
#  After completion a file is written:
#    /path/to/Raw_Data/batch_report.txt
#
#  This report lists every deployment processed, pass/fail, elapsed
#  time, and a final summary — suitable for documentation.
# ============================================================

set -euo pipefail

# ── Parse args ──────────────────────────────────────────────────────
RAW_DATA_DIR=""
DO_INGEST=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ingest) DO_INGEST=1; shift ;;
        -h|--help)
            echo "Usage: bash batch_run_all.sh <RAW_DATA_DIR> [--ingest]"
            exit 0 ;;
        -*)  echo "Unknown option: $1" >&2; exit 2 ;;
        *)
            if [[ -z "$RAW_DATA_DIR" ]]; then
                RAW_DATA_DIR="$1"; shift
            else
                echo "Unexpected argument: $1" >&2; exit 2
            fi ;;
    esac
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "$RAW_DATA_DIR" ]]; then
    # Auto-detect: look for a Raw_Data sibling or common locations
    for candidate in \
        "$(dirname "$REPO_ROOT")/Raw_Data" \
        "$HOME/PAJO/GliderProcessingChain/Glider_RTQC/Raw_Data" \
        "$HOME/Raw_Data" \
        "/data/Raw_Data"; do
        if [[ -d "$candidate" ]]; then
            RAW_DATA_DIR="$candidate"
            echo "Auto-detected Raw_Data: $RAW_DATA_DIR"
            break
        fi
    done
fi

if [[ -z "$RAW_DATA_DIR" ]]; then
    echo "ERROR: must pass the Raw_Data directory." >&2
    echo "  bash batch_run_all.sh /path/to/Raw_Data" >&2
    exit 2
fi

if [[ ! -d "$RAW_DATA_DIR" ]]; then
    echo "ERROR: not a directory: $RAW_DATA_DIR" >&2
    exit 1
fi

RAW_DATA_DIR="$(cd "$RAW_DATA_DIR" && pwd)"
PIPELINE="$REPO_ROOT/pipeline/run_pipeline.py"
REPORT="$RAW_DATA_DIR/batch_report.txt"

# ── Find Python ─────────────────────────────────────────────────────
PYTHON="${GLIDER_PYTHON:-}"
if [[ -z "$PYTHON" ]]; then
    for c in "$REPO_ROOT/.venv/bin/python" "$REPO_ROOT/venv/bin/python"; do
        [[ -x "$c" ]] && PYTHON="$c" && break
    done
fi
if [[ -z "$PYTHON" ]]; then
    if command -v conda &>/dev/null; then
        CONDA_BASE=$(conda info --base 2>/dev/null)
        for ENV in glider base; do
            PY="$CONDA_BASE/envs/$ENV/bin/python"
            [[ "$ENV" = "base" ]] && PY="$CONDA_BASE/bin/python"
            [[ -x "$PY" ]] && PYTHON="$PY" && break
        done
    fi
fi
if [[ -z "$PYTHON" ]]; then
    PYTHON="$(command -v python3 || command -v python || true)"
fi
if [[ -z "$PYTHON" ]]; then
    echo "ERROR: no python found." >&2; exit 1
fi

# ── Detect deployments (same logic as the dashboard) ────────────────
# A valid deployment has deployment.yml, combined_binary/, raw binaries,
# an output/ directory, or NetCDF files within two levels.
is_deployment() {
    local dir="$1"
    [[ -f "$dir/deployment.yml" ]] && return 0
    [[ -d "$dir/combined_binary" ]] && return 0
    [[ -d "$dir/output" ]] && return 0
    # Check for raw binaries or .nc at top or one level down
    find "$dir" -maxdepth 2 \( -name "*.dcd" -o -name "*.ecd" \
         -o -name "*.dbd" -o -name "*.ebd" -o -name "*.nc" \) \
         -print -quit 2>/dev/null | grep -q . && return 0
    return 1
}

# Handle nested deployments (e.g. 1131-Data/1131-Data/...)
resolve_root() {
    local base="$1"
    if [[ -d "$base/output" ]] || [[ -f "$base/deployment.yml" ]] \
       || [[ -d "$base/combined_binary" ]]; then
        echo "$base"; return
    fi
    for child in "$base"/*/; do
        child="${child%/}"
        if [[ -d "$child/output" ]] || [[ -f "$child/deployment.yml" ]] \
           || [[ -d "$child/combined_binary" ]]; then
            echo "$child"; return
        fi
    done
    echo "$base"
}

DEPLOYMENTS=()
for dir in "$RAW_DATA_DIR"/*/; do
    dir="${dir%/}"
    name="$(basename "$dir")"
    if is_deployment "$dir"; then
        DEPLOYMENTS+=("$name")
    fi
done

N=${#DEPLOYMENTS[@]}
if [[ $N -eq 0 ]]; then
    echo "ERROR: no deployment folders found in $RAW_DATA_DIR" >&2
    exit 1
fi

# ── Begin ───────────────────────────────────────────────────────────
BATCH_START=$(date +%s)
NOW=$(date '+%Y-%m-%d %H:%M:%S')

tee "$REPORT" <<EOF
================================================================
  GLIDER RTQC BATCH PROCESSING REPORT
================================================================
  Date       : $NOW
  Raw_Data   : $RAW_DATA_DIR
  Repo       : $REPO_ROOT
  Python     : $PYTHON ($($PYTHON --version 2>&1))
  Deployments: $N
  Ingest DB  : $(if [[ $DO_INGEST -eq 1 ]]; then echo "YES (after all runs)"; else echo "no"; fi)
================================================================

EOF

OK=0
FAIL=0
SKIPPED=0

for i in "${!DEPLOYMENTS[@]}"; do
    name="${DEPLOYMENTS[$i]}"
    idx=$((i + 1))
    dep_dir="$(resolve_root "$RAW_DATA_DIR/$name")"

    echo ""
    echo "────────────────────────────────────────────────────────────"
    echo "  [$idx/$N]  $name"
    echo "────────────────────────────────────────────────────────────"

    {
        echo "────────────────────────────────────────────────────────────"
        echo "  [$idx/$N]  $name"
        echo "  path: $dep_dir"
        echo "  started: $(date '+%H:%M:%S')"
    } >> "$REPORT"

    T0=$(date +%s)

    # Run the pipeline, capture exit code
    set +e
    "$PYTHON" -u "$PIPELINE" --data-dir "$dep_dir" --l0-source auto 2>&1 \
        | tee -a "$RAW_DATA_DIR/${name}_pipeline.log"
    RC=$?
    set -e

    T1=$(date +%s)
    ELAPSED=$(( T1 - T0 ))

    if [[ $RC -eq 0 ]]; then
        STATUS="OK"
        OK=$((OK + 1))
    else
        STATUS="FAILED (exit $RC)"
        FAIL=$((FAIL + 1))
    fi

    {
        echo "  finished: $(date '+%H:%M:%S')  elapsed: ${ELAPSED}s"
        echo "  status: $STATUS"

        # Append key file sizes if output exists
        OUT="$dep_dir/output"
        if [[ -d "$OUT" ]]; then
            echo "  outputs:"
            # L0
            for f in "$OUT"/L0-timeseries/*.nc; do
                [[ -f "$f" ]] && echo "    L0 timeseries: $(basename "$f") ($(du -h "$f" | cut -f1))"
            done
            # L1
            for f in "$OUT"/L1-timeseries/*.nc; do
                [[ -f "$f" ]] && echo "    L1 timeseries: $(basename "$f") ($(du -h "$f" | cut -f1))"
            done
            # EGO
            for f in "$OUT"/EGO-timeseries/*.nc; do
                [[ -f "$f" ]] && echo "    EGO:           $(basename "$f") ($(du -h "$f" | cut -f1))"
            done
            # Grid
            for f in "$OUT"/L1-gridfiles/*.nc; do
                [[ -f "$f" ]] && echo "    L1 grid:       $(basename "$f") ($(du -h "$f" | cut -f1))"
            done
            # Profiles count
            N_PROF=$(find "$OUT/L1-profiles" -name "*.nc" 2>/dev/null | wc -l)
            [[ $N_PROF -gt 0 ]] && echo "    L1 profiles:   $N_PROF files"
            # Plots count
            N_PLOTS=$(find "$OUT/plots" -name "*.png" 2>/dev/null | wc -l)
            [[ $N_PLOTS -gt 0 ]] && echo "    plots:         $N_PLOTS PNG files"
        fi
        echo ""
    } >> "$REPORT"

    echo "  >> $name: $STATUS (${ELAPSED}s)"
done

# ── Optional: ingest all into combined DB ───────────────────────────
DB="$RAW_DATA_DIR/glider_rtqc.db"
if [[ $DO_INGEST -eq 1 ]]; then
    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "  INGESTING ALL DEPLOYMENTS INTO: $DB"
    echo "════════════════════════════════════════════════════════════"

    {
        echo "────────────────────────────────────────────────────────────"
        echo "  DATABASE INGESTION"
        echo "  database: $DB"
        echo "  started: $(date '+%H:%M:%S')"
    } >> "$REPORT"

    set +e
    for name in "${DEPLOYMENTS[@]}"; do
        dep_dir="$(resolve_root "$RAW_DATA_DIR/$name")"
        EGO_DIR="$dep_dir/output/EGO-timeseries"
        if [[ -d "$EGO_DIR" ]] && ls "$EGO_DIR"/*.nc >/dev/null 2>&1; then
            "$PYTHON" -m db.load_deployment --ego-dir "$EGO_DIR" --db "$DB" 2>&1 \
                | tail -5
        fi
    done
    set -e

    {
        echo "  finished: $(date '+%H:%M:%S')"
        echo "  database size: $(du -h "$DB" 2>/dev/null | cut -f1)"
        echo ""
    } >> "$REPORT"
fi

# ── Final summary ──────────────────────────────────────────────────
BATCH_END=$(date +%s)
TOTAL_ELAPSED=$(( BATCH_END - BATCH_START ))

SUMMARY=$(cat <<EOF
================================================================
  BATCH SUMMARY
================================================================
  Total deployments : $N
  Succeeded         : $OK
  Failed            : $FAIL
  Total time        : ${TOTAL_ELAPSED}s ($(( TOTAL_ELAPSED / 60 ))m $(( TOTAL_ELAPSED % 60 ))s)
  Report file       : $REPORT
  Per-deployment logs: ${RAW_DATA_DIR}/<name>_pipeline.log
  Combined database : $DB
================================================================
EOF
)

echo ""
echo "$SUMMARY"
echo "$SUMMARY" >> "$REPORT"

echo ""
echo "Done. Full report: $REPORT"
