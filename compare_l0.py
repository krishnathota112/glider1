#!/usr/bin/env python3
"""
Compare existing L0 file with pipeline-generated L0 file.
"""
import sys
import xarray as xr
import numpy as np

def summarize_nc(path, label):
    """Print summary stats for a NetCDF file."""
    try:
        try:
            ds = xr.open_dataset(path)
        except ValueError:
            # Try explicit engine if auto-detection fails
            try:
                ds = xr.open_dataset(path, engine='netcdf4')
            except Exception:
                ds = xr.open_dataset(path, engine='scipy')
        print(f"\n{'='*60}")
        print(f"{label}")
        print(f"{'='*60}")
        print(f"File: {path}")
        print(f"Dimensions: {dict(ds.dims)}")
        print(f"Variables: {len(ds.data_vars)} total")
        print(f"  {', '.join(list(ds.data_vars)[:10])}")
        if len(ds.data_vars) > 10:
            print(f"  ... and {len(ds.data_vars) - 10} more")
        
        if 'time' in ds.dims:
            print(f"Time points: {len(ds.time)}")
            print(f"Time range: {ds.time.values[0]} to {ds.time.values[-1]}")
        
        if 'depth' in ds.dims:
            print(f"Depth bins: {len(ds.depth)}")
        
        if 'pressure' in ds:
            pres = ds.pressure.values
            if pres.ndim == 1:
                valid = pres[np.isfinite(pres)]
                if len(valid) > 0:
                    print(f"Pressure range: {valid.min():.1f} to {valid.max():.1f} dbar")
            elif pres.ndim == 2:
                valid = pres[np.isfinite(pres)]
                if len(valid) > 0:
                    print(f"Pressure range: {valid.min():.1f} to {valid.max():.1f} dbar")
        
        if 'temperature' in ds or 'temp' in ds:
            tvar = 'temperature' if 'temperature' in ds else 'temp'
            temp = ds[tvar].values
            valid = temp[np.isfinite(temp)]
            if len(valid) > 0:
                print(f"Temperature: {valid.min():.2f} to {valid.max():.2f} °C")
        
        if 'salinity' in ds or 'salt' in ds:
            svar = 'salinity' if 'salinity' in ds else 'salt'
            salt = ds[svar].values
            valid = salt[np.isfinite(salt)]
            if len(valid) > 0:
                print(f"Salinity: {valid.min():.2f} to {valid.max():.2f} PSU")
        
        if 'profile_index' in ds:
            pi = ds.profile_index.values.flatten()
            n_profiles = len(np.unique(pi[np.isfinite(pi)]))
            print(f"Number of profiles: {n_profiles}")
        
        # Total data coverage
        total_cells = np.prod(list(ds.dims.values()))
        if 'temperature' in ds or 'temp' in ds:
            tvar = 'temperature' if 'temperature' in ds else 'temp'
            valid_temp = np.sum(np.isfinite(ds[tvar].values))
            coverage = 100 * valid_temp / total_cells
            print(f"Data coverage (temperature): {coverage:.1f}%")
        
        ds.close()
        return True
    except Exception as e:
        print(f"\nERROR reading {path}: {e}")
        return False


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python compare_l0.py <data_dir>")
        print("  Compares:")
        print("    <data_dir>/L0-gridfiles/slocum_*.nc")
        print("    <data_dir>/output/incois_glider_*_L0.nc")
        sys.exit(1)
    
    data_dir = sys.argv[1]
    
    # Find existing L0
    import os
    import glob
    
    existing_l0 = None
    l0_grid_dir = os.path.join(data_dir, "L0-gridfiles")
    if os.path.isdir(l0_grid_dir):
        candidates = glob.glob(os.path.join(l0_grid_dir, "slocum_*.nc"))
        if candidates:
            existing_l0 = candidates[0]
    
    # Find pipeline output L0 — check all likely subdirectories
    output_dir = os.path.join(data_dir, "output")
    pipeline_l0 = None
    search_dirs = [
        output_dir,
        os.path.join(output_dir, "L0-timeseries"),
        os.path.join(output_dir, "l0-timeseries"),
    ]
    for sdir in search_dirs:
        if os.path.isdir(sdir):
            candidates = glob.glob(os.path.join(sdir, "incois_glider_*_L0.nc"))
            if candidates:
                pipeline_l0 = sorted(candidates)[-1]  # largest/latest
                break
    
    # Compare
    print("\n" + "="*60)
    print("L0 FILE COMPARISON")
    print("="*60)
    
    if existing_l0:
        summarize_nc(existing_l0, "EXISTING L0 (from L0-gridfiles/)")
    else:
        print("\nNo existing L0 file found in L0-gridfiles/")
    
    if pipeline_l0:
        summarize_nc(pipeline_l0, "PIPELINE OUTPUT L0 (from output/)")
    else:
        print("\nNo pipeline L0 output found yet. Run the pipeline first:")
        print(f"  bash run_pipeline.sh {data_dir}")
    
    print("\n" + "="*60)
    print("SUMMARY")
    print("="*60)
    if existing_l0 and pipeline_l0:
        print("✓ Both files found — see comparison above")
        print("\nKey differences to check:")
        print("  - Existing L0 is likely gridded (depth × time)")
        print("  - Pipeline L0 is a 1D timeseries (time only)")
        print("  - Profile counts should match if decoding the same deployment")
    elif existing_l0 and not pipeline_l0:
        print("⚠ Pipeline hasn't run yet — only existing L0 found")
    elif pipeline_l0 and not existing_l0:
        print("✓ Pipeline L0 created, no pre-existing L0 to compare")
    else:
        print("✗ No L0 files found")
    print("="*60)
