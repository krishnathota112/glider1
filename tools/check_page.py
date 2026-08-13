"""Confirm the served page really contains the EGO panel and its wiring."""
import sys
import urllib.request

BASE = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:5000"
with urllib.request.urlopen(f"{BASE}/", timeout=60) as r:
    html = r.read().decode("utf-8", "replace")

print(f"page size: {len(html):,} bytes\n")

MARKERS = [
    ('id="ego-card"', "EGO panel container"),
    ('id="ego-badge"', "compliance badge"),
    ('data-ego-tab="db"', "Database tab"),
    ('data-ego-tab="compliance"', "Compliance tab"),
    ('data-ego-tab="platform"', "Platform tab"),
    ('data-ego-tab="sensors"', "Sensors tab"),
    ('data-ego-tab="params"', "Parameters tab"),
    ('data-ego-tab="history"', "History tab"),
    ("function egoLoad", "egoLoad()"),
    ("egoRenderDB", "database renderer"),
    ("egoRenderCompliance", "compliance renderer"),
    ("egoRenderMetadata", "metadata renderer"),
    ("egoQCBar", "QC bar renderer"),
    ("setupEgoListeners", "tab listeners"),
    ("/api/ego/${encodeURIComponent(gid)}/compliance", "compliance fetch"),
    ("/api/db/${encodeURIComponent(gid)}/qc", "QC fetch"),
    ("/api/db/deployments", "deployments fetch"),
    ("egoLoad(transect.glider_id", "wired into selectTransect"),
]

missing = 0
for needle, label in MARKERS:
    ok = needle in html
    if not ok:
        missing += 1
    print(f"  [{'OK ' if ok else 'MISS'}] {label}")

print()
print(f"  {len(MARKERS) - missing}/{len(MARKERS)} markers present")
sys.exit(1 if missing else 0)
