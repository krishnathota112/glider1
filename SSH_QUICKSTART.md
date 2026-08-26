# SSH Quick-Start — Glider RTQC Pipeline

Copy-paste these commands. Replace `/path/to/Raw_Data` with your actual data path.

---

## 1. First-time setup (once)

```bash
# Clone the repo
git clone https://github.com/pajonnakuti/Glider_RTQC.git
cd Glider_RTQC

# Create a venv and install everything
python3 -m venv .venv
source .venv/bin/activate
pip install -e ".[decode,plots,dashboard]"
```

---

## 2. Run the pipeline on ONE deployment

```bash
cd Glider_RTQC
source .venv/bin/activate

bash run_pipeline.sh /path/to/Raw_Data/1130-Mar-2025
```

Output goes to `/path/to/Raw_Data/1130-Mar-2025/output/`.

---

## 3. Batch-run ALL deployments + get a report

```bash
cd Glider_RTQC
source .venv/bin/activate

# Process everything and ingest into one database:
bash batch_run_all.sh /path/to/Raw_Data --ingest
```

When it finishes you get:

| File | What |
|------|------|
| `/path/to/Raw_Data/batch_report.txt` | Full end-to-end report (pass/fail, timings, outputs) |
| `/path/to/Raw_Data/<name>_pipeline.log` | Detailed log per deployment |
| `/path/to/Raw_Data/glider_rtqc.db` | Combined SQLite database |

---

## 4. Start the web dashboard

```bash
cd Glider_RTQC
source .venv/bin/activate

bash run_dashboard.sh /path/to/Raw_Data
```

It binds to `localhost:5000`. On your laptop open an SSH tunnel:

```bash
ssh -N -L 5000:localhost:5000 user@server
```

Then open http://localhost:5000 in your browser.

From the dashboard you can also trigger batch runs and view results in the UI.

---

## 5. Check results

```bash
# Read the batch report
cat /path/to/Raw_Data/batch_report.txt

# Check a specific deployment's log
cat /path/to/Raw_Data/1130-Mar-2025_pipeline.log

# List what was produced
ls /path/to/Raw_Data/1130-Mar-2025/output/

# Quick DB check
sqlite3 /path/to/Raw_Data/glider_rtqc.db "SELECT glider_id, n_profiles, distance_over_ground_km FROM meta;"
```

---

## TL;DR — the absolute minimum

```bash
cd Glider_RTQC
source .venv/bin/activate
bash batch_run_all.sh /path/to/Raw_Data --ingest
cat /path/to/Raw_Data/batch_report.txt
```

That's it. Everything processes, a report is written, and the database is ready.
