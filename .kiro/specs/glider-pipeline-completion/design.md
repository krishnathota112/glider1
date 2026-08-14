# Design Document: Glider Pipeline Completion

## Overview

This design addresses the completion and deployment of the glider data processing pipeline. The system processes raw glider data through quality control stages, ingests results into a queryable database, and provides a web interface for pipeline execution and monitoring.

The design covers five major components:

1. **Bug Fixes**: Correct dimension coordinate handling in step4.py to prevent ValueError exceptions
2. **Database Layer**: SQLite schema and ingestion system for storing and querying glider observations
3. **Web Dashboard**: Flask-based interface for pipeline execution, monitoring, and results viewing
4. **Deployment Automation**: SSH environment setup with systemd service configuration
5. **Integration**: Connect pipeline outputs to database ingestion and web dashboard

The existing pipeline (step1-step6) already handles binary decoding, quality control, plotting, and EGO format conversion. This design adds the missing infrastructure for production deployment and data management.

## Architecture

### System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                      SSH Production Server                       │
│                                                                  │
│  ┌────────────────────┐      ┌─────────────────────────────┐  │
│  │  Web Dashboard     │      │   Processing Pipeline        │  │
│  │  (Flask/FastAPI)   │◄─────┤   (step1-step6 + step_ego)  │  │
│  │                    │      │                               │  │
│  │  - File upload UI  │      │  • Binary decode              │  │
│  │  - Pipeline trigger│      │  • QC processing              │  │
│  │  - Progress monitor│      │  • NetCDF generation          │  │
│  │  - Results viewer  │      │  • Plotting                   │  │
│  └────────┬───────────┘      │  • EGO format conversion      │  │
│           │                  └──────────┬────────────────────┘  │
│           │                             │                        │
│           │                             │                        │
│           │                             ▼                        │
│           │                  ┌─────────────────────┐           │
│           │                  │  Database Ingestion │           │
│           │                  │   (ingest_netcdf.py)│           │
│           │                  └──────────┬──────────┘           │
│           │                             │                        │
│           ▼                             ▼                        │
│  ┌────────────────────────────────────────────────────────┐   │
│  │              SQLite Database                            │   │
│  │  ┌────────────┐  ┌──────────────┐  ┌──────────────┐  │   │
│  │  │deployments │  │ observations │  │    core_     │  │   │
│  │  │            │◄─┤              │◄─┤measurements  │  │   │
│  │  └────────────┘  └──────────────┘  └──────────────┘  │   │
│  │                                      ┌──────────────┐  │   │
│  │                                      │    bgc_      │  │   │
│  │                                      │measurements  │  │   │
│  │                                      └──────────────┘  │   │
│  └────────────────────────────────────────────────────────┘   │
│                                                                  │
│  File System:                                                   │
│  /home/user/glider/                                            │
│    ├── uploads/         (uploaded binary files)                │
│    ├── deployments/     (processed data by deployment)         │
│    ├── database/        (SQLite files)                         │
│    └── logs/            (pipeline execution logs)              │
└─────────────────────────────────────────────────────────────────┘
```

### Component Interaction Flow

1. **Upload Phase**: User uploads binary files via web dashboard → stored in `uploads/{deployment_id}/`
2. **Execution Phase**: Dashboard triggers `bash run_pipeline.sh` → pipeline processes data → outputs to `deployments/{deployment_id}/output/`
3. **Ingestion Phase**: Pipeline completion triggers database ingestion → EGO NetCDF parsed → data inserted into SQLite
4. **Query Phase**: Dashboard or external scripts query database → results exported as CSV/NetCDF
5. **Monitoring Phase**: Dashboard polls pipeline logs → displays progress in real-time → shows final results when complete


## Components and Interfaces

### Component 1: Bug Fix for Dimension Coordinate Handling

**Location**: `pipeline/step4.py`

**Problem**: xarray dimension coordinates cannot be reassigned directly with `.values =` syntax. Attempting to do so raises `ValueError: cannot reindex or align along dimension 'TIME' because of conflicting dimension sizes`. The bug occurs in two functions:

1. `split_profiles()`: When masking bad QC values, tries to overwrite dimension coordinates
2. `make_grid()`: Similar issue when creating masked dataset copies

**Solution Architecture**:

```python
# Current (broken) pattern:
if base_v in ds_masked:
    vals = ds_masked[base_v].values.copy()
    vals[bad] = np.nan
    ds_masked[base_v].values = vals  # ← FAILS for dimension coordinates

# Fixed pattern:
if base_v in ds_masked.dims:
    # Skip dimension coordinates - they cannot be masked
    continue
if base_v in ds_masked:
    vals = ds_masked[base_v].values.copy()
    vals[bad] = np.nan
    ds_masked[base_v] = xr.DataArray(vals, dims=ds_masked[base_v].dims,
                                      attrs=ds_masked[base_v].attrs)
```

**Implementation Details**:

- Add dimension coordinate check before attempting to mask variables
- Use `xr.DataArray` constructor for non-dimension variables to create new array
- Preserve original dims and attrs when reconstructing variables
- Handle both old (`time`, `depth`) and new (`TIME`, `DEPTH`) dimension name conventions

**Interface Changes**: None - functions maintain same signatures and return values


### Component 2: Database Schema

**Technology**: SQLite 3.x with foreign key constraints enabled

**Schema Design Philosophy**: 
- Normalize observations from measurements to reduce redundancy
- Store ARGO QC pattern A: both raw and adjusted values with separate QC flags
- Use deterministic composite keys for idempotent ingestion
- Optimize for time-series queries with indexed temporal/spatial fields

**Table Definitions**:

#### Table 1: deployments

Primary key: `deployment_id`

```sql
CREATE TABLE deployments (
    deployment_id TEXT PRIMARY KEY,
    glider_id TEXT NOT NULL,
    platform_type TEXT,  -- 'seaglider', 'slocum', 'seaexplorer'
    data_source TEXT,    -- 'binary', 'rtqc_pipeline', 'gdac'
    deployment_start TEXT,  -- ISO8601: '2023-01-15T00:00:00Z'
    deployment_end TEXT,    -- ISO8601: '2023-03-20T00:00:00Z'
    processing_level TEXT,  -- 'L0', 'L1', 'L2'
    ingest_timestamp TEXT DEFAULT CURRENT_TIMESTAMP,
    netcdf_path TEXT,    -- Source file path for provenance
    UNIQUE(glider_id, deployment_start)
);
CREATE INDEX idx_deployments_glider_id ON deployments(glider_id);
CREATE INDEX idx_deployments_dates ON deployments(deployment_start, deployment_end);
```

#### Table 2: observations

Primary key: `observation_id` (deterministic hash of deployment_id + time + depth)

```sql
CREATE TABLE observations (
    observation_id TEXT PRIMARY KEY,
    deployment_id TEXT NOT NULL,
    time TEXT NOT NULL,           -- ISO8601 with microseconds
    latitude REAL,
    longitude REAL,
    depth REAL,                   -- meters, positive down
    profile_index INTEGER,        -- dive/climb cycle number
    profile_direction INTEGER,    -- -1=dive, 1=climb, 0=surface
    FOREIGN KEY (deployment_id) REFERENCES deployments(deployment_id) ON DELETE CASCADE
);
CREATE INDEX idx_observations_deployment ON observations(deployment_id);
CREATE INDEX idx_observations_time ON observations(time);
CREATE INDEX idx_observations_location ON observations(latitude, longitude);
CREATE INDEX idx_observations_depth ON observations(depth);
CREATE INDEX idx_observations_profile ON observations(deployment_id, profile_index);
```


#### Table 3: core_measurements

Physical oceanography variables (always present)

```sql
CREATE TABLE core_measurements (
    observation_id TEXT PRIMARY KEY,
    -- Pressure
    pressure REAL,
    pressure_qc INTEGER,
    pressure_adjusted REAL,
    pressure_adjusted_qc INTEGER,
    -- Temperature
    temperature REAL,
    temperature_qc INTEGER,
    temperature_adjusted REAL,
    temperature_adjusted_qc INTEGER,
    -- Salinity
    salinity REAL,
    salinity_qc INTEGER,
    salinity_adjusted REAL,
    salinity_adjusted_qc INTEGER,
    -- Conductivity
    conductivity REAL,
    conductivity_qc INTEGER,
    conductivity_adjusted REAL,
    conductivity_adjusted_qc INTEGER,
    -- Derived
    density REAL,
    sound_speed REAL,
    FOREIGN KEY (observation_id) REFERENCES observations(observation_id) ON DELETE CASCADE
);
CREATE INDEX idx_core_observation ON core_measurements(observation_id);
```

#### Table 4: bgc_measurements

Biogeochemical variables (optional, sensor-dependent)

```sql
CREATE TABLE bgc_measurements (
    observation_id TEXT PRIMARY KEY,
    -- Oxygen
    oxygen REAL,
    oxygen_qc INTEGER,
    oxygen_adjusted REAL,
    oxygen_adjusted_qc INTEGER,
    -- Chlorophyll
    chlorophyll REAL,
    chlorophyll_qc INTEGER,
    chlorophyll_adjusted REAL,
    chlorophyll_adjusted_qc INTEGER,
    -- CDOM
    cdom REAL,
    cdom_qc INTEGER,
    cdom_adjusted REAL,
    cdom_adjusted_qc INTEGER,
    -- Backscatter
    backscatter_700 REAL,
    backscatter_700_qc INTEGER,
    backscatter_700_adjusted REAL,
    backscatter_700_adjusted_qc INTEGER,
    FOREIGN KEY (observation_id) REFERENCES observations(observation_id) ON DELETE CASCADE
);
CREATE INDEX idx_bgc_observation ON bgc_measurements(observation_id);
```


**View: best_value_measurements**

Provides COALESCE(adjusted, raw) for convenient querying:

```sql
CREATE VIEW best_value_measurements AS
SELECT 
    o.observation_id,
    o.deployment_id,
    o.time,
    o.latitude,
    o.longitude,
    o.depth,
    o.profile_index,
    COALESCE(c.pressure_adjusted, c.pressure) AS pressure,
    COALESCE(c.temperature_adjusted, c.temperature) AS temperature,
    COALESCE(c.salinity_adjusted, c.salinity) AS salinity,
    COALESCE(b.oxygen_adjusted, b.oxygen) AS oxygen,
    COALESCE(b.chlorophyll_adjusted, b.chlorophyll) AS chlorophyll
FROM observations o
LEFT JOIN core_measurements c ON o.observation_id = c.observation_id
LEFT JOIN bgc_measurements b ON o.observation_id = b.observation_id;
```

### Component 3: Database Ingestion System

**File**: `database/ingest_netcdf.py`

**Purpose**: Parse EGO-format NetCDF files and insert data into SQLite database with idempotent behavior.

**Architecture**:

```python
class NetCDFIngester:
    def __init__(self, db_path):
        self.conn = sqlite3.connect(db_path)
        self.conn.execute("PRAGMA foreign_keys = ON")
    
    def ingest_file(self, netcdf_path):
        """Main entry point - ingest one NetCDF file."""
        with xr.open_dataset(netcdf_path) as ds:
            deployment_id = self._extract_deployment_id(ds)
            self._upsert_deployment(ds, deployment_id, netcdf_path)
            self._ingest_observations(ds, deployment_id)
        self.conn.commit()
    
    def _generate_observation_id(self, deployment_id, time_str, depth):
        """Deterministic ID from deployment+time+depth."""
        key = f"{deployment_id}:{time_str}:{depth:.2f}"
        return hashlib.sha256(key.encode()).hexdigest()[:16]
    
    def _upsert_deployment(self, ds, deployment_id, netcdf_path):
        """Insert or update deployment metadata."""
        # Extract from global attributes
        # Use INSERT OR REPLACE for idempotence
    
    def _ingest_observations(self, ds, deployment_id):
        """Batch insert observations and measurements."""
        # Process in chunks of 1000 for memory efficiency
        # Skip if observation_id already exists
        # Handle NaN → NULL conversion
```


**Idempotence Strategy**:

1. **Deployment level**: Use `INSERT OR REPLACE` with unique constraint on (glider_id, deployment_start)
2. **Observation level**: Generate deterministic `observation_id` from (deployment_id, time, depth)
3. **Measurement level**: Use `observation_id` as primary key, skip if already exists
4. **Result**: Running ingestion twice produces identical database state

**NaN Handling**:

```python
def _convert_value(val):
    """Convert numpy value to SQL-compatible type."""
    if isinstance(val, (np.floating, float)):
        if np.isnan(val):
            return None  # NULL in database
        return float(val)
    elif isinstance(val, (np.integer, int)):
        return int(val)
    return val
```

**Batch Insertion Pattern**:

```python
def _batch_insert(self, table, records, batch_size=1000):
    """Insert records in batches to optimize performance."""
    for i in range(0, len(records), batch_size):
        batch = records[i:i+batch_size]
        # Check for existing IDs
        existing = self._get_existing_ids(table, [r['id'] for r in batch])
        # Filter out existing records
        new_records = [r for r in batch if r['id'] not in existing]
        if new_records:
            self._insert_many(table, new_records)
```

### Component 4: Web Dashboard

**Technology Stack**: 
- Backend: Flask 3.x (lightweight, suitable for single-server deployment)
- Frontend: Jinja2 templates + vanilla JavaScript (no framework overhead)
- Task execution: subprocess.Popen for pipeline runs
- Authentication: Flask-Login with bcrypt password hashing
- Database: SQLite (same database as ingestion system)

**Application Structure**:

```
dashboard/
├── app.py                  # Flask application entry point
├── routes/
│   ├── auth.py            # Login/logout routes
│   ├── upload.py          # File upload handling
│   ├── pipeline.py        # Pipeline execution & monitoring
│   ├── results.py         # Results viewing & download
│   └── admin.py           # User management (admin only)
├── models/
│   ├── user.py            # User model for authentication
│   ├── pipeline_run.py    # Pipeline execution tracking
│   └── database.py        # Database query helpers
├── templates/
│   ├── base.html          # Base template with navigation
│   ├── login.html
│   ├── upload.html
│   ├── monitor.html       # Real-time progress view
│   └── results.html       # Deployment results browser
├── static/
│   ├── css/style.css
│   └── js/
│       ├── upload.js      # File upload with progress bar
│       └── monitor.js     # WebSocket/SSE for live updates
└── config.py              # Configuration (paths, secrets)
```


**Route Definitions**:

```python
# Authentication
POST   /login                    # Authenticate user
GET    /logout                   # End session
GET    /                         # Redirect to /upload if authenticated, else /login

# File Upload
GET    /upload                   # Display upload form
POST   /upload                   # Handle file upload, create deployment directory
DELETE /upload/<deployment_id>   # Delete uploaded files (before processing)

# Pipeline Execution
POST   /pipeline/run/<deployment_id>   # Start pipeline on uploaded data
GET    /pipeline/status/<run_id>       # Get current status (JSON)
GET    /pipeline/logs/<run_id>         # Stream log output (SSE)
POST   /pipeline/stop/<run_id>         # Kill running pipeline

# Results Viewing
GET    /results                         # List all deployments
GET    /results/<deployment_id>         # View single deployment details
GET    /results/<deployment_id>/plots   # Gallery of diagnostic plots
GET    /results/<deployment_id>/download/<file>  # Download NetCDF/report

# Admin
GET    /admin/users                     # User management (admin only)
POST   /admin/users/create              # Create new user
DELETE /admin/users/<user_id>           # Delete user
```

**Pipeline Execution Design**:

```python
class PipelineRunner:
    def __init__(self, deployment_dir, run_id):
        self.deployment_dir = deployment_dir
        self.run_id = run_id
        self.log_path = f"logs/{run_id}.log"
        self.status_path = f"logs/{run_id}.status"
    
    def start(self):
        """Start pipeline as background subprocess."""
        cmd = ["bash", "run_pipeline.sh", self.deployment_dir]
        self.process = subprocess.Popen(
            cmd,
            stdout=open(self.log_path, 'w'),
            stderr=subprocess.STDOUT,
            cwd=PIPELINE_ROOT
        )
        self._update_status("running")
        # Store PID for later termination
        with open(f"logs/{self.run_id}.pid", 'w') as f:
            f.write(str(self.process.pid))
    
    def get_status(self):
        """Check if pipeline is still running."""
        if self.process.poll() is None:
            return {"status": "running", "pid": self.process.pid}
        else:
            returncode = self.process.returncode
            status = "completed" if returncode == 0 else "failed"
            return {"status": status, "returncode": returncode}
    
    def tail_logs(self, n_lines=50):
        """Get last n lines of log file."""
        with open(self.log_path) as f:
            return f.readlines()[-n_lines:]
```


**Authentication Implementation**:

```python
from flask_login import LoginManager, UserMixin, login_user, login_required
import bcrypt

class User(UserMixin):
    def __init__(self, user_id, username, password_hash, is_admin=False):
        self.id = user_id
        self.username = username
        self.password_hash = password_hash
        self.is_admin = is_admin
    
    @staticmethod
    def verify_password(password, password_hash):
        return bcrypt.checkpw(password.encode(), password_hash.encode())
    
    @staticmethod
    def hash_password(password):
        return bcrypt.hashpw(password.encode(), bcrypt.gensalt(rounds=12)).decode()

# User storage in SQLite
CREATE TABLE users (
    user_id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    is_admin INTEGER DEFAULT 0,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);
```

**Real-time Progress Monitoring**:

Use Server-Sent Events (SSE) for streaming log output:

```python
@app.route('/pipeline/logs/<run_id>')
@login_required
def stream_logs(run_id):
    def generate():
        log_path = f"logs/{run_id}.log"
        with open(log_path) as f:
            # Send existing content
            for line in f:
                yield f"data: {line}\n\n"
            # Tail new lines
            while True:
                line = f.readline()
                if line:
                    yield f"data: {line}\n\n"
                else:
                    time.sleep(0.5)
                # Check if process finished
                if os.path.exists(f"logs/{run_id}.complete"):
                    break
    return Response(generate(), mimetype='text/event-stream')
```

### Component 5: Deployment Configuration

**Target Environment**: Linux SSH server (Ubuntu 22.04 or similar)

**Directory Structure**:

```
/home/glider/production/
├── pipeline/              # Git checkout of pipeline code
│   ├── step1.py
│   ├── step4.py
│   ├── run_pipeline.sh
│   └── ...
├── dashboard/             # Web dashboard application
│   ├── app.py
│   ├── requirements.txt
│   └── ...
├── venv/                  # Python virtual environment
├── uploads/               # Uploaded binary files (organized by deployment_id)
├── deployments/           # Processed data (output/ directories)
├── database/              # SQLite database files
│   └── glider_data.db
├── logs/                  # Pipeline execution logs
├── backups/               # Daily database backups
└── config/
    ├── production.env     # Environment variables
    └── dashboard.conf     # Web server configuration
```


**Setup Script** (`deployment/setup.sh`):

```bash
#!/bin/bash
set -e

INSTALL_DIR="/home/glider/production"
REPO_URL="<git_repository_url>"

echo "Setting up glider pipeline production environment..."

# Create directory structure
mkdir -p "$INSTALL_DIR"/{uploads,deployments,database,logs,backups,config}

# Clone repository
cd "$INSTALL_DIR"
if [ ! -d "pipeline" ]; then
    git clone "$REPO_URL" pipeline
fi

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install Python dependencies
pip install --upgrade pip
pip install -r pipeline/requirements.txt
pip install -r dashboard/requirements.txt

# Initialize database
python database/init_db.py

# Create systemd service
sudo cp deployment/glider-dashboard.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable glider-dashboard

# Setup cron jobs for backups
(crontab -l 2>/dev/null; echo "0 2 * * * $INSTALL_DIR/deployment/backup.sh") | crontab -

echo "Setup complete. Start dashboard with:"
echo "  sudo systemctl start glider-dashboard"
```

**Systemd Service File** (`deployment/glider-dashboard.service`):

```ini
[Unit]
Description=Glider Data Dashboard
After=network.target

[Service]
Type=simple
User=glider
WorkingDirectory=/home/glider/production
Environment="PATH=/home/glider/production/venv/bin"
Environment="PYTHONUNBUFFERED=1"
ExecStart=/home/glider/production/venv/bin/python dashboard/app.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

**Backup Script** (`deployment/backup.sh`):

```bash
#!/bin/bash
set -e

DB_PATH="/home/glider/production/database/glider_data.db"
BACKUP_DIR="/home/glider/production/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/glider_data_$TIMESTAMP.sql.gz"

# Export database to SQL dump
sqlite3 "$DB_PATH" .dump | gzip > "$BACKUP_FILE"

# Verify backup integrity
gunzip -t "$BACKUP_FILE"
if [ $? -eq 0 ]; then
    echo "Backup successful: $BACKUP_FILE"
else
    echo "ERROR: Backup verification failed"
    exit 1
fi

# Delete backups older than 30 days
find "$BACKUP_DIR" -name "glider_data_*.sql.gz" -mtime +30 -delete

echo "Backup retention: $(ls -1 $BACKUP_DIR | wc -l) files"
```


**SSH Port Forwarding**:

For local access to dashboard running on remote server:

```bash
# Forward remote port 5000 to local port 8080
ssh -L 8080:localhost:5000 glider@remote-server.example.com

# Then access dashboard at http://localhost:8080 in browser
```

**Environment Configuration** (`config/production.env`):

```bash
# Flask settings
FLASK_APP=dashboard.app
FLASK_ENV=production
SECRET_KEY=<generate_random_secret>

# Paths
UPLOAD_DIR=/home/glider/production/uploads
DEPLOYMENT_DIR=/home/glider/production/deployments
DATABASE_PATH=/home/glider/production/database/glider_data.db
LOG_DIR=/home/glider/production/logs
PIPELINE_ROOT=/home/glider/production/pipeline

# Dashboard settings
HOST=0.0.0.0
PORT=5000
MAX_UPLOAD_SIZE=1073741824  # 1 GB in bytes
ALLOWED_EXTENSIONS=dbd,ebd,dcd,ecd

# Database settings
DB_TIMEOUT=30
DB_POOL_SIZE=5

# Admin user (created on first run)
ADMIN_USERNAME=admin
ADMIN_PASSWORD=<change_on_first_login>
```

## Data Models

### NetCDF to Database Mapping

**EGO Format NetCDF Structure**:

```
Dimensions:
    TIME: 125893
    N_PARAM: 20
    STRING64: 64

Variables:
    TIME(TIME): datetime64[ns]
    LATITUDE_GPS(TIME): float64
    LONGITUDE_GPS(TIME): float64
    PRES(TIME): float32
    PRES_QC(TIME): int8
    PRES_ADJUSTED(TIME): float32
    PRES_ADJUSTED_QC(TIME): int8
    TEMP(TIME): float32
    TEMP_QC(TIME): int8
    ...
    
Global Attributes:
    platform_serial_number: "sg_890"
    deployment_id: "incois_glider_890_2023"
    time_coverage_start: "2023-01-15T00:00:00Z"
    time_coverage_end: "2023-03-20T23:59:59Z"
    ...
```


**Ingestion Mapping Logic**:

```python
def extract_deployment_metadata(ds):
    """Extract deployment info from NetCDF global attributes."""
    return {
        'deployment_id': ds.attrs.get('deployment_id', 'unknown'),
        'glider_id': ds.attrs.get('platform_serial_number', 'unknown'),
        'platform_type': ds.attrs.get('platform_type', 'unknown'),
        'data_source': 'rtqc_pipeline',
        'deployment_start': ds.attrs.get('time_coverage_start'),
        'deployment_end': ds.attrs.get('time_coverage_end'),
        'processing_level': ds.attrs.get('processing_level', 'L1'),
    }

def extract_observations(ds):
    """Extract observation records from NetCDF."""
    n_obs = len(ds.TIME)
    observations = []
    
    for i in range(n_obs):
        obs = {
            'time': str(ds.TIME.values[i]),
            'latitude': float(ds.LATITUDE_GPS.values[i]) if not np.isnan(ds.LATITUDE_GPS.values[i]) else None,
            'longitude': float(ds.LONGITUDE_GPS.values[i]) if not np.isnan(ds.LONGITUDE_GPS.values[i]) else None,
            'depth': float(ds.DEPTH.values[i]) if 'DEPTH' in ds else None,
            'profile_index': int(ds.PHASE_NUMBER.values[i]) if 'PHASE_NUMBER' in ds else None,
            'profile_direction': int(ds.PHASE.values[i]) if 'PHASE' in ds else None,
        }
        observations.append(obs)
    
    return observations

def extract_core_measurements(ds, observation_id, i):
    """Extract core measurements for observation index i."""
    return {
        'observation_id': observation_id,
        'pressure': _get_value(ds, 'PRES', i),
        'pressure_qc': _get_qc(ds, 'PRES_QC', i),
        'pressure_adjusted': _get_value(ds, 'PRES_ADJUSTED', i),
        'pressure_adjusted_qc': _get_qc(ds, 'PRES_ADJUSTED_QC', i),
        'temperature': _get_value(ds, 'TEMP', i),
        'temperature_qc': _get_qc(ds, 'TEMP_QC', i),
        'temperature_adjusted': _get_value(ds, 'TEMP_ADJUSTED', i),
        'temperature_adjusted_qc': _get_qc(ds, 'TEMP_ADJUSTED_QC', i),
        # ... similar for salinity, conductivity, density
    }
```

### Pipeline Run Tracking Model

```python
class PipelineRun:
    """Model for tracking pipeline execution."""
    def __init__(self, run_id, deployment_id, user_id):
        self.run_id = run_id
        self.deployment_id = deployment_id
        self.user_id = user_id
        self.status = 'queued'  # queued, running, completed, failed
        self.start_time = None
        self.end_time = None
        self.log_path = None
        self.error_message = None
    
    def to_dict(self):
        return {
            'run_id': self.run_id,
            'deployment_id': self.deployment_id,
            'status': self.status,
            'start_time': str(self.start_time),
            'end_time': str(self.end_time),
            'duration': (self.end_time - self.start_time).total_seconds() if self.end_time else None,
        }
```


Database table for pipeline runs:

```sql
CREATE TABLE pipeline_runs (
    run_id TEXT PRIMARY KEY,
    deployment_id TEXT NOT NULL,
    user_id INTEGER NOT NULL,
    status TEXT NOT NULL,  -- 'queued', 'running', 'completed', 'failed'
    start_time TEXT,
    end_time TEXT,
    log_path TEXT,
    error_message TEXT,
    FOREIGN KEY (user_id) REFERENCES users(user_id)
);
CREATE INDEX idx_runs_deployment ON pipeline_runs(deployment_id);
CREATE INDEX idx_runs_status ON pipeline_runs(status);
CREATE INDEX idx_runs_time ON pipeline_runs(start_time DESC);
```

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system—essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property Analysis

This feature involves several components with different testing approaches:

1. **Bug fixes** (step4.py dimension coordinate handling) - Example-based unit tests
2. **Database ingestion** - Property-based testing for idempotence and data preservation
3. **Web dashboard** - Integration and UI tests (not suitable for PBT)
4. **Deployment automation** - Smoke tests (one-time setup verification)
5. **Configuration management** - Property-based validation testing

**Components suitable for property-based testing**:
- Database ingestion (idempotence, NaN handling, ID generation)
- Query filtering (correctness of time/spatial/depth filters)
- Configuration validation (parsing and bounds checking)

**Components requiring other testing approaches**:
- UI rendering and interactions → Selenium/Playwright integration tests
- SSH deployment → Smoke tests in staging environment
- Authentication → Security-focused example-based tests
- Pipeline execution monitoring → Integration tests with mock pipelines

### Property 1: Database Ingestion Idempotence

*For any* EGO-format NetCDF file, ingesting it twice SHALL produce identical database state with no duplicate observations or measurements.

**Validates: Requirements 4.3, 4.8**


### Property 2: Observation ID Determinism

*For any* combination of (deployment_id, timestamp, depth), generating the observation_id multiple times SHALL always produce the same hash value.

**Validates: Requirements 4.2**

### Property 3: NaN to NULL Conversion

*For any* measurement value in the NetCDF file, if the value is NaN then the database SHALL store NULL, and if the value is finite then the database SHALL store the numeric value.

**Validates: Requirements 4.5**

### Property 4: QC Flag Preservation

*For any* variable with QC flags in the NetCDF file, the database SHALL store both raw and adjusted values with their corresponding QC flags without any flag value alteration.

**Validates: Requirements 4.4**

### Property 5: Spatial Query Correctness

*For any* geographic bounding box query (lat_min, lat_max, lon_min, lon_max), all returned observations SHALL have latitude within [lat_min, lat_max] and longitude within [lon_min, lon_max].

**Validates: Requirements 5.2**

### Property 6: Temporal Query Correctness

*For any* time range query (start_time, end_time), all returned observations SHALL have timestamps within [start_time, end_time] inclusive.

**Validates: Requirements 5.1**

### Property 7: Depth Query Correctness

*For any* depth range query (min_depth, max_depth), all returned observations SHALL have depth values within [min_depth, max_depth] inclusive.

**Validates: Requirements 5.3**

### Property 8: Configuration Validation Consistency

*For any* deployment configuration with invalid parameters (negative max_depth, latitude outside [-90, 90], or end_date before start_date), the validation function SHALL reject the configuration and return a descriptive error message.

**Validates: Requirements 11.5**


## Error Handling

### Pipeline Execution Errors

**Error Categories**:

1. **Binary Decoding Errors**: Corrupt or incomplete binary files
   - **Handling**: Log specific file that failed, continue with remaining files, report in summary
   - **User feedback**: "Warning: 3 files could not be decoded (see log for details)"

2. **QC Processing Errors**: Unexpected data ranges or missing sensors
   - **Handling**: Apply best-effort QC, flag problematic variables, continue processing
   - **User feedback**: "QC completed with warnings: oxygen sensor data appears corrupted"

3. **Database Ingestion Errors**: Schema mismatch or constraint violations
   - **Handling**: Log error, skip problematic records, continue with valid data
   - **User feedback**: "Database ingestion completed: 125000 observations inserted, 45 skipped due to invalid coordinates"

4. **File System Errors**: Disk full, permission denied
   - **Handling**: Fail fast with clear error message, cleanup partial outputs
   - **User feedback**: "ERROR: Insufficient disk space. Pipeline aborted. Please free up space and retry."

**Error Recovery Mechanisms**:

```python
# Step-level checkpointing
def run_pipeline_with_recovery(data_dir, start_from=None, force=False):
    steps = [
        ('step1', decode_binary),
        ('step2', apply_pre_cleaning),
        ('step3', apply_qc),
        ('step4', split_and_grid),
        ('step5', generate_plots),
        ('step6', generate_report),
        ('step_ego', convert_to_ego),
        ('ingest', ingest_to_database),
    ]
    
    for step_name, step_func in steps:
        if start_from and step_name != start_from:
            if not force:
                # Skip if output already exists
                if step_output_exists(data_dir, step_name):
                    logger.info(f"Skipping {step_name} (output exists)")
                    continue
        
        try:
            logger.info(f"Starting {step_name}")
            step_func(data_dir)
            mark_step_complete(data_dir, step_name)
        except Exception as e:
            logger.error(f"Step {step_name} failed: {e}", exc_info=True)
            if is_critical_step(step_name):
                raise  # Abort pipeline
            else:
                logger.warning(f"Continuing despite {step_name} failure")
```


### Database Error Handling

**Constraint Violation Handling**:

```python
def insert_observation(obs):
    """Insert observation with graceful error handling."""
    try:
        cursor.execute("""
            INSERT INTO observations (observation_id, deployment_id, time, ...)
            VALUES (?, ?, ?, ...)
        """, obs)
    except sqlite3.IntegrityError as e:
        if "UNIQUE constraint" in str(e):
            # Observation already exists - this is expected for idempotent ingestion
            logger.debug(f"Observation {obs['observation_id']} already exists, skipping")
        elif "FOREIGN KEY constraint" in str(e):
            # Referenced deployment doesn't exist
            logger.error(f"Cannot insert observation: deployment {obs['deployment_id']} not found")
            raise
        else:
            logger.error(f"Integrity error inserting observation: {e}")
            raise
```

**Transaction Management**:

```python
def ingest_with_rollback(netcdf_path):
    """Ingest NetCDF with automatic rollback on error."""
    try:
        conn.execute("BEGIN TRANSACTION")
        ingest_deployment(netcdf_path)
        ingest_observations(netcdf_path)
        ingest_measurements(netcdf_path)
        conn.execute("COMMIT")
        logger.info("Ingestion committed successfully")
    except Exception as e:
        conn.execute("ROLLBACK")
        logger.error(f"Ingestion failed, changes rolled back: {e}")
        raise
```

### Web Dashboard Error Handling

**Upload Validation**:

```python
def validate_upload(file):
    """Validate uploaded file before saving."""
    # Check file extension
    if not file.filename.endswith(('.dbd', '.ebd', '.dcd', '.ecd')):
        return False, "Invalid file type. Only .dbd, .ebd, .dcd, .ecd files are allowed."
    
    # Check file size
    file.seek(0, os.SEEK_END)
    size = file.tell()
    file.seek(0)
    if size > MAX_UPLOAD_SIZE:
        return False, f"File too large ({size / 1e6:.1f} MB). Maximum size is {MAX_UPLOAD_SIZE / 1e6:.1f} MB."
    
    # Check filename for malicious characters
    if any(c in file.filename for c in ['..', '/', '\\']):
        return False, "Invalid filename."
    
    return True, None
```

**Pipeline Timeout Handling**:

```python
def monitor_pipeline(run_id, timeout_hours=24):
    """Monitor pipeline execution with timeout."""
    start_time = time.time()
    while True:
        status = get_pipeline_status(run_id)
        if status in ['completed', 'failed']:
            break
        
        elapsed = time.time() - start_time
        if elapsed > timeout_hours * 3600:
            logger.warning(f"Pipeline {run_id} exceeded timeout, killing process")
            kill_pipeline(run_id)
            update_status(run_id, 'failed', 'Timeout exceeded')
            break
        
        time.sleep(10)
```


## Testing Strategy

### Dual Testing Approach

This feature requires a combination of testing strategies:

1. **Unit Tests**: Specific bug fixes, helper functions, edge cases
2. **Property-Based Tests**: Database ingestion idempotence, query correctness, configuration validation
3. **Integration Tests**: Full pipeline execution, dashboard workflow, authentication
4. **Smoke Tests**: Deployment setup, systemd service, database schema creation

### Property-Based Testing

**Library Choice**: `pytest` with `hypothesis` plugin for Python

**Configuration**: Minimum 100 iterations per property test

**Test Organization**:

```
tests/
├── unit/
│   ├── test_step4_dimension_coords.py      # Bug fix verification
│   ├── test_database_helpers.py            # ID generation, NaN conversion
│   └── test_config_parsing.py              # Configuration validation
├── properties/
│   ├── test_ingestion_idempotence.py       # Property 1
│   ├── test_observation_id_determinism.py  # Property 2
│   ├── test_nan_conversion.py              # Property 3
│   ├── test_qc_preservation.py             # Property 4
│   ├── test_spatial_queries.py             # Property 5
│   ├── test_temporal_queries.py            # Property 6
│   ├── test_depth_queries.py               # Property 7
│   └── test_config_validation.py           # Property 8
├── integration/
│   ├── test_pipeline_end_to_end.py
│   ├── test_dashboard_workflow.py
│   └── test_authentication.py
└── fixtures/
    ├── sample_netcdf.nc
    └── test_deployment.yml
```

**Property Test Example**:

```python
import pytest
from hypothesis import given, strategies as st
from database.ingest_netcdf import NetCDFIngester, generate_observation_id

@given(
    deployment_id=st.text(min_size=1, max_size=64),
    timestamp=st.datetimes(min_value=datetime(2000, 1, 1)),
    depth=st.floats(min_value=0, max_value=6000, allow_nan=False)
)
def test_observation_id_determinism(deployment_id, timestamp, depth):
    """
    Feature: glider-pipeline-completion, Property 2: Observation ID Determinism
    For any combination of (deployment_id, timestamp, depth), generating the
    observation_id multiple times SHALL always produce the same hash value.
    """
    time_str = timestamp.isoformat()
    
    # Generate ID multiple times
    id1 = generate_observation_id(deployment_id, time_str, depth)
    id2 = generate_observation_id(deployment_id, time_str, depth)
    id3 = generate_observation_id(deployment_id, time_str, depth)
    
    # All should be identical
    assert id1 == id2 == id3
    # Should be a valid hex string of expected length
    assert len(id1) == 16
    assert all(c in '0123456789abcdef' for c in id1)
```


**Integration Test Example**:

```python
def test_pipeline_with_dimension_coordinate_fix(tmp_path, sample_binary_files):
    """
    Feature: glider-pipeline-completion, Requirement 1.4
    THE Pipeline SHALL complete step1 through step6 without dimension 
    coordinate ValueError exceptions.
    """
    # Setup test deployment directory
    deployment_dir = tmp_path / "test_deployment"
    deployment_dir.mkdir()
    
    # Copy sample binary files
    binary_dir = deployment_dir / "binary"
    binary_dir.mkdir()
    for src in sample_binary_files:
        shutil.copy(src, binary_dir)
    
    # Run full pipeline
    result = subprocess.run(
        ["bash", "run_pipeline.sh", str(deployment_dir)],
        capture_output=True,
        text=True,
        timeout=300
    )
    
    # Should complete without ValueError
    assert result.returncode == 0
    assert "ValueError" not in result.stderr
    assert "cannot reindex or align along dimension" not in result.stderr
    
    # Verify outputs exist
    output_dir = deployment_dir / "output"
    assert (output_dir / "L0-timeseries").exists()
    assert (output_dir / "L1-timeseries").exists()
    assert (output_dir / "plots").exists()
    
    # Verify L0 and L1 NetCDF files were created
    l0_files = list((output_dir / "L0-timeseries").glob("*.nc"))
    l1_files = list((output_dir / "L1-timeseries").glob("*.nc"))
    assert len(l0_files) > 0
    assert len(l1_files) > 0
```

### Unit Testing for Bug Fixes

**Test Coverage Requirements**: >80% line coverage for step4.py

```python
def test_dimension_coordinate_detection():
    """Verify that dimension coordinates are correctly identified."""
    ds = xr.Dataset({
        'TIME': (['TIME'], np.arange(100)),
        'temperature': (['TIME'], np.random.randn(100)),
        'salinity': (['TIME'], np.random.randn(100)),
    })
    
    # TIME is a dimension coordinate
    assert 'TIME' in ds.dims
    # temperature and salinity are not
    assert 'temperature' not in ds.dims
    assert 'salinity' not in ds.dims

def test_qc_masking_skips_dimension_coords():
    """Verify QC masking does not attempt to modify dimension coordinates."""
    ds = xr.Dataset({
        'TIME': (['TIME'], np.arange(10)),
        'temperature': (['TIME'], np.random.randn(10)),
        'temperature_QC': (['TIME'], np.array([1,1,3,1,1,4,1,1,1,1])),
    })
    
    # Apply QC masking (simulating step4 logic)
    ds_masked = ds.copy(deep=True)
    for qv in [v for v in ds.data_vars if v.endswith('_QC')]:
        base_v = qv.replace('_QC', '')
        if base_v in ds_masked.dims:
            continue  # Skip dimension coordinates
        # Mask bad values
        qc = ds_masked[qv].values
        bad = (qc == 3) | (qc == 4)
        vals = ds_masked[base_v].values.copy()
        vals[bad] = np.nan
        ds_masked[base_v] = xr.DataArray(vals, dims=ds_masked[base_v].dims)
    
    # TIME should be unchanged
    assert np.array_equal(ds_masked['TIME'].values, ds['TIME'].values)
    # temperature should have NaN at indices 2 and 5
    assert np.isnan(ds_masked['temperature'].values[2])
    assert np.isnan(ds_masked['temperature'].values[5])
    assert not np.isnan(ds_masked['temperature'].values[0])
```


### Dashboard Testing

**Authentication Tests**:

```python
def test_login_with_valid_credentials(client, test_user):
    """Valid credentials should create session and redirect to /upload."""
    response = client.post('/login', data={
        'username': 'testuser',
        'password': 'correct_password'
    }, follow_redirects=True)
    assert response.status_code == 200
    assert b'Upload Files' in response.data

def test_login_with_invalid_credentials(client):
    """Invalid credentials should show error and not create session."""
    response = client.post('/login', data={
        'username': 'testuser',
        'password': 'wrong_password'
    })
    assert response.status_code == 200
    assert b'Invalid username or password' in response.data

def test_protected_route_requires_login(client):
    """Accessing /upload without login should redirect to /login."""
    response = client.get('/upload')
    assert response.status_code == 302
    assert '/login' in response.location
```

**Upload Tests**:

```python
def test_upload_valid_binary_file(client, auth_client):
    """Valid binary file should be saved to deployment directory."""
    data = {
        'file': (io.BytesIO(b'fake dbd content'), 'test.dbd')
    }
    response = auth_client.post('/upload', data=data, content_type='multipart/form-data')
    assert response.status_code == 200
    
    # Check file was saved
    deployment_id = response.json['deployment_id']
    upload_path = UPLOAD_DIR / deployment_id / 'test.dbd'
    assert upload_path.exists()

def test_upload_rejects_invalid_extension(client, auth_client):
    """Files with wrong extension should be rejected."""
    data = {
        'file': (io.BytesIO(b'fake content'), 'test.txt')
    }
    response = auth_client.post('/upload', data=data, content_type='multipart/form-data')
    assert response.status_code == 400
    assert 'Invalid file type' in response.json['error']
```

### Performance Testing

**Pipeline Performance Monitoring**:

```python
def test_performance_metrics_recorded(tmp_path):
    """Pipeline should record timing for each step."""
    deployment_dir = tmp_path / "perf_test"
    run_pipeline(deployment_dir)
    
    perf_file = deployment_dir / "output" / "performance.json"
    assert perf_file.exists()
    
    with open(perf_file) as f:
        perf = json.load(f)
    
    # Should have entries for all steps
    assert 'step1' in perf
    assert 'step4' in perf
    assert 'step5' in perf
    
    # Each entry should have required fields
    for step, data in perf.items():
        assert 'start_time' in data
        assert 'end_time' in data
        assert 'duration_seconds' in data
        assert data['duration_seconds'] > 0
```


### Database Testing

**Idempotence Property Test**:

```python
@pytest.mark.slow
def test_ingestion_idempotence(sample_netcdf_path, temp_database):
    """
    Feature: glider-pipeline-completion, Property 1: Database Ingestion Idempotence
    For any EGO-format NetCDF file, ingesting it twice SHALL produce identical
    database state with no duplicate observations or measurements.
    """
    ingester = NetCDFIngester(temp_database)
    
    # First ingestion
    ingester.ingest_file(sample_netcdf_path)
    
    # Count records after first ingestion
    conn = sqlite3.connect(temp_database)
    cursor = conn.cursor()
    
    cursor.execute("SELECT COUNT(*) FROM deployments")
    n_deployments_1 = cursor.fetchone()[0]
    
    cursor.execute("SELECT COUNT(*) FROM observations")
    n_observations_1 = cursor.fetchone()[0]
    
    cursor.execute("SELECT COUNT(*) FROM core_measurements")
    n_core_1 = cursor.fetchone()[0]
    
    # Second ingestion (should be idempotent)
    ingester.ingest_file(sample_netcdf_path)
    
    # Count records after second ingestion
    cursor.execute("SELECT COUNT(*) FROM deployments")
    n_deployments_2 = cursor.fetchone()[0]
    
    cursor.execute("SELECT COUNT(*) FROM observations")
    n_observations_2 = cursor.fetchone()[0]
    
    cursor.execute("SELECT COUNT(*) FROM core_measurements")
    n_core_2 = cursor.fetchone()[0]
    
    # Counts should be identical
    assert n_deployments_1 == n_deployments_2
    assert n_observations_1 == n_observations_2
    assert n_core_1 == n_core_2
    
    # Verify no duplicate observation_ids
    cursor.execute("""
        SELECT observation_id, COUNT(*) 
        FROM observations 
        GROUP BY observation_id 
        HAVING COUNT(*) > 1
    """)
    duplicates = cursor.fetchall()
    assert len(duplicates) == 0, f"Found duplicate observations: {duplicates}"
    
    conn.close()
```

**Query Correctness Tests**:

```python
@given(
    lat_min=st.floats(min_value=-90, max_value=85),
    lat_range=st.floats(min_value=0.1, max_value=5)
)
def test_spatial_query_correctness(temp_database, populated_database, lat_min, lat_range):
    """
    Feature: glider-pipeline-completion, Property 5: Spatial Query Correctness
    For any geographic bounding box query, all returned observations SHALL have
    coordinates within the specified bounds.
    """
    lat_max = min(lat_min + lat_range, 90.0)
    lon_min, lon_max = -180.0, 180.0  # Simplify to lat-only for this test
    
    conn = sqlite3.connect(temp_database)
    cursor = conn.cursor()
    
    cursor.execute("""
        SELECT latitude, longitude
        FROM observations
        WHERE latitude BETWEEN ? AND ?
          AND longitude BETWEEN ? AND ?
    """, (lat_min, lat_max, lon_min, lon_max))
    
    results = cursor.fetchall()
    
    # Every result should be within bounds
    for lat, lon in results:
        if lat is not None:  # Handle NULL values
            assert lat_min <= lat <= lat_max, \
                f"Latitude {lat} outside range [{lat_min}, {lat_max}]"
        if lon is not None:
            assert lon_min <= lon <= lon_max
    
    conn.close()
```


## Integration Patterns

### Pipeline to Database Integration

**Automatic Ingestion Hook**:

Add to end of `run_pipeline.sh`:

```bash
#!/bin/bash
# ... existing pipeline steps ...

# Step 7: Database ingestion (optional)
if [ "$SKIP_DB_INGESTION" != "true" ]; then
    echo "Ingesting to database..."
    EGO_FILE=$(find "$OUTPUT_DIR/EGO-timeseries" -name "*.nc" | head -n1)
    if [ -f "$EGO_FILE" ]; then
        python "$PIPELINE_ROOT/database/ingest_netcdf.py" \
            --database "$DATABASE_PATH" \
            --netcdf "$EGO_FILE" \
            || echo "WARNING: Database ingestion failed (pipeline outputs are still valid)"
    else
        echo "WARNING: No EGO NetCDF file found, skipping database ingestion"
    fi
fi

echo "Pipeline complete!"
```

**Ingestion Script** (`database/ingest_netcdf.py`):

```python
#!/usr/bin/env python3
"""Ingest EGO NetCDF files into SQLite database."""
import argparse
import sys
from pathlib import Path
from .ingester import NetCDFIngester

def main():
    parser = argparse.ArgumentParser(description="Ingest glider NetCDF to database")
    parser.add_argument("--database", required=True, help="Path to SQLite database")
    parser.add_argument("--netcdf", required=True, help="Path to EGO NetCDF file")
    parser.add_argument("--verbose", action="store_true", help="Enable verbose logging")
    args = parser.parse_args()
    
    if not Path(args.netcdf).exists():
        print(f"ERROR: NetCDF file not found: {args.netcdf}", file=sys.stderr)
        return 1
    
    try:
        ingester = NetCDFIngester(args.database)
        stats = ingester.ingest_file(args.netcdf)
        
        print(f"Database ingestion complete:")
        print(f"  Deployment: {stats['deployment_id']}")
        print(f"  Observations inserted: {stats['n_observations']}")
        print(f"  Core measurements: {stats['n_core']}")
        print(f"  BGC measurements: {stats['n_bgc']}")
        return 0
        
    except Exception as e:
        print(f"ERROR: Ingestion failed: {e}", file=sys.stderr)
        if args.verbose:
            import traceback
            traceback.print_exc()
        return 1

if __name__ == "__main__":
    sys.exit(main())
```

### Dashboard to Pipeline Integration

**Pipeline Execution Flow**:

```python
# dashboard/routes/pipeline.py

@app.route('/pipeline/run/<deployment_id>', methods=['POST'])
@login_required
def run_pipeline(deployment_id):
    """Start pipeline processing for uploaded deployment."""
    deployment_dir = Path(DEPLOYMENT_DIR) / deployment_id
    if not deployment_dir.exists():
        return jsonify({'error': 'Deployment not found'}), 404
    
    # Generate unique run ID
    run_id = f"{deployment_id}_{int(time.time())}"
    
    # Create pipeline run record
    run = PipelineRun(run_id, deployment_id, current_user.id)
    db.session.add(run)
    db.session.commit()
    
    # Start pipeline as background process
    runner = PipelineRunner(deployment_dir, run_id)
    runner.start()
    
    return jsonify({
        'run_id': run_id,
        'status': 'started',
        'log_url': f'/pipeline/logs/{run_id}'
    })
```

