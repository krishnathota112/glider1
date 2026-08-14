#!/bin/bash
# process_all.sh — Process all glider data and create databases
#
# Usage: ./process_all.sh /path/to/glider_data

set -e  # Exit on any error

if [ -z "$1" ]; then
    echo "Usage: ./process_all.sh <glider_data_directory>"
    echo "Example: ./process_all.sh /data/glider_data"
    exit 1
fi

DATA_ROOT="$1"

echo ""
echo "============================================================"
echo "GLIDER DATA PROCESSING - FULL WORKFLOW"
echo "============================================================"
echo "Data root: $DATA_ROOT"
echo ""

# Step 1: Batch process all deployments
echo ""
echo "[1/2] Processing all deployments..."
echo "============================================================"
python3 pipeline/batch_process.py "$DATA_ROOT"

# Step 2: Ingest to databases
echo ""
echo "[2/2] Creating databases..."
echo "============================================================"
python3 pipeline/ingest_to_db.py "$DATA_ROOT"

echo ""
echo "============================================================"
echo "COMPLETE"
echo "============================================================"
echo ""
echo "Individual databases: $DATA_ROOT/<deployment>/output/<deployment>.db"
echo "Combined database: $DATA_ROOT/glider_data_combined.db"
echo ""
