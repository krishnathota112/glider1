#!/usr/bin/env python3
"""
inspect_nc.py - Dump the structure of a glider NetCDF file.

Reports dimensions, coordinates, variables (with attrs), and global attrs so we
can check EGO format compliance before designing anything downstream.

Usage:
    python inspect_nc.py <path.nc>
    python inspect_nc.py <path.nc> --ego-check
"""
import sys
import argparse
import xarray as xr


# EGO v1.4/1.5 required global attributes (netcdf format manual)
EGO_GLOBAL_REQUIRED = [
    "data_type", "format_version", "platform_code", "date_update",
    "institution", "wmo_platform_code", "id", "source",
    "Conventions", "title", "naming_authority",
]

# EGO core coordinate / positioning variables
EGO_COORD_VARS = [
    "TIME", "LATITUDE", "LONGITUDE", "PRES", "DEPTH",
    "TIME_GPS", "LATITUDE_GPS", "LONGITUDE_GPS",
    "POSITION_QC", "TIME_QC", "PRES_QC",
]

# EGO parameter names (core physics + BGC)
EGO_CORE_PARAMS = ["PRES", "TEMP", "CNDC", "PSAL"]
EGO_BGC_PARAMS = [
    "DOXY", "CHLA", "CDOM", "BBP700", "BBP470", "BBP532",
    "TURBIDITY", "PH_IN_SITU_TOTAL", "NITRATE",
    "DOWNWELLING_PAR", "DOWN_IRRADIANCE380",
    "DOWN_IRRADIANCE412", "DOWN_IRRADIANCE490",
]

# EGO trajectory / technical variables
EGO_TECH_VARS = [
    "PHASE", "PHASE_NUMBER", "POSITIONING_METHOD",
    "GLIDER_HEADING", "GLIDER_PITCH", "GLIDER_ROLL",
    "GLIDER_VERTICAL_SPEED", "CLOCK_OFFSET",
]


def dump(path):
    ds = xr.open_dataset(path, engine="netcdf4", decode_times=True)

    print("=" * 72)
    print(f"FILE: {path}")
    print("=" * 72)

    print("\n--- DIMENSIONS ---")
    for d, n in ds.dims.items():
        print(f"  {d}: {n}")

    print("\n--- COORDINATES ---")
    for c in ds.coords:
        da = ds[c]
        print(f"  {c}: dims={da.dims} dtype={da.dtype}")

    print(f"\n--- DATA VARIABLES ({len(ds.data_vars)}) ---")
    for v in ds.data_vars:
        da = ds[v]
        units = da.attrs.get("units", "")
        sname = da.attrs.get("standard_name", "")
        lname = da.attrs.get("long_name", "")
        print(f"  {v:<32} dims={str(da.dims):<20} dtype={str(da.dtype):<10}")
        if units or sname or lname:
            print(f"       units={units!r} standard_name={sname!r}")
            print(f"       long_name={lname!r}")

    print(f"\n--- GLOBAL ATTRIBUTES ({len(ds.attrs)}) ---")
    for k, val in ds.attrs.items():
        sval = str(val)
        if len(sval) > 100:
            sval = sval[:100] + " ..."
        print(f"  {k}: {sval}")

    ds.close()
    return path


def ego_check(path):
    ds = xr.open_dataset(path, engine="netcdf4", decode_times=True)

    print("=" * 72)
    print(f"EGO FORMAT COMPLIANCE CHECK: {path}")
    print("=" * 72)

    fmt = ds.attrs.get("format_version", "<absent>")
    dtype_attr = ds.attrs.get("data_type", "<absent>")
    print(f"\n  format_version : {fmt}")
    print(f"  data_type      : {dtype_attr}")
    print("  (EGO expects data_type='EGO glider time-series data')")

    print("\n--- REQUIRED GLOBAL ATTRIBUTES ---")
    missing_global = []
    for a in EGO_GLOBAL_REQUIRED:
        if a in ds.attrs:
            print(f"  [ok]      {a}")
        else:
            print(f"  [MISSING] {a}")
            missing_global.append(a)

    print("\n--- COORDINATE / POSITIONING VARIABLES ---")
    for v in EGO_COORD_VARS:
        present = v in ds or v in ds.coords
        print(f"  {'[ok]     ' if present else '[MISSING]'} {v}")

    print("\n--- CORE PARAMETERS (physics) ---")
    core_found = []
    for v in EGO_CORE_PARAMS:
        if v in ds:
            core_found.append(v)
            qc = f"{v}_QC"
            qc_mark = "with _QC" if qc in ds else "NO _QC"
            print(f"  [ok]      {v:<10} ({qc_mark})")
        else:
            print(f"  [absent]  {v}")

    print("\n--- BGC PARAMETERS ---")
    bgc_found = []
    for v in EGO_BGC_PARAMS:
        if v in ds:
            bgc_found.append(v)
            qc = f"{v}_QC"
            qc_mark = "with _QC" if qc in ds else "NO _QC"
            print(f"  [ok]      {v:<20} ({qc_mark})")
    if not bgc_found:
        print("  (none of the EGO BGC parameter names present)")

    print("\n--- TECHNICAL / TRAJECTORY VARIABLES ---")
    for v in EGO_TECH_VARS:
        if v in ds:
            print(f"  [ok]      {v}")

    # Anything that is NOT an EGO name -> non-standard
    known = set(EGO_COORD_VARS + EGO_CORE_PARAMS + EGO_BGC_PARAMS
                + EGO_TECH_VARS)
    known |= {f"{n}_QC" for n in known}
    nonstd = [v for v in ds.data_vars if v not in known]

    print(f"\n--- NON-EGO VARIABLE NAMES ({len(nonstd)}) ---")
    print("  (these are lowercase/internal names, not EGO canonical)")
    for v in nonstd:
        print(f"    {v}")

    print("\n--- SUMMARY ---")
    print(f"  Core params found : {core_found}")
    print(f"  BGC params found  : {bgc_found}")
    print(f"  Missing globals   : {len(missing_global)}")
    print(f"  Non-EGO var names : {len(nonstd)}")

    ds.close()


def main():
    p = argparse.ArgumentParser()
    p.add_argument("path")
    p.add_argument("--ego-check", action="store_true")
    args = p.parse_args()

    if args.ego_check:
        ego_check(args.path)
    else:
        dump(args.path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
