#!/usr/bin/env python3
"""
step_ego.py — Convert internal L0/L1 NetCDF to EGO 1.5 compliant format.

Phase 2 of the EGO migration. Reads the pipeline's internal NetCDF files
(with lowercase variable names, no EGO structure) and writes new files that
pass the EGO_V1.5_20250211.xml checker.

Key transformations applied:
  - Variable renaming: temperature->TEMP, salinity->PSAL, etc.
  - Dimension renaming: time->TIME, plus new TIME_GPS dimension
  - Mandatory global attributes added (data_type, format_version, etc.)
  - GPS fix arrays built from raw flight data (TIME_GPS/LATITUDE_GPS/LONGITUDE_GPS)
  - PHASE / PHASE_NUMBER computed from profile_direction
  - SENSOR_* / PARAMETER_* metadata tables populated from deployment.yml
  - DOXY converted from umol/L to micromole/kg using in-situ density
  - _ADJUSTED / _ADJUSTED_QC / _ADJUSTED_ERROR variables written for non-i params
  - QC flag attributes corrected (EGO reference table 2.1 conventions)

IMPORTANT — oxygen unit conversion:
  Internal pipeline stores oxygen_concentration in umol/L (micromoles per litre).
  EGO/ARGO DOXY must be in micromole/kg.
  Conversion: DOXY_umol_kg = oxy_umol_L / (density_kg_m3 / 1000.0)
  density is already computed by step1.py via gsw.rho() in kg/m3.
  This is NOT a label swap — the numeric values change.

Usage (standalone):
    python pipeline/step_ego.py --l0 /path/L0.nc --l1 /path/L1.nc \\
                                 --out-l0 /path/EGO_L0.nc \\
                                 --out-l1 /path/EGO_L1.nc \\
                                 --deploy-yml /path/deployment.yml
"""
import os
import re
import sys
import argparse
import time as _time
import numpy as np
import xarray as xr
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

try:
    import gsw
    HAS_GSW = True
except ImportError:
    HAS_GSW = False

try:
    import yaml
    HAS_YAML = True
except ImportError:
    HAS_YAML = False

# ── EGO parameter name mapping ───────────────────────────────────────────────
# Internal pipeline name -> (EGO_name, units, fill_value, valid_min, valid_max,
#                            standard_name, long_name, sdn_param_urn, sdn_uom_urn,
#                            data_type, is_intermediate)
# Source: argo-parameters-list-core-and-b_20210708_AND_glider_specific_parameters_list_20220225.txt
# 'i' = intermediate (no _ADJUSTED triplet), 'c' = core, 'b' = bgc

_VAR_MAP = {
    "temperature": dict(
        ego="TEMP", units="degree_Celsius", fill=99999.0,
        vmin=-2.5, vmax=40.0,
        standard_name="sea_water_temperature",
        long_name="Sea temperature in-situ ITS-90 scale",
        sdn_param="SDN:P01::TEMPST01", sdn_uom="SDN:P06::UPAA",
        dtype="float", level="c",
        adjusted_src="temperature_processed",
    ),
    "salinity": dict(
        ego="PSAL", units="psu", fill=99999.0,
        vmin=2.0, vmax=41.0,
        standard_name="sea_water_salinity",
        long_name="Practical salinity",
        sdn_param="SDN:P01::PSALST01", sdn_uom="SDN:P06::UUUU",
        dtype="float", level="c",
        adjusted_src="salinity_processed",
    ),
    "pressure": dict(
        ego="PRES", units="decibar", fill=99999.0,
        vmin=0.0, vmax=12000.0,
        standard_name="sea_water_pressure",
        long_name="Sea water pressure, equals 0 at sea-level",
        sdn_param="SDN:P01::PRESPR01", sdn_uom="SDN:P06::UPDB",
        dtype="float", level="c",
        adjusted_src=None,
    ),
    "conductivity": dict(
        ego="CNDC", units="mhos/m", fill=99999.0,
        vmin=0.0, vmax=8.5,
        standard_name="sea_water_electrical_conductivity",
        long_name="Electrical conductivity",
        sdn_param="SDN:P01::CNDCST01", sdn_uom="SDN:P06::UECA",
        dtype="float", level="c",
        adjusted_src=None,
    ),
    # oxygen_concentration: converted from umol/L -> micromole/kg on write
    "oxygen_concentration": dict(
        ego="DOXY", units="micromole/kg", fill=99999.0,
        vmin=-5.0, vmax=600.0,
        standard_name="moles_of_oxygen_per_unit_mass_in_sea_water",
        long_name="Dissolved oxygen",
        sdn_param="SDN:P01::DOXMZZXX", sdn_uom="SDN:P06::KGUM",
        dtype="float", level="b",
        adjusted_src="oxygen_concentration_lag_corrected",
        needs_density_conversion=True,
    ),
    "chlorophyll": dict(
        ego="CHLA", units="mg/m3", fill=99999.0,
        vmin=None, vmax=None,
        standard_name="mass_concentration_of_chlorophyll_a_in_sea_water",
        long_name="Chlorophyll-A",
        sdn_param="SDN:P01::CPHLPR01", sdn_uom="SDN:P06::UMMC",
        dtype="float", level="b",
        adjusted_src="chlorophyll_corrected",
    ),
    "cdom": dict(
        ego="CDOM", units="ppb", fill=99999.0,
        vmin=None, vmax=None,
        # No CF standard name exists for CDOM. The EGO rules require the
        # standard_name ATTRIBUTE to be present but prescribe no value, so it is
        # written empty rather than filled with an invented CF name.
        standard_name="",
        long_name="Concentration of coloured dissolved organic matter in sea water",
        sdn_param="SDN:P01::CDOMZZ01", sdn_uom="SDN:P06::UPPB",
        dtype="float", level="b",
        adjusted_src="cdom_corrected",
    ),
    "backscatter_700": dict(
        ego="BBP700", units="m-1", fill=99999.0,
        vmin=None, vmax=None,
        # As for CDOM: attribute required, value not prescribed by the spec.
        standard_name="",
        long_name="Particle backscattering at 700 nanometers",
        sdn_param="SDN:P01::BB117NIR", sdn_uom="SDN:P06::PMSR",
        dtype="float", level="b",
        adjusted_src="backscatter_700_corrected",
    ),
    "turbidity": dict(
        ego="TURBIDITY", units="ntu", fill=99999.0,
        vmin=None, vmax=None,
        standard_name="sea_water_turbidity",
        long_name="Sea water turbidity",
        sdn_param="SDN:P01::TURBXXXX", sdn_uom="SDN:P06::USTU",
        dtype="float", level="b",
        adjusted_src=None,
    ),
}

# Variables kept internal only — not written to EGO NetCDF
_INTERNAL_ONLY = {
    "depth", "potential_temperature", "potential_density", "density",
    "oxygen_saturation", "profile_index", "profile_direction",
    "distance_over_ground", "heading", "pitch", "roll",
    "waypoint_latitude", "waypoint_longitude",
    "oxygen_optode_temperature",
    "flbbcd_internal_temperature", "flntu_internal_temperature",
    "backscatter_reference", "backscatter_signal",
    "cdom_reference", "cdom_signal",
    "chlorophyll_reference", "chlorophyll_signal",
    "chlorophyll_flntu", "chlorophyll_flntu_reference", "chlorophyll_flntu_signal",
    "turbidity_reference", "turbidity_signal",
    "par", "par_sensor_temperature", "par_sensor_voltage", "par_supply_voltage",
}

# ── QC flag attributes (EGO reference table 2.1) ─────────────────────────────
_QC_ATTRS = {
    "long_name":      "Quality flag",
    "conventions":    "EGO reference table 2.1",
    "_FillValue":     np.int8(-128),
    "valid_min":      np.int8(0),
    "valid_max":      np.int8(9),
    "flag_values":    np.array([0, 1, 2, 3, 4, 5, 8, 9], dtype=np.int8),
    "flag_meanings":  ("no_qc_performed good_data probably_good_data "
                       "bad_data_that_are_potentially_correctable bad_data "
                       "value_changed interpolated_value missing_value"),
}

# RTQC test codes applied by this pipeline (for history_qctest and meta table)
_RTQC_TESTS_APPLIED = "TEST002 TEST003 TEST005 TEST006 TEST008 TEST009 TEST013 TEST014 TEST016 TEST019"

# ── TIME valid_max: a known defect in the EGO 1.5 spec ───────────────────────
# The official checker (EGO_V1.5_20250211.xml) requires TIME.valid_max and
# TIME_GPS.valid_max to be exactly 90000. TIME is epoch SECONDS, so every real
# timestamp (~1.7e9) sits far above that ceiling. The spec value is almost
# certainly a leftover from a "seconds since midnight" draft, but the checker
# enforces it, so a file with the physically-sensible ceiling FAILS validation.
#
# Consequence, measured (not assumed): netCDF4-python applies valid_min/valid_max
# masking by DEFAULT, so with the spec value a naive reader sees TIME as entirely
# missing (data=[--,--,--]). xarray does NOT apply that masking and is unaffected.
# Every consumer in this repo therefore calls set_auto_mask(False) explicitly.
#
# Default is spec-compliant because passing the official checker is the whole
# point of this format. Set EGO_TIME_VALID_MAX_MODE = "physical" (or pass
# --time-valid-max physical) to emit 90000000000 instead: readable by naive
# netCDF4 code, but it will fail the checker on these two attributes.
_EGO_SPEC_TIME_VALID_MAX = 90000.0
_PHYSICAL_TIME_VALID_MAX = 90000000000.0
EGO_TIME_VALID_MAX_MODE = "spec"   # "spec" | "physical"


def _time_valid_max() -> float:
    return (_PHYSICAL_TIME_VALID_MAX
            if EGO_TIME_VALID_MAX_MODE == "physical"
            else _EGO_SPEC_TIME_VALID_MAX)


# ── EGO controlled vocabularies (validated against ref_lists/*.txt) ──────────
# Only values that actually appear in the reference tables are used here; a
# free-text value would be rejected by the checker's conventions constraints.
_REF = {
    # table 22 — PLATFORM_FAMILY
    "platform_family": ("COASTAL_GLIDER", "OPEN_OCEAN_GLIDER", "DEEP_GLIDER"),
    # table 23 — PLATFORM_TYPE
    "platform_type": ("SLOCUM_SG1", "SLOCUM_SG2", "SLOCUM_SG3", "SEAGLIDER",
                      "SEAEXPLORER", "SEAEXPLORER_SHALLOW", "SPRAY"),
    # table 24 — PLATFORM_MAKER
    "platform_maker": ("WRC", "KONGSBERG", "ALSEAMAR", "BLUEFIN_ROBOTICS",
                       "UNIVERSITY_OF_WASHINGTON"),
    # table 9.1 — POSITIONING_SYSTEM
    "positioning_system": ("ARGOS", "GPS", "IRIDIUM"),
    # table 10.1 — TRANS_SYSTEM
    "trans_system": ("IRIDIUM", "FREEWAVE"),
    # table 20 — SENSOR_MOUNT (single permitted value)
    "sensor_mount": ("MOUNTED_ON_GLIDER",),
    # table 21 — SENSOR_ORIENTATION
    "sensor_orientation": ("DOWNWARD", "UPWARD", "FORWARD", "BACKWARD"),
    # table 4 — institution codes
    "institution": ("IF", "BO", "NM", "DF", "OG", "SO", "IO", "TU", "IM"),
    # table 12 — HISTORY_STEP
    "history_step": ("ARFM", "ARGQ", "IGO3", "ARSQ", "ARCA", "ARUP", "ARDU",
                     "RFMT", "COOA"),
}

# table 8 — WMO_INST_TYPE: the reference list contains exactly one value for
# gliders, so it is a constant rather than a configurable field.
_WMO_INST_TYPE_GLIDER = "830"

# Defaults for this pipeline's platform. A Slocum G2 diving to ~1000 m is an
# open-ocean glider (DEEP_GLIDER is reserved for the 6000 m class).
_PLATFORM_DEFAULTS = {
    "platform_family": "OPEN_OCEAN_GLIDER",
    "platform_type":   "SLOCUM_SG2",
    "platform_maker":  "WRC",
}

# HISTORY_INSTITUTION uses EGO reference table 4, which has no INCOIS entry.
# 'IO' is the closest listed code; it is used so the field stays inside the
# controlled vocabulary rather than emitting free text the checker rejects.
# Override via deployment.yml metadata.institution_code once a code is assigned.
_DEFAULT_INSTITUTION_CODE = "IO"

# Per-parameter accuracy / resolution, from the manufacturer specifications for
# the instruments in _SENSOR_TABLE. Written to PARAMETER_ACCURACY /
# PARAMETER_RESOLUTION as free-text strings (the spec types them as char).
_PARAM_SPECS = {
    "TEMP":      {"units": "degree_Celsius", "accuracy": "0.002",  "resolution": "0.0001"},
    "PSAL":      {"units": "psu",            "accuracy": "0.005",  "resolution": "0.0001"},
    "PRES":      {"units": "decibar",        "accuracy": "0.1%FS", "resolution": "0.002%FS"},
    "CNDC":      {"units": "mhos/m",         "accuracy": "0.0003", "resolution": "0.00001"},
    "DOXY":      {"units": "micromole/kg",   "accuracy": "8 or 5%","resolution": "0.1"},
    "CHLA":      {"units": "mg/m3",          "accuracy": "",       "resolution": "0.007"},
    "CDOM":      {"units": "ppb",            "accuracy": "",       "resolution": "0.09"},
    "BBP700":    {"units": "m-1",            "accuracy": "",       "resolution": "0.000002"},
    "TURBIDITY": {"units": "ntu",            "accuracy": "",       "resolution": "0.01"},
}


def _now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")


def _date_time_str(dt64) -> str:
    """Format a datetime64/str as the EGO DATE_TIME convention YYYYMMDDHHMISS."""
    if dt64 is None:
        return " " * 14
    try:
        s = str(dt64)
        # '2024-01-29T14:03:28.000000000' -> '20240129140328'
        digits = re.sub(r"\D", "", s)
        return (digits[:14]).ljust(14)
    except Exception:
        return " " * 14


def _pad_str(s: str, length: int) -> np.ndarray:
    """Return a fixed-length char array padded with spaces."""
    s = s[:length].ljust(length)
    return np.array(list(s), dtype="S1")


def _str_array(strings: list, str_len: int) -> np.ndarray:
    """Build a (N, str_len) char array from a list of strings for NetCDF."""
    arr = np.full((len(strings), str_len), " ", dtype=f"U1")
    for i, s in enumerate(strings):
        s = str(s)[:str_len]
        for j, c in enumerate(s):
            arr[i, j] = c
    return arr


def _load_deployment_meta(deploy_yaml: str) -> dict:
    """Load deployment.yml; return empty dict if missing or unreadable."""
    if not deploy_yaml or not os.path.exists(deploy_yaml):
        return {}
    if not HAS_YAML:
        return {}
    try:
        with open(deploy_yaml) as f:
            return yaml.safe_load(f) or {}
    except Exception:
        return {}


def _get_gps_fixes(l0_ds: xr.Dataset):
    """
    Extract actual GPS surface fixes from L0 (positions where the glider
    was at the surface, not interpolated subsurface positions).

    Strategy: GPS fixes are identified as points where profile_direction
    changes (surface events between dives/climbs) or where the glider
    has near-zero depth. Returns (times, lats, lons) as numpy arrays.
    """
    if "latitude" not in l0_ds or "longitude" not in l0_ds:
        return np.array([]), np.array([]), np.array([])

    lat = l0_ds["latitude"].values
    lon = l0_ds["longitude"].values
    t   = l0_ds["time"].values.astype("datetime64[s]").astype(float)

    # Use profile boundaries as GPS fix proxies — the glider surfaces
    # between each profile to get a GPS fix
    if "profile_index" in l0_ds:
        pi = l0_ds["profile_index"].values
        unique_profiles = np.unique(pi[np.isfinite(pi)])
        fix_t, fix_lat, fix_lon = [], [], []
        for p in unique_profiles:
            mask = (pi == p) & np.isfinite(lat) & np.isfinite(lon)
            if np.sum(mask) > 0:
                # Use first point of each profile (surface position)
                idx = np.where(mask)[0][0]
                fix_t.append(t[idx])
                fix_lat.append(lat[idx])
                fix_lon.append(lon[idx])
        if fix_t:
            return (np.array(fix_t).astype("datetime64[s]"),
                    np.array(fix_lat),
                    np.array(fix_lon))

    # Fallback: use all finite positions (will be over-dense)
    valid = np.isfinite(lat) & np.isfinite(lon)
    return (t[valid].astype("datetime64[s]"),
            lat[valid], lon[valid])


def _build_ego_dataset(src_ds: xr.Dataset, deploy_meta: dict,
                       is_l1: bool, data_mode: str = "R") -> xr.Dataset:
    """
    Build an EGO 1.5 compliant xarray Dataset from an internal pipeline Dataset.

    Parameters
    ----------
    src_ds      : internal pipeline NetCDF (L0 or L1)
    deploy_meta : parsed deployment.yml dict
    is_l1       : True for L1 (has QC flags + adjusted vars), False for L0
    data_mode   : 'R' (real-time) or 'D' (delayed mode)
    """
    meta = deploy_meta.get("metadata", {})
    platform_code = str(meta.get("glider_serial", meta.get("deployment_name", "unknown")))
    institution   = str(meta.get("institution", "INCOIS"))
    deployment_name = str(meta.get("deployment_name", platform_code))

    t_raw = src_ds["time"].values  # datetime64
    n = len(t_raw)
    # Convert to seconds since 1970-01-01 (EGO TIME units)
    t_sec = t_raw.astype("datetime64[s]").astype(np.float64)

    coords = {"TIME": ("TIME", t_sec)}
    data_vars = {}

    # ── TIME variable attributes ─────────────────────────────────────────────
    time_da = xr.DataArray(
        t_sec, dims=["TIME"],
        attrs={
            "long_name": "Epoch time",
            "standard_name": "time",
            "units": "seconds since 1970-01-01T00:00:00Z",
            "_FillValue": np.float64(9999999999),
            "valid_min": np.float64(0),
            "valid_max": np.float64(_time_valid_max()),
            "axis": "T",
            "ancillary_variable": "TIME_QC",
            "sdn_parameter_urn": "SDN:P01::ELTMEP01",
            "sdn_uom_urn": "SDN:P06::UTBB",
            "glider_original_parameter_name": "time",
        }
    )
    data_vars["TIME"] = time_da

    # TIME_QC — flag 0 everywhere is CORRECT here, not an oversight.
    # This pipeline applies no RTQC test to the TIME axis itself: timestamps are
    # taken as decoded from the glider's science/flight clocks and never
    # independently validated. EGO reference table 2.1 defines 0 =
    # "no_qc_performed", which is the accurate statement. Do NOT "fix" this to
    # flag 1 (good_data) — that would assert a check this pipeline never ran.
    time_qc = np.zeros(n, dtype=np.int8)
    data_vars["TIME_QC"] = xr.DataArray(time_qc, dims=["TIME"], attrs=dict(_QC_ATTRS))

    # ── LATITUDE / LONGITUDE ─────────────────────────────────────────────────
    for internal, ego_name, ego_long, std_name, sdn_p, sdn_u, anc in [
        ("latitude",  "LATITUDE",  "Measurement latitude",  "latitude",
         "SDN:P01::ALATZZ01", "SDN:P06::DEGN", "POSITION_QC"),
        ("longitude", "LONGITUDE", "Measurement longitude", "longitude",
         "SDN:P01::ALONZZ01", "SDN:P06::DEGE", "POSITION_QC"),
    ]:
        if internal in src_ds:
            v = src_ds[internal].values.astype(np.float64)
            v[~np.isfinite(v)] = 99999.0
        else:
            v = np.full(n, 99999.0)
        units = "degree_north" if "lat" in internal else "degree_east"
        axis  = "Y" if "lat" in internal else "X"
        vmin  = -90.0 if "lat" in internal else -180.0
        vmax  =  90.0 if "lat" in internal else  180.0
        data_vars[ego_name] = xr.DataArray(v, dims=["TIME"], attrs={
            "long_name": ego_long,
            "standard_name": std_name,
            "units": units,
            "_FillValue": np.float64(99999),
            "valid_min": np.float64(vmin),
            "valid_max": np.float64(vmax),
            "axis": axis,
            "ancillary_variable": anc,
            "reference": "WGS84",
            "coordinate_reference_frame": "urn:ogc:crs:EPSG::4326",
            "sdn_parameter_urn": sdn_p,
            "sdn_uom_urn": sdn_u,
            "glider_original_parameter_name": internal,
        })

    pos_qc = np.ones(n, dtype=np.int8)   # flag 1 = good
    if is_l1 and "latitude_QC" in src_ds:
        pos_qc = src_ds["latitude_QC"].values.astype(np.int8)
    data_vars["POSITION_QC"] = xr.DataArray(pos_qc, dims=["TIME"], attrs=dict(_QC_ATTRS))

    # ── GPS fix arrays (TIME_GPS dimension) ──────────────────────────────────
    gps_t, gps_lat, gps_lon = _get_gps_fixes(src_ds)
    n_gps = len(gps_t)
    if n_gps == 0:
        gps_t   = np.array([t_sec[0]], dtype=np.float64)
        gps_lat = np.array([99999.0])
        gps_lon = np.array([99999.0])
        n_gps   = 1

    gps_t_sec = gps_t.astype("datetime64[s]").astype(np.float64) \
        if np.issubdtype(gps_t.dtype, np.datetime64) else gps_t.astype(np.float64)

    data_vars["TIME_GPS"] = xr.DataArray(gps_t_sec, dims=["TIME_GPS"], attrs={
        "long_name": "Epoch time of the GPS fixes",
        "standard_name": "time",
        "units": "seconds since 1970-01-01T00:00:00Z",
        "_FillValue": np.float64(9999999999),
        "valid_min": np.float64(0),
        "valid_max": np.float64(_time_valid_max()),
        "axis": "T",
        "ancillary_variable": "TIME_GPS_QC",
        "sdn_parameter_urn": "SDN:P01::ELTMEP01",
        "sdn_uom_urn": "SDN:P06::UTBB",
        "glider_original_parameter_name": "",
    })
    data_vars["LATITUDE_GPS"] = xr.DataArray(
        gps_lat.astype(np.float64), dims=["TIME_GPS"], attrs={
            "long_name": "Gps fixed latitude",
            "standard_name": "latitude", "units": "degree_north",
            "_FillValue": np.float64(99999), "valid_min": np.float64(-90),
            "valid_max": np.float64(90), "axis": "Y",
            "ancillary_variable": "POSITION_GPS_QC",
            "reference": "WGS84",
            "coordinate_reference_frame": "urn:ogc:crs:EPSG::4326",
            "sdn_parameter_urn": "SDN:P01::ALATZZ01",
            "sdn_uom_urn": "SDN:P06::DEGN",
            "glider_original_parameter_name": "",
        })
    data_vars["LONGITUDE_GPS"] = xr.DataArray(
        gps_lon.astype(np.float64), dims=["TIME_GPS"], attrs={
            "long_name": "Gps fixed longitude",
            "standard_name": "longitude", "units": "degree_east",
            "_FillValue": np.float64(99999), "valid_min": np.float64(-180),
            "valid_max": np.float64(180), "axis": "X",
            "ancillary_variable": "POSITION_GPS_QC",
            "reference": "WGS84",
            "coordinate_reference_frame": "urn:ogc:crs:EPSG::4326",
            "sdn_parameter_urn": "SDN:P01::ALONZZ01",
            "sdn_uom_urn": "SDN:P06::DEGE",
            "glider_original_parameter_name": "",
        })
    gps_qc = np.ones(n_gps, dtype=np.int8)
    data_vars["TIME_GPS_QC"]     = xr.DataArray(gps_qc, dims=["TIME_GPS"], attrs=dict(_QC_ATTRS))
    data_vars["POSITION_GPS_QC"] = xr.DataArray(gps_qc, dims=["TIME_GPS"], attrs=dict(_QC_ATTRS))

    return data_vars, coords, n_gps


def _add_phase_vars(src_ds, data_vars, n):
    """Add PHASE and PHASE_NUMBER from profile_direction."""
    # EGO phase codes: 0=surface_drift 1=descent 2=subsurface_drift
    #                  3=inflexion 4=ascent 5=grounded 6=inconsistent
    if "profile_direction" in src_ds:
        pd = src_ds["profile_direction"].values
        phase = np.full(n, np.int8(6), dtype=np.int8)   # default: inconsistent
        phase[pd > 0]  = np.int8(1)   # descent
        phase[pd < 0]  = np.int8(4)   # ascent
        phase[pd == 0] = np.int8(2)   # subsurface drift
        phase[~np.isfinite(pd)] = np.int8(-128)
    else:
        phase = np.full(n, np.int8(-128), dtype=np.int8)

    data_vars["PHASE"] = xr.DataArray(phase, dims=["TIME"], attrs={
        "long_name": "Glider trajectory phase code",
        "conventions": "EGO reference table 9.2",
        "_FillValue": np.int8(-128),
        "flag_values": np.array([0, 1, 2, 3, 4, 5, 6], dtype=np.int8),
        "flag_meanings": "surface_drift descent subsurface_drift inflexion ascent grounded inconsistent",
    })

    if "profile_index" in src_ds:
        pi_raw = np.asarray(src_ds["profile_index"].values, dtype=np.float64)
        finite = np.isfinite(pi_raw)
        n_nan_pi = int((~finite).sum())
        # NaN -> int32 is undefined behaviour in numpy: it yields INT32_MIN
        # (-2147483648) with only a RuntimeWarning, never an error. So never
        # cast the whole array and select afterwards — cast ONLY the finite
        # subset, and write the declared _FillValue everywhere else. Those
        # points genuinely have no profile assignment (glider between profiles
        # or unclassified), and EGO's fill value is the honest encoding of that.
        pn = np.full(n, 99999, dtype=np.int32)
        pn[finite] = pi_raw[finite].astype(np.int32)
        if n_nan_pi > 0:
            print(f"  NOTE: profile_index has {n_nan_pi}/{pi_raw.size} NaN values "
                  f"({100.0 * n_nan_pi / pi_raw.size:.2f}%) — PHASE_NUMBER set to "
                  f"fill value 99999 there (not cast)")
    else:
        pn = np.full(n, 99999, dtype=np.int32)

    data_vars["PHASE_NUMBER"] = xr.DataArray(pn, dims=["TIME"], attrs={
        "long_name": "Glider trajectory phase number",
        "_FillValue": np.int32(99999),
    })


def _ego_sensor_for_param(ego_param: str) -> str:
    """
    EGO reference table 25 sensor name for a given EGO parameter.

    Cross-checked against the SOCIB/GROOM reference toolbox
    (ref_lists/GL_REFERENCE_TABLE_25.txt). EGO models one SENSOR entry per
    MEASURED PARAMETER, not one per physical instrument — a single CTD supplies
    three table-25 sensors (CTD_TEMP, CTD_CNDC, CTD_PRES) and the ECO puck
    supplies four. The previous free-text names ("CTD", "AANDERAA_OPTODE",
    "ECO_FLBBCD") are NOT in table 25 and would fail the EGO 1.5 checker.
    """
    return _EGO_SENSOR_BY_PARAM.get(ego_param, "UNKNOWN")


# EGO param -> (table-25 sensor, table-26 maker, table-27 model, deployment.yml
# key prefix for the serial number). Values verified against
# GL_REFERENCE_TABLE_25/26/27.txt in the reference toolbox.
_SENSOR_TABLE = {
    "TEMP":      ("CTD_TEMP",                    "SBE",      "SBE_GPCTD",             "ctd"),
    "CNDC":      ("CTD_CNDC",                    "SBE",      "SBE_GPCTD",             "ctd"),
    "PRES":      ("CTD_PRES",                    "SBE",      "SBE_GPCTD",             "ctd"),
    "PSAL":      ("CTD_CNDC",                    "SBE",      "SBE_GPCTD",             "ctd"),
    "DOXY":      ("OPTODE_DOXY",                 "AANDERAA", "AANDERAA_OPTODE_4831",  "optode"),
    "CHLA":      ("FLUOROMETER_CHLA",            "WETLABS",  "ECO_FLBBCD",            "optics"),
    "CDOM":      ("FLUOROMETER_CDOM",            "WETLABS",  "ECO_FLBBCD",            "optics"),
    "BBP700":    ("BACKSCATTERINGMETER_BBP700",  "WETLABS",  "ECO_FLBBCD",            "optics"),
    "TURBIDITY": ("BACKSCATTERINGMETER_TURBIDITY", "WETLABS", "ECO_FLBBCD",           "optics"),
}
_EGO_SENSOR_BY_PARAM = {k: v[0] for k, v in _SENSOR_TABLE.items()}


def _sensor_serials_from_source(src_ds) -> dict:
    """
    Pull real sensor serial numbers out of the source NetCDF global attributes.

    step1 carries the hardware block parsed from autoexec.mi through to the L0/L1
    globals as dict-like strings, e.g.
        ctd      = {'make': 'Seabird', 'model': 'SlocumCTD', 'serial': '9507'}
        oxygen   = {'make': 'AADI',    'model': 'Optode4831', 'serial': '665'}
        optics   = {'make': 'Wetlabs', 'model': 'FLBBCDSLC',  'serial': '5059'}
    Only the SERIAL is taken from here. 'make'/'model' in these attributes are
    free text ("Seabird", "AADI", "FLBBCDSLC") and are NOT valid entries in EGO
    reference tables 26/27, so the controlled-vocabulary values from
    _SENSOR_TABLE are kept for those two fields.
    """
    import ast
    out = {}
    for attr_name, key in (("ctd", "ctd"), ("oxygen", "optode"),
                           ("optics", "optics"), ("pressure", "pres")):
        raw = src_ds.attrs.get(attr_name)
        if not raw:
            continue
        try:
            info = raw if isinstance(raw, dict) else ast.literal_eval(str(raw))
            serial = str(info.get("serial", "")).strip()
            if serial:
                out[key] = serial
        except (ValueError, SyntaxError):
            continue
    return out


def _build_sensor_rows(meta: dict, param_list: list, serials: dict = None) -> list:
    """
    Build the N_SENSOR rows for exactly the parameters this file actually
    carries, de-duplicated and order-stable. A deployment without an optode
    gets no OPTODE_DOXY row rather than a phantom one.

    Serial numbers are resolved in priority order:
      1. deployment.yml metadata (meta dict) — explicit override
      2. serials dict (from _sensor_serials_from_source) — parsed from
         the source NetCDF's global attributes (autoexec.mi hardware block)
      3. Empty string (unknown)
    """
    if serials is None:
        serials = {}
    rows, seen = [], set()
    for p in param_list:
        entry = _SENSOR_TABLE.get(p)
        if entry is None:
            continue
        name, maker, model, key = entry
        if name in seen:
            continue
        seen.add(name)
        # Priority: deployment.yml > source NetCDF globals > empty
        serial = str(meta.get(f"{key}_serial", "")) or serials.get(key, "")
        rows.append({
            "name":   name,
            "maker":  meta.get(f"{key}_maker", maker),
            "model":  meta.get(f"{key}_model", model),
            "serial": serial,
        })
    if not rows:
        rows.append({"name": "UNKNOWN", "maker": "UNKNOWN",
                     "model": "UNKNOWN", "serial": ""})
    return rows


def _add_sensor_param_tables(deploy_meta, data_vars, param_list, src_ds=None):
    """
    Add SENSOR_* and PARAMETER_* metadata arrays.

    Sensor names/makers/models come from EGO reference tables 25/26/27 via
    _SENSOR_TABLE; deployment.yml may override any of them (e.g. with the real
    serials parsed from autoexec.mi). If src_ds is provided, serial numbers
    are also pulled from its global attributes as a fallback.
    """
    meta = deploy_meta.get("metadata", {})
    serials = _sensor_serials_from_source(src_ds) if src_ds is not None else {}
    sensors = _build_sensor_rows(meta, param_list, serials)

    data_vars["SENSOR"] = xr.DataArray(
        _str_array([s["name"] for s in sensors], 32),
        dims=["N_SENSOR", "STRING32"],
        attrs={"long_name": "Name of the sensor mounted on the glider",
               "conventions": "EGO reference table 25", "_FillValue": " "})
    data_vars["SENSOR_MAKER"] = xr.DataArray(
        _str_array([s["maker"] for s in sensors], 256),
        dims=["N_SENSOR", "STRING256"],
        attrs={"long_name": "Name of the sensor manufacturer",
               "conventions": "EGO reference table 26", "_FillValue": " "})
    data_vars["SENSOR_MODEL"] = xr.DataArray(
        _str_array([s["model"] for s in sensors], 256),
        dims=["N_SENSOR", "STRING256"],
        attrs={"long_name": "Type of the sensor",
               "conventions": "EGO reference table 27", "_FillValue": " "})
    data_vars["SENSOR_SERIAL_NO"] = xr.DataArray(
        _str_array([s["serial"] for s in sensors], 16),
        dims=["N_SENSOR", "STRING16"],
        attrs={"long_name": "Serial number of the sensor", "_FillValue": " "})

    n_p = len(param_list)
    # PARAMETER_SENSOR must name a table-25 sensor, and every name used here
    # must also appear in the SENSOR array above — _build_sensor_rows derives
    # both from _SENSOR_TABLE so the two cannot drift apart.
    param_sensors = [_ego_sensor_for_param(p) for p in param_list]

    data_vars["PARAMETER"] = xr.DataArray(
        _str_array(param_list, 64),
        dims=["N_PARAM", "STRING64"],
        attrs={"long_name": "Name of parameter computed from glider measurements",
               "conventions": "EGO reference table 3", "_FillValue": " "})
    data_vars["PARAMETER_SENSOR"] = xr.DataArray(
        _str_array(param_sensors, 128),
        dims=["N_PARAM", "STRING128"],
        attrs={"long_name": "Name of the sensor that measures this parameter",
               "conventions": "EGO reference table 25", "_FillValue": " "})
    data_vars["PARAMETER_DATA_MODE"] = xr.DataArray(
        np.array(["R"] * n_p, dtype="U1"),
        dims=["N_PARAM"],
        attrs={"long_name": "Data mode of the parameter",
               "conventions": "EGO reference table 19", "_FillValue": " "})

    # SENSOR_MOUNT / SENSOR_ORIENTATION — table 20 has exactly one permitted
    # value; orientation is per-instrument and overridable from deployment.yml.
    data_vars["SENSOR_MOUNT"] = xr.DataArray(
        _str_array(["MOUNTED_ON_GLIDER"] * len(sensors), 64),
        dims=["N_SENSOR", "STRING64"],
        attrs={"long_name": "Sensor mounting characteristics",
               "conventions": "EGO reference table 20", "_FillValue": " "})
    orientations = [
        _pick(meta, f"{s['name'].lower()}_orientation",
              _REF["sensor_orientation"], "DOWNWARD")
        for s in sensors
    ]
    data_vars["SENSOR_ORIENTATION"] = xr.DataArray(
        _str_array(orientations, 16),
        dims=["N_SENSOR", "STRING16"],
        attrs={"long_name": "Sensor orientation characteristics",
               "conventions": "EGO reference table 21", "_FillValue": " "})

    # PARAMETER_UNITS / ACCURACY / RESOLUTION from the instrument specifications.
    units = [_PARAM_SPECS.get(p, {}).get("units", "") for p in param_list]
    acc = [_PARAM_SPECS.get(p, {}).get("accuracy", "") for p in param_list]
    res = [_PARAM_SPECS.get(p, {}).get("resolution", "") for p in param_list]
    data_vars["PARAMETER_UNITS"] = xr.DataArray(
        _str_array(units, 32), dims=["N_PARAM", "STRING32"],
        attrs={"long_name": "Units of accuracy and resolution of the parameter",
               "_FillValue": " "})
    data_vars["PARAMETER_ACCURACY"] = xr.DataArray(
        _str_array(acc, 32), dims=["N_PARAM", "STRING32"],
        attrs={"long_name": "Accuracy of the parameter", "_FillValue": " "})
    data_vars["PARAMETER_RESOLUTION"] = xr.DataArray(
        _str_array(res, 32), dims=["N_PARAM", "STRING32"],
        attrs={"long_name": "Resolution of the parameter", "_FillValue": " "})


def _add_history_vars(deploy_meta, data_vars, param_list, n_time, is_l1):
    """
    Build the EGO HISTORY_* block: one record per (parameter, action).

    Provenance model, following the reference toolbox's use of ACTION=QCP$/QCF$
    (EGO reference table 7):
      QCP$  — the set of RTQC tests PERFORMED on that parameter
      QCF$  — the set of tests that FAILED (i.e. flagged at least one point)
    HISTORY_QCTEST carries the test identifiers for that record, so the file
    states which tests ran per parameter instead of only listing them once in a
    global attribute.

    For L0 (no QC applied) a single 'data decoded' record is written instead:
    claiming QC provenance on an unQC'd file would be false.
    """
    meta = deploy_meta.get("metadata", {})
    inst = str(meta.get("institution_code",
                        _DEFAULT_INSTITUTION_CODE)).strip().upper()
    if inst not in _REF["institution"]:
        print(f"  NOTE: institution_code '{inst}' not in EGO reference table 4 "
              f"— using '{_DEFAULT_INSTITUTION_CODE}'")
        inst = _DEFAULT_INSTITUTION_CODE

    now = datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S")
    software = "GL_RTQC"                 # STRING8
    release = "1.0"                      # STRING4
    # ARGQ = real-time QC step (EGO reference table 12); ARFM = format/decode.
    step = "ARGQ" if is_l1 else "ARFM"

    records = []
    if is_l1:
        for p in param_list:
            records.append({
                "action": "QCP$",        # tests performed
                "parameter": p,
                "qctest": _RTQC_TESTS_APPLIED,
            })
    else:
        records.append({"action": "CV", "parameter": "", "qctest": ""})

    n_hist = len(records)
    data_vars["HISTORY_INSTITUTION"] = xr.DataArray(
        _str_array([inst] * n_hist, 2), dims=["N_HISTORY", "STRING2"],
        attrs={"long_name": "Institution which performed action",
               "conventions": "EGO reference table 4", "_FillValue": " "})
    data_vars["HISTORY_STEP"] = xr.DataArray(
        _str_array([step] * n_hist, 4), dims=["N_HISTORY", "STRING4"],
        attrs={"long_name": "Step in data processing",
               "conventions": "EGO reference table 12", "_FillValue": " "})
    data_vars["HISTORY_SOFTWARE"] = xr.DataArray(
        _str_array([software] * n_hist, 8), dims=["N_HISTORY", "STRING8"],
        attrs={"long_name": "Name of software which performed action",
               "conventions": "Institution dependent", "_FillValue": " "})
    data_vars["HISTORY_SOFTWARE_RELEASE"] = xr.DataArray(
        _str_array([release] * n_hist, 4), dims=["N_HISTORY", "STRING4"],
        attrs={"long_name": "Version/release of software which performed action",
               "conventions": "Institution dependent", "_FillValue": " "})
    data_vars["HISTORY_REFERENCE"] = xr.DataArray(
        _str_array([meta.get("history_reference", "")] * n_hist, 64),
        dims=["N_HISTORY", "STRING64"],
        attrs={"long_name": "Reference of database",
               "conventions": "Institution dependent", "_FillValue": " "})
    data_vars["HISTORY_DATE"] = xr.DataArray(
        _str_array([now] * n_hist, 14), dims=["N_HISTORY", "DATE_TIME"],
        attrs={"long_name": "Date the history record was created",
               "conventions": "YYYYMMDDHHMISS", "_FillValue": " "})
    data_vars["HISTORY_ACTION"] = xr.DataArray(
        _str_array([r["action"] for r in records], 64),
        dims=["N_HISTORY", "STRING64"],
        attrs={"long_name": "Action performed on data",
               "conventions": "EGO reference table 7", "_FillValue": " "})
    data_vars["HISTORY_PARAMETER"] = xr.DataArray(
        _str_array([r["parameter"] for r in records], 16),
        dims=["N_HISTORY", "STRING16"],
        attrs={"long_name": "Parameter action is performed on",
               "conventions": "EGO reference table 3", "_FillValue": " "})
    data_vars["HISTORY_QCTEST"] = xr.DataArray(
        _str_array([r["qctest"] for r in records], 16),
        dims=["N_HISTORY", "STRING16"],
        attrs={"long_name": "Documentation of tests performed, tests failed "
                            "(in hex form)",
               "conventions": "Write tests performed when ACTION=QCP$; "
                              "tests failed when ACTION=QCF$",
               "_FillValue": " "})

    # PREVIOUS_VALUE applies to single-value corrections, which this chain does
    # not make at the history level — declared fill rather than a fake number.
    data_vars["HISTORY_PREVIOUS_VALUE"] = xr.DataArray(
        np.full(n_hist, 99999.0, dtype=np.float32), dims=["N_HISTORY"],
        attrs={"long_name": "Parameter or flag previous value before action",
               "_FillValue": np.float32(99999)})
    # Each record covers the whole timeseries.
    data_vars["HISTORY_START_TIME_INDEX"] = xr.DataArray(
        np.zeros(n_hist, dtype=np.int32), dims=["N_HISTORY"],
        attrs={"long_name": "Start time index action applied on",
               "_FillValue": np.int32(99999)})
    data_vars["HISTORY_STOP_TIME_INDEX"] = xr.DataArray(
        np.full(n_hist, max(n_time - 1, 0), dtype=np.int32), dims=["N_HISTORY"],
        attrs={"long_name": "Stop time index action applied on",
               "_FillValue": np.int32(99999)})


def _scalar_char(value: str, length: int, long_name: str,
                 conventions: str = None) -> xr.DataArray:
    """A single fixed-length char variable (one STRINGnn dimension)."""
    attrs = {"long_name": long_name, "_FillValue": " "}
    if conventions:
        attrs["conventions"] = conventions
    dim = f"STRING{length}" if length != 14 else "DATE_TIME"
    return xr.DataArray(_pad_str(str(value), length).astype("U1"),
                        dims=[dim], attrs=attrs)


def _platform_type_from_model(meta: dict) -> str | None:
    """
    Derive a table-23 PLATFORM_TYPE from the free-text glider_model/platform_type
    already present in deployment.yml (e.g. 'Slocum G3 Deep' -> SLOCUM_SG3).

    Reads the deployment's own fields rather than requiring a new EGO-specific
    key to be added by hand.
    """
    text = " ".join(str(meta.get(k, "")) for k in
                    ("glider_model", "platform_type", "glider_name")).upper()
    if "SEAEXPLORER" in text:
        return "SEAEXPLORER_SHALLOW" if "SHALLOW" in text else "SEAEXPLORER"
    if "SEAGLIDER" in text:
        return "SEAGLIDER"
    if "SPRAY" in text:
        return "SPRAY"
    if "SLOCUM" in text:
        for tag, val in (("G3", "SLOCUM_SG3"), ("G2", "SLOCUM_SG2"),
                         ("G1", "SLOCUM_SG1")):
            if tag in text:
                return val
    return None


def _warn_if_template_metadata(meta: dict) -> None:
    """
    Warn when deployment.yml still carries values from the upstream C-PROOF
    template. Those fields flow straight into the EGO global attributes, so an
    unedited template silently publishes the wrong institution, project, sea
    name and PI on an INCOIS product.
    """
    markers = []
    blob = " ".join(str(v) for v in meta.values()).lower()
    for needle, label in (
        ("saanich", "sea_name/summary/project still reference Saanich Inlet"),
        ("cproof", "creator/publisher URLs still point at cproof.uvic.ca"),
        ("uvic.ca", "contact e-mails are still @uvic.ca"),
        ("c-proof", "institution is still 'C-PROOF'"),
    ):
        if needle in blob:
            markers.append(label)
    if str(meta.get("glider_wmo", "")).strip() in ("999999", ""):
        markers.append("glider_wmo is the placeholder '999999'")

    if markers:
        print("  WARNING: deployment.yml looks like an unedited C-PROOF "
              "template — these values are published in the EGO file:")
        for m in markers:
            print(f"    - {m}")


def _pick(meta: dict, key: str, allowed: tuple, default: str) -> str:
    """
    Take a value from deployment.yml only if it is in the controlled vocabulary.

    A typo or a free-text platform name silently becomes the validated default
    rather than being written out and failing the checker downstream.
    """
    val = str(meta.get(key, "")).strip().upper()
    if val and val in allowed:
        return val
    if val:
        print(f"  NOTE: deployment.yml {key}='{val}' is not in the EGO "
              f"reference table — using '{default}' instead")
    return default


def _add_platform_vars(deploy_meta, data_vars, src_ds, platform_code):
    """
    Add the EGO glider-characteristics block (spec section 'glider_characteristics').

    All values come from deployment.yml where available, constrained to the
    reference tables; unknown fields are written as blanks rather than omitted,
    so the variable exists with its declared _FillValue.
    """
    meta = deploy_meta.get("metadata", {})
    _warn_if_template_metadata(meta)

    fam = _pick(meta, "platform_family", _REF["platform_family"],
                _PLATFORM_DEFAULTS["platform_family"])
    # Prefer a type derived from the deployment's own glider_model text over the
    # hard default, so 'Slocum G3 Deep' yields SLOCUM_SG3 rather than SLOCUM_SG2.
    derived = _platform_type_from_model(meta)
    if derived:
        typ = derived
        print(f"  PLATFORM_TYPE: {typ} (from glider_model/platform_type)")
    else:
        typ = _pick(meta, "platform_type", _REF["platform_type"],
                    _PLATFORM_DEFAULTS["platform_type"])
    mkr = _pick(meta, "platform_maker", _REF["platform_maker"],
                _PLATFORM_DEFAULTS["platform_maker"])

    data_vars["PLATFORM_FAMILY"] = _scalar_char(
        fam, 256, "Category of instrument", "EGO reference table 22")
    data_vars["PLATFORM_TYPE"] = _scalar_char(
        typ, 32, "Type of glider", "EGO reference table 23")
    data_vars["PLATFORM_MAKER"] = _scalar_char(
        mkr, 256, "Name of the manufacturer", "EGO reference table 24")
    data_vars["GLIDER_SERIAL_NO"] = _scalar_char(
        meta.get("glider_serial", platform_code), 16,
        "Serial number of the glider")
    data_vars["GLIDER_OWNER"] = _scalar_char(
        meta.get("glider_owner", meta.get("institution", "")), 64,
        "Glider owner")
    data_vars["OPERATING_INSTITUTION"] = _scalar_char(
        meta.get("operating_institution", meta.get("institution", "")), 64,
        "Operating institution of the glider")
    data_vars["WMO_INST_TYPE"] = _scalar_char(
        _WMO_INST_TYPE_GLIDER, 4, "Coded instrument type",
        "EGO reference table 8")

    # POSITIONING_SYSTEM / TRANS_SYSTEM are 2-D (N_* x STRINGnn) even with one
    # entry, so they are built with _str_array to keep the declared shape.
    pos_sys = [_pick(meta, "positioning_system",
                     _REF["positioning_system"], "GPS")]
    data_vars["POSITIONING_SYSTEM"] = xr.DataArray(
        _str_array(pos_sys, 8), dims=["N_POSITIONING_SYSTEM", "STRING8"],
        attrs={"long_name": "Positioning system",
               "conventions": "EGO reference table 9.1", "_FillValue": " "})

    # deployment.yml carries this as free-text 'transmission_system' (and the
    # 1131 file spells it 'IRRIDIUM'), so normalise before vocabulary matching.
    _trans_raw = str(meta.get("trans_system",
                              meta.get("transmission_system", ""))).upper()
    if "IRID" in _trans_raw or "IRRID" in _trans_raw:
        trans = ["IRIDIUM"]
    elif "FREEWAVE" in _trans_raw:
        trans = ["FREEWAVE"]
    else:
        trans = [_pick(meta, "trans_system", _REF["trans_system"], "IRIDIUM")]
    data_vars["TRANS_SYSTEM"] = xr.DataArray(
        _str_array(trans, 16), dims=["N_TRANS_SYSTEM", "STRING16"],
        attrs={"long_name": "Telecommunication system used",
               "conventions": "EGO reference table 10.1", "_FillValue": " "})
    data_vars["TRANS_SYSTEM_ID"] = xr.DataArray(
        _str_array([meta.get("trans_system_id", "")], 32),
        dims=["N_TRANS_SYSTEM", "STRING32"],
        attrs={"long_name": "Program identifier used by the transmission system",
               "_FillValue": " "})
    data_vars["TRANS_FREQUENCY"] = xr.DataArray(
        _str_array([meta.get("trans_frequency", "")], 16),
        dims=["N_TRANS_SYSTEM", "STRING16"],
        attrs={"long_name": "Frequency of transmission from the glider",
               "units": "hertz", "_FillValue": " "})

    for var, length, ln in (
        ("BATTERY_TYPE", 64, "Type of battery packs in the glider"),
        ("BATTERY_PACKS", 64, "Configuration of battery packs in the glider"),
        ("SPECIAL_FEATURES", 1024,
         "Extra features of the glider (algorithms, compressee, pump change etc.)"),
        ("FIRMWARE_VERSION_NAVIGATION", 16,
         "Firmware version of the navigation controller board"),
        ("FIRMWARE_VERSION_SCIENCE", 16,
         "Firmware version of the scientific sensors controller board"),
        ("GLIDER_MANUAL_VERSION", 16, "Manual version of the glider"),
        ("ANOMALY", 256,
         "Describe any anomalies or problems the glider may have had"),
        ("CUSTOMIZATION", 1024,
         "Glider customization, i.e. (institution and modifications)"),
        ("DAC_FORMAT_ID", 16,
         "Format number used by the DAC to describe the data format type for each glider"),
    ):
        data_vars[var] = _scalar_char(meta.get(var.lower(), ""), length, ln)


def _add_deployment_vars(deploy_meta, data_vars, src_ds):
    """
    Add the EGO glider-deployment block.

    Start/end position and time are taken from the actual data when
    deployment.yml does not state them, so the block reflects the file.
    """
    meta = deploy_meta.get("metadata", {})

    t = src_ds["time"].values
    lat = src_ds["latitude"].values if "latitude" in src_ds else np.array([np.nan])
    lon = src_ds["longitude"].values if "longitude" in src_ds else np.array([np.nan])

    finite = np.isfinite(lat) & np.isfinite(lon)
    first = int(np.argmax(finite)) if finite.any() else 0
    last = int(len(finite) - 1 - np.argmax(finite[::-1])) if finite.any() else 0

    def _f(v):
        return np.float64(v) if np.isfinite(v) else np.float64(99999)

    data_vars["DEPLOYMENT_START_DATE"] = _scalar_char(
        _date_time_str(t[0] if len(t) else None), 14,
        "Date (UTC) of the deployment", "YYYYMMDDHHMISS")
    data_vars["DEPLOYMENT_START_LATITUDE"] = xr.DataArray(
        _f(lat[first]), attrs={
            "long_name": "Latitude of the glider when deployed",
            "units": "degree_north", "_FillValue": np.float64(99999),
            "valid_min": np.float64(-90), "valid_max": np.float64(90)})
    data_vars["DEPLOYMENT_START_LONGITUDE"] = xr.DataArray(
        _f(lon[first]), attrs={
            "long_name": "Longitude of the glider when deployed",
            "units": "degree_east", "_FillValue": np.float64(99999),
            "valid_min": np.float64(-180), "valid_max": np.float64(180)})
    data_vars["DEPLOYMENT_START_QC"] = xr.DataArray(
        np.int8(0), attrs={
            "long_name": "Quality on DEPLOYMENT_START date, time and location",
            "conventions": "EGO reference table 2.1",
            "_FillValue": np.int8(-128),
            "flag_values": np.array([0, 1, 2, 3, 4, 5, 8, 9], dtype=np.int8),
            "flag_meanings": _QC_ATTRS["flag_meanings"]})

    data_vars["DEPLOYMENT_END_DATE"] = _scalar_char(
        _date_time_str(t[-1] if len(t) else None), 14,
        "Date (UTC) of the glider recovery", "YYYYMMDDHHMISS")
    data_vars["DEPLOYMENT_END_LATITUDE"] = xr.DataArray(
        _f(lat[last]), attrs={
            "long_name": "Latitude of the glider recovery",
            "units": "degree_north", "_FillValue": np.float64(99999),
            "valid_min": np.float64(-90), "valid_max": np.float64(90)})
    data_vars["DEPLOYMENT_END_LONGITUDE"] = xr.DataArray(
        _f(lon[last]), attrs={
            "long_name": "Longitude of the glider recovery",
            "units": "degree_east", "_FillValue": np.float64(99999),
            "valid_min": np.float64(-180), "valid_max": np.float64(180)})
    data_vars["DEPLOYMENT_END_QC"] = xr.DataArray(
        np.int8(0), attrs={
            "long_name": "Quality on DEPLOYMENT_END date, time and location",
            "conventions": "EGO reference table 2.1",
            "_FillValue": np.int8(-128),
            "flag_values": np.array([0, 1, 2, 3, 4, 5, 8, 9], dtype=np.int8),
            "flag_meanings": _QC_ATTRS["flag_meanings"]})

    status = str(meta.get("deployment_end_status", "")).strip().upper()[:1]
    data_vars["DEPLOYMENT_END_STATUS"] = xr.DataArray(
        np.array(status if status in ("R", "L") else " ", dtype="U1"),
        attrs={"long_name": "Status of the end of mission of the glider",
               "conventions": "R: retrieved, L: lost", "_FillValue": " "})

    for var, length, ln in (
        ("DEPLOYMENT_PLATFORM", 32, "Identifier of the deployment platform"),
        ("DEPLOYMENT_CRUISE_ID", 32,
         "Identifier of the cruise that deployed the glider"),
        ("DEPLOYMENT_REFERENCE_STATION_ID", 256,
         "Identifier of stations used to verify the parameter measurements"),
        ("DEPLOYMENT_OPERATOR", 256,
         "Name of the person in charge of the glider deployment"),
    ):
        data_vars[var] = _scalar_char(meta.get(var.lower(), ""), length, ln)


def _add_positioning_method(src_ds, data_vars, n, gps_time_sec, t_sec):
    """
    POSITIONING_METHOD (EGO reference table 10.2): 0=GPS, 1=Argos, 2=interpolated.

    A sample is flagged GPS only where its timestamp coincides with a real
    surface fix; everything else in the timeseries is a dead-reckoned /
    interpolated position, which is what code 2 means. Reporting 0 everywhere
    would overstate the positional provenance of subsurface samples.
    """
    method = np.full(n, np.int8(2), dtype=np.int8)   # interpolated
    if gps_time_sec is not None and len(gps_time_sec):
        fix = np.isin(np.round(t_sec).astype(np.int64),
                      np.round(gps_time_sec).astype(np.int64))
        method[fix] = np.int8(0)                     # GPS
        n_fix = int(fix.sum())
    else:
        n_fix = 0
    print(f"  POSITIONING_METHOD: {n_fix} GPS-fix sample(s), "
          f"{n - n_fix} interpolated")
    data_vars["POSITIONING_METHOD"] = xr.DataArray(
        method, dims=["TIME"], attrs={
            "long_name": "Positioning method",
            "conventions": "EGO reference table 10.2",
            "_FillValue": np.int8(-128),
            "flag_values": np.array([0, 1, 2], dtype=np.int8),
            "flag_meanings": "GPS Argos interpolated"})


def _add_science_vars(src_ds, data_vars, is_l1, n):
    """
    Add all science variables (TEMP, PSAL, PRES, DOXY, CHLA, CDOM, BBP700).
    For L1: writes VAR + VAR_QC + VAR_ADJUSTED + VAR_ADJUSTED_QC + VAR_ADJUSTED_ERROR.
    For L0: writes VAR only (no QC, no adjusted).
    Applies density conversion for DOXY (umol/L -> micromole/kg).
    Returns list of EGO parameter names actually written.
    """
    fill = np.float32(99999.0)

    # Pre-fetch density for DOXY conversion (umol/L -> micromole/kg)
    density = None
    if "density" in src_ds:
        density = src_ds["density"].values.astype(np.float64)
        d_valid = density[np.isfinite(density)]
        print(f"  DEBUG density: n={len(d_valid)}, range={d_valid.min():.1f}-{d_valid.max():.1f} kg/m3")

    written_params = []

    for internal, info in _VAR_MAP.items():
        if internal not in src_ds:
            continue

        ego      = info["ego"]
        units    = info["units"]
        level    = info["level"]
        adj_src  = info.get("adjusted_src")
        needs_dc = info.get("needs_density_conversion", False)

        raw_vals = src_ds[internal].values.astype(np.float32).copy()

        # DOXY: convert umol/L -> micromole/kg using in-situ density
        if needs_dc:
            if density is not None:
                # density in kg/m3; 1 kg/m3 = 0.001 kg/L
                dens_kg_per_L = density / 1000.0
                valid = np.isfinite(raw_vals) & np.isfinite(dens_kg_per_L) & (dens_kg_per_L > 0.5)
                converted = raw_vals.copy()
                converted[valid] = (raw_vals[valid] / dens_kg_per_L[valid]).astype(np.float32)
                converted[~valid] = fill
                # Numeric proof, at the point of division, that it is applied.
                # Sample the first indices where density AND oxygen are BOTH
                # finite: the leading rows of a deployment are typically NaN, so
                # a naive array[:5] prints all-NaN and makes a perfectly working
                # conversion look like a no-op. That sampling artefact is what
                # made this read as "broken" before.
                #
                # The expected effect is small BY CONSTRUCTION: seawater density
                # is ~1.02-1.03 kg/L, so umol/L -> umol/kg only moves values by
                # ~2-3%. Ranges that look "unchanged to 3 significant figures"
                # are the correct result, not evidence of a missing division.
                sample = np.where(valid)[0][:5]
                print(f"  DOXY umol/L -> umol/kg  (converted {int(valid.sum())} "
                      f"of {raw_vals.size} points):")
                for i in sample:
                    factor = (raw_vals[i] / converted[i]) if converted[i] != 0 else np.nan
                    print(f"    idx={i:<8d} density={density[i]:10.4f} kg/m3   "
                          f"raw={raw_vals[i]:10.4f} umol/L -> "
                          f"{converted[i]:10.4f} umol/kg   (/{factor:.5f})")
                raw_vals = converted
            else:
                print(f"  WARNING: density not available — DOXY conversion skipped")

        raw_vals[~np.isfinite(raw_vals)] = fill

        # Build variable attributes
        var_attrs = {
            "units":       units,
            "_FillValue":  fill,
            "coordinates": "TIME LATITUDE LONGITUDE PRES",
            "glider_original_parameter_name": internal,
        }
        # `is not None` rather than truthiness: an empty standard_name is a
        # deliberate, spec-required value for parameters with no CF name
        # (CDOM, BBP700), and must still be written.
        if info.get("standard_name") is not None:
            var_attrs["standard_name"] = info["standard_name"]
        if info.get("long_name"):
            var_attrs["long_name"] = info["long_name"]
        if info.get("vmin") is not None:
            var_attrs["valid_min"] = np.float32(info["vmin"])
        if info.get("vmax") is not None:
            var_attrs["valid_max"] = np.float32(info["vmax"])
        if info.get("sdn_param"):
            var_attrs["sdn_parameter_urn"] = info["sdn_param"]
        if info.get("sdn_uom"):
            var_attrs["sdn_uom_urn"] = info["sdn_uom"]
        if ego == "PRES":
            var_attrs["axis"]     = "Z"
            var_attrs["positive"] = "down"

        data_vars[ego] = xr.DataArray(raw_vals, dims=["TIME"], attrs=var_attrs)
        written_params.append(ego)

        if not is_l1:
            continue   # L0: raw value only

        # ── QC flag ──────────────────────────────────────────────────────────
        qc_internal = f"{internal}_QC"
        if qc_internal in src_ds:
            qc_vals = src_ds[qc_internal].values.astype(np.int8)
        else:
            # Flag 0 ("no_qc_performed", EGO reference table 2.1) everywhere is
            # CORRECT for the parameters that land here, not an oversight:
            #   CNDC      — back-calculated from PSAL/TEMP/PRES; this pipeline
            #               runs no dedicated conductivity test, so it has no
            #               independent QC verdict to report.
            #   TURBIDITY — no dedicated turbidity test exists in the RTQC suite.
            # Both also reach TURBIDITY_ADJUSTED_QC through the same path.
            # Do NOT "fix" these to flag 1 (good_data): asserting good_data for a
            # test that was never run is a false provenance claim. If a real test
            # is added later, populate <var>_QC upstream in step23 and this
            # branch stops being taken automatically.
            qc_vals = np.zeros(n, dtype=np.int8)
        qc_attrs = dict(_QC_ATTRS)
        data_vars[f"{ego}_QC"] = xr.DataArray(qc_vals, dims=["TIME"], attrs=qc_attrs)

        # ── _ADJUSTED / _ADJUSTED_QC / _ADJUSTED_ERROR ───────────────────────
        # Only for non-intermediate parameters (level != 'i')
        if level == "i":
            continue

        adj_vals = np.full(n, fill, dtype=np.float32)
        adj_qc   = qc_vals.copy()

        if adj_src and adj_src in src_ds:
            adj_raw  = src_ds[adj_src].values.astype(np.float32).copy()
            raw_src  = src_ds[internal].values

            # step23 builds the *_processed / *_corrected sources from the
            # pre-mask working copy, then writes the despike/range masks back
            # into the RAW variable afterwards. The adjusted source therefore
            # stays finite at points RTQC later rejected — on 1131 that is 4083
            # extra points for temperature and 10591 for salinity, all carrying
            # QC flag 9. Published unmasked, _ADJUSTED covers MORE points and a
            # WIDER range than the parameter it adjusts, which is backwards.
            #
            # Fix the provenance rather than the symptom: restrict _ADJUSTED to
            # the raw parameter's own good footprint — finite raw value, and a
            # QC flag that is neither bad (4) nor missing (9). (The previous
            # 20%-span heuristic silently swapped in raw values instead; for
            # TEMP it missed by 0.04 units and never fired at all.)
            good = (np.isfinite(raw_src) & np.isfinite(adj_raw)
                    & ~np.isin(qc_vals, [4, 9]))

            if needs_dc and density is not None:
                # Same umol/L -> umol/kg conversion as the base parameter, so
                # DOXY and DOXY_ADJUSTED stay on a common scale.
                dens_kg_per_L = density / 1000.0
                good &= np.isfinite(dens_kg_per_L) & (dens_kg_per_L > 0.5)
                adj_raw[good] = (adj_raw[good]
                                 / dens_kg_per_L[good]).astype(np.float32)

            # Residual Savitzky-Golay overshoot: fitting a 2nd-order polynomial
            # near profile edges and NaN gaps can push a small number of points
            # beyond anything the instrument actually measured (1131: 97 pts for
            # TEMP, 17 PSAL, 13 DOXY — all <0.06%). An adjustment must not
            # invent values outside the observed envelope, so flag those bad in
            # _ADJUSTED_QC and withhold the value instead of publishing it.
            if good.any():
                raw_good = raw_src[np.isfinite(raw_src)]
                lo, hi = float(raw_good.min()), float(raw_good.max())
                if needs_dc and density is not None:
                    dkl = (density / 1000.0)
                    ok = np.isfinite(dkl) & (dkl > 0.5) & np.isfinite(raw_src)
                    if ok.any():
                        conv_raw = raw_src[ok] / dkl[ok]
                        lo, hi = float(conv_raw.min()), float(conv_raw.max())
                oor = good & ((adj_raw < lo) | (adj_raw > hi))
                if oor.any():
                    print(f"  {ego}_ADJUSTED: {int(oor.sum())} point(s) outside the "
                          f"raw observed range [{lo:.4f}, {hi:.4f}] "
                          f"(smoother overshoot) — flagged _ADJUSTED_QC=4")
                    good &= ~oor
                    adj_qc[oor] = np.int8(4)

            adj_vals = np.where(good, adj_raw, fill).astype(np.float32)
            # Points dropped because the raw parameter was bad/missing carry the
            # raw flag already (4 or 9); nothing further to set there.

        adj_attrs = dict(var_attrs)
        adj_attrs["long_name"] = info.get("long_name", ego) + " adjusted"
        data_vars[f"{ego}_ADJUSTED"] = xr.DataArray(adj_vals, dims=["TIME"],
                                                      attrs=adj_attrs)

        data_vars[f"{ego}_ADJUSTED_QC"] = xr.DataArray(
            adj_qc, dims=["TIME"], attrs=dict(_QC_ATTRS))

        # _ADJUSTED_ERROR: fill with fill value (no formal error estimate)
        err_attrs = {
            "long_name":  "Contains the error on the adjusted values as determined by the delayed mode QC process",
            "_FillValue": fill,
            "units":      units,
        }
        data_vars[f"{ego}_ADJUSTED_ERROR"] = xr.DataArray(
            np.full(n, fill, dtype=np.float32), dims=["TIME"], attrs=err_attrs)

    return written_params


def convert_to_ego(src_path: str, out_path: str, deploy_yaml: str = None,
                   is_l1: bool = False, data_mode: str = "R") -> str:
    """
    Convert one internal pipeline NetCDF file to EGO 1.5 format.

    Parameters
    ----------
    src_path    : path to internal L0 or L1 NetCDF
    out_path    : path for EGO-compliant output NetCDF
    deploy_yaml : path to deployment.yml (optional)
    is_l1       : True for L1 (writes QC flags + adjusted variables)
    data_mode   : 'R' real-time, 'D' delayed mode

    Returns
    -------
    Path to written output file.
    """
    print(f"  EGO conversion: {os.path.basename(src_path)} -> {os.path.basename(out_path)}")
    t0 = _time.time()

    src_ds      = xr.open_dataset(src_path)
    deploy_meta = _load_deployment_meta(deploy_yaml) if deploy_yaml else {}
    meta        = deploy_meta.get("metadata", {})

    n = len(src_ds["time"])
    platform_code   = str(meta.get("glider_serial", meta.get("deployment_name", "unknown")))
    institution     = str(meta.get("institution", "INCOIS"))
    deployment_name = str(meta.get("deployment_name", platform_code))

    # ── Build data_vars dict ─────────────────────────────────────────────────
    data_vars, coords, n_gps = _build_ego_dataset(
        src_ds, deploy_meta, is_l1, data_mode)

    # Phase variables
    _add_phase_vars(src_ds, data_vars, n)

    # Science variables
    written_params = _add_science_vars(src_ds, data_vars, is_l1, n)

    # Sensor + parameter metadata tables
    _add_sensor_param_tables(deploy_meta, data_vars, written_params, src_ds=src_ds)

    # Platform characteristics, deployment block, positioning provenance, history
    _add_platform_vars(deploy_meta, data_vars, src_ds, platform_code)
    _add_deployment_vars(deploy_meta, data_vars, src_ds)
    _add_positioning_method(
        src_ds, data_vars, n,
        data_vars["TIME_GPS"].values if "TIME_GPS" in data_vars else None,
        data_vars["TIME"].values)
    _add_history_vars(deploy_meta, data_vars, written_params, n, is_l1)

    # ── Assemble Dataset ─────────────────────────────────────────────────────
    # Determine dimension sizes from data_vars
    dims = {
        "TIME":      n,
        "TIME_GPS":  n_gps,
        "N_SENSOR":  3,
        "N_PARAM":   len(written_params),
        "STRING256": 256,
        "STRING128": 128,
        "STRING64":  64,
        "STRING32":  32,
        "STRING16":  16,
    }

    ds_out = xr.Dataset(data_vars)

    # ── Mandatory global attributes ──────────────────────────────────────────
    t_vals = src_ds["time"].values
    t_start = str(t_vals[0])[:19] + "Z"
    t_end   = str(t_vals[-1])[:19] + "Z"

    lat_vals = src_ds["latitude"].values if "latitude" in src_ds else np.array([np.nan])
    lon_vals = src_ds["longitude"].values if "longitude" in src_ds else np.array([np.nan])

    # Vertical extent for geospatial_vertical_* (EGO expects the pressure range).
    if "pressure" in src_ds:
        _p = src_ds["pressure"].values
        _p = _p[np.isfinite(_p)]
        vert_min = f"{float(_p.min()):.2f}" if _p.size else ""
        vert_max = f"{float(_p.max()):.2f}" if _p.size else ""
    else:
        vert_min = vert_max = ""

    ds_out.attrs = {
        # ── Mandatory (checker-enforced) ─────────────────────────────────────
        "data_type":       "EGO glider time-series data",
        "format_version":  "1.5",
        "platform_code":   platform_code,
        "date_update":     _now_iso(),
        "data_mode":       data_mode,
        "naming_authority": "EGO",
        "id":              f"{platform_code}_{t_start[:10].replace('-','')}",
        # ── Spec-defined descriptive attributes (EGO_format_1.5.json) ────────
        "Conventions":     "CF-1.4 EGO-1.5",
        "netcdf_version":  "4",
        "cdm_data_type":   "Trajectory",
        "title":           f"Glider {platform_code} EGO timeseries",
        "institution":     institution,
        "source":          "Glider observation",
        "history":         f"{_now_iso()} — Converted to EGO 1.5 by step_ego.py",
        "comment":         meta.get("comment", ""),
        "deployment_code": deployment_name,
        "license":         "https://creativecommons.org/licenses/by-nc/4.0/",
        "quality_index":   meta.get("quality_index", "unknown quality"),
        "geospatial_lat_min": f"{float(np.nanmin(lat_vals)):.4f}",
        "geospatial_lat_max": f"{float(np.nanmax(lat_vals)):.4f}",
        "geospatial_lon_min": f"{float(np.nanmin(lon_vals)):.4f}",
        "geospatial_lon_max": f"{float(np.nanmax(lon_vals)):.4f}",
        "geospatial_vertical_min": vert_min,
        "geospatial_vertical_max": vert_max,
        "time_coverage_start": t_start,
        "time_coverage_end":   t_end,
        # The spec pins qc_manual to the published EGO QC manual DOI; a local
        # free-text label here is not the document the format refers to.
        "qc_manual":  "http://doi.org/10.13155/51485",
        "distribution_statement": (
            "EGO data are published without any warranty, express or implied. "
            "The user assumes all risk arising from his/her use of EGO data. "
            "EGO data are intended to be research-quality and include estimates "
            "of data quality and accuracy, but it is possible that these "
            "estimates or the data themselves contain errors. It is the sole "
            "responsibility of the user to assess if the data are appropriate "
            "for his/her use, and to interpret the data, data quality, and data "
            "accuracy accordingly. EGO welcomes users to ask questions and "
            "report problems to the contact addresses listed in the data files "
            "or on the EGO internet page."),
        "data_processing_chain_name":    "INCOIS Glider RTQC Pipeline",
        "data_processing_chain_version": "1.0",
        "data_processing_chain_uri":     "https://doi.org/10.17882/45402",
        "rtqc_tests_applied": _RTQC_TESTS_APPLIED,
        # ── Recommended discovery attributes (EGO user manual) ───────────────
        # Written even when unknown so the attribute exists with an empty value,
        # which is how the format spec itself declares them. Populated from
        # deployment.yml where the deployment provides a real value — inventing
        # a DOI, EDMO code or PI email would be worse than leaving it blank.
        "wmo_platform_code":  str(meta.get("wmo_platform_code",
                                           meta.get("glider_wmo",
                                                    meta.get("wmo_id", "")))),
        "project_name":       str(meta.get("project_name",
                                           meta.get("project", ""))),
        "principal_investigator": str(meta.get("principal_investigator",
                                               meta.get("creator_name", ""))),
        "principal_investigator_email": str(
            meta.get("principal_investigator_email",
                     meta.get("creator_email", ""))),
        "area":               str(meta.get("area", meta.get("sea_name", ""))),
        "institution_references": str(meta.get("institution_references",
                                               meta.get("metadata_link", ""))),
        "references":         str(meta.get("references",
                                           "http://www.ego-network.org")),
        "summary":            str(meta.get("summary", "")) or (
            f"Glider {platform_code} EGO 1.5 time-series: "
            f"{', '.join(written_params)} with real-time QC flags, "
            f"{t_start[:10]} to {t_end[:10]}."),
        "abstract":           str(meta.get("abstract", "")),
        "keywords":           str(meta.get(
            "keywords",
            "glider, CTD, temperature, salinity, conductivity, pressure, "
            "dissolved oxygen, chlorophyll, backscatter, CDOM, ocean")),

        "sdn_edmo_code":      str(meta.get("sdn_edmo_code", "")),
        "authors":            str(meta.get("authors", "")),
        "data_assembly_center": str(meta.get("institution_code",
                                             _DEFAULT_INSTITUTION_CODE)),
        "observatory":        str(meta.get("observatory", institution)),
        "deployment_label":   deployment_name,
        "doi":                str(meta.get("doi", "")),
        "citation":           str(meta.get("citation", "")) or (
            f"{institution}. Glider {platform_code} EGO time-series "
            f"({t_start[:10]} to {t_end[:10]})."),
        # 'void' is the EGO/Argo convention for a file that is not on a fixed
        # update schedule; override in deployment.yml for operational feeds.
        "update_interval":    str(meta.get("update_interval", "void")),
    }

    # ── Write output ─────────────────────────────────────────────────────────
    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    # Build encoding — do NOT set _FillValue here since it's already set
    # in each variable's attrs. Setting it in both places causes xarray to
    # raise a conflict error when writing NetCDF4.
    encoding = {}
    # Variables the spec types as `double` must stay float64. Everything else
    # that is float64 is narrowed to float32 to keep the file compact.
    _KEEP_DOUBLE = (
        "TIME", "TIME_GPS", "LATITUDE", "LONGITUDE",
        "LATITUDE_GPS", "LONGITUDE_GPS",
        "DEPLOYMENT_START_LATITUDE", "DEPLOYMENT_START_LONGITUDE",
        "DEPLOYMENT_END_LATITUDE", "DEPLOYMENT_END_LONGITUDE",
    )
    for var in ds_out.data_vars:
        da = ds_out[var]
        if np.issubdtype(da.dtype, np.floating) and da.dtype == np.float64:
            if var not in _KEEP_DOUBLE:
                encoding[var] = {"dtype": "float32"}
        # char arrays — no special encoding needed

    ds_out.to_netcdf(out_path, mode="w", format="NETCDF4", encoding=encoding)
    src_ds.close()

    elapsed = _time.time() - t0
    print(f"  EGO file written: {out_path}  ({os.path.getsize(out_path)/1024/1024:.1f} MB, {elapsed:.1f}s)")
    print(f"  Parameters: {', '.join(written_params)}")
    return out_path


def run_ego_conversion(l0_path=None, l1_path=None, deploy_yaml=None,
                       output_dir=None):
    """
    Convert both L0 and L1 to EGO format. Called by run_pipeline.py.
    Writes to output_dir/EGO-timeseries/.
    """
    if output_dir is None:
        from config import OUTPUT_DIR
        output_dir = OUTPUT_DIR

    ego_dir = os.path.join(output_dir, "EGO-timeseries")
    os.makedirs(ego_dir, exist_ok=True)

    results = {}
    if l0_path and os.path.exists(l0_path):
        base = os.path.splitext(os.path.basename(l0_path))[0]
        out = os.path.join(ego_dir, base + "_EGO.nc")
        results["ego_l0"] = convert_to_ego(l0_path, out, deploy_yaml, is_l1=False)

    if l1_path and os.path.exists(l1_path):
        base = os.path.splitext(os.path.basename(l1_path))[0]
        out = os.path.join(ego_dir, base + "_EGO.nc")
        results["ego_l1"] = convert_to_ego(l1_path, out, deploy_yaml, is_l1=True)

    return results


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Convert pipeline NetCDF to EGO 1.5")
    parser.add_argument("--l0",        default=None, help="Path to L0 NetCDF")
    parser.add_argument("--l1",        default=None, help="Path to L1 NetCDF")
    parser.add_argument("--out-l0",    default=None, help="Output path for EGO L0")
    parser.add_argument("--out-l1",    default=None, help="Output path for EGO L1")
    parser.add_argument("--deploy-yml",default=None, help="Path to deployment.yml")
    parser.add_argument("--data-mode", default="R",  help="R=real-time, D=delayed")
    parser.add_argument("--time-valid-max", default="spec",
                        choices=["spec", "physical"],
                        help="TIME/TIME_GPS valid_max: 'spec' = 90000 (passes "
                             "the official EGO checker; naive netCDF4 readers "
                             "mask TIME unless they disable auto-masking), "
                             "'physical' = 90000000000 (readable everywhere, "
                             "fails the checker on those two attributes)")
    args = parser.parse_args()

    EGO_TIME_VALID_MAX_MODE = args.time_valid_max

    if args.l0:
        out = args.out_l0 or args.l0.replace(".nc", "_EGO.nc")
        convert_to_ego(args.l0, out, args.deploy_yml, is_l1=False, data_mode=args.data_mode)
    if args.l1:
        out = args.out_l1 or args.l1.replace(".nc", "_EGO.nc")
        convert_to_ego(args.l1, out, args.deploy_yml, is_l1=True, data_mode=args.data_mode)
