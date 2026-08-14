#!/usr/bin/env python3
"""
query_db.py — Query and inspect glider databases.

Usage:
    python query_db.py <database_path> [--stats] [--deployments] [--query "SQL"]
    
Examples:
    python query_db.py glider_data_combined.db --stats
    python query_db.py output/deployment.db --deployments
    python query_db.py combined.db --query "SELECT * FROM deployments LIMIT 5"
"""
import sqlite3
import sys
from pathlib import Path
import argparse


def print_stats(db_path):
    """Print database statistics."""
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    print(f"\n{'='*60}")
    print(f"DATABASE STATISTICS: {Path(db_path).name}")
    print(f"{'='*60}")
    
    # Deployments
    cursor.execute("SELECT COUNT(*) FROM deployments")
    n_deps = cursor.fetchone()[0]
    print(f"\nDeployments: {n_deps}")
    
    if n_deps > 0:
        cursor.execute("""
            SELECT deployment_id, glider_id, deployment_start, deployment_end, 
                   n_profiles, n_observations
            FROM deployments
        """)
        print(f"\n{'ID':<30} {'Glider':<15} {'Start':<20} {'Profiles':>10} {'Obs':>12}")
        print("─" * 90)
        for row in cursor.fetchall():
            dep_id, glider, start, end, profs, obs = row
            start_short = start[:10] if start else "?"
            print(f"{dep_id:<30} {glider:<15} {start_short:<20} {profs or 0:>10} {obs or 0:>12,}")
    
    # Observations
    cursor.execute("SELECT COUNT(*) FROM observations")
    n_obs = cursor.fetchone()[0]
    print(f"\nTotal observations: {n_obs:,}")
    
    # Time range
    cursor.execute("SELECT MIN(time), MAX(time) FROM observations")
    t_min, t_max = cursor.fetchone()
    if t_min:
        print(f"Time range: {t_min[:10]} to {t_max[:10]}")
    
    # Spatial extent
    cursor.execute("""
        SELECT MIN(latitude), MAX(latitude), MIN(longitude), MAX(longitude)
        FROM observations
    """)
    lat_min, lat_max, lon_min, lon_max = cursor.fetchone()
    if lat_min:
        print(f"Latitude: {lat_min:.2f} to {lat_max:.2f}")
        print(f"Longitude: {lon_min:.2f} to {lon_max:.2f}")
    
    # Depth range
    cursor.execute("SELECT MIN(depth), MAX(depth) FROM observations WHERE depth IS NOT NULL")
    d_min, d_max = cursor.fetchone()
    if d_min:
        print(f"Depth: {d_min:.1f} to {d_max:.1f} m")
    
    # Core measurements coverage
    cursor.execute("""
        SELECT 
            SUM(CASE WHEN temperature IS NOT NULL THEN 1 ELSE 0 END) as temp,
            SUM(CASE WHEN salinity IS NOT NULL THEN 1 ELSE 0 END) as sal,
            SUM(CASE WHEN pressure IS NOT NULL THEN 1 ELSE 0 END) as pres
        FROM core_measurements
    """)
    temp, sal, pres = cursor.fetchone()
    print(f"\nCore measurements coverage:")
    print(f"  Temperature: {temp:,} ({100*temp/n_obs:.1f}%)")
    print(f"  Salinity: {sal:,} ({100*sal/n_obs:.1f}%)")
    print(f"  Pressure: {pres:,} ({100*pres/n_obs:.1f}%)")
    
    # BGC measurements coverage
    cursor.execute("""
        SELECT 
            SUM(CASE WHEN oxygen_concentration IS NOT NULL THEN 1 ELSE 0 END) as oxy,
            SUM(CASE WHEN chlorophyll IS NOT NULL THEN 1 ELSE 0 END) as chl
        FROM bgc_measurements
    """)
    oxy, chl = cursor.fetchone()
    if oxy or chl:
        print(f"\nBGC measurements coverage:")
        if oxy:
            print(f"  Oxygen: {oxy:,} ({100*oxy/n_obs:.1f}%)")
        if chl:
            print(f"  Chlorophyll: {chl:,} ({100*chl/n_obs:.1f}%)")
    
    # Database size
    db_size_mb = Path(db_path).stat().st_size / (1024 * 1024)
    print(f"\nDatabase size: {db_size_mb:.1f} MB")
    
    conn.close()


def print_deployments(db_path):
    """Print detailed deployment information."""
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    cursor.execute("""
        SELECT deployment_id, glider_id, deployment_start, deployment_end,
               n_profiles, n_observations, lat_min, lat_max, lon_min, lon_max,
               depth_max, processing_level
        FROM deployments
        ORDER BY deployment_start
    """)
    
    print(f"\n{'='*60}")
    print("DEPLOYMENTS")
    print(f"{'='*60}\n")
    
    for row in cursor.fetchall():
        dep_id, glider, start, end, profs, obs, lat_min, lat_max, lon_min, lon_max, depth_max, level = row
        print(f"Deployment: {dep_id}")
        print(f"  Glider: {glider}")
        print(f"  Period: {start[:10]} to {end[:10]}")
        print(f"  Profiles: {profs or 0}")
        print(f"  Observations: {obs or 0:,}")
        print(f"  Bounds: lat [{lat_min:.2f}, {lat_max:.2f}]  lon [{lon_min:.2f}, {lon_max:.2f}]")
        print(f"  Max depth: {depth_max:.1f} m")
        print(f"  Level: {level}")
        print()
    
    conn.close()


def run_query(db_path, query):
    """Execute custom SQL query."""
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    try:
        cursor.execute(query)
        rows = cursor.fetchall()
        
        # Print column names
        if cursor.description:
            cols = [desc[0] for desc in cursor.description]
            print("\n" + " | ".join(cols))
            print("─" * (sum(len(c) for c in cols) + 3 * len(cols)))
            
            # Print rows
            for row in rows:
                print(" | ".join(str(v) for v in row))
            
            print(f"\n{len(rows)} row(s)")
        else:
            print("Query executed successfully")
    
    except Exception as e:
        print(f"ERROR: {e}")
    
    finally:
        conn.close()


def main():
    parser = argparse.ArgumentParser(description="Query glider databases")
    parser.add_argument("database", help="Path to SQLite database")
    parser.add_argument("--stats", action="store_true", help="Show database statistics")
    parser.add_argument("--deployments", action="store_true", help="List all deployments")
    parser.add_argument("--query", help="Execute custom SQL query")
    
    args = parser.parse_args()
    
    db_path = Path(args.database)
    if not db_path.exists():
        print(f"ERROR: Database not found: {db_path}")
        return 1
    
    if args.stats:
        print_stats(db_path)
    elif args.deployments:
        print_deployments(db_path)
    elif args.query:
        run_query(db_path, args.query)
    else:
        # Default: show stats
        print_stats(db_path)
    
    return 0


if __name__ == "__main__":
    sys.exit(main())
