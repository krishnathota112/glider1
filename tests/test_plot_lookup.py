"""
Regression tests for the plot lookup tables (pipeline/step5.py).

Panels are titled by *slot* label ("oxygen") while the lookup tables are keyed
by *variable* name ("oxygen_concentration"). A direct dict .get() on the slot
label therefore missed, silently: the oxygen panel fell through to the
(-inf, inf) physical range, so -9999 fill values reached the colour scale and
flattened it, and its colourbar read a bare "oxygen".
"""
import os
import sys

import matplotlib
matplotlib.use("Agg")
import numpy as np
import pytest

sys.path.insert(0, os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "pipeline"))

import step5  # noqa: E402


@pytest.mark.parametrize("slot_label", [s[0] for s in step5.PLOT_SLOTS])
def test_every_slot_resolves_a_physical_range(slot_label):
    """No panel may fall through to the unbounded default."""
    lo, hi = step5._slot_lookup(slot_label, step5._PLOT_PHYS_RANGE,
                                (-np.inf, np.inf))
    assert np.isfinite(lo) and np.isfinite(hi), \
        f"slot {slot_label!r} has no physical range — fill values unclamped"
    assert lo < hi


@pytest.mark.parametrize("slot_label", [s[0] for s in step5.PLOT_SLOTS])
def test_every_slot_resolves_a_colourbar_label(slot_label):
    label = step5._slot_lookup(slot_label, step5.VAR_LABELS, None)
    assert label is not None, f"slot {slot_label!r} has no colourbar label"
    assert label != slot_label, \
        f"slot {slot_label!r} fell back to its raw name"


def test_slot_lookup_accepts_variable_names_directly():
    lo, hi = step5._slot_lookup("oxygen_concentration",
                                step5._PLOT_PHYS_RANGE, None)
    assert (lo, hi) == step5._PLOT_PHYS_RANGE["oxygen_concentration"]


def test_slot_lookup_falls_back_for_unknown_names():
    sentinel = ("fallback",)
    assert step5._slot_lookup("not_a_variable",
                              step5._PLOT_PHYS_RANGE, sentinel) is sentinel


def test_oxygen_fill_values_are_clamped():
    """The concrete regression: a -9999 sentinel on the oxygen panel."""
    V = np.array([[250.0, 260.0], [270.0, -9999.0]])
    cleaned, n_bad = step5._apply_phys_range(V, "oxygen")
    assert n_bad == 1, "oxygen slot did not clamp its fill value"
    assert np.isnan(cleaned[1, 1])
    assert np.isfinite(cleaned[0, 0])
    # never mutates its input
    assert V[1, 1] == -9999.0
