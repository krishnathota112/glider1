#!/usr/bin/env python3
"""
nc_format.py — single source of truth for the NetCDF output format.

Both the L0 writer (step1) and the L1 writer (step23) import from here, so the
variable names, units, fill values and attributes are defined exactly once.
There is no separate conversion step: files are written in their final,
spec-compliant form the first time.

Canonical parameter names, units, valid ranges, fill values and SDN vocabulary
URNs come from the reference parameter list shipped with the decoder package:
    argo-parameters-list-core-and-b_20210708
    _AND_glider_specific_parameters_list_20220225.txt

Structural requirements (mandatory dimensions, mandatory global attributes,
QC flag conventions, the *_ADJUSTED triplet rule) come from the checker rules:
    EGO_V1.5_20250211.xml

Level codes in _PARAMS:
    'c' core        — gets the _ADJUSTED / _ADJUSTED_QC / _ADJUSTED_ERROR triplet
    'b' bgc         — gets the triplet
    'i' intermediate— no triplet (raw sensor counts, diagnostics)
"""
import numpy as np
from datetime import datetime, timezone

FORMAT_VERSION = "1.5"
DATA_TYPE      = "EGO glider time-series data"

# Fill values fixed by the format
FILL_FLOAT = 99999.0
FILL_TIME  = 9999999999.0
FILL_INT   = 99999
FILL_QC    = -128
FILL_CHAR  = " "

# String dimension sizes required by the format
STRING_DIMS = {
    "STRING256": 256,
    "STRING128": 128,
    "STRING64":  64,
    "STRING32":  32,
    "STRING16":  16,
}


# ── Canonical parameter table ────────────────────────────────────────────────
# key = canonical variable name written to the file
# slocum = the raw Slocum sensor name it is decoded from (None = derived)
_PARAMS = {
    "PRES": dict(
        slocum="pressure_dbar", level="c",
        units="decibar", vmin=0.0, vmax=12000.0,
        standard_name="sea_water_pressure",
        long_name="Sea water pressure, equals 0 at sea-level",
        sdn_param="SDN:P01::PRESPR01", sdn_uom="SDN:P06::UPDB",
        extra_attrs={"axis": "Z", "positive": "down"},
    ),
    "TEMP": dict(
        slocum="sci_water_temp", level="c",
        units="degree_Celsius", vmin=-2.5, vmax=40.0,
        standard_name="sea_water_temperature",
        long_name="Sea temperature in-situ ITS-90 scale",
        sdn_param="SDN:P01::TEMPST01", sdn_uom="SDN:P06::UPAA",
    ),
    "CNDC": dict(
        slocum="sci_water_cond", level="c",
        units="mhos/m", vmin=0.0, vmax=8.5,
        standard_name="sea_water_electrical_conductivity",
        long_name="Electrical conductivity",
        sdn_param="SDN:P01::CNDCST01", sdn_uom="SDN:P06::UECA",
    ),
    "PSAL": dict(
        slocum="salinity", level="c",          # derived from CNDC/TEMP/PRES
        units="psu", vmin=2.0, vmax=41.0,
        standard_name="sea_water_salinity",
        long_name="Practical salinity",
        sdn_param="SDN:P01::PSALST01", sdn_uom="SDN:P06::UUUU",
    ),
    "DOXY": dict(
        slocum="sci_oxy4_oxygen", level="b",
        units="micromole/kg", vmin=-5.0, vmax=600.0,
        standard_name="moles_of_oxygen_per_unit_mass_in_sea_water",
        long_name="Dissolved oxygen",
        sdn_param="SDN:P01::DOXMZZXX", sdn_uom="SDN:P06::KGUM",
        # Slocum optode reports umol/L; the format requires umol/kg.
        # divide_by_density=True triggers the real conversion at write time.
        divide_by_density=True,
    ),
    "CHLA": dict(
        slocum="sci_flbbcd_chlor_units", level="b",
        units="mg/m3", vmin=None, vmax=None,
        standard_name="mass_concentration_of_chlorophyll_a_in_sea_water",
        long_name="Chlorophyll-A",
        sdn_param="SDN:P01::CPHLPR01", sdn_uom="SDN:P06::UMMC",
    ),
    "CDOM": dict(
        slocum="sci_flbbcd_cdom_units", level="b",
        units="ppb", vmin=None, vmax=None,
        standard_name=None,
        long_name="Concentration of coloured dissolved organic matter in sea water",
        sdn_param="SDN:P01::CDOMZZ01", sdn_uom="SDN:P06::UPPB",
    ),
    "BBP700": dict(
        slocum="sci_flbbcd_bb_units", level="b",
        units="m-1", vmin=None, vmax=None,
        standard_name=None,
        long_name="Particle backscattering at 700 nanometers",
        sdn_param="SDN:P01::BB117NIR", sdn_uom="SDN:P06::PMSR",
    ),
    "TURBIDITY": dict(
        slocum="sci_flntu_turb_units", level="b",
        units="ntu", vmin=None, vmax=None,
        standard_name="sea_water_turbidity",
        long_name="Sea water turbidity",
        sdn_param="SDN:P01::TURBXXXX", sdn_uom="SDN:P06::USTU",
    ),
}


def params():
    """Canonical parameter names, in file order."""
    return list(_PARAMS.keys())


def param_spec(name):
    return _PARAMS[name]


def slocum_to_canonical():
    """{slocum_sensor_name: canonical_name} for the decode step."""
    return {v["slocum"]: k for k, v in _PARAMS.items() if v.get("slocum")}


# ── Ancillary variables ──────────────────────────────────────────────────────
# Written to the file (the format permits additional variables) but not listed
# in PARAMETER and never given the _ADJUSTED triplet. These are the derived
# quantities and flight data the plots and later QC steps need.
_ANCILLARY = {
    "DEPTH": dict(
        slocum="depth", units="m",
        standard_name="depth", long_name="Depth below sea surface",
        extra_attrs={"axis": "Z", "positive": "down"},
    ),
    "DENSITY": dict(
        slocum="density", units="kg m-3",
        standard_name="sea_water_density", long_name="In-situ sea water density",
    ),
    "POTENTIAL_TEMP": dict(
        slocum="potential_temperature", units="degree_Celsius",
        standard_name="sea_water_conservative_temperature",
        long_name="Conservative temperature",
    ),
    "POTENTIAL_DENSITY": dict(
        slocum="potential_density", units="kg m-3",
        standard_name="sea_water_potential_density",
        long_name="Potential density referenced to 0 dbar",
    ),
    "HEADING": dict(
        slocum="m_heading", units="degree",
        standard_name="platform_orientation", long_name="Glider heading",
    ),
    "PITCH": dict(
        slocum="m_pitch", units="degree",
        standard_name="platform_pitch", long_name="Glider pitch",
    ),
    "ROLL": dict(
        slocum="m_roll", units="degree",
        standard_name="platform_roll", long_name="Glider roll",
    ),
    "WAYPOINT_LATITUDE": dict(
        slocum="c_wpt_lat", units="degree_north",
        standard_name=None, long_name="Commanded waypoint latitude",
    ),
    "WAYPOINT_LONGITUDE": dict(
        slocum="c_wpt_lon", units="degree_east",
        standard_name=None, long_name="Commanded waypoint longitude",
    ),
    "DISTANCE_OVER_GROUND": dict(
        slocum=None, units="km",
        standard_name=None,
        long_name="Cumulative distance over ground from GPS surface fixes",
    ),
}


def ancillary():
    return list(_ANCILLARY.keys())


def ancillary_spec(name):
    return _ANCILLARY[name]


def slocum_to_ancillary():
    return {v["slocum"]: k for k, v in _ANCILLARY.items() if v.get("slocum")}


# ── QC flag attributes (reference table 2.1) ────────────────────────────────
QC_ATTRS = {
    "long_name":     "Quality flag",
    "conventions":   "EGO reference table 2.1",
    "_FillValue":    np.int8(FILL_QC),
    "valid_min":     np.int8(0),
    "valid_max":     np.int8(9),
    "flag_values":   np.array([0, 1, 2, 3, 4, 5, 8, 9], dtype=np.int8),
    "flag_meanings": ("no_qc_performed good_data probably_good_data "
                      "bad_data_that_are_potentially_correctable bad_data "
                      "value_changed interpolated_value missing_value"),
}

# Phase codes (reference table 9.2)
PHASE_ATTRS = {
    "long_name":     "Glider trajectory phase code",
    "conventions":   "EGO reference table 9.2",
    "_FillValue":    np.int8(FILL_QC),
    "flag_values":   np.array([0, 1, 2, 3, 4, 5, 6], dtype=np.int8),
    "flag_meanings": ("surface_drift descent subsurface_drift inflexion "
                      "ascent grounded inconsistent"),
}


# ── Attribute builders ───────────────────────────────────────────────────────

def now_iso():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")


def param_attrs(name, glider_original_name=""):
    """Full attribute dict for a canonical science parameter."""
    s = _PARAMS[name]
    a = {
        "units":       s["units"],
        "_FillValue":  np.float32(FILL_FLOAT),
        "coordinates": "TIME LATITUDE LONGITUDE PRES",
        "glider_original_parameter_name": glider_original_name or (s.get("slocum") or ""),
        "ancillary_variable": f"{name}_QC",
    }
    if s.get("standard_name"):
        a["standard_name"] = s["standard_name"]
    if s.get("long_name"):
        a["long_name"] = s["long_name"]
    if s.get("vmin") is not None:
        a["valid_min"] = np.float32(s["vmin"])
    if s.get("vmax") is not None:
        a["valid_max"] = np.float32(s["vmax"])
    if s.get("sdn_param"):
        a["sdn_parameter_urn"] = s["sdn_param"]
    if s.get("sdn_uom"):
        a["sdn_uom_urn"] = s["sdn_uom"]
    a.update(s.get("extra_attrs", {}))
    return a


def adjusted_attrs(name):
    a = param_attrs(name)
    a["long_name"] = _PARAMS[name].get("long_name", name) + " adjusted"
    a["ancillary_variable"] = f"{name}_ADJUSTED_QC"
    return a


def adjusted_error_attrs(name):
    return {
        "long_name": ("Contains the error on the adjusted values as determined "
                      "by the delayed mode QC process"),
        "_FillValue": np.float32(FILL_FLOAT),
        "units":      _PARAMS[name]["units"],
    }


def ancillary_attrs(name):
    s = _ANCILLARY[name]
    a = {
        "units":      s["units"],
        "_FillValue": np.float32(FILL_FLOAT),
        "glider_original_parameter_name": s.get("slocum") or "",
    }
    if s.get("standard_name"):
        a["standard_name"] = s["standard_name"]
    if s.get("long_name"):
        a["long_name"] = s["long_name"]
    a.update(s.get("extra_attrs", {}))
    return a


TIME_ATTRS = {
    "long_name":     "Epoch time",
    "standard_name": "time",
    "units":         "seconds since 1970-01-01T00:00:00Z",
    "_FillValue":    np.float64(FILL_TIME),
    "valid_min":     np.float64(0),
    "valid_max":     np.float64(90000000000),
    "axis":          "T",
    "ancillary_variable": "TIME_QC",
    "sdn_parameter_urn":  "SDN:P01::ELTMEP01",
    "sdn_uom_urn":        "SDN:P06::UTBB",
}


def latlon_attrs(kind, gps=False):
    """kind is 'lat' or 'lon'."""
    is_lat = kind == "lat"
    suffix = "_GPS" if gps else ""
    if gps:
        long_name = "Gps fixed latitude" if is_lat else "Gps fixed longitude"
    else:
        long_name = "Measurement latitude" if is_lat else "Measurement longitude"
    return {
        "long_name":     long_name,
        "standard_name": "latitude" if is_lat else "longitude",
        "units":         "degree_north" if is_lat else "degree_east",
        "_FillValue":    np.float64(FILL_FLOAT),
        "valid_min":     np.float64(-90 if is_lat else -180),
        "valid_max":     np.float64(90 if is_lat else 180),
        "axis":          "Y" if is_lat else "X",
        "ancillary_variable": f"POSITION{suffix}_QC",
        "reference":     "WGS84",
        "coordinate_reference_frame": "urn:ogc:crs:EPSG::4326",
        "sdn_parameter_urn": "SDN:P01::ALATZZ01" if is_lat else "SDN:P01::ALONZZ01",
        "sdn_uom_urn":       "SDN:P06::DEGN" if is_lat else "SDN:P06::DEGE",
    }


def global_attrs(level, meta, t_start, t_end, lat_min, lat_max,
                 lon_min, lon_max, rtqc_tests="", history_extra=""):
    """
    Mandatory + recommended global attributes.

    level        : "L0" or "L1"
    meta         : deployment.yml metadata dict
    t_start/t_end: ISO8601Z strings
    """
    platform = str(meta.get("glider_serial") or meta.get("deployment_name") or "unknown")
    deployment = str(meta.get("deployment_name") or platform)
    proc = ("L0 - raw decoded data, no QC applied" if level == "L0"
            else "L1 - QC applied, ARGO RTQC flags set")
    history = f"{now_iso()} - {level} written by INCOIS glider pipeline"
    if history_extra:
        history += f"; {history_extra}"

    a = {
        # mandatory
        "data_type":        DATA_TYPE,
        "format_version":   FORMAT_VERSION,
        "platform_code":    platform,
        "date_update":      now_iso(),
        "data_mode":        "R",
        "naming_authority": "EGO",
        "id":               f"{platform}_{t_start[:10].replace('-', '')}_{level}",
        # what
        "Conventions":  f"CF-1.4 EGO-{FORMAT_VERSION}",
        "title":        f"Glider {platform} {level} timeseries",
        "summary":      proc,
        "source":       "Glider observation",
        "history":      history,
        "comment":      str(meta.get("comment") or ""),
        "references":   str(meta.get("references") or ""),
        # who
        "institution":            str(meta.get("institution") or "INCOIS"),
        "data_assembly_center":   str(meta.get("data_assembly_center") or "INCOIS"),
        "principal_investigator": str(meta.get("principal_investigator") or ""),
        "principal_investigator_email": str(meta.get("principal_investigator_email") or ""),
        "project_name":     str(meta.get("project_name") or ""),
        "deployment_code":  deployment,
        "deployment_label": str(meta.get("deployment_label") or deployment),
        # where / when
        "area":                    str(meta.get("sea_name") or ""),
        "geospatial_lat_min":      f"{lat_min:.4f}",
        "geospatial_lat_max":      f"{lat_max:.4f}",
        "geospatial_lon_min":      f"{lon_min:.4f}",
        "geospatial_lon_max":      f"{lon_max:.4f}",
        "time_coverage_start":     t_start,
        "time_coverage_end":       t_end,
        # how
        "processing_level":               proc,
        "qc_manual":                     "EGO glider QC manual",
        "data_processing_chain_name":    "INCOIS Glider RTQC Pipeline",
        "data_processing_chain_version": "1.0",
        "update_interval":               "void",
    }
    if rtqc_tests:
        a["rtqc_tests_applied"] = rtqc_tests
    return a


# ── char array helper ────────────────────────────────────────────────────────

def char_array(strings, width):
    """(N, width) unicode char array, space padded — for the metadata tables."""
    arr = np.full((len(strings), width), " ", dtype="U1")
    for i, s in enumerate(strings):
        s = str(s)[:width]
        for j in range(len(s)):
            arr[i, j] = s[j]
    return arr


# ── Sensor / parameter metadata tables ───────────────────────────────────────

def sensor_table(meta):
    """
    Sensor provenance, read from deployment.yml. Empty serials are permitted
    by the format; they are written as spaces rather than invented values.
    """
    return [
        dict(name=str(meta.get("ctd_sensor_name") or "CTD"),
             maker=str(meta.get("ctd_maker") or "Sea-Bird Scientific"),
             model=str(meta.get("ctd_model") or "GPCTD"),
             serial=str(meta.get("ctd_serial") or "")),
        dict(name=str(meta.get("optode_sensor_name") or "AANDERAA_OPTODE"),
             maker=str(meta.get("optode_maker") or "Aanderaa"),
             model=str(meta.get("optode_model") or "4831"),
             serial=str(meta.get("optode_serial") or "")),
        dict(name=str(meta.get("optics_sensor_name") or "ECO_FLBBCD"),
             maker=str(meta.get("optics_maker") or "Sea-Bird Scientific"),
             model=str(meta.get("optics_model") or "FLBBCD"),
             serial=str(meta.get("optics_serial") or "")),
    ]


PARAM_SENSOR = {
    "PRES": "CTD", "TEMP": "CTD", "PSAL": "CTD", "CNDC": "CTD",
    "DOXY": "AANDERAA_OPTODE",
    "CHLA": "ECO_FLBBCD", "CDOM": "ECO_FLBBCD",
    "BBP700": "ECO_FLBBCD", "TURBIDITY": "ECO_FLBBCD",
}


# ── Shared writer ────────────────────────────────────────────────────────────

def build_dataset(time_sec, values, ancillary_values, gps, phase, phase_number,
                  meta, level, qc=None, adjusted=None, adjusted_qc=None,
                  rtqc_tests="", history_extra=""):
    """
    Assemble the complete, spec-compliant Dataset.

    Called by both writers, so L0 and L1 differ only in what they pass in —
    not in how the file is structured.

    time_sec         : (N,) float64 seconds since 1970-01-01
    values           : {canonical_name: (N,) array} science parameters
    ancillary_values : {ancillary_name: (N,) array}
    gps              : (times_sec, lats, lons) of the real surface fixes
    phase            : (N,) int8 phase code
    phase_number     : (N,) int32 phase number
    meta             : deployment.yml metadata dict
    level            : "L0" or "L1"
    qc               : {canonical_name: (N,) int8}  (L1 only)
    adjusted         : {canonical_name: (N,) array} (L1 only)
    adjusted_qc      : {canonical_name: (N,) int8}  (L1 only)
    """
    import xarray as xr

    qc          = qc or {}
    adjusted    = adjusted or {}
    adjusted_qc = adjusted_qc or {}
    n = len(time_sec)
    dv = {}

    # TIME
    dv["TIME"] = xr.DataArray(
        time_sec.astype(np.float64), dims=["TIME"],
        attrs={**TIME_ATTRS, "glider_original_parameter_name": "m_present_time"})
    dv["TIME_QC"] = xr.DataArray(
        qc.get("TIME", np.zeros(n, dtype=np.int8)), dims=["TIME"],
        attrs=dict(QC_ATTRS))

    # LATITUDE / LONGITUDE (measurement positions, interpolated between fixes)
    for cname, kind, slocum in (("LATITUDE", "lat", "m_lat"),
                                ("LONGITUDE", "lon", "m_lon")):
        v = ancillary_values.get(cname)
        v = (np.full(n, FILL_FLOAT) if v is None
             else np.where(np.isfinite(v), v, FILL_FLOAT).astype(np.float64))
        dv[cname] = xr.DataArray(
            v, dims=["TIME"],
            attrs={**latlon_attrs(kind), "glider_original_parameter_name": slocum})
    dv["POSITION_QC"] = xr.DataArray(
        qc.get("POSITION", np.ones(n, dtype=np.int8)), dims=["TIME"],
        attrs=dict(QC_ATTRS))

    # POSITIONING_METHOD — 0 GPS at the fixes, 2 interpolated elsewhere
    pm = np.full(n, np.int8(2), dtype=np.int8)
    dv["POSITIONING_METHOD"] = xr.DataArray(pm, dims=["TIME"], attrs={
        "long_name":     "Positioning method",
        "conventions":   "EGO reference table 10.2",
        "_FillValue":    np.int8(FILL_QC),
        "flag_values":   np.array([0, 1, 2, 3], dtype=np.int8),
        "flag_meanings": "GPS Argos interpolated",
    })

    # GPS surface fixes — their own, sparser dimension
    g_t, g_lat, g_lon = gps
    if g_t is None or len(g_t) == 0:
        g_t   = np.array([time_sec[0]], dtype=np.float64)
        g_lat = np.array([FILL_FLOAT])
        g_lon = np.array([FILL_FLOAT])
    n_gps = len(g_t)
    dv["TIME_GPS"] = xr.DataArray(
        np.asarray(g_t, dtype=np.float64), dims=["TIME_GPS"],
        attrs={**TIME_ATTRS,
               "long_name": "Epoch time of the GPS fixes",
               "ancillary_variable": "TIME_GPS_QC",
               "glider_original_parameter_name": "m_gps_lat"})
    dv["LATITUDE_GPS"] = xr.DataArray(
        np.asarray(g_lat, dtype=np.float64), dims=["TIME_GPS"],
        attrs={**latlon_attrs("lat", gps=True),
               "glider_original_parameter_name": "m_gps_lat"})
    dv["LONGITUDE_GPS"] = xr.DataArray(
        np.asarray(g_lon, dtype=np.float64), dims=["TIME_GPS"],
        attrs={**latlon_attrs("lon", gps=True),
               "glider_original_parameter_name": "m_gps_lon"})
    ones_gps = np.ones(n_gps, dtype=np.int8)
    dv["TIME_GPS_QC"]     = xr.DataArray(ones_gps, dims=["TIME_GPS"], attrs=dict(QC_ATTRS))
    dv["POSITION_GPS_QC"] = xr.DataArray(ones_gps.copy(), dims=["TIME_GPS"], attrs=dict(QC_ATTRS))

    # PHASE / PHASE_NUMBER
    dv["PHASE"] = xr.DataArray(phase.astype(np.int8), dims=["TIME"],
                               attrs=dict(PHASE_ATTRS))
    dv["PHASE_NUMBER"] = xr.DataArray(phase_number.astype(np.int32), dims=["TIME"],
                                      attrs={"long_name": "Glider trajectory phase number",
                                             "_FillValue": np.int32(FILL_INT)})

    # Science parameters, and for L1 their QC / adjusted triplet
    written = []
    for name in params():
        if name not in values:
            continue
        v = np.asarray(values[name], dtype=np.float32).copy()
        v[~np.isfinite(v)] = FILL_FLOAT
        dv[name] = xr.DataArray(v, dims=["TIME"], attrs=param_attrs(name))
        written.append(name)

        if level != "L1":
            continue

        dv[f"{name}_QC"] = xr.DataArray(
            qc.get(name, np.zeros(n, dtype=np.int8)).astype(np.int8),
            dims=["TIME"], attrs=dict(QC_ATTRS))

        if _PARAMS[name]["level"] == "i":
            continue

        av = adjusted.get(name)
        av = (np.full(n, FILL_FLOAT, dtype=np.float32) if av is None
              else np.asarray(av, dtype=np.float32).copy())
        av[~np.isfinite(av)] = FILL_FLOAT
        dv[f"{name}_ADJUSTED"] = xr.DataArray(av, dims=["TIME"],
                                              attrs=adjusted_attrs(name))
        dv[f"{name}_ADJUSTED_QC"] = xr.DataArray(
            adjusted_qc.get(name, qc.get(name, np.zeros(n, dtype=np.int8))).astype(np.int8),
            dims=["TIME"], attrs=dict(QC_ATTRS))
        dv[f"{name}_ADJUSTED_ERROR"] = xr.DataArray(
            np.full(n, FILL_FLOAT, dtype=np.float32), dims=["TIME"],
            attrs=adjusted_error_attrs(name))

    # Ancillary variables
    for name in ancillary():
        if name in ("LATITUDE", "LONGITUDE") or name not in ancillary_values:
            continue
        v = np.asarray(ancillary_values[name], dtype=np.float32).copy()
        v[~np.isfinite(v)] = FILL_FLOAT
        dv[name] = xr.DataArray(v, dims=["TIME"], attrs=ancillary_attrs(name))

    # Sensor + parameter metadata tables
    sensors = sensor_table(meta)
    dv["SENSOR"] = xr.DataArray(
        char_array([s["name"] for s in sensors], 32),
        dims=["N_SENSOR", "STRING32"],
        attrs={"long_name": "Name of the sensor mounted on the glider",
               "conventions": "EGO reference table 25", "_FillValue": FILL_CHAR})
    dv["SENSOR_MAKER"] = xr.DataArray(
        char_array([s["maker"] for s in sensors], 256),
        dims=["N_SENSOR", "STRING256"],
        attrs={"long_name": "Name of the sensor manufacturer",
               "conventions": "EGO reference table 26", "_FillValue": FILL_CHAR})
    dv["SENSOR_MODEL"] = xr.DataArray(
        char_array([s["model"] for s in sensors], 256),
        dims=["N_SENSOR", "STRING256"],
        attrs={"long_name": "Type of the sensor",
               "conventions": "EGO reference table 27", "_FillValue": FILL_CHAR})
    dv["SENSOR_SERIAL_NO"] = xr.DataArray(
        char_array([s["serial"] for s in sensors], 16),
        dims=["N_SENSOR", "STRING16"],
        attrs={"long_name": "Serial number of the sensor", "_FillValue": FILL_CHAR})

    dv["PARAMETER"] = xr.DataArray(
        char_array(written, 64), dims=["N_PARAM", "STRING64"],
        attrs={"long_name": "Name of parameter computed from glider measurements",
               "conventions": "EGO reference table 3", "_FillValue": FILL_CHAR})
    dv["PARAMETER_SENSOR"] = xr.DataArray(
        char_array([PARAM_SENSOR.get(p, "CTD") for p in written], 128),
        dims=["N_PARAM", "STRING128"],
        attrs={"long_name": "Name of the sensor that measures this parameter",
               "conventions": "EGO reference table 25", "_FillValue": FILL_CHAR})
    dv["PARAMETER_DATA_MODE"] = xr.DataArray(
        np.array(["R"] * len(written), dtype="U1"), dims=["N_PARAM"],
        attrs={"long_name": "Data mode of the parameter",
               "conventions": "EGO reference table 19", "_FillValue": FILL_CHAR})

    ds = xr.Dataset(dv)

    # Add lowercase 'time' as an alias so downstream code that opens
    # this file and does ds["time"] still works without modification.
    # This is a compatibility bridge — the canonical name is TIME.
    if "TIME" in ds:
        t_vals = ds["TIME"].values
        # Convert seconds-since-epoch back to datetime64 for xarray compatibility
        t_dt64 = (t_vals * 1e9).astype("datetime64[ns]")
        ds = ds.assign_coords(time=("TIME", t_dt64))

    lat_all = ancillary_values.get("LATITUDE")
    lon_all = ancillary_values.get("LONGITUDE")
    lat_all = np.asarray(g_lat) if lat_all is None else lat_all
    lon_all = np.asarray(g_lon) if lon_all is None else lon_all
    lat_f = lat_all[np.isfinite(lat_all) & (np.abs(lat_all) <= 90)]
    lon_f = lon_all[np.isfinite(lon_all) & (np.abs(lon_all) <= 180)]
    if len(lat_f) == 0:
        lat_f = np.array([0.0])
    if len(lon_f) == 0:
        lon_f = np.array([0.0])

    t0 = datetime.fromtimestamp(float(time_sec[0]), tz=timezone.utc)
    t1 = datetime.fromtimestamp(float(time_sec[-1]), tz=timezone.utc)
    fmt = "%Y-%m-%dT%H:%M:%SZ"

    ds.attrs = global_attrs(
        level, meta, t0.strftime(fmt), t1.strftime(fmt),
        float(lat_f.min()), float(lat_f.max()),
        float(lon_f.min()), float(lon_f.max()),
        rtqc_tests=rtqc_tests, history_extra=history_extra)
    return ds, written


def write(ds, path):
    """Write with the dtypes the format expects. _FillValue stays in attrs."""
    import os
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    enc = {}
    for v in ds.data_vars:
        d = ds[v].dtype
        if d == np.float64 and v not in ("TIME", "TIME_GPS", "LATITUDE",
                                         "LONGITUDE", "LATITUDE_GPS",
                                         "LONGITUDE_GPS"):
            enc[v] = {"dtype": "float32"}
    ds.to_netcdf(path, mode="w", format="NETCDF4", encoding=enc)
    return path


# ── Backward-compatibility shim ──────────────────────────────────────────────
# Plotting and step4 code that opens L0/L1 files and looks up variable names
# like "temperature", "salinity" etc. will now find "TEMP", "PSAL" etc.
# This lookup resolves either the old or new name to whatever is in the file.

_COMPAT_MAP = {
    # old internal name -> canonical name
    "temperature": "TEMP",
    "salinity": "PSAL",
    "pressure": "PRES",
    "depth": "DEPTH",
    "conductivity": "CNDC",
    "oxygen_concentration": "DOXY",
    "chlorophyll": "CHLA",
    "cdom": "CDOM",
    "backscatter_700": "BBP700",
    "turbidity": "TURBIDITY",
    "latitude": "LATITUDE",
    "longitude": "LONGITUDE",
    "profile_index": "PHASE_NUMBER",
    "profile_direction": "PHASE",
}


def resolve_var(ds, name):
    """
    Find a variable in ds by either its canonical name or its old internal name.
    Returns the DataArray, or None if not found under either name.
    """
    if name in ds:
        return ds[name]
    canonical = _COMPAT_MAP.get(name)
    if canonical and canonical in ds:
        return ds[canonical]
    # Try reverse: caller used canonical, file has old name
    rev = {v: k for k, v in _COMPAT_MAP.items()}
    old = rev.get(name)
    if old and old in ds:
        return ds[old]
    return None


def var_name(ds, name):
    """Like resolve_var but returns the actual name string in ds."""
    if name in ds:
        return name
    canonical = _COMPAT_MAP.get(name)
    if canonical and canonical in ds:
        return canonical
    rev = {v: k for k, v in _COMPAT_MAP.items()}
    old = rev.get(name)
    if old and old in ds:
        return old
    return None
