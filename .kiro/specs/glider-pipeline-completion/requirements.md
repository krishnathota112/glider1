# Requirements Document

## Introduction

This document specifies requirements for completing and deploying the glider data processing pipeline. The system processes raw glider data through multiple quality control stages, ingests results into a database, and provides a web interface for pipeline execution and monitoring. The existing pipeline (step1-step6) has bugs that must be fixed, and new components (database ingestion, web dashboard, deployment automation) must be added.

## Glossary

- **Pipeline**: The end-to-end glider data processing system consisting of step1 through step6
- **L0_Data**: Level 0 raw decoded timeseries data from binary glider files
- **L1_Data**: Level 1 quality-controlled data with ARGO flags applied
- **NetCDF**: Network Common Data Form, the file format for storing glider profile data
- **Profile**: A single dive or climb cycle from a glider deployment
- **QC_Flags**: ARGO Real-Time Quality Control flags (1=good, 2=probably good, 3=bad, 4=bad, 9=missing)
- **Dimension_Coordinate**: An xarray coordinate variable that defines a dimension (cannot be reassigned directly)
- **Database**: SQLite database storing glider observations and measurements
- **Dashboard**: Web interface for running the pipeline and viewing results
- **SSH_Environment**: Remote Linux server where the production system will be deployed
- **Deployment**: A single glider mission with associated raw data and processed outputs
- **EGO_Format**: European Glider Observatories NetCDF format (version 1.5)

## Requirements

### Requirement 1: Fix Dimension Coordinate Assignment Errors

**User Story:** As a pipeline operator, I want the pipeline to correctly handle xarray dimension coordinates, so that step4 completes without ValueError exceptions.

#### Acceptance Criteria

1. WHEN step4.py encounters a dimension coordinate variable (TIME, DEPTH, LATITUDE, LONGITUDE), THE Pipeline SHALL use Dataset.assign_coords() instead of direct .values assignment
2. WHEN step4.py applies QC masks to data variables, THE Pipeline SHALL skip dimension coordinates
3. WHEN step4.py creates a masked dataset copy, THE Pipeline SHALL use xr.DataArray constructor for non-dimension variables only
4. THE Pipeline SHALL complete step1 through step6 without dimension coordinate ValueError exceptions
5. WHEN processing the test dataset from T:\glider_data, THE Pipeline SHALL produce L0 and L1 NetCDF outputs without errors

### Requirement 2: Complete Pipeline End-to-End Testing

**User Story:** As a pipeline developer, I want to run the complete pipeline on real glider data, so that I can verify all processing steps work correctly together.

#### Acceptance Criteria

1. WHEN provided with raw binary files from T:\glider_data, THE Pipeline SHALL decode them into L0 NetCDF format
2. WHEN L0 data exists, THE Pipeline SHALL apply quality control and produce L1 NetCDF files
3. WHEN L1 data exists, THE Pipeline SHALL generate diagnostic plots and reports
4. THE Pipeline SHALL produce outputs in all expected directories (L0-timeseries, L0-profiles, L0-gridfiles, L1-timeseries, L1-profiles, L1-gridfiles, plots, reports)
5. WHEN the pipeline completes, THE Pipeline SHALL log a summary of processed profiles, data coverage, and QC statistics

### Requirement 3: Database Schema for Glider Observations

**User Story:** As a data manager, I want glider data stored in a structured database, so that I can query observations across multiple deployments.

#### Acceptance Criteria

1. THE Database SHALL have a deployments table with fields (deployment_id, glider_id, start_date, end_date, platform_type, data_source)
2. THE Database SHALL have an observations table with fields (observation_id, deployment_id, time, latitude, longitude, depth, profile_index, profile_direction)
3. THE Database SHALL have a core_measurements table with fields (observation_id, pressure, pressure_qc, temperature, temperature_qc, salinity, salinity_qc, conductivity, conductivity_qc)
4. THE Database SHALL have a bgc_measurements table with fields (observation_id, oxygen, oxygen_qc, chlorophyll, chlorophyll_qc, cdom, cdom_qc, backscatter_700, backscatter_700_qc)
5. THE Database SHALL enforce foreign key constraints (observations.deployment_id → deployments.deployment_id, measurements.observation_id → observations.observation_id)
6. THE Database SHALL use SQLite as the storage engine
7. THE Database SHALL store QC flag values as integers (1, 2, 3, 4, 9)

### Requirement 4: NetCDF to Database Ingestion

**User Story:** As a data manager, I want to ingest NetCDF files into the database, so that all glider data is queryable in one place.

#### Acceptance Criteria

1. WHEN provided with an EGO-format NetCDF file, THE Ingestion_System SHALL extract deployment metadata and insert it into the deployments table
2. WHEN ingesting observations, THE Ingestion_System SHALL create unique observation_id values from (deployment_id, time, depth)
3. WHEN an observation already exists in the database, THE Ingestion_System SHALL skip it (idempotent ingestion)
4. WHEN ingesting measurements, THE Ingestion_System SHALL store both raw values and QC flags for each variable
5. WHEN a variable has missing data (NaN), THE Ingestion_System SHALL store NULL in the database
6. THE Ingestion_System SHALL commit records in batches of 1000 to optimize performance
7. WHEN ingestion completes, THE Ingestion_System SHALL log the count of inserted deployments, observations, and measurements
8. THE Ingestion_System SHALL handle multiple NetCDF files from the same deployment without creating duplicate records

### Requirement 5: Database Querying and Export

**User Story:** As a scientist, I want to query glider data by time, location, and depth range, so that I can extract datasets for analysis.

#### Acceptance Criteria

1. THE Database SHALL support SQL queries filtering by time range (observations.time BETWEEN start AND end)
2. THE Database SHALL support SQL queries filtering by geographic bounding box (latitude/longitude ranges)
3. THE Database SHALL support SQL queries filtering by depth range (observations.depth BETWEEN min AND max)
4. THE Database SHALL support SQL queries filtering by QC flag values (e.g., WHERE temperature_qc IN (1, 2))
5. THE Database SHALL support JOIN queries combining observations with core and BGC measurements
6. THE Database SHALL provide a view "best_value_measurements" that returns COALESCE(adjusted_value, raw_value) for each variable
7. WHEN exporting query results, THE Database SHALL support CSV and NetCDF output formats

### Requirement 6: Web Dashboard for Pipeline Execution

**User Story:** As a pipeline operator, I want a web interface to run the pipeline, so that I don't need command-line access to the server.

#### Acceptance Criteria

1. THE Dashboard SHALL display a file upload form accepting .dbd, .ebd, .dcd, .ecd binary files
2. WHEN files are uploaded, THE Dashboard SHALL store them in a deployment-specific directory structure
3. THE Dashboard SHALL display a "Run Pipeline" button that triggers bash run_pipeline.sh on the uploaded data directory
4. WHEN the pipeline is running, THE Dashboard SHALL display real-time progress updates from pipeline step outputs
5. WHEN the pipeline completes, THE Dashboard SHALL display a summary of outputs produced (NetCDF file paths, plot counts, report location)
6. THE Dashboard SHALL display a list of recent pipeline runs with status (running, completed, failed)
7. WHEN a pipeline run fails, THE Dashboard SHALL display the error message and full log output

### Requirement 7: Web Dashboard Results Viewing

**User Story:** As a scientist, I want to view processed glider data through the web dashboard, so that I can quickly assess data quality without downloading files.

#### Acceptance Criteria

1. THE Dashboard SHALL display a list of all deployments in the database with metadata (glider_id, start_date, end_date, profile_count)
2. WHEN a deployment is selected, THE Dashboard SHALL display diagnostic plots (track map, T-S diagram, section plots)
3. WHEN a deployment is selected, THE Dashboard SHALL display data coverage statistics (variable availability, QC pass rates)
4. THE Dashboard SHALL provide download links for NetCDF files (L0, L1, EGO format)
5. THE Dashboard SHALL provide a download link for the summary report PDF
6. THE Dashboard SHALL support filtering deployments by date range and glider ID

### Requirement 8: Database Ingestion Integration with Pipeline

**User Story:** As a pipeline operator, I want the pipeline to automatically ingest results into the database, so that new data is immediately available for querying.

#### Acceptance Criteria

1. WHEN the pipeline completes step_ego.py, THE Pipeline SHALL automatically invoke the database ingestion script
2. WHEN ingestion is invoked, THE Pipeline SHALL pass the path to EGO-format NetCDF files
3. IF ingestion fails, THE Pipeline SHALL log the error but not abort (pipeline outputs are still valid)
4. WHEN ingestion completes successfully, THE Pipeline SHALL log "Database ingestion complete: N observations inserted"
5. THE Pipeline SHALL support a --skip-db-ingestion flag to disable automatic ingestion

### Requirement 9: SSH Deployment Configuration

**User Story:** As a system administrator, I want deployment scripts for the SSH environment, so that the production system is reproducible and maintainable.

#### Acceptance Criteria

1. THE Deployment_System SHALL provide a requirements.txt file listing all Python dependencies with pinned versions
2. THE Deployment_System SHALL provide a setup.sh script that creates a Python virtual environment and installs dependencies
3. THE Deployment_System SHALL provide a systemd service file for running the web dashboard as a background service
4. THE Deployment_System SHALL provide environment configuration files (production.env, staging.env) with database paths and upload directories
5. WHEN setup.sh is executed on the SSH server, THE Deployment_System SHALL create all required directories (uploads, database, logs)
6. THE Deployment_System SHALL document SSH port forwarding commands for accessing the web dashboard from a local browser
7. THE Deployment_System SHALL provide a backup script that exports the database to SQL dump files daily

### Requirement 10: Pipeline Error Recovery

**User Story:** As a pipeline operator, I want the pipeline to gracefully handle errors and resume from the last successful step, so that transient failures don't require reprocessing all data.

#### Acceptance Criteria

1. WHEN a pipeline step fails, THE Pipeline SHALL log the error with full stack trace to a step-specific log file
2. WHEN rerunning the pipeline on the same data directory, THE Pipeline SHALL detect existing output files and skip already-completed steps
3. THE Pipeline SHALL support a --force flag that deletes existing outputs and reruns all steps
4. THE Pipeline SHALL support a --start-from flag that begins execution at a specific step (e.g., --start-from step4)
5. WHEN resuming from a partial run, THE Pipeline SHALL validate that required input files exist before starting a step

### Requirement 11: Configuration Management for Deployment Parameters

**User Story:** As a pipeline operator, I want to override auto-detected parameters via configuration files, so that I can handle edge cases without modifying code.

#### Acceptance Criteria

1. WHEN a deployment.yml file exists in the data directory, THE Pipeline SHALL read deployment metadata (start_date, end_date, max_depth, gps_bounds)
2. WHEN deployment.yml specifies a time window, THE Pipeline SHALL crop data outside that window during pre-cleaning
3. WHEN deployment.yml is absent, THE Pipeline SHALL auto-detect parameters from GPS fixes and binary file headers
4. THE Pipeline SHALL support a --config flag to specify an alternate configuration file path
5. THE Pipeline SHALL validate configuration values (e.g., max_depth > 0, GPS bounds within -90 to 90 latitude)
6. WHEN configuration validation fails, THE Pipeline SHALL print a detailed error message and exit with status code 1

### Requirement 12: Web Dashboard Authentication

**User Story:** As a system administrator, I want the web dashboard to require login credentials, so that only authorized users can run the pipeline and view data.

#### Acceptance Criteria

1. THE Dashboard SHALL display a login form requiring username and password
2. WHEN valid credentials are provided, THE Dashboard SHALL create a session token valid for 24 hours
3. WHEN invalid credentials are provided, THE Dashboard SHALL display "Invalid username or password" and not create a session
4. WHEN a user is not logged in, THE Dashboard SHALL redirect all requests to the login page
5. THE Dashboard SHALL support a user management interface for adding/removing accounts (admin users only)
6. THE Dashboard SHALL hash passwords using bcrypt with a cost factor of 12
7. THE Dashboard SHALL log all login attempts (successful and failed) with timestamp and IP address

### Requirement 13: Pipeline Performance Monitoring

**User Story:** As a pipeline operator, I want to track processing time for each step, so that I can identify performance bottlenecks.

#### Acceptance Criteria

1. WHEN each pipeline step completes, THE Pipeline SHALL log the elapsed time in seconds
2. WHEN the pipeline completes, THE Pipeline SHALL write a performance summary to output/performance.json
3. THE Performance_Summary SHALL include fields (step_name, start_time, end_time, duration_seconds, input_file_count, output_file_size_mb)
4. THE Dashboard SHALL display a performance chart showing step durations for recent pipeline runs
5. WHEN a step takes longer than expected, THE Dashboard SHALL highlight it in the performance chart

### Requirement 14: Automated Testing for Bug Fixes

**User Story:** As a pipeline developer, I want automated tests for the dimension coordinate fix, so that the bug cannot reoccur in future changes.

#### Acceptance Criteria

1. THE Test_Suite SHALL include a unit test that creates a dataset with TIME as a dimension coordinate
2. THE Test_Suite SHALL verify that step4.split_profiles() does not raise ValueError when masking QC flags
3. THE Test_Suite SHALL verify that step4.make_grid() correctly handles both "time" and "TIME" dimension names
4. THE Test_Suite SHALL include an integration test that runs the full pipeline on a minimal test dataset (10 profiles)
5. THE Test_Suite SHALL verify that all expected output files exist after the integration test
6. THE Test_Suite SHALL run using pytest and complete in under 60 seconds
7. THE Test_Suite SHALL generate a coverage report showing >80% line coverage for step4.py

### Requirement 15: Database Backup and Recovery

**User Story:** As a system administrator, I want automated database backups, so that glider data is not lost due to hardware failure.

#### Acceptance Criteria

1. THE Backup_System SHALL export the database to a timestamped SQL dump file daily at 02:00 UTC
2. THE Backup_System SHALL compress backups using gzip to reduce storage space
3. THE Backup_System SHALL retain backups for 30 days, then delete older files
4. THE Backup_System SHALL verify backup integrity by attempting to restore to a temporary database
5. WHEN backup verification fails, THE Backup_System SHALL send an alert email to the system administrator
6. THE Backup_System SHALL provide a restore.sh script that imports a backup file into the production database
7. WHEN restoring from backup, THE Restore_Script SHALL prompt for confirmation before overwriting the existing database
