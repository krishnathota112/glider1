"""
Regression tests for output-path plumbing.

`from config import OUTPUT_DIR` binds the value at import time. run_pipeline
used to reassign `config.OUTPUT_DIR` *after* importing a step module and expect
the step to notice, which it cannot. The L0 therefore landed in output/ while
the orchestrator had just created output/L0-timeseries/ for it and went on
reporting that as the location. (L1 escaped the same fate only because
run_pipeline shutil.move'd the file afterwards.)

The fix is for each step to take its destination as an argument, the way
make_grid and split_profiles already did. These tests assert that contract
rather than the symptom, since the symptom needs raw binaries to reproduce.
"""
import ast
import inspect
import os
import sys

import pytest

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO, "pipeline"))

import step1     # noqa: E402
import step23    # noqa: E402
import step4     # noqa: E402


@pytest.mark.parametrize("func", [
    step1.run_step1,
    step23.run_step23,
    step4.make_grid,
    step4.split_profiles,
])
def test_steps_accept_an_explicit_destination(func):
    params = inspect.signature(func).parameters
    assert {"out_dir"} & set(params), \
        f"{func.__name__} has no out_dir parameter — its caller cannot " \
        f"choose where output lands"


@pytest.mark.parametrize("func", [step1.run_step1, step23.run_step23])
def test_destination_defaults_to_none_not_a_bound_global(func):
    """
    Defaulting to None and resolving inside the body is what lets
    config.OUTPUT_DIR be read at call time. A default captured in the signature
    would freeze the import-time value all over again.
    """
    assert inspect.signature(func).parameters["out_dir"].default is None


def _calls_in(source, func_name):
    """Every ast.Call node for `func_name` in a source file."""
    tree = ast.parse(source)
    return [node for node in ast.walk(tree)
            if isinstance(node, ast.Call)
            and isinstance(node.func, ast.Name)
            and node.func.id == func_name]


@pytest.mark.parametrize("callee", ["run_step1", "run_step23"])
def test_orchestrator_passes_the_destination(callee):
    with open(os.path.join(REPO, "pipeline", "run_pipeline.py"),
              encoding="utf-8") as fh:
        source = fh.read()

    calls = _calls_in(source, callee)
    assert calls, f"run_pipeline.py never calls {callee}"
    for call in calls:
        assert any(kw.arg == "out_dir" for kw in call.keywords), \
            f"run_pipeline.py calls {callee} without out_dir — the step will " \
            f"fall back to the import-time config.OUTPUT_DIR"


def test_orchestrator_does_not_retarget_config_mid_run():
    """
    Reassigning config.OUTPUT_DIR *mid-run* is the pattern that caused this bug:
    a step module that already did `from config import OUTPUT_DIR` holds the
    old value and never sees the change.

    Setting it at module scope is fine and expected — that happens before any
    step is imported, which is what makes --data-dir and --output-dir work. So
    this only rejects assignments inside a function body, where the step
    imports have already happened.
    """
    with open(os.path.join(REPO, "pipeline", "run_pipeline.py"),
              encoding="utf-8") as fh:
        tree = ast.parse(fh.read())

    offenders = []
    for func in ast.walk(tree):
        if not isinstance(func, (ast.FunctionDef, ast.AsyncFunctionDef)):
            continue
        for node in ast.walk(func):
            if not isinstance(node, ast.Assign):
                continue
            for target in node.targets:
                if (isinstance(target, ast.Attribute)
                        and target.attr == "OUTPUT_DIR"
                        and isinstance(target.value, ast.Name)):
                    offenders.append(f"{func.name}():{node.lineno}")

    assert not offenders, (
        f"run_pipeline.py retargets config.OUTPUT_DIR after import at "
        f"{offenders}. Steps bound the old value; pass out_dir instead."
    )
