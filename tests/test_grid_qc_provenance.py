"""
Regression tests for QC provenance surviving into the gridded product
(pipeline/step4.py -> pipeline/step5.py).

make_grid drops every <var>_QC array, because a grid cell averages many source
observations and a per-cell flag would be meaningless. But step5's annotation
read only those arrays, so on the grid path — the default path — the L1
gridplot's "QC: n% good" box never rendered, while the figure title claimed to
show what QC had removed.

The fix records the retention figures as variable attributes at grid time.
"""
import os
import sys

import matplotlib
matplotlib.use("Agg")
import numpy as np
import xarray as xr

sys.path.insert(0, os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "pipeline"))

import step4  # noqa: E402
import step5  # noqa: E402


def _l1_like(tmp_path, n=400):
    """A minimal L1 timeseries: two profiles, temperature with mixed flags."""
    time = np.datetime64("2024-01-01T00:00:00") + \
        np.arange(n) * np.timedelta64(15, "s")
    depth = np.concatenate([np.linspace(1, 100, n // 2),
                            np.linspace(100, 1, n - n // 2)])
    qc = np.ones(n, dtype=np.int8)
    qc[:40] = 4      # 10% bad
    qc[40:60] = 9    # 5% missing

    ds = xr.Dataset(
        {
            "temperature": ("time", np.linspace(28, 12, n)),
            "depth": ("time", depth),
            "profile_index": ("time", np.repeat([0.0, 1.0], n // 2)),
            "temperature_QC": ("time", qc),
        },
        coords={"time": time},
    )
    path = tmp_path / "l1.nc"
    ds.to_netcdf(path)
    ds.close()
    return str(path)


def test_grid_records_qc_retention(tmp_path):
    grid_path = step4.make_grid(_l1_like(tmp_path), str(tmp_path),
                                "grid.nc", apply_qc=True)
    assert grid_path is not None

    with xr.open_dataset(grid_path) as g:
        attrs = g["temperature"].attrs
        assert attrs["qc_source_variable"] == "temperature_QC"
        assert float(attrs["qc_pct_good"]) == 85.0
        assert float(attrs["qc_pct_removed"]) == 10.0
        assert float(attrs["qc_pct_missing"]) == 5.0


def test_annotation_reads_retention_from_grid_attrs(tmp_path):
    """_qc_retention must work on a grid, which carries no <var>_QC array."""
    grid_path = step4.make_grid(_l1_like(tmp_path), str(tmp_path),
                                "grid.nc", apply_qc=True)
    with xr.open_dataset(grid_path) as g:
        assert not any(v.endswith("_QC") for v in g.data_vars), \
            "grid unexpectedly carries per-cell flags"
        retention = step5._qc_retention(g, "temperature")

    assert retention is not None, "annotation still blind on the grid path"
    pct_good, pct_removed = retention
    assert pct_good == 85.0
    assert pct_removed == 15.0      # bad + missing


def test_annotation_still_reads_flag_arrays_directly(tmp_path):
    """The timeseries path must keep working off the flag array itself."""
    with xr.open_dataset(_l1_like(tmp_path)) as ds:
        retention = step5._qc_retention(ds, "temperature")
    assert retention == (85.0, 15.0)


def test_no_qc_retention_without_flags(tmp_path):
    grid_path = step4.make_grid(_l1_like(tmp_path), str(tmp_path),
                                "grid_noqc.nc", apply_qc=False)
    with xr.open_dataset(grid_path) as g:
        assert "qc_pct_good" not in g["temperature"].attrs
        assert step5._qc_retention(g, "temperature") is None
