"""
Regression tests for ARGO QC flag assignment (pipeline/step23.py).

The invariant these lock down: a QC test may only make a verdict *worse*.
Before _raise_flag existed, the tests assigned flags unconditionally in
sequence, so a later mild test silently erased an earlier severe one — the
observable symptom on real data was every variable carrying an identical
count of flag 3, because test 5 (impossible speed) stamped 'probably bad'
over every flag 4 and flag 9 in the dataset.
"""
import os
import sys

import numpy as np
import pytest
import xarray as xr

sys.path.insert(0, os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "pipeline"))

import step23  # noqa: E402


# ---------------------------------------------------------------- _raise_flag

def test_raise_flag_upgrades_severity():
    qc = np.array([1, 1, 1], dtype=np.int8)
    assert step23._raise_flag(qc, np.array([True, True, False]), 4) == 2
    assert qc.tolist() == [4, 4, 1]


def test_raise_flag_never_downgrades():
    """A flag 3 verdict must not erase an existing flag 4."""
    qc = np.array([4, 3, 1], dtype=np.int8)
    changed = step23._raise_flag(qc, np.ones(3, dtype=bool), 3)
    assert qc.tolist() == [4, 3, 3]
    assert changed == 1          # only the flag-1 position moved


def test_raise_flag_leaves_missing_alone():
    """Flag 9 means 'no value here' — no test verdict can apply to it."""
    qc = np.array([9, 9, 1], dtype=np.int8)
    for flag in (3, 4):
        step23._raise_flag(qc, np.ones(3, dtype=bool), flag)
    assert qc.tolist() == [9, 9, 4]


def test_raise_flag_rejects_flag_9():
    qc = np.array([1], dtype=np.int8)
    with pytest.raises(ValueError, match="got 9"):
        step23._raise_flag(qc, np.ones(1, dtype=bool), 9)


def test_raise_flag_is_idempotent():
    qc = np.array([1, 4], dtype=np.int8)
    mask = np.ones(2, dtype=bool)
    step23._raise_flag(qc, mask, 4)
    assert step23._raise_flag(qc, mask, 4) == 0
    assert qc.tolist() == [4, 4]


# ------------------------------------------------------- test interaction

def _toy_dataset(n=200):
    """A small synthetic profile with a few deliberately bad samples."""
    time = np.datetime64("2024-01-01T00:00:00") + \
        np.arange(n) * np.timedelta64(10, "s")
    pressure = np.linspace(0, 500, n)
    return xr.Dataset(
        {
            "temperature": ("time", np.full(n, 20.0)),
            "salinity": ("time", np.full(n, 35.0)),
            "pressure": ("time", pressure),
            "latitude": ("time", np.full(n, 12.0)),
            "longitude": ("time", np.full(n, 70.0)),
            "profile_index": ("time", np.zeros(n)),
        },
        coords={"time": time},
    )


def test_deepest_pressure_does_not_erase_global_range():
    """
    The concrete regression: test 6 flags an impossible pressure Bad (4), then
    test 19 runs and judges the same point 'probably bad' (3). If that
    overwrites, pressure_cascade no longer sees a bad pressure and the T/S
    measured there stay flag 1.
    """
    ds = _toy_dataset()
    ds["pressure"].values[50] = 2500.0        # beyond the 2000 dbar global max

    qc_dict = {v: np.ones(len(ds.time), dtype=np.int8)
               for v in ("temperature", "salinity", "pressure")}

    step23.test_global_range(ds, qc_dict)
    assert qc_dict["pressure"][50] == 4

    step23.test_deepest_pressure(ds, qc_dict, config_pressure_dbar=1000.0)
    assert qc_dict["pressure"][50] == 4, \
        "test 19 downgraded a flag 4 to flag 3"

    n_cascaded = step23.pressure_cascade(ds, qc_dict)
    assert n_cascaded > 0
    assert qc_dict["temperature"][50] == 4
    assert qc_dict["salinity"][50] == 4


def test_impossible_speed_preserves_bad_and_missing():
    """
    Test 5 judges every variable at a suspect GPS leg. It must not overwrite a
    Bad verdict another test already reached, nor claim a verdict about a
    value that is missing.
    """
    ds = _toy_dataset()
    # A GPS jump far beyond 3 m/s between consecutive 10 s samples.
    ds["latitude"].values[100] = 40.0

    n = len(ds.time)
    qc_dict = {
        "temperature": np.ones(n, dtype=np.int8),
        "salinity": np.ones(n, dtype=np.int8),
        "latitude": np.ones(n, dtype=np.int8),
        "longitude": np.ones(n, dtype=np.int8),
    }
    qc_dict["temperature"][100] = 4      # already known bad
    qc_dict["salinity"][100] = 9         # already known missing

    flagged = step23.test_impossible_speed(ds, qc_dict)

    assert flagged > 0
    assert qc_dict["temperature"][100] == 4, "Bad was downgraded to 3"
    assert qc_dict["salinity"][100] == 9, "Missing was overwritten with 3"
    assert qc_dict["latitude"][100] == 3, "the suspect fix should be flagged"


def test_impossible_speed_counts_distinct_positions():
    """
    The return value is a count of flagged samples. Assigning per pair meant
    consecutive bad legs counted their shared endpoint twice, so the reported
    number could exceed the number of observations.
    """
    ds = _toy_dataset(n=50)
    ds["latitude"].values[20] = 40.0
    ds["latitude"].values[21] = -40.0      # back-to-back offending legs

    n = len(ds.time)
    qc_dict = {"latitude": np.ones(n, dtype=np.int8)}
    flagged = step23.test_impossible_speed(ds, qc_dict)

    assert flagged == int(np.count_nonzero(qc_dict["latitude"] == 3))
    assert flagged <= n


def test_impossible_location_ignores_absent_positions():
    """
    A NaN position is missing, not wrong. Flagging it Bad (4) mislabels an
    absent GPS fix — gliders only surface periodically — as a sensor fault.
    """
    ds = _toy_dataset()
    ds["latitude"].values[10] = np.nan
    ds["latitude"].values[11] = 999.0      # genuinely impossible

    n = len(ds.time)
    qc_dict = {"latitude": np.ones(n, dtype=np.int8),
               "longitude": np.ones(n, dtype=np.int8)}
    qc_dict["latitude"][10] = 9            # as apply_argo_qc would set it

    step23.test_impossible_location(ds, qc_dict)

    assert qc_dict["latitude"][10] == 9, "absent position marked Bad"
    assert qc_dict["latitude"][11] == 4, "impossible position not flagged"


def test_pressure_cascade_does_not_touch_missing():
    ds = _toy_dataset()
    n = len(ds.time)
    qc_dict = {
        "pressure": np.ones(n, dtype=np.int8),
        "temperature": np.ones(n, dtype=np.int8),
    }
    qc_dict["pressure"][5] = 4
    qc_dict["temperature"][5] = 9

    step23.pressure_cascade(ds, qc_dict)
    assert qc_dict["temperature"][5] == 9
