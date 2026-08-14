#!/usr/bin/env python3
"""
test_workflow.py — Test the complete glider pipeline workflow.

This script helps verify that:
1. The pipeline runs without errors
2. NetCDF outputs are generated
3. Databases can be created
4. Data can be queried

Usage:
    python test_workflow.py <data_folder>
    
Example:
    python test_workflow.py T:\glider_data\test_deployment
"""
import os
import sys
import subprocess
from pathlib import Path
import tempfile
import shutil


def run_command(cmd, cwd=None):
    """Run a command and return success status."""
    print(f"\n$ {' '.join(cmd)}")
    result = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    
    if result.returncode == 0:
        print("✓ Success")
        if result.stdout:
            print(result.stdout[-500:])  # Last 500 chars
        return True
    else:
        print(f"✗ Failed with code {result.returncode}")
        if result.stderr:
            print(result.stderr[-500:])
        return False


def check_file_exists(path, description):
    """Check if a file exists and report."""
    if path.exists():
        size_mb = path.stat().st_size / (1024 * 1024)
        print(f"✓ {description}: {path.name} ({size_mb:.1f} MB)")
        return True
    else:
        print(f"✗ {description}: {path.name} NOT FOUND")
        return False


def main():
    if len(sys.argv) < 2:
        print("Usage: python test_workflow.py <data_folder>")
        print("Example: python test_workflow.py T:\\glider_data\\test_deployment")
        return 1
    
    data_folder = Path(sys.argv[1])
    if not data_folder.exists():
        print(f"ERROR: {data_folder} does not exist")
        return 1
    
    script_dir = Path(__file__).parent
    pipeline_dir = script_dir / "pipeline"
    
    print("="*60)
    print("GLIDER PIPELINE WORKFLOW TEST")
    print("="*60)
    print(f"Data folder: {data_folder}")
    print(f"Script dir: {script_dir}")
    
    # Test 1: Run pipeline on single deployment
    print(f"\n{'─'*60}")
    print("TEST 1: Run pipeline")
    print(f"{'─'*60}")
    
    success = run_command(
        [sys.executable, str(pipeline_dir / "run_pipeline.py")],
        cwd=script_dir
    )
    
    if not success:
        print("\n⚠ Pipeline failed — check error messages above")
        print("Common issues:")
        print("  - Missing binary files or L0-timeseries/")
        print("  - Missing dependencies (xarray, netCDF4, scipy)")
        print("  - Dimension coordinate errors (should be fixed)")
        return 1
    
    # Test 2: Check outputs
    print(f"\n{'─'*60}")
    print("TEST 2: Check outputs")
    print(f"{'─'*60}")
    
    output_dir = data_folder / "output"
    if not output_dir.exists():
        print(f"✗ Output directory not found: {output_dir}")
        return 1
    
    # Look for NetCDF files
    l0_file = None
    l1_file = None
    
    for nc_file in output_dir.glob("*.nc"):
        name = nc_file.name.lower()
        if 'grid' in name or 'profile' in name:
            continue
        if 'l0' in name and 'l1' not in name:
            l0_file = nc_file
        elif 'l1' in name:
            l1_file = nc_file
    
    outputs_ok = True
    if l0_file:
        outputs_ok &= check_file_exists(l0_file, "L0 NetCDF")
    else:
        print("✗ L0 NetCDF not found")
        outputs_ok = False
    
    if l1_file:
        outputs_ok &= check_file_exists(l1_file, "L1 NetCDF")
    else:
        print("⚠ L1 NetCDF not found (may be expected)")
    
    if not outputs_ok:
        print("\n⚠ Pipeline did not generate expected outputs")
        return 1
    
    # Test 3: Create database
    print(f"\n{'─'*60}")
    print("TEST 3: Create database")
    print(f"{'─'*60}")
    
    test_db = output_dir / "test_workflow.db"
    if test_db.exists():
        test_db.unlink()
    
    success = run_command([
        sys.executable,
        str(pipeline_dir / "ingest_to_db.py"),
        str(data_folder.parent),
        "--combined-db", str(test_db)
    ])
    
    if not success or not test_db.exists():
        print("\n⚠ Database creation failed")
        return 1
    
    check_file_exists(test_db, "Test database")
    
    # Test 4: Query database
    print(f"\n{'─'*60}")
    print("TEST 4: Query database")
    print(f"{'─'*60}")
    
    success = run_command([
        sys.executable,
        str(pipeline_dir / "query_db.py"),
        str(test_db),
        "--stats"
    ])
    
    if not success:
        print("\n⚠ Database query failed")
        return 1
    
    # Summary
    print(f"\n{'='*60}")
    print("TEST SUMMARY")
    print(f"{'='*60}")
    print("✓ Pipeline execution")
    print("✓ NetCDF generation")
    print("✓ Database creation")
    print("✓ Database queries")
    print(f"\nAll tests passed!")
    print(f"\nGenerated files:")
    print(f"  NetCDF: {output_dir}")
    print(f"  Database: {test_db}")
    print(f"\nYou can now run the full batch workflow:")
    print(f"  python pipeline/batch_process.py {data_folder.parent}")
    print(f"  python pipeline/ingest_to_db.py {data_folder.parent}")
    
    return 0


if __name__ == "__main__":
    sys.exit(main())
