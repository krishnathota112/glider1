# Glider Data Processing & Database Workflow

Complete workflow for processing glider data and ingesting into SQLite databases.

## Overview

This workflow:
1. Processes raw glider binary data through the pipeline (L0 → L1)
2. Creates individual `.db` files for each deployment
3. Creates a combined `.db` file with all deployments
4. Provides query tools for data exploration

## Quick Start

### Windows

```cmd
process_all.bat T:\glider_data
```

### Linux/SSH

```bash
./process_all.sh /path/to/glider_data
```

This runs the complete workflow:
- Batch processes all deployments in the folder
- Creates individual databases per deployment
- Creates combined database with all data

## Step-by-Step Manual Workflow

### 1. Batch Process Multiple Deployments

```bash
python pipeline/batch_process.py T:\glider_data
```

This:
- Scans `T:\glider_data` for glider data folders
- Runs `run_pipeline.py` for each deployment
- Generates NetCDF outputs (L0, L1) in each `output/` folder

### 2. Create Databases

```bash
python pipeline/ingest_to_db.py T:\glider_data
```

This:
- Finds all processed NetCDF files
- Creates `<deployment>.db` in each `output/` folder
- Creates `glider_data_combined.db` in the root folder

Options:
```bash
# Only create combined database (skip individual DBs)
python pipeline/ingest_to_db.py T:\glider_data --combined-only

# Specify custom combined database path
python pipeline/ingest_to_db.py T:\glider_data --combined-db /path/to/custom.db
```

### 3. Query Databases

View statistics:
```bash
python pipeline/query_db.py T:\glider_data\glider_data_combined.db --stats
```

List deployments:
```bash
python pipeline/query_db.py combined.db --deployments
```

Custom SQL query:
```bash
python pipeline/query_db.py combined.db --query "SELECT * FROM deployments"
```

## Database Schema

### `deployments` table
Metadata about each deployment/processing level combination:
- `deployment_id`: Unique ID (e.g., "glider890_L0", "glider890_L1")
- `glider_id`: Glider identifier
- `deployment_start/end`: Time range
- `n_profiles`: Number of profiles
- `n_observations`: Number of timesteps
- `lat_min/max, lon_min/max`: Spatial bounds
- `depth_max`: Maximum depth
- `processing_level`: L0 or L1
- `netcdf_source`: Original NetCDF file path
- `metadata_json`: Full NetCDF attributes

### `observations` table
Time-indexed observations with location:
- `obs_id`: Unique observation ID (MD5 hash)
- `deployment_id`: Foreign key to deployments
- `time`: ISO timestamp
- `latitude, longitude, depth`: Position
- `profile_index`: Profile number
- `profile_direction`: Climb (1) or dive (-1)

### `core_measurements` table
CTD measurements:
- `obs_id`: Foreign key to observations
- `temperature`: °C
- `salinity`: PSU
- `conductivity`: S/m
- `pressure`: dbar
- `density`: kg/m³
- `sound_speed`: m/s

### `bgc_measurements` table
Biogeochemical measurements:
- `obs_id`: Foreign key to observations
- `oxygen_concentration`: µmol/L
- `oxygen_saturation`: %
- `chlorophyll`: mg/m³
- `backscatter_700`: m⁻¹
- `cdom`: ppb

## Example Queries

### Get all temperature profiles for a deployment

```sql
SELECT o.time, o.depth, c.temperature
FROM observations o
JOIN core_measurements c ON o.obs_id = c.obs_id
WHERE o.deployment_id = 'glider890_L1'
  AND c.temperature IS NOT NULL
ORDER BY o.time, o.depth;
```

### Find observations in a specific region

```sql
SELECT o.time, o.latitude, o.longitude, o.depth, c.temperature, c.salinity
FROM observations o
JOIN core_measurements c ON o.obs_id = c.obs_id
WHERE o.latitude BETWEEN 10.0 AND 15.0
  AND o.longitude BETWEEN 70.0 AND 75.0
  AND o.depth < 100;
```

### Calculate average temperature by depth bin

```sql
SELECT 
    CAST(o.depth / 10 AS INTEGER) * 10 as depth_bin,
    AVG(c.temperature) as avg_temp,
    COUNT(*) as n_obs
FROM observations o
JOIN core_measurements c ON o.obs_id = c.obs_id
WHERE c.temperature IS NOT NULL
GROUP BY depth_bin
ORDER BY depth_bin;
```

### Get deployment summary

```sql
SELECT 
    d.deployment_id,
    d.glider_id,
    d.deployment_start,
    d.n_profiles,
    COUNT(o.obs_id) as actual_obs,
    AVG(c.temperature) as avg_temp,
    AVG(c.salinity) as avg_sal
FROM deployments d
JOIN observations o ON d.deployment_id = o.deployment_id
LEFT JOIN core_measurements c ON o.obs_id = c.obs_id
GROUP BY d.deployment_id;
```

## Output Structure

```
T:\glider_data\
├── deployment1\
│   └── output\
│       ├── incois_glider_deployment1_L0.nc
│       ├── incois_glider_deployment1_L1.nc
│       └── deployment1.db              ← Individual database
├── deployment2\
│   └── output\
│       ├── incois_glider_deployment2_L0.nc
│       ├── incois_glider_deployment2_L1.nc
│       └── deployment2.db              ← Individual database
└── glider_data_combined.db             ← Combined database
```

## Integration with Web Dashboard

The SQLite databases can be directly integrated with:
- Flask/FastAPI web applications
- Plotly Dash dashboards
- Jupyter notebooks
- R Shiny applications

Example Flask query endpoint:
```python
@app.route('/api/observations')
def get_observations():
    deployment = request.args.get('deployment')
    start_time = request.args.get('start')
    end_time = request.args.get('end')
    
    conn = sqlite3.connect('glider_data_combined.db')
    cursor = conn.cursor()
    
    cursor.execute("""
        SELECT o.time, o.latitude, o.longitude, o.depth,
               c.temperature, c.salinity
        FROM observations o
        JOIN core_measurements c ON o.obs_id = c.obs_id
        WHERE o.deployment_id = ?
          AND o.time BETWEEN ? AND ?
    """, (deployment, start_time, end_time))
    
    rows = cursor.fetchall()
    conn.close()
    
    return jsonify(rows)
```

## Performance Tips

1. **Indexes**: The schema includes indexes on frequently-queried columns:
   - `deployment_id`, `time`, `latitude/longitude`, `depth`, `profile_index`

2. **Batch queries**: Use JOINs instead of multiple queries:
   ```sql
   -- Good: Single query with JOIN
   SELECT o.*, c.*, b.*
   FROM observations o
   LEFT JOIN core_measurements c ON o.obs_id = c.obs_id
   LEFT JOIN bgc_measurements b ON o.obs_id = b.obs_id
   
   -- Avoid: Multiple separate queries
   ```

3. **Limit results**: Always use `LIMIT` when exploring:
   ```sql
   SELECT * FROM observations LIMIT 100;
   ```

4. **Database size**: Expected ~1-2 MB per 10,000 observations

## Troubleshooting

### "No NetCDF files found"
- Run `batch_process.py` first to generate NetCDF files
- Check that `output/` folders contain `*_L0.nc` or `*_L1.nc` files

### "Already ingested" messages
- The database uses idempotent ingestion (skips duplicates)
- Delete the `.db` file and re-run to force re-ingestion

### Missing measurements
- Check `--stats` output to see data coverage
- Some deployments may not have all sensors (BGC)
- NULL values are stored for missing data

### Database locked
- Close all connections before re-ingesting
- SQLite allows multiple readers but only one writer

## Next Steps

1. ✅ Fix pipeline bugs (dimension coordinate handling)
2. ✅ Batch processing script
3. ✅ Database ingestion system
4. ⏳ Web dashboard (Flask + Plotly)
5. ⏳ SSH deployment configuration
6. ⏳ Automated backup system

See `requirements.md` in `.kiro/specs/glider-pipeline-completion/` for full requirements.
