#!/usr/bin/env python3
"""
ingest_to_db.py — Ingest NetCDF glider data into SQLite databases.

Creates two database outputs:
  1. Individual .db files per deployment (in each deployment's output/ folder)
  2. Combined glider_data_combined.db with all deployments

Schema:
  - deployments: metadata about each deployment
  - observations: time-indexed observations (time, lat, lon, depth per row)
  - core_measurements: CTD data (temp, salinity, pressure, etc.)
  - bgc_measurements: biogeochemical data (O2, chl, backscatter, etc.)

Usage:
    python ingest_to_db.py T:\\glider_data
    python ingest_to_db.py T:\\glider_data --combined-only
"""
import os
import sys
import sqlite3
import hashlib
from pathlib import Path
from datetime import datetime
import numpy as np
import xarray as xr


# Database schema
SCHEMA = """
CREATE TABLE IF NOT EXISTS deployments (
    deployment_id TEXT PRIMARY KEY,
    glider_id TEXT,
    deployment_start TEXT,
    deployment_end TEXT,
    n_profiles INTEGER,
    n_observations INTEGER,
    lat_min REAL,
    lat_max REAL,
    lon_min REAL,
    lon_max REAL,
    depth_max REAL,
    processing_level TEXT,
    netcdf_source TEXT,
    ingestion_timestamp TEXT,
    metadata_json TEXT
);

CREATE TABLE IF NOT EXISTS observations (
    obs_id TEXT PRIMARY KEY,
    deployment_id TEXT,
    time TEXT,
    latitude REAL,
    longitude REAL,
    depth REAL,
    profile_index INTEGER,
    profile_direction INTEGER,
    FOREIGN KEY (deployment_id) REFERENCES deployments(deployment_id)
);

CREATE TABLE IF NOT EXISTS core_measurements (
    obs_id TEXT PRIMARY KEY,
    temperature REAL,
    salinity REAL,
    conductivity REAL,
    pressure REAL,
    density REAL,
    sound_speed REAL,
    FOREIGN KEY (obs_id) REFERENCES observations(obs_id)
);

CREATE TABLE IF NOT EXISTS bgc_measurements (
    obs_id TEXT PRIMARY KEY,
    oxygen_concentration REAL,
    oxygen_saturation REAL,
    chlorophyll REAL,
    backscatter_700 REAL,
    cdom REAL,
    FOREIGN KEY (obs_id) REFERENCES observations(obs_id)
);

CREATE INDEX IF NOT EXISTS idx_obs_deployment ON observations(deployment_id);
CREATE INDEX IF NOT EXISTS idx_obs_time ON observations(time);
CREATE INDEX IF NOT EXISTS idx_obs_location ON observations(latitude, longitude);
CREATE INDEX IF NOT EXISTS idx_obs_depth ON observations(depth);
CREATE INDEX IF NOT EXISTS idx_obs_profile ON observations(profile_index);
"""


def create_database(db_path):
    """Create or connect to database and ensure schema exists."""
    conn = sqlite3.connect(db_path)
    conn.executescript(SCHEMA)
    conn.commit()
    return conn


def generate_obs_id(deployment_id, time_str, depth):
    """Generate unique observation ID from deployment, time, and depth."""
    key = f"{deployment_id}_{time_str}_{depth:.2f}"
    return hashlib.md5(key.encode()).hexdigest()[:16]


def extract_deployment_metadata(ds, nc_path):
    """Extract deployment-level metadata from NetCDF dataset."""
    attrs = ds.attrs
    
    # Extract time range
    time_var = 'time' if 'time' in ds.coords else 'TIME'
    times = ds[time_var].values
    time_start = str(np.datetime64(times[0], 's'))
    time_end = str(np.datetime64(times[-1], 's'))
    
    # Extract spatial bounds
    lat_var = next((v for v in ['latitude', 'LATITUDE', 'lat'] if v in ds), None)
    lon_var = next((v for v in ['longitude', 'LONGITUDE', 'lon'] if v in ds), None)
    depth_var = next((v for v in ['depth', 'DEPTH', 'pressure', 'PRESSURE'] if v in ds), None)
    
    lat_min = float(np.nanmin(ds[lat_var].values)) if lat_var else None
    lat_max = float(np.nanmax(ds[lat_var].values)) if lat_var else None
    lon_min = float(np.nanmin(ds[lon_var].values)) if lon_var else None
    lon_max = float(np.nanmax(ds[lon_var].values)) if lon_var else None
    depth_max = float(np.nanmax(ds[depth_var].values)) if depth_var else None
    
    # Count profiles if available
    pi_var = next((v for v in ['profile_index', 'PHASE_NUMBER'] if v in ds), None)
    n_profiles = len(np.unique(ds[pi_var].values[np.isfinite(ds[pi_var].values)])) if pi_var else None
    
    return {
        'glider_id': attrs.get('glider_id', attrs.get('id', 'unknown')),
        'deployment_start': time_start,
        'deployment_end': time_end,
        'n_profiles': n_profiles,
        'n_observations': len(times),
        'lat_min': lat_min,
        'lat_max': lat_max,
        'lon_min': lon_min,
        'lon_max': lon_max,
        'depth_max': depth_max,
        'processing_level': attrs.get('processing_level', 'unknown'),
        'netcdf_source': str(nc_path),
        'ingestion_timestamp': datetime.now().isoformat(),
        'metadata_json': str(dict(attrs))  # Full attrs as JSON-like string
    }


def ingest_netcdf_to_db(nc_path, conn, deployment_id):
    """
    Ingest a single NetCDF file into the database.
    
    Returns True if successful, False otherwise.
    """
    try:
        ds = xr.open_dataset(nc_path, engine='netcdf4')
    except Exception as e:
        print(f"  ERROR opening {nc_path}: {e}")
        return False
    
    # Extract metadata
    try:
        metadata = extract_deployment_metadata(ds, nc_path)
        metadata['deployment_id'] = deployment_id
    except Exception as e:
        print(f"  ERROR extracting metadata: {e}")
        ds.close()
        return False
    
    # Check if already ingested
    cursor = conn.cursor()
    cursor.execute("SELECT deployment_id FROM deployments WHERE deployment_id = ?", 
                   (deployment_id,))
    if cursor.fetchone():
        print(f"  Already ingested: {deployment_id} (skipping)")
        ds.close()
        return True
    
    print(f"  Ingesting {deployment_id}...")
    print(f"    {metadata['n_observations']} observations, "
          f"{metadata['n_profiles']} profiles")
    
    # Insert deployment metadata
    cursor.execute("""
        INSERT INTO deployments VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """, tuple(metadata.values()))
    
    # Prepare variable mappings (support both old and new names)
    time_var = 'time' if 'time' in ds.coords else 'TIME'
    lat_var = next((v for v in ['latitude', 'LATITUDE', 'lat'] if v in ds), None)
    lon_var = next((v for v in ['longitude', 'LONGITUDE', 'lon'] if v in ds), None)
    depth_var = next((v for v in ['depth', 'DEPTH'] if v in ds), None)
    pi_var = next((v for v in ['profile_index', 'PHASE_NUMBER'] if v in ds), None)
    pd_var = next((v for v in ['profile_direction', 'PHASE'] if v in ds), None)
    
    # Core measurements mapping
    core_map = {
        'temperature': ['temperature', 'TEMP', 'temp'],
        'salinity': ['salinity', 'PSAL', 'sal'],
        'conductivity': ['conductivity', 'CNDC', 'cond'],
        'pressure': ['pressure', 'PRES', 'pres'],
        'density': ['density', 'DENS', 'dens', 'potential_density'],
        'sound_speed': ['sound_speed', 'sound_velocity']
    }
    
    # BGC measurements mapping
    bgc_map = {
        'oxygen_concentration': ['oxygen_concentration', 'DOXY', 'oxygen'],
        'oxygen_saturation': ['oxygen_saturation', 'oxygen_sat'],
        'chlorophyll': ['chlorophyll', 'CHLA', 'chl'],
        'backscatter_700': ['backscatter_700', 'BBP700', 'backscatter'],
        'cdom': ['cdom', 'CDOM']
    }
    
    def find_var(names_list):
        """Find first matching variable name in dataset."""
        for name in names_list:
            if name in ds:
                return name
        return None
    
    # Find actual variable names
    core_vars = {k: find_var(v) for k, v in core_map.items()}
    bgc_vars = {k: find_var(v) for k, v in bgc_map.items()}
    
    # Batch insert observations
    obs_batch = []
    core_batch = []
    bgc_batch = []
    
    n = len(ds[time_var])
    for i in range(n):
        # Extract observation data
        time_val = str(np.datetime64(ds[time_var].values[i], 's'))
        lat_val = float(ds[lat_var].values[i]) if lat_var else None
        lon_val = float(ds[lon_var].values[i]) if lon_var else None
        depth_val = float(ds[depth_var].values[i]) if depth_var else None
        pi_val = int(ds[pi_var].values[i]) if pi_var and np.isfinite(ds[pi_var].values[i]) else None
        pd_val = int(ds[pd_var].values[i]) if pd_var and np.isfinite(ds[pd_var].values[i]) else None
        
        # Generate observation ID
        obs_id = generate_obs_id(deployment_id, time_val, depth_val or 0.0)
        
        # Observation record
        obs_batch.append((
            obs_id, deployment_id, time_val, lat_val, lon_val, depth_val, pi_val, pd_val
        ))
        
        # Core measurements
        core_row = [obs_id]
        for key, var_name in core_vars.items():
            if var_name:
                val = ds[var_name].values[i]
                core_row.append(float(val) if np.isfinite(val) else None)
            else:
                core_row.append(None)
        core_batch.append(tuple(core_row))
        
        # BGC measurements
        bgc_row = [obs_id]
        for key, var_name in bgc_vars.items():
            if var_name:
                val = ds[var_name].values[i]
                bgc_row.append(float(val) if np.isfinite(val) else None)
            else:
                bgc_row.append(None)
        bgc_batch.append(tuple(bgc_row))
        
        # Progress indicator
        if (i + 1) % 10000 == 0:
            print(f"    ... {i+1}/{n} observations")
    
    # Insert batches
    cursor.executemany("""
        INSERT OR IGNORE INTO observations VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    """, obs_batch)
    
    cursor.executemany("""
        INSERT OR IGNORE INTO core_measurements VALUES (?, ?, ?, ?, ?, ?, ?)
    """, core_batch)
    
    cursor.executemany("""
        INSERT OR IGNORE INTO bgc_measurements VALUES (?, ?, ?, ?, ?, ?)
    """, bgc_batch)
    
    conn.commit()
    ds.close()
    
    print(f"  ✓ Ingested {len(obs_batch)} observations")
    return True


def find_netcdf_files(data_folder):
    """
    Find L0 and L1 NetCDF files in a data folder.
    
    Searches in:
      - L0-timeseries/ folder
      - output/ folder
      - output/L1-timeseries/ folder
    
    Returns dict with 'L0' and 'L1' keys pointing to file paths.
    """
    files = {}
    
    # Check L0-timeseries/ folder
    l0_ts_dir = data_folder / 'L0-timeseries'
    if l0_ts_dir.exists():
        for nc_file in l0_ts_dir.glob('*.nc'):
            name = nc_file.name.lower()
            if 'grid' not in name and 'profile' not in name:
                files['L0'] = nc_file
                break
    
    # Check output/ folder
    output_dir = data_folder / 'output'
    if output_dir.exists():
        # Check for L0 files directly in output/
        for nc_file in output_dir.glob('*.nc'):
            name = nc_file.name.lower()
            if 'grid' not in name and 'profile' not in name:
                if 'l0' in name and 'l1' not in name:
                    files['L0'] = nc_file
        
        # Check output/L1-timeseries/ subfolder
        l1_ts_dir = output_dir / 'L1-timeseries'
        if l1_ts_dir.exists():
            for nc_file in l1_ts_dir.glob('*.nc'):
                name = nc_file.name.lower()
                if 'grid' not in name and 'profile' not in name and 'l1' in name:
                    files['L1'] = nc_file
                    break
    
    return files


def process_deployment(data_folder, combined_db_conn=None):
    """
    Process a single deployment folder:
      1. Create individual .db in output/ folder
      2. Optionally ingest into combined database
    
    Returns True if successful.
    """
    print(f"\n{'─'*60}")
    print(f"Deployment: {data_folder.name}")
    print(f"{'─'*60}")
    
    # Find NetCDF files
    nc_files = find_netcdf_files(data_folder)
    if not nc_files:
        print("  No NetCDF files found — skipping")
        return False
    
    print(f"  Found: {', '.join(nc_files.keys())}")
    
    # Create individual database
    output_dir = data_folder / 'output'
    output_dir.mkdir(exist_ok=True)
    
    individual_db = output_dir / f"{data_folder.name}.db"
    print(f"  Creating: {individual_db.name}")
    
    ind_conn = create_database(str(individual_db))
    
    # Ingest each level
    success = True
    for level, nc_path in sorted(nc_files.items()):
        deployment_id = f"{data_folder.name}_{level}"
        
        # Ingest to individual DB
        if not ingest_netcdf_to_db(nc_path, ind_conn, deployment_id):
            success = False
            continue
        
        # Ingest to combined DB if provided
        if combined_db_conn:
            ingest_netcdf_to_db(nc_path, combined_db_conn, deployment_id)
    
    ind_conn.close()
    
    if success:
        print(f"  ✓ Created {individual_db.name}")
    
    return success


def main():
    import argparse
    
    parser = argparse.ArgumentParser(
        description="Ingest glider NetCDF data into SQLite databases")
    parser.add_argument("root_dir", 
                       help="Root directory containing glider data folders")
    parser.add_argument("--combined-only", action="store_true",
                       help="Only create combined database, skip individual DBs")
    parser.add_argument("--combined-db", default=None,
                       help="Path for combined database (default: root_dir/glider_data_combined.db)")
    
    args = parser.parse_args()
    
    root_dir = Path(args.root_dir)
    if not root_dir.exists():
        print(f"ERROR: {root_dir} does not exist")
        return 1
    
    # Find all data folders
    data_folders = []
    for item in root_dir.iterdir():
        if not item.is_dir():
            continue
        if item.name.lower() in ('output', 'cache', 'logs', 'tmp', 'temp'):
            continue
        
        # Check for L0-timeseries folder (processed data)
        l0_dir = item / 'L0-timeseries'
        has_l0_ts = l0_dir.exists() and list(l0_dir.glob('*.nc'))
        
        # Check for output folder with NetCDF
        output_dir = item / 'output'
        has_output_nc = False
        if output_dir.exists():
            has_output_nc = (list(output_dir.glob('*.nc')) or 
                           list((output_dir / 'L1-timeseries').glob('*.nc')) if (output_dir / 'L1-timeseries').exists() else False)
        
        if has_l0_ts or has_output_nc:
            data_folders.append(item)
    
    if not data_folders:
        print("No processed data folders found")
        print("Run batch_process.py first to process raw data")
        return 1
    
    print(f"Found {len(data_folders)} processed deployment(s)")
    
    # Create combined database
    combined_db_path = args.combined_db or (root_dir / "glider_data_combined.db")
    print(f"\nCombined database: {combined_db_path}")
    combined_conn = create_database(str(combined_db_path))
    
    # Process each deployment
    results = {}
    for folder in sorted(data_folders):
        if args.combined_only:
            # Only ingest to combined DB
            nc_files = find_netcdf_files(folder)
            success = True
            for level, nc_path in nc_files.items():
                deployment_id = f"{folder.name}_{level}"
                if not ingest_netcdf_to_db(nc_path, combined_conn, deployment_id):
                    success = False
            results[folder.name] = success
        else:
            # Create individual DB and ingest to combined
            success = process_deployment(folder, combined_conn)
            results[folder.name] = success
    
    combined_conn.close()
    
    # Summary
    print(f"\n{'='*60}")
    print("DATABASE INGESTION SUMMARY")
    print(f"{'='*60}")
    
    successful = sum(1 for v in results.values() if v)
    failed = len(results) - successful
    
    print(f"Deployments processed: {len(results)}")
    print(f"  ✓ Successful: {successful}")
    print(f"  ✗ Failed: {failed}")
    
    if not args.combined_only:
        print(f"\nIndividual databases created in each output/ folder")
    
    print(f"\nCombined database: {combined_db_path}")
    
    # Show combined DB stats
    conn = sqlite3.connect(str(combined_db_path))
    cursor = conn.cursor()
    
    cursor.execute("SELECT COUNT(*) FROM deployments")
    n_deps = cursor.fetchone()[0]
    
    cursor.execute("SELECT COUNT(*) FROM observations")
    n_obs = cursor.fetchone()[0]
    
    print(f"  Deployments: {n_deps}")
    print(f"  Observations: {n_obs:,}")
    
    conn.close()
    
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
