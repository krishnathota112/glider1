# Glider RTQC Pipeline — Design Document

## Overview

Single command to process any Slocum glider deployment end-to-end:

```bash
bash run_pipeline.sh /path/to/deployment_folder
```

Produces: L0 products, L1 products (QC'd), EGO-compliant NetCDF, plots, reports, and database ingestion.

---

## Pipeline Flow

```
Raw Binary Files (.dbd/.ebd/.dcd/.ecd)
         │
         ▼
┌─────────────────────────────────────────────┐
│  STEP 1: Binary → L0 NetCDF                 │
│  • Decode via dbdreader                     │
│  • Sync flight + science onto unified time  │
│  • Derive: salinity, density, depth         │
│  • Detect profiles (pressure inflections)   │
│  • Write L0 timeseries NetCDF               │
└─────────────────────────────────────────────┘
         │
         ├──→ L0-timeseries/*.nc
         ├──→ L0-profiles/ (one .nc per dive)
         ├──→ L0-gridfiles/ (time × depth grid)
         │
         ▼
┌─────────────────────────────────────────────┐
│  STEP 2/3: L0 → L1 (QC + ARGO Flags)        │
│                                             │
│  Pre-clean:                                 │
│    • Time crop (deployment.yml window)      │
│    • Shallow test-dive segmentation         │
│    • Physical range guard (T, S, O2)        │
│    • Zero-GPS NaN'ing                       │
│    • Hemisphere filter                      │
│                                             │
│  Corruption detection:                      │
│    • Optics vs pressure identity check      │
│    • (only fires if values are NUMERICALLY  │
│      identical, not just correlated)        │
│                                             │
│  Optics QC (GliderTools-style):             │
│    • IQR outlier removal                    │
│    • In-situ dark count subtraction         │
│    • Zhang backscatter correction           │
│    • Median despike                         │
│    • Bad profile detection                  │
│    • Quenching correction (day/night)       │
│    → Writes *_corrected variables           │
│                                             │
│  Physics QC:                                │
│    • Per-profile IQR (T/S/O2)               │
│    • Median despike                         │
│    • Savitzky-Golay smoothing per profile   │
│    • Horizontal diff outliers (salinity)    │
│    → Writes *_processed variables           │
│                                             │
│  Oxygen lag correction:                     │
│    • First-order tau=30s, profile-aware     │
│    Writes oxygen_concentration_lag_corrected│
│                                             │
│  ARGO RTQC Flag Assignment:                 │
│    • Test 2:  Impossible date               │
│    • Test 3:  Impossible location           │
│    • Test 5:  Impossible speed              │
│    • Test 6:  Global range                  │
│    • Test 8:  Pressure increasing           │
│    • Test 9:  Spike test                    │
│    • Test 13: Stuck value                   │
│    • Test 14: Density inversion             │
│    • Test 16: Gross sensor drift            │
│    • Test 19: Deepest pressure              │
│    • Pressure cascade (QC=4 → T/S/O2)       │
│    • Temperature cascade → salinity         │
│                                             │
│  Flag logic:                                │
│    • _raise_flag() — severity-ordered,      │
│      never downgrades a harsher flag        │
│    • l0_nan_mask distinguishes "originally  │
│      missing" (flag 9) from "QC-removed"    │
│      (flag 4)                               │
│                                             │
│  Write L1 timeseries NetCDF                 │
└─────────────────────────────────────────────┘
         │
         ├──→ L1-timeseries/*.nc
         ├──→ L1-profiles/ (one .nc per dive, QC-masked)
         ├──→ L1-gridfiles/ (time × depth, QC flags 1&2 only)
         │
         ▼
┌─────────────────────────────────────────────┐
│  STEP 5: Plotting                           │
│                                             │
│  • L0 gridplot (raw, all values)            │
│  • L1 gridplot (QC good only)               │
│  • Individual variable section plots        │
│    (uses pre-built grid, pcolormesh)        │
│  • Physical range guard on colorscale       │
│  • Time gap masking (>48h → white)          │
└─────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────┐
│  STEP 6: Diagnostics & Report               │
│                                             │
│  • Track map (GPS positions)                │
│  • T-S diagram (temperature vs salinity,    │
│    coloured by depth, density contours)     │
│  • Data coverage matrix                     │
│  • Mixed Layer Depth                        │
│  • Sensor failure detection:                │
│    - Simultaneous-stop grouping             │
│    - Never-installed vs mid-mission failure │
│    - Oxygen bad-block detection (from QC)   │
│  • Summary report (.txt):                   │
│    - Deployment metadata                    │
│    - QC flag summary per variable           │
│    - Data gaps >48h                         │
│    - Track distance (GPS fixes only)        │
└─────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────┐
│  STEP 7: Oceanographic Sections             │
│                                             │
│  • Contour sections (T, S, O2, density)     │
│  • Optics contour sections                  │
│  • Profile envelopes (min/max/median)       │
│  • Surface properties timeseries            │
│  • Isotherm/isohaline depth tracking        │
│  • Hovmöller anomaly                        │
│  • Vertical gradients                       │
│  • T-S density diagram (time + depth color) │
│  • Overview section (5-panel summary)       │
└─────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────┐
│  STEP EGO: EGO 1.5 NetCDF Conversion        │
│                                             │
│  • Variable renaming → ARGO/EGO canonical:  │
│    temperature → TEMP                       │
│    salinity → PSAL                          │
│    pressure → PRES                          │
│    oxygen_concentration → DOXY              │
│    chlorophyll → CHLA                       │
│    cdom → CDOM                              │
│    backscatter_700 → BBP700                 │
│                                             │
│  • DOXY unit conversion:                    │
│    umol/L ÷ (density_kg_m3 / 1000)          │
│    = micromole/kg (real arithmetic)         │
│                                             │
│  • Mandatory EGO structure:                 │
│    - TIME_GPS / LATITUDE_GPS / LONGITUDE_GPS│
│    - PHASE / PHASE_NUMBER                   │
│    - SENSOR / SENSOR_MAKER / SENSOR_MODEL   │
│    - PARAMETER / PARAMETER_SENSOR           │
│    - *_ADJUSTED / *_ADJUSTED_QC             │
│    - *_ADJUSTED_ERROR                       │
│    - All mandatory global attributes        │
│    - QC ref table 2.1 conventions           │
└─────────────────────────────────────────────┘
         │
         ├──→ EGO-timeseries/*.nc
         │
         ▼
┌─────────────────────────────────────────────┐
│  VERIFY: Automated Integrity Checks         │
│                                             │
│  • New-dataset checks:                      │
│    - Optics corruption (value=pressure?)    │
│    - Mission gap detection                  │
│    - Sample cadence verification            │
│  • GPS anomalies (jumps >50km)              │
│  • T-S plausibility                         │
│  • QC flag consistency                      │
│  • L0 vs L1 comparison                      │
└─────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────┐
│  DB INGESTION (load_deployment.py)          │
│                                             │
│  • Reads EGO NetCDF files                   │
│  • 4-table SQLite schema:                   │
│    - deployment (metadata)                  │
│    - observation (time, position, depth)    │
│    - core (PRES, TEMP, PSAL, CNDC)          │
│    - bgc (DOXY, CHLA, CDOM, BBP700, ...)    │
│  • Pattern A: value, qc_flag,               │
│    value_adjusted, adjusted_qc_flag         │
│  • Idempotent (deterministic observation_id)│
│  • Safe to re-run on same deployment        │
└─────────────────────────────────────────────┘

---

## Output Directory Structure

```
<deployment>/output/
├── L0-timeseries/       # Raw decoded timeseries
├── L0-profiles/         # One .nc per dive/climb
├── L0-gridfiles/        # Depth × time grid (all values)
├── L1-timeseries/       # QC-processed timeseries
├── L1-profiles/         # Per-profile, QC-masked
├── L1-gridfiles/        # Depth × time grid (QC good only)
├── EGO-timeseries/      # EGO 1.5 compliant NetCDF
├── plots/               # All PNG diagnostic plots
└── reports/             # Summary text report
```

---

## Key Design Decisions

| Decision | Rationale |
|---|---|
| Single entry point (`bash run_pipeline.sh /path`) | No manual config edits per deployment |
| Auto-detection over hardcoded parameters | GPS bounds, depth, year, factory tests — all discovered from data |
| Signal-based segmentation (not date heuristics) | Works across deployments with different test-dive patterns |
| `_raise_flag()` severity ordering | Later QC tests cannot downgrade earlier, harsher verdicts |
| `l0_nan_mask` snapshot before any QC runs | Distinguishes "sensor never recorded" from "QC removed" |
| Corruption detection requires numeric identity | Correlation alone is not corruption (depth-varying vars correlate with pressure naturally) |
| DOXY density conversion (not label swap) | Scientifically correct: umol/L ÷ density = micromole/kg |
| Track distance from GPS fixes only | Not from 1.26M interpolated positions (was showing Earth-circumference distances) |
| EGO as separate conversion step | Internal pipeline stays in familiar units/names; EGO compliance is a write-time transform |
| Pattern A for DB (no stored COALESCE) | Matches ARGO convention; derived "best value" lives in a SQL view, not a stored column |
