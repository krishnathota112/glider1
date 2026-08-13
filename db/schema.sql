-- ============================================================
--  glider_rtqc — SQLite schema  (EGO 1.5 source)
--
--    meta         one row per deployment
--    observation  one row per (glider_id, timestamp) sample
--    core         one row per observation, one column set per physical param
--    bgc          one row per observation, one column set per bgc param
--
--  `core` and `bgc` are BOTH wide: every parameter gets four real, named
--  columns —  <VAR>, <VAR>_QC, <VAR>_ADJUSTED, <VAR>_ADJUSTED_QC — so the
--  tables read directly in a SQL browser with no pivoting and no
--  variable_name string column.
--
--  Those two tables are NOT declared here. Their columns depend on which
--  parameters a deployment actually carries, so db/load_deployment.py builds
--  the CREATE TABLE statements from the EGO PARAMETER array at load time.
--  That keeps the columns named and wide without hardcoding a sensor list:
--  a deployment carrying NITRATE or PH_IN_SITU_TOTAL gets those columns
--  automatically.
--
--  All writes are idempotent: observation_id is a deterministic hash of
--  (glider_id, timestamp) and every insert is ON CONFLICT DO UPDATE.
--  DO UPDATE, never INSERT OR REPLACE: with foreign_keys=ON, REPLACE deletes
--  the existing row first, which cascades and would wipe the child rows.
-- ============================================================

PRAGMA foreign_keys = ON;


-- ------------------------------------------------------------
--  meta — one row per deployment
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS meta (
    glider_id                TEXT    PRIMARY KEY,
    deployment_name          TEXT,
    deployment_start         TEXT,
    deployment_end           TEXT,
    max_depth_dbar           REAL,
    n_profiles               INTEGER,
    n_observations           INTEGER,
    n_gps_fixes              INTEGER,
    distance_over_ground_km  REAL,
    pipeline_version         TEXT,
    ego_format_version       TEXT,
    data_mode                TEXT,
    institution              TEXT,
    rtqc_tests_applied       TEXT,
    processed_at             TEXT,
    ego_l0_path              TEXT,
    ego_l1_path              TEXT
);


-- ------------------------------------------------------------
--  observation — one row per (glider_id, timestamp)
--
--  observation_id is a deterministic 63-bit hash of (glider_id, timestamp),
--  declared INTEGER PRIMARY KEY so SQLite aliases it to the rowid; joins from
--  core/bgc then hit the B-tree directly with no secondary index.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS observation (
    observation_id   INTEGER PRIMARY KEY,
    glider_id        TEXT    NOT NULL
                         REFERENCES meta(glider_id) ON DELETE CASCADE,
    timestamp        TEXT    NOT NULL,
    latitude         REAL,
    longitude        REAL,
    phase            INTEGER,   -- EGO reference table 9.2
    phase_number     INTEGER,   -- profile number
    position_qc      INTEGER,
    has_gps_fix      INTEGER DEFAULT 0
);


-- ------------------------------------------------------------
--  Indexes on observation (core/bgc indexes are created by the loader)
-- ------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_obs_glider_time
    ON observation (glider_id, timestamp);

CREATE INDEX IF NOT EXISTS idx_obs_glider_phase
    ON observation (glider_id, phase_number);

CREATE INDEX IF NOT EXISTS idx_obs_gps
    ON observation (glider_id, has_gps_fix);
