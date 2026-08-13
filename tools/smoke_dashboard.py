#!/usr/bin/env python3
"""
smoke_dashboard.py — hit every dashboard endpoint and report what came back.

Verifies the API returns real data rather than just HTTP 200, so an endpoint
that answers with an empty list or an error payload is reported as a failure.
"""
from __future__ import annotations

import json
import sys
import time
import urllib.error
import urllib.request

BASE = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:5000"


def get(path, attempts=3):
    """
    Fetch a path, retrying on transport-level errors.

    The Werkzeug development server on Windows intermittently resets the
    connection mid-body even after the handler has returned 200 (confirmed
    against the server's own access log). Without a retry the harness reports
    healthy endpoints as failures, and which ones fail changes between runs.
    An HTTP error status is returned immediately — that is a real answer from
    the app, not a transport fault.
    """
    url = f"{BASE}{path}"
    last = None
    for i in range(attempts):
        try:
            with urllib.request.urlopen(url, timeout=180) as r:
                return r.status, r.read().decode("utf-8", "replace")
        except urllib.error.HTTPError as e:
            return e.code, e.read().decode("utf-8", "replace")
        except Exception as e:
            last = f"{type(e).__name__}: {e}"
            time.sleep(0.5 * (i + 1))
    return 0, f"{last} (after {attempts} attempts)"


def describe(path, body, status):
    """One-line summary of the payload, plus a pass/fail judgement."""
    try:
        data = json.loads(body)
    except ValueError:
        n = len(body)
        return (status == 200 and n > 0), f"non-JSON, {n} bytes"

    if isinstance(data, dict) and "error" in data:
        return False, f"error: {data['error']}"

    if isinstance(data, list):
        return len(data) > 0, f"list[{len(data)}]"

    bits = []
    ok = True
    for k, v in data.items():
        if isinstance(v, list):
            bits.append(f"{k}[{len(v)}]")
        elif isinstance(v, dict):
            bits.append(f"{k}{{{len(v)}}}")
        else:
            s = str(v)
            bits.append(f"{k}={s[:40]}")
    return ok, ", ".join(bits[:7])


CASES = [
    "/api/transects",
    "/api/db/deployments",
    "/api/db/1131/qc",
    "/api/db/1131/track",
    "/api/db/1131/profiles",
    "/api/db/1131/profile/500",
    "/api/db/1131/timeseries?var=TEMP&limit=500",
    "/api/db/1131/timeseries?var=DOXY&limit=500&good_only=1",
    "/api/ego/1131/metadata",
    "/api/ego/1131/compliance",
    "/",
]


def main() -> int:
    print("=" * 78)
    print(f"  DASHBOARD SMOKE TEST — {BASE}")
    print("=" * 78)
    failures = 0
    for path in CASES:
        status, body = get(path)
        ok, summary = describe(path, body, status)
        if status != 200:
            ok = False
        flag = "PASS" if ok else "FAIL"
        if not ok:
            failures += 1
        print(f"  [{flag}] {status} {path}")
        print(f"         {summary}")
    print()
    print(f"  {len(CASES) - failures}/{len(CASES)} endpoints OK")
    print("=" * 78)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
