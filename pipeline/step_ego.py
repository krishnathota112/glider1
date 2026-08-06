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
        standard_name=None,
        long_name="Concentration of coloured dissolved organic matter in sea water",
        sdn_param="SDN:P01::CDOMZZ01", sdn_uom="SDN:P06::UPPB",
        dtype="float", level="b",
        adjusted_src="cdom_corrected",
    ),
    "backscatter_700": dict(
        ego="BBP700", units="m-1", fill=99999.0,
        vmin=None, vmax=None,
        standard_name=None,
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


def _now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")


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
            "valid_max": np.float64(90000000000),
            "axis": "T",
            "ancillary_variable": "TIME_QC",
            "sdn_parameter_urn": "SDN:P01::ELTMEP01",
            "sdn_uom_urn": "SDN:P06::UTBB",
            "glider_original_parameter_name": "time",
        }
    )
    data_vars["TIME"] = time_da

    # TIME_QC — flag 0 (no QC performed) for all points
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
        "valid_max": np.float64(90000000000),
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
        pn = src_ds["profile_index"].values.astype(np.int32)
        pn[~np.isfinite(src_ds["profile_index"].values)] = 99999
    else:
        pn = np.full(n, 99999, dtype=np.int32)

    data_vars["PHASE_NUMBER"] = xr.DataArray(pn, dims=["TIME"], attrs={
        "long_name": "Glider trajectory phase number",
        "_FillValue": np.int32(99999),
    })


def _add_sensor_param_tables(deploy_meta, data_vars, param_list):
    """
    Add SENSOR_* and PARAMETER_* metadata arrays.
    Reads sensor info from deployment.yml metadata section.
    Falls back to generic strings when not available.
    """
    meta = deploy_meta.get("metadata", {})

    # Sensor definitions — extend from deployment.yml when available
    sensors = [
        {
            "name":   meta.get("ctd_sensor_name", "CTD"),
            "maker":  meta.get("ctd_maker", "Sea-Bird Scientific"),
            "model":  meta.get("ctd_model", "GPCTD"),
            "serial": meta.get("ctd_serial", ""),
        },
        {
            "name":   meta.get("optode_sensor_name", "AANDERAA_OPTODE"),
            "maker":  meta.get("optode_maker", "Aanderaa"),
            "model":  meta.get("optode_model", "4831"),
            "serial": meta.get("optode_serial", ""),
        },
        {
            "name":   meta.get("optics_sensor_name", "ECO_FLBBCD"),
            "maker":  meta.get("optics_maker", "Sea-Bird Scientific"),
            "model":  meta.get("optics_model", "FLBBCD"),
            "serial": meta.get("optics_serial", ""),
        },
    ]
    n_s = len(sensors)

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
    # PARAMETER_SENSOR maps each parameter to which sensor provides it
    _param_sensor_map = {
        "PRES": "CTD", "TEMP": "CTD", "PSAL": "CTD", "CNDC": "CTD",
        "DOXY": "AANDERAA_OPTODE",
        "CHLA": "ECO_FLBBCD", "CDOM": "ECO_FLBBCD", "BBP700": "ECO_FLBBCD",
        "TURBIDITY": "ECO_FLBBCD",
    }
    param_sensors = [_param_sensor_map.get(p, "CTD") for p in param_list]

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


def _add_science_vars(src_ds, data_vars, is_l1, n):
    """
    Add all science variables (TEMP, PSAL, PRES, DOXY, CHLA, CDOM, BBP700).
    For L1: writes VAR + VAR_QC + VAR_ADJUSTED + VAR_ADJUSTED_QC + VAR_ADJUSTED_ERROR.
    For L0: writes VAR only (no QC, no adjusted).
    Applies density conversion for DOXY (umol/L -> micromole/kg).
    Returns list of EGO parameter names actually written.
    """
    fill = np.float32(99999.0)

    # Pre-fetch density for DOXY conversion
    density = None
    if "density" in src_ds:
        density = src_ds["density"].values.astype(np.float64)

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
                converted[valid] = raw_vals[valid] / dens_kg_per_L[valid].astype(np.float32)
                converted[~valid] = fill
                raw_vals = converted
            else:
                print(f"  WARNING: density not available — DOXY conversion skipped, "
                      f"values remain in umol/L (label will be wrong)")

        raw_vals[~np.isfinite(raw_vals)] = fill

        # Build variable attributes
        var_attrs = {
            "units":       units,
            "_FillValue":  fill,
            "coordinates": "TIME LATITUDE LONGITUDE PRES",
            "glider_original_parameter_name": internal,
        }
        if info.get("standard_name"):
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
            # No QC available — flag 0 (not performed)
            qc_vals = np.zeros(n, dtype=np.int8)
        qc_attrs = dict(_QC_ATTRS)
        data_vars[f"{ego}_QC"] = xr.DataArray(qc_vals, dims=["TIME"], attrs=qc_attrs)

        # ── _ADJUSTED / _ADJUSTED_QC / _ADJUSTED_ERROR ───────────────────────
        # Only for non-intermediate parameters (level != 'i')
        if level == "i":
            continue

        adj_vals = np.full(n, fill, dtype=np.float32)
        if adj_src and adj_src in src_ds:
            adj_raw = src_ds[adj_src].values.astype(np.float32).copy()
            if needs_dc and density is not None:
                dens_kg_per_L = density / 1000.0
                valid = np.isfinite(adj_raw) & np.isfinite(dens_kg_per_L) & (dens_kg_per_L > 0.5)
                adj_raw[valid]  = adj_raw[valid] / dens_kg_per_L[valid].astype(np.float32)
                adj_raw[~valid] = fill
            adj_raw[~np.isfinite(adj_raw)] = fill
            adj_vals = adj_raw

        adj_attrs = dict(var_attrs)
        adj_attrs["long_name"] = info.get("long_name", ego) + " adjusted"
        data_vars[f"{ego}_ADJUSTED"] = xr.DataArray(adj_vals, dims=["TIME"],
                                                      attrs=adj_attrs)

        # _ADJUSTED_QC: use raw QC if no separate adjusted QC exists
        data_vars[f"{ego}_ADJUSTED_QC"] = xr.DataArray(
            qc_vals.copy(), dims=["TIME"], attrs=dict(_QC_ATTRS))

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
    _add_sensor_param_tables(deploy_meta, data_vars, written_params)

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

    ds_out.attrs = {
        # Mandatory
        "data_type":       "EGO glider time-series data",
        "format_version":  "1.5",
        "platform_code":   platform_code,
        "date_update":     _now_iso(),
        "data_mode":       data_mode,
        "naming_authority": "EGO",
        "id":              f"{platform_code}_{t_start[:10].replace('-','')}",
        # Optional but strongly recommended
        "Conventions":     "CF-1.4 EGO-1.5",
        "title":           f"Glider {platform_code} EGO timeseries",
        "institution":     institution,
        "source":          "Glider observation",
        "history":         f"{_now_iso()} — Converted to EGO 1.5 by step_ego.py",
        "comment":         meta.get("comment", ""),
        "project_name":    meta.get("project_name", ""),
        "deployment_code": deployment_name,
        "principal_investigator": meta.get("principal_investigator", ""),
        "geospatial_lat_min": f"{float(np.nanmin(lat_vals)):.4f}",
        "geospatial_lat_max": f"{float(np.nanmax(lat_vals)):.4f}",
        "geospatial_lon_min": f"{float(np.nanmin(lon_vals)):.4f}",
        "geospatial_lon_max": f"{float(np.nanmax(lon_vals)):.4f}",
        "time_coverage_start": t_start,
        "time_coverage_end":   t_end,
        "qc_manual":  "EGO QC Manual v1.0",
        "data_processing_chain_name":    "INCOIS Glider RTQC Pipeline",
        "data_processing_chain_version": "1.0",
        "rtqc_tests_applied": _RTQC_TESTS_APPLIED,
    }

    # ── Write output ─────────────────────────────────────────────────────────
    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    # Build encoding — do NOT set _FillValue here since it's already set
    # in each variable's attrs. Setting it in both places causes xarray to
    # raise a conflict error when writing NetCDF4.
    encoding = {}
    for var in ds_out.data_vars:
        da = ds_out[var]
        if np.issubdtype(da.dtype, np.floating) and da.dtype == np.float64:
            if var not in ("TIME", "TIME_GPS", "LATITUDE", "LONGITUDE",
                           "LATITUDE_GPS", "LONGITUDE_GPS"):
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
    args = parser.parse_args()

    if args.l0:
        out = args.out_l0 or args.l0.replace(".nc", "_EGO.nc")
        convert_to_ego(args.l0, out, args.deploy_yml, is_l1=False, data_mode=args.data_mode)
    if args.l1:
        out = args.out_l1 or args.l1.replace(".nc", "_EGO.nc")
        convert_to_ego(args.l1, out, args.deploy_yml, is_l1=True, data_mode=args.data_mode)
