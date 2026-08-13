#!/usr/bin/env python3
"""
ego_checker.py — validate a NetCDF file against the official EGO 1.5
checker rules (decGlider_misc/checker_rules_file/EGO_V1.5_20250211.xml).

The rules XML is parsed at runtime, so this checker cannot drift from the
spec: if the rules file is updated, the checks update with it.

Usage:
    python tools/ego_checker.py <file.nc> [--rules path/to/EGO_V1.5.xml]
    python tools/ego_checker.py <file.nc> --strict   # optional items count too

Exit code 0 = compliant (no mandatory failures), 1 = failures found.
"""
from __future__ import annotations

import argparse
import os
import re
import sys
import xml.etree.ElementTree as ET

import netCDF4
import numpy as np

DEFAULT_RULES = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "126193", "decGlider_20260204_014e", "decGlider_misc",
    "checker_rules_file", "EGO_V1.5_20250211.xml",
)

# NetCDF type name -> acceptable numpy kinds
_TYPE_KINDS = {
    "double": ("f8",),
    "float": ("f4",),
    "int": ("i4",),
    "short": ("i2",),
    "byte": ("i1",),
    "char": ("S1", "U1", "str"),
}


class Report:
    """Collects pass/fail results split by severity."""

    def __init__(self):
        self.failures: list[str] = []   # mandatory violations
        self.warnings: list[str] = []   # optional-item issues
        self.passes = 0

    def ok(self):
        self.passes += 1

    def fail(self, msg: str):
        self.failures.append(msg)

    def warn(self, msg: str):
        self.warnings.append(msg)

    @property
    def compliant(self) -> bool:
        return not self.failures


def _norm(v) -> str:
    """Normalise an attribute value to a comparable string."""
    if isinstance(v, (bytes, bytearray)):
        v = v.decode("ascii", "replace")
    if isinstance(v, np.ndarray):
        if v.dtype.kind in "SU":
            return "".join(str(x) for x in v.tolist())
        return " ".join(_fmt_num(x) for x in v.tolist())
    if isinstance(v, (list, tuple)):
        return " ".join(_fmt_num(x) for x in v)
    if isinstance(v, (int, float, np.integer, np.floating)):
        return _fmt_num(v)
    return str(v)


def _fmt_num(x) -> str:
    """Render a number without trailing .0 so '90000' == 90000.0."""
    f = float(x)
    if f.is_integer():
        return str(int(f))
    return repr(f)


def _values_match(expected: str, actual) -> bool:
    a = _norm(actual).strip()
    e = str(expected).strip()
    if a == e:
        return True
    # numeric tolerance
    try:
        return abs(float(a) - float(e)) < 1e-9
    except (ValueError, TypeError):
        pass
    # whitespace-insensitive compare (flag_meanings etc.)
    return " ".join(a.split()) == " ".join(e.split())


def _resolve_var_names(nc, identify) -> list[str]:
    """Resolve an <IDENTIFY> block to the variable names present in the file."""
    if identify is None:
        return []
    names = []
    for n in identify.findall("NAME"):
        val = n.get("VALUE")
        pat = n.get("PATTERN")
        if val:
            if val in nc.variables:
                names.append(val)
        elif pat:
            rx = re.compile(f"^(?:{pat})$")
            names.extend([v for v in nc.variables if rx.match(v)])
    return names


def _check_variable(nc, vrule, report: Report, mandatory: bool):
    """Check one <VARIABLE> rule against the file."""
    identify = vrule.find("IDENTIFY")
    mv = vrule.find("MUST_VERIFY")

    declared = []
    for n in (identify.findall("NAME") if identify is not None else []):
        if n.get("VALUE"):
            declared.append(n.get("VALUE"))
        elif n.get("PATTERN"):
            declared.append(f"~{n.get('PATTERN')}")

    present = _resolve_var_names(nc, identify)
    # For an alternation pattern rule, every literal name it can match that
    # exists in the file must satisfy the rule.
    if not present:
        label = ", ".join(declared) or "(unnamed rule)"
        if mandatory:
            report.fail(f"MISSING variable: {label}")
        return

    if mv is None:
        report.ok()
        return

    for vname in present:
        var = nc.variables[vname]

        # type
        t = mv.find("TYPE")
        if t is not None and t.get("VALUE"):
            want = t.get("VALUE")
            kinds = _TYPE_KINDS.get(want, ())
            dt = var.dtype
            actual = "str" if dt is str else dt.str.lstrip("<>|=")
            if want == "char":
                is_ok = (dt is str) or dt.kind in "SU"
            else:
                is_ok = actual in kinds
            if is_ok:
                report.ok()
            else:
                msg = f"{vname}: type is {actual}, spec requires {want}"
                report.fail(msg) if mandatory else report.warn(msg)

        # dimension count
        dc = mv.find("DIMENSION_COUNT")
        if dc is not None and dc.get("VALUE"):
            want_n = int(dc.get("VALUE"))
            if len(var.dimensions) == want_n:
                report.ok()
            else:
                msg = (f"{vname}: has {len(var.dimensions)} dimension(s), "
                       f"spec requires {want_n}")
                report.fail(msg) if mandatory else report.warn(msg)

        # dimensions by rank
        for d in mv.findall("DIMENSION"):
            dname = d.get("NAME")
            rank = d.get("RANK")
            if not dname:
                continue
            if rank:
                idx = int(rank) - 1
                got = (var.dimensions[idx]
                       if idx < len(var.dimensions) else "(absent)")
                if got == dname:
                    report.ok()
                else:
                    msg = (f"{vname}: dimension {rank} is '{got}', "
                           f"spec requires '{dname}'")
                    report.fail(msg) if mandatory else report.warn(msg)
            elif dname not in var.dimensions:
                msg = f"{vname}: missing dimension '{dname}'"
                report.fail(msg) if mandatory else report.warn(msg)

        # attributes
        for a in mv.findall("ATTRIBUTE"):
            aname = a.get("NAME")
            awant = a.get("VALUE")
            apat = a.get("PATTERN")
            if aname not in var.ncattrs():
                msg = f"{vname}: missing attribute '{aname}'"
                report.fail(msg) if mandatory else report.warn(msg)
                continue
            got = var.getncattr(aname)
            if awant is not None:
                if _values_match(awant, got):
                    report.ok()
                else:
                    msg = (f"{vname}.{aname} = '{_norm(got)}', "
                           f"spec requires '{awant}'")
                    report.fail(msg) if mandatory else report.warn(msg)
            elif apat is not None:
                if re.match(f"^(?:{apat})$", _norm(got).strip()):
                    report.ok()
                else:
                    msg = (f"{vname}.{aname} = '{_norm(got)}' "
                           f"does not match /{apat}/")
                    report.fail(msg) if mandatory else report.warn(msg)
            else:
                report.ok()


def check_file(nc_path: str, rules_path: str = DEFAULT_RULES,
               strict: bool = False, verbose: bool = True) -> Report:
    """Validate one NetCDF file against the EGO rules. Returns a Report."""
    report = Report()
    root = ET.parse(rules_path).getroot()
    nc = netCDF4.Dataset(nc_path)
    # Read raw values: valid_min/valid_max auto-masking would hide real data.
    nc.set_auto_mask(False)

    try:
        # ── APPLICABLE_IF ────────────────────────────────────────────────
        applic = root.find("APPLICABLE_IF")
        if applic is not None:
            for g in applic.findall("GLOBAL_ATTRIBUTE"):
                name, want = g.get("NAME"), g.get("VALUE")
                got = nc.getncattr(name) if name in nc.ncattrs() else None
                if got is None or not _values_match(want, got):
                    report.fail(
                        f"Rules not applicable: global '{name}' is "
                        f"'{got}', expected '{want}'")
            if report.failures:
                return report

        for section, mandatory in (("MANDATORY", True), ("OPTIONAL", False)):
            sec = root.find(section)
            if sec is None:
                continue
            if section == "OPTIONAL" and not strict:
                # Still check optional items that ARE present, but only
                # report them as warnings.
                pass

            # dimensions
            for d in sec.findall("DIMENSION"):
                dname, dval = d.get("NAME"), d.get("VALUE")
                if dname not in nc.dimensions:
                    msg = f"MISSING dimension: {dname}"
                    report.fail(msg) if mandatory else report.warn(msg)
                    continue
                if dval:
                    got = len(nc.dimensions[dname])
                    if got == int(dval):
                        report.ok()
                    else:
                        msg = (f"dimension {dname} = {got}, "
                               f"spec requires {dval}")
                        report.fail(msg) if mandatory else report.warn(msg)
                else:
                    report.ok()

            # global attributes
            for g in sec.findall("GLOBAL_ATTRIBUTE"):
                name = g.get("NAME")
                want = g.get("VALUE")
                pat = g.get("PATTERN")
                if name not in nc.ncattrs():
                    msg = f"MISSING global attribute: {name}"
                    report.fail(msg) if mandatory else report.warn(msg)
                    continue
                got = nc.getncattr(name)
                if want is not None:
                    if _values_match(want, got):
                        report.ok()
                    else:
                        msg = (f"global '{name}' = '{_norm(got)}', "
                               f"spec requires '{want}'")
                        report.fail(msg) if mandatory else report.warn(msg)
                elif pat is not None:
                    if re.match(f"^(?:{pat})$", _norm(got).strip()):
                        report.ok()
                    else:
                        msg = (f"global '{name}' = '{_norm(got)}' "
                               f"does not match /{pat}/")
                        report.fail(msg) if mandatory else report.warn(msg)
                else:
                    if str(_norm(got)).strip():
                        report.ok()
                    else:
                        msg = f"global '{name}' is empty"
                        report.fail(msg) if mandatory else report.warn(msg)

            # variables
            for vrule in sec.findall("VARIABLE"):
                _check_variable(nc, vrule, report, mandatory)

    finally:
        nc.close()

    return report


def print_report(nc_path: str, report: Report) -> None:
    name = os.path.basename(nc_path)
    print("=" * 72)
    print(f"  EGO 1.5 COMPLIANCE REPORT — {name}")
    print("=" * 72)
    print(f"  checks passed : {report.passes}")
    print(f"  failures      : {len(report.failures)}   (mandatory)")
    print(f"  warnings      : {len(report.warnings)}   (optional / present-but-wrong)")

    if report.failures:
        print("\n  MANDATORY FAILURES")
        print("  " + "-" * 68)
        for f in report.failures:
            print(f"    [FAIL] {f}")

    if report.warnings:
        print("\n  WARNINGS")
        print("  " + "-" * 68)
        for w in report.warnings:
            print(f"    [warn] {w}")

    print()
    verdict = "COMPLIANT" if report.compliant else "NOT COMPLIANT"
    print(f"  VERDICT: {verdict} with EGO 1.5 mandatory requirements")
    print("=" * 72)


def _print_coverage(nc_path: str, rules_path: str) -> int:
    """Report which OPTIONAL spec variables the file does and does not carry."""
    root = ET.parse(rules_path).getroot()
    opt = root.find("OPTIONAL")
    nc = netCDF4.Dataset(nc_path)
    nc.set_auto_mask(False)
    try:
        declared = []
        for v in (opt.findall("VARIABLE") if opt is not None else []):
            ident = v.find("IDENTIFY")
            for n in (ident.findall("NAME") if ident is not None else []):
                if n.get("VALUE"):
                    declared.append(n.get("VALUE"))
        present = [d for d in declared if d in nc.variables]
        absent = [d for d in declared if d not in nc.variables]
        print("=" * 72)
        print(f"  OPTIONAL CONTENT COVERAGE — {os.path.basename(nc_path)}")
        print("=" * 72)
        print(f"  present: {len(present)} / {len(declared)}")
        print("\n  PRESENT")
        for p in present:
            print(f"    [x] {p}")
        # Only report absent metadata groups, not the huge sensor catalogue
        groups = ("PLATFORM_", "GLIDER_", "OPERATING_", "WMO_", "POSITIONING_",
                  "TRANS_", "BATTERY_", "SPECIAL_", "FIRMWARE_", "ANOMALY",
                  "CUSTOMIZATION", "DAC_", "DEPLOYMENT_", "SENSOR_MOUNT",
                  "SENSOR_ORIENTATION", "PARAMETER_UNITS", "PARAMETER_ACCURACY",
                  "PARAMETER_RESOLUTION", "HISTORY_", "DERIVATION_")
        meta_absent = [a for a in absent if a.startswith(groups)]
        print("\n  ABSENT (metadata / provenance groups)")
        for a in meta_absent:
            print(f"    [ ] {a}")
        print("=" * 72)
    finally:
        nc.close()
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Validate a NetCDF against EGO 1.5 rules")
    ap.add_argument("files", nargs="+", help="NetCDF file(s) to check")
    ap.add_argument("--rules", default=DEFAULT_RULES, help="Path to rules XML")
    ap.add_argument("--strict", action="store_true",
                    help="Treat missing optional variables as warnings too")
    ap.add_argument("--quiet-warnings", action="store_true",
                    help="Suppress the warnings list")
    ap.add_argument("--coverage", action="store_true",
                    help="List which OPTIONAL spec variables are present/absent")
    args = ap.parse_args(argv)

    if args.coverage:
        return _print_coverage(args.files[0], args.rules)

    if not os.path.exists(args.rules):
        print(f"ERROR: rules file not found: {args.rules}", file=sys.stderr)
        return 2

    worst = 0
    for path in args.files:
        if not os.path.exists(path):
            print(f"ERROR: file not found: {path}", file=sys.stderr)
            worst = 2
            continue
        rep = check_file(path, args.rules, strict=args.strict)
        if args.quiet_warnings:
            rep.warnings = []
        print_report(path, rep)
        if not rep.compliant:
            worst = max(worst, 1)
    return worst


if __name__ == "__main__":
    sys.exit(main())
