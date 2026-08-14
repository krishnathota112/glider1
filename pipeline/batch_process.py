#!/usr/bin/env python3
"""
batch_process.py — Process multiple glider data products and generate databases.

Usage:
    python batch_process.py T:\\glider_data

Processes all subdirectories that look like glider data folders, then:
  - Creates individual .db files for each deployment
  - Creates a combined .db with all deployments
"""
import os
import sys
import glob
import time
import subprocess
from pathlib import Path


def find_glider_data_folders(root_dir):
    """
    Find all folders under root_dir that look like glider data.
    
    A folder is considered glider data if it contains:
      - Binary files (.dbd, .ebd, .dcd, .ecd)
      - OR L0-timeseries/ folder
      - OR output/ folder with NetCDF files
    """
    root = Path(root_dir)
    if not root.exists():
        print(f"ERROR: {root_dir} does not exist")
        return []
    
    candidates = []
    
    # Check immediate subdirectories
    for item in root.iterdir():
        if not item.is_dir():
            continue
        
        # Skip common non-data folders
        if item.name.lower() in ('output', 'cache', 'logs', 'tmp', 'temp'):
            continue
        
        # Check for binary files
        has_binary = any(item.glob(f'**/*.{ext}') 
                        for ext in ['dbd', 'ebd', 'dcd', 'ecd'])
        
        # Check for L0-timeseries folder
        has_l0_folder = (item / 'L0-timeseries').exists()
        
        # Check for output with NetCDF
        has_output_nc = False
        output_dir = item / 'output'
        if output_dir.exists():
            has_output_nc = any(output_dir.glob('*.nc'))
        
        if has_binary or has_l0_folder or has_output_nc:
            candidates.append(item)
            print(f"  Found: {item.name}")
    
    return sorted(candidates)


def run_pipeline_for_folder(data_folder, pipeline_script):
    """
    Run the pipeline for a single data folder.
    
    Returns True on success, False on failure.
    """
    print(f"\n{'='*60}")
    print(f"Processing: {data_folder.name}")
    print(f"{'='*60}")
    
    env = os.environ.copy()
    env['GLIDER_DATA_DIR'] = str(data_folder)
    
    try:
        result = subprocess.run(
            [sys.executable, str(pipeline_script)],
            env=env,
            capture_output=False,
            text=True,
            timeout=3600  # 1 hour timeout per deployment
        )
        
        if result.returncode == 0:
            print(f"✓ {data_folder.name} completed successfully")
            return True
        else:
            print(f"✗ {data_folder.name} failed with code {result.returncode}")
            return False
            
    except subprocess.TimeoutExpired:
        print(f"✗ {data_folder.name} timed out after 1 hour")
        return False
    except Exception as e:
        print(f"✗ {data_folder.name} error: {e}")
        return False


def main():
    if len(sys.argv) < 2:
        print("Usage: python batch_process.py <root_data_dir>")
        print("Example: python batch_process.py T:\\glider_data")
        return 1
    
    root_data_dir = sys.argv[1]
    
    # Find pipeline script
    script_dir = Path(__file__).parent
    pipeline_script = script_dir / "run_pipeline.py"
    
    if not pipeline_script.exists():
        print(f"ERROR: run_pipeline.py not found at {pipeline_script}")
        return 1
    
    print(f"Scanning {root_data_dir} for glider data folders...")
    folders = find_glider_data_folders(root_data_dir)
    
    if not folders:
        print("No glider data folders found")
        return 1
    
    print(f"\nFound {len(folders)} data folder(s)")
    print("\nStarting batch processing...")
    
    results = {}
    start_time = time.time()
    
    for folder in folders:
        success = run_pipeline_for_folder(folder, pipeline_script)
        results[folder.name] = success
    
    elapsed = time.time() - start_time
    
    # Summary
    print(f"\n{'='*60}")
    print("BATCH PROCESSING SUMMARY")
    print(f"{'='*60}")
    print(f"Total time: {elapsed/60:.1f} minutes")
    print(f"Processed: {len(results)} deployments")
    
    successful = sum(1 for v in results.values() if v)
    failed = len(results) - successful
    
    print(f"  ✓ Successful: {successful}")
    print(f"  ✗ Failed: {failed}")
    
    if failed > 0:
        print("\nFailed deployments:")
        for name, success in results.items():
            if not success:
                print(f"  - {name}")
    
    print(f"\nNext step: Run database ingestion")
    print(f"  python pipeline/ingest_to_db.py {root_data_dir}")
    
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
