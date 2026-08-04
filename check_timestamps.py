#!/usr/bin/env python3
"""
check_timestamps.py — detect cross-deployment contamination in a binary folder.

Reads the timestamps out of Slocum flight files and reports any that fall
outside the deployment window, which is how binaries from an earlier mission or
a factory test end up silently merged into an L0.

Usage
-----
    python check_timestamps.py <binary_dir> [--start YYYY-MM-DD] [--end YYYY-MM-DD]

With no --start/--end the window is inferred from the data itself: the modal
month of the file timestamps is taken as the deployment, and anything more than
--margin days outside its span is reported. Pass explicit dates when you know
them — deployment.yml has them under metadata.deployment_start / _end.
"""
import argparse
import os
import sys
from datetime import datetime, timedelta, timezone

import numpy as np

try:
    import dbdreader
except ImportError:
    sys.exit("ERROR: dbdreader not installed.  Run: pip install dbdreader")


FLIGHT_EXTS = (".dbd", ".dcd")


def _utc(epoch_seconds):
    return datetime.fromtimestamp(epoch_seconds, tz=timezone.utc)


def read_file_span(path, cache_dir=None):
    """Return (first, last) UTC datetimes for one binary, or None."""
    try:
        d = dbdreader.DBD(path, cacheDir=cache_dir) if cache_dir \
            else dbdreader.DBD(path)
        try:
            t = d.get("m_present_time")
        finally:
            d.close()
    except Exception as exc:
        return exc

    times = t[0] if isinstance(t, (tuple, list)) else t
    times = np.asarray(times, dtype=float)
    times = times[np.isfinite(times)]
    if times.size == 0:
        return None
    return _utc(times.min()), _utc(times.max())


def infer_window(spans, margin_days):
    """
    Infer the deployment window from the modal month of the file spans.

    Contamination is by definition the minority — the bulk of the files belong
    to the real deployment, so the month holding most of them defines it.
    """
    if not spans:
        return None, None
    months = [d.strftime("%Y-%m") for d, _ in spans]
    modal = max(set(months), key=months.count)
    in_modal = [(a, b) for (a, b), m in zip(spans, months) if m == modal]
    start = min(a for a, _ in in_modal) - timedelta(days=margin_days)
    end = max(b for _, b in in_modal) + timedelta(days=margin_days)
    return start, end


def main(argv=None):
    p = argparse.ArgumentParser(
        description="Detect cross-deployment contamination in a binary folder.")
    p.add_argument("binary_dir",
                   help="folder of .dbd/.dcd flight files "
                        "(usually <data_dir>/combined_binary)")
    p.add_argument("--start", default=None,
                   help="deployment start, YYYY-MM-DD (default: inferred)")
    p.add_argument("--end", default=None,
                   help="deployment end, YYYY-MM-DD (default: inferred)")
    p.add_argument("--margin", type=int, default=30,
                   help="days of slack around the window (default: 30)")
    p.add_argument("--limit", type=int, default=0,
                   help="inspect at most N files (0 = all, the default). "
                        "Counts below are always over the files inspected.")
    args = p.parse_args(argv)

    binary_dir = os.path.abspath(args.binary_dir)
    if not os.path.isdir(binary_dir):
        sys.exit(f"ERROR: not a directory: {binary_dir}")

    # The pipeline keeps its dbdreader cache next to the binary folder.
    cache_dir = os.path.join(os.path.dirname(binary_dir), "cache")
    cache_dir = cache_dir if os.path.isdir(cache_dir) else None
    if cache_dir:
        print(f"Using cache: {cache_dir}")

    files = sorted(f for f in os.listdir(binary_dir)
                   if f.lower().endswith(FLIGHT_EXTS))
    if not files:
        sys.exit(f"ERROR: no {'/'.join(FLIGHT_EXTS)} files in {binary_dir}")

    if args.limit and args.limit < len(files):
        files = files[:args.limit]
        print(f"Inspecting the first {len(files)} flight files "
              f"(--limit); totals below cover only these.")
    else:
        print(f"Inspecting all {len(files)} flight files in {binary_dir}")
    print()

    spans, empty, errors = [], [], []
    for fn in files:
        result = read_file_span(os.path.join(binary_dir, fn), cache_dir)
        if result is None:
            empty.append(fn)
        elif isinstance(result, Exception):
            errors.append((fn, result))
        else:
            spans.append((fn, result[0], result[1]))

    if not spans:
        sys.exit("ERROR: no file yielded a usable timestamp.")

    if args.start or args.end:
        margin = timedelta(days=args.margin)
        start = (datetime.strptime(args.start, "%Y-%m-%d")
                 .replace(tzinfo=timezone.utc) - margin) if args.start else None
        end = (datetime.strptime(args.end, "%Y-%m-%d")
               .replace(tzinfo=timezone.utc) + margin) if args.end else None
        source = "command line"
    else:
        start, end = infer_window([(a, b) for _, a, b in spans], args.margin)
        source = "inferred from modal month"

    print(f"Deployment window ({source}, ±{args.margin}d):")
    print(f"  {start}  ->  {end}")
    print()

    outside = [(fn, a, b) for fn, a, b in spans
               if (start is not None and a < start)
               or (end is not None and b > end)]
    inside = len(spans) - len(outside)

    for fn, a, b in spans[:10]:
        mark = "OUT" if (fn, a, b) in outside else " OK"
        print(f"  {mark} {fn}: {a:%Y-%m-%d %H:%M} -> {b:%Y-%m-%d %H:%M}")
    if len(spans) > 10:
        print(f"  ... {len(spans) - 10} more")

    if empty:
        print(f"\n{len(empty)} file(s) had no m_present_time data")
    if errors:
        print(f"{len(errors)} file(s) could not be read "
              f"(first: {errors[0][0]} — {type(errors[0][1]).__name__})")

    print(f"\nTotal: {len(outside)} outside the window, "
          f"{inside} within, out of {len(spans)} readable files")

    if outside:
        outside.sort(key=lambda r: r[1])
        print(f"\nFiles outside the deployment window:")
        for fn, a, b in outside[:20]:
            print(f"  {fn}: {a:%Y-%m-%d %H:%M} -> {b:%Y-%m-%d %H:%M}")
        if len(outside) > 20:
            print(f"  ... and {len(outside) - 20} more")
        print(f"\nEarliest: {outside[0][0]} starts {outside[0][1]}")
        print(f"Latest:   {outside[-1][0]} ends   {outside[-1][2]}")
        print(f"\nRECOMMENDATION: review these {len(outside)} file(s) before "
              f"decoding — they look like a different deployment or a test "
              f"session and will contaminate the L0. Removing them from "
              f"{os.path.basename(binary_dir)}/ is safe; the originals stay "
              f"in their source folders.")
        return 1

    print("\nNo contamination detected.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
