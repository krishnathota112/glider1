#!/usr/bin/env python3
"""
layout.py — the single source of truth for a deployment's output layout.

Every path under a deployment's output/ is defined here and nowhere else.
Before this module the same directory names were hardcoded in step1, step4,
step5, step6, step7, step_ego, run_pipeline, three tools/ scripts, the web
dashboard and the database loader — eleven places that had to agree, and
didn't. Changing the layout meant finding all of them.

Layout
------
    <deployment>/
        output/
            L0/
                L0_timeseries/    L0 NetCDF, incl. the EGO 1.5 conversion
                L0_profiles/      one NetCDF per dive/climb
                L0_gridfiles/     time x depth gridded NetCDF
            L1/
                L1_timeseries/    L1 NetCDF, incl. the EGO 1.5 conversion
                L1_profiles/
                L1_gridfiles/
            plots/                PNG figures
            reports/              text/PDF deployment summaries
            <deployment>.db       SQLite for THIS deployment only

The combined database lives one level up, beside the deployment folders:

    <Raw_Data>/glider_rtqc.db

Legacy layout
-------------
Earlier runs used flat directories directly under output/:

    output/L0-timeseries/  output/L0-profiles/  output/L0-gridfiles/
    output/L1-timeseries/  output/L1-profiles/  output/L1-gridfiles/
    output/EGO-timeseries/

Readers must keep working against data produced before the change, so every
lookup helper here searches the current location first and then the legacy
ones. Writers only ever use the current layout.
"""
from __future__ import annotations

import os
import glob

# Current layout: output/<LEVEL>/<LEVEL>_<kind>/
_KINDS = ("timeseries", "profiles", "gridfiles")

# Legacy flat names, searched by readers only. Order matters: the first hit
# wins, so the current layout must be tried before these.
_LEGACY = {
    ("L0", "timeseries"): ("L0-timeseries",),
    ("L0", "profiles"):   ("L0-profiles", "profiles"),
    ("L0", "gridfiles"):  ("L0-gridfiles", "gridfiles"),
    ("L1", "timeseries"): ("L1-timeseries",),
    ("L1", "profiles"):   ("L1-profiles", "profiles"),
    ("L1", "gridfiles"):  ("L1-gridfiles", "gridfiles"),
}

# EGO products used to get their own directory. They now sit in the timeseries
# directory of the level they describe.
_LEGACY_EGO = ("EGO-timeseries",)


# ── Writers: the current layout only ────────────────────────────────

def level_dir(output_dir: str, level: str) -> str:
    """output/L0 or output/L1."""
    return os.path.join(output_dir, level.upper())


def product_dir(output_dir: str, level: str, kind: str) -> str:
    """
    output/<LEVEL>/<LEVEL>_<kind>, e.g. output/L0/L0_timeseries.

    `kind` is one of 'timeseries', 'profiles', 'gridfiles'.
    """
    level = level.upper()
    if kind not in _KINDS:
        raise ValueError(f"kind must be one of {_KINDS}, got {kind!r}")
    return os.path.join(level_dir(output_dir, level), f"{level}_{kind}")


def plots_dir(output_dir: str) -> str:
    return os.path.join(output_dir, "plots")


def reports_dir(output_dir: str) -> str:
    return os.path.join(output_dir, "reports")


def deployment_db(output_dir: str, deployment_name: str) -> str:
    """
    The per-deployment SQLite file: output/<deployment_name>.db

    Holds only this deployment. Named after the data product so it is
    self-identifying once copied elsewhere.
    """
    return os.path.join(output_dir, f"{deployment_name}.db")


COMBINED_DB_NAME = "glider_rtqc.db"


def combined_db(raw_data_dir: str) -> str:
    """
    The combined database, beside the deployment folders in Raw_Data.

    Deliberately outside any single deployment's output/: it aggregates all of
    them, so storing it inside one would make that deployment's directory
    non-self-contained and invite it being deleted with a re-run.
    """
    return os.path.join(raw_data_dir, COMBINED_DB_NAME)


def all_dirs(output_dir: str) -> dict:
    """
    Every directory a pipeline run writes to, keyed for run_pipeline.

    Keys are kept stable (L0_ts, L0_profiles, ...) so callers do not need to
    know the on-disk names.
    """
    return {
        "L0_ts":       product_dir(output_dir, "L0", "timeseries"),
        "L0_profiles": product_dir(output_dir, "L0", "profiles"),
        "L0_grid":     product_dir(output_dir, "L0", "gridfiles"),
        "L1_ts":       product_dir(output_dir, "L1", "timeseries"),
        "L1_profiles": product_dir(output_dir, "L1", "profiles"),
        "L1_grid":     product_dir(output_dir, "L1", "gridfiles"),
        "plots":       plots_dir(output_dir),
        "reports":     reports_dir(output_dir),
    }


def make_all(output_dir: str) -> dict:
    """Create every output directory and return the same mapping."""
    d = all_dirs(output_dir)
    for p in d.values():
        os.makedirs(p, exist_ok=True)
    return d


# ── Readers: current layout, then legacy ────────────────────────────

def search_dirs(output_dir: str, level: str, kind: str) -> list:
    """
    Candidate directories for a product, current layout first.

    Only directories that exist are returned, so callers can iterate without
    checking. Deployments processed before the layout change resolve through
    the legacy entries.
    """
    level = level.upper()
    cands = [product_dir(output_dir, level, kind)]
    for name in _LEGACY.get((level, kind), ()):
        cands.append(os.path.join(output_dir, name))
    if kind == "timeseries":
        for name in _LEGACY_EGO:
            cands.append(os.path.join(output_dir, name))
    # The L0 timeseries has also been found at the deployment root rather than
    # under output/, from runs that predated the output/ directory entirely.
    if kind == "timeseries":
        parent = os.path.dirname(os.path.abspath(output_dir))
        cands.append(os.path.join(parent, f"{level}-timeseries"))
        cands.append(os.path.join(parent, level, f"{level}_{kind}"))

    seen, out = set(), []
    for c in cands:
        rc = os.path.abspath(c)
        if rc in seen:
            continue
        seen.add(rc)
        if os.path.isdir(rc):
            out.append(rc)
    return out


def find_products(output_dir: str, level: str, kind: str,
                  pattern: str = "*.nc") -> list:
    """All files of one kind for one level, across current and legacy dirs."""
    hits = []
    for d in search_dirs(output_dir, level, kind):
        hits.extend(sorted(glob.glob(os.path.join(d, pattern))))
    # Deduplicate by real path: legacy and current can be the same directory
    # when a deployment was migrated by moving rather than reprocessing.
    seen, out = set(), []
    for h in hits:
        rh = os.path.realpath(h)
        if rh not in seen:
            seen.add(rh)
            out.append(h)
    return out


def find_timeseries(output_dir: str, level: str) -> list:
    """
    Timeseries NetCDFs for a level, current layout first.

    There is one product file per level and it is EGO 1.5 format:

        output/L0/L0_timeseries/incois_glider_<ID>_L0.nc
        output/L1/L1_timeseries/incois_glider_<ID>_L1.nc

    Older runs also produced a parallel *_EGO.nc copy; those are still returned
    so previously-processed deployments remain readable, but nothing writes
    them any more.
    """
    return find_products(output_dir, level, "timeseries")


def product_file(output_dir: str, level: str, glider_id: str) -> str:
    """The canonical timeseries product path for a level."""
    level = level.upper()
    return os.path.join(product_dir(output_dir, level, "timeseries"),
                        f"incois_glider_{glider_id}_{level}.nc")


def legacy_dirs_present(output_dir: str) -> list:
    """
    Legacy directories that still exist, for migration reporting.

    Used by the migration helper and by the dashboard so a half-migrated
    deployment is visible rather than silently mixed.
    """
    names = set()
    for v in _LEGACY.values():
        names.update(v)
    names.update(_LEGACY_EGO)
    return [os.path.join(output_dir, n) for n in sorted(names)
            if os.path.isdir(os.path.join(output_dir, n))]
