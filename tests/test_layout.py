"""
Tests for pipeline/layout.py — the single definition of the output layout.

Covers the two things that actually break: that writers use the new nested
layout, and that readers still resolve data written under the old flat one.
"""
import os
import sys

import pytest

_REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(_REPO, "pipeline"))

import layout  # noqa: E402


def test_product_dir_is_nested_per_level():
    out = os.path.join("dep", "output")
    assert layout.product_dir(out, "L0", "timeseries") == \
        os.path.join(out, "L0", "L0_timeseries")
    assert layout.product_dir(out, "L1", "gridfiles") == \
        os.path.join(out, "L1", "L1_gridfiles")
    assert layout.product_dir(out, "L1", "profiles") == \
        os.path.join(out, "L1", "L1_profiles")


def test_level_is_case_insensitive():
    out = "o"
    assert layout.product_dir(out, "l0", "profiles") == \
        layout.product_dir(out, "L0", "profiles")


def test_rejects_unknown_kind():
    with pytest.raises(ValueError):
        layout.product_dir("o", "L0", "nonsense")


def test_all_dirs_covers_every_product():
    d = layout.all_dirs(os.path.join("dep", "output"))
    assert set(d) == {"L0_ts", "L0_profiles", "L0_grid",
                      "L1_ts", "L1_profiles", "L1_grid",
                      "plots", "reports"}


def test_per_deployment_db_is_named_after_the_product():
    out = os.path.join("Raw_Data", "1127", "output")
    assert layout.deployment_db(out, "1127") == os.path.join(out, "1127.db")


def test_combined_db_sits_beside_the_deployments():
    # Deliberately NOT inside any deployment: it aggregates all of them, so
    # putting it in one would make that folder non-self-contained.
    assert layout.combined_db("Raw_Data") == \
        os.path.join("Raw_Data", "glider_rtqc.db")


def test_make_all_creates_the_nested_tree(tmp_path):
    out = tmp_path / "output"
    d = layout.make_all(str(out))
    for p in d.values():
        assert os.path.isdir(p), p
    assert (out / "L0" / "L0_timeseries").is_dir()
    assert (out / "L1" / "L1_gridfiles").is_dir()
    assert (out / "plots").is_dir()


def test_search_dirs_prefers_current_over_legacy(tmp_path):
    out = tmp_path / "output"
    current = out / "L1" / "L1_timeseries"
    legacy = out / "L1-timeseries"
    current.mkdir(parents=True)
    legacy.mkdir(parents=True)

    dirs = layout.search_dirs(str(out), "L1", "timeseries")
    assert dirs[0] == str(current), "current layout must be searched first"
    assert str(legacy) in dirs, "legacy layout must remain readable"


def test_search_dirs_omits_absent_directories(tmp_path):
    out = tmp_path / "output"
    out.mkdir()
    assert layout.search_dirs(str(out), "L0", "profiles") == []


def test_find_products_reads_both_layouts(tmp_path):
    out = tmp_path / "output"
    current = out / "L0" / "L0_profiles"
    legacy = out / "L0-profiles"
    current.mkdir(parents=True)
    legacy.mkdir(parents=True)
    (current / "new.nc").write_bytes(b"x")
    (legacy / "old.nc").write_bytes(b"x")

    names = {os.path.basename(p)
             for p in layout.find_products(str(out), "L0", "profiles")}
    assert names == {"new.nc", "old.nc"}


def test_product_file_has_no_ego_suffix(tmp_path):
    # The EGO-format file IS the product; it does not get a parallel _EGO copy.
    out = str(tmp_path / "output")
    assert layout.product_file(out, "L1", "1127") == os.path.join(
        out, "L1", "L1_timeseries", "incois_glider_1127_L1.nc")
    assert layout.product_file(out, "L0", "1127") == os.path.join(
        out, "L0", "L0_timeseries", "incois_glider_1127_L0.nc")


def test_find_timeseries_still_returns_legacy_ego_copies(tmp_path):
    out = tmp_path / "output"
    ts = out / "L1" / "L1_timeseries"
    ts.mkdir(parents=True)
    (ts / "g_L1.nc").write_bytes(b"x")          # current product
    (ts / "g_L1_EGO.nc").write_bytes(b"x")      # from an older run

    every = {os.path.basename(p)
             for p in layout.find_timeseries(str(out), "L1")}
    assert every == {"g_L1.nc", "g_L1_EGO.nc"}


def test_legacy_dirs_present_reports_only_what_exists(tmp_path):
    out = tmp_path / "output"
    (out / "EGO-timeseries").mkdir(parents=True)
    (out / "L0-gridfiles").mkdir(parents=True)
    (out / "L1" / "L1_timeseries").mkdir(parents=True)

    found = {os.path.basename(p)
             for p in layout.legacy_dirs_present(str(out))}
    assert found == {"EGO-timeseries", "L0-gridfiles"}
    assert "L1_timeseries" not in found


def test_find_products_deduplicates_same_real_path(tmp_path):
    # A migrated deployment can have the same directory reachable twice.
    out = tmp_path / "output"
    ts = out / "L0" / "L0_timeseries"
    ts.mkdir(parents=True)
    (ts / "a.nc").write_bytes(b"x")
    hits = layout.find_products(str(out), "L0", "timeseries")
    assert len(hits) == 1
