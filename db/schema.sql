-- ============================================================
--  glider_rtqc — SQLite schema  (EGO 1.5 source)
--
--  Four tables:
--
--    meta         one row per deployment (glider_id)
--    observation  one row per (glider_id, timestamp) sample
--    core         one row per (observation_id, variable_name), physical vars
--    bgc          one row per (observation_id, variable_name), biogeochemical
--
--  This schema reads from EGO 1.5 format NetCDF files — the single
--  authoritative source of variable names, units, and QC flags. Variable
--  names stored in core/bgc match the EGO PARAMETER array exactly (TEMP,
--  PSAL, PRES, DOXY, CHLA, etc.). No independent name-mapping exists here.
--
--  `core` and `bgc` are keyed on a variable_name string rather than having a
--  column per variable, so a glider with a sensor suite never seen before
--  adds new rows, never new columns. No ALTER TABLE, ever.
--
--  All writes are idempotent: observation_id is a deterministic hash of
--  (glider_id, timestamp), and every insert is an ON CONFLICT DO UPDATE
--  upsert. Re-ingesting the same deployment overwrites in place.
--
--  NOTE ON UPSERT STRATEGY
--  -----------------------
--  We deliberately use ON CONFLICT DO UPDATE and *not* INSERT OR REPLACE.
--  With foreign_keys=ON, REPLACE resolves a conflict by DELETEing the
--  existing row first, which fires ON DELETE CASCADE and would silently
--  wipe the core/bgc rows belonging to that observation. DO UPDATE mutates
--  the row in place and leaves children intact.
--
--  Apply with:  sqlite3 glider_rtqc.db < db/schema.sql
--  (db/load_deployment.py applies it automatically.)
-- ============================================================

PRAGMA foreign_keys = ON;


-- ------------------------------------------------------------
--  meta — one row per deployment
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS meta (
    glider_id             TEXT    PRIMARY KEY,
    deployment_name       TEXT,
    deployment_start      TEXT,              -- ISO 8601 UTC
    deployment_end        TEXT,              -- ISO 8601 UTC
    max_depth_dbar        REAL,
    n_profiles            INTEGER,
    n_observations        INTEGER,
    n_gps_fixes           INTEGER,
    distance_over_ground_km  REAL,           -- from GPS fixes only
    pipeline_version      TEXT,
    ego_format_version    TEXT,              -- e.g. "1.5"
    data_mode             TEXT,              -- R or D
    institution           TEXT,
    rtqc_tests_applied    TEXT,
    processed_at          TEXT,              -- ISO 8601 UTC, when ingested
    -- provenance: which files this row was built from
    ego_l0_path           TEXT,
    ego_l1_path           TEXT
);


-- ------------------------------------------------------------
--  observation — one row per (glider_id, timestamp)
--
--  Holds everything that describes *where and when* the sample was taken.
--  Every core/bgc reading points back here.
--
--  observation_id is a deterministic 63-bit hash of (glider_id, timestamp).
--  Declared INTEGER PRIMARY KEY so SQLite aliases it to the rowid — the
--  joins from core/bgc then hit the B-tree directly with no extra index.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS observation (
    observation_id        INTEGER PRIMARY KEY,
    glider_id             TEXT    NOT NULL
                              REFERENCES meta(glider_id) ON DELETE CASCADE,
    timestamp             TEXT    NOT NULL,   -- ISO 8601 UTC
    pressure              REAL,              -- PRES in decibar
    latitude              REAL,              -- interpolated position
    longitude             REAL,              -- interpolated position
    phase                 INTEGER,           -- EGO phase code (table 9.2)
    phase_number          INTEGER,           -- profile number
    position_qc           INTEGER,           -- POSITION_QC flag
    has_gps_fix           INTEGER DEFAULT 0  -- 1 if this timestamp is a real GPS fix
);


-- ------------------------------------------------------------
--  core — physical / CTD-derived variables
--
--  value            EGO <VAR> (raw measurement in EGO units)
--  qc_flag          <VAR>_QC        (EGO reference table 2.1)
--  value_adjusted   <VAR>_ADJUSTED  (corrected value),
--                   NULL when fill value or no correction computed
--  adjusted_qc_flag <VAR>_ADJUSTED_QC, NULL when none exists
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS core (
    observation_id    INTEGER NOT NULL
                          REFERENCES observation(observation_id) ON DELETE CASCADE,
    variable_name     TEXT    NOT NULL,   -- EGO parameter name, e.g. TEMP, PSAL
    value             REAL,
    qc_flag           INTEGER,
    value_adjusted    REAL,
    adjusted_qc_flag  INTEGER,
    PRIMARY KEY (observation_id, variable_name)
) WITHOUT ROWID;


-- ------------------------------------------------------------
--  bgc — biogeochemical variables. Identical shape to core.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bgc (
    observation_id    INTEGER NOT NULL
                          REFERENCES observation(observation_id) ON DELETE CASCADE,
    variable_name     TEXT    NOT NULL,   -- EGO parameter name, e.g. DOXY, CHLA
    value             REAL,
    qc_flag           INTEGER,
    value_adjusted    REAL,
    adjusted_qc_flag  INTEGER,
    PRIMARY KEY (observation_id, variable_name)
) WITHOUT ROWID;


-- ------------------------------------------------------------
--  Indexes
-- ------------------------------------------------------------

-- Primary access path: "this glider, this time window".
CREATE INDEX IF NOT EXISTS idx_observation_glider_time
    ON observation (glider_id, timestamp);

-- Cross-deployment time slices.
CREATE INDEX IF NOT EXISTS idx_observation_timestamp
    ON observation (timestamp);

-- Profile-wise extraction (plotting a single dive).
CREATE INDEX IF NOT EXISTS idx_observation_glider_phase
    ON observation (glider_id, phase_number);

-- Pressure-binned queries.
CREATE INDEX IF NOT EXISTS idx_observation_pressure
    ON observation (pressure);

-- "give me all TEMP" without scanning the whole table.
CREATE INDEX IF NOT EXISTS idx_core_variable
    ON core (variable_name);
CREATE INDEX IF NOT EXISTS idx_bgc_variable
    ON bgc (variable_name);

-- "all good TEMP" — covers the overwhelmingly common qc_flag filter.
CREATE INDEX IF NOT EXISTS idx_core_variable_qc
    ON core (variable_name, qc_flag);
CREATE INDEX IF NOT EXISTS idx_bgc_variable_qc
    ON bgc (variable_name, qc_flag);


-- ------------------------------------------------------------
--  Views
-- ------------------------------------------------------------

-- Every measurement, core and bgc together, tagged with its source table.
CREATE VIEW IF NOT EXISTS measurement AS
    SELECT 'core' AS family, observation_id, variable_name,
           value, qc_flag, value_adjusted, adjusted_qc_flag
      FROM core
    UNION ALL
    SELECT 'bgc'  AS family, observation_id, variable_name,
           value, qc_flag, value_adjusted, adjusted_qc_flag
      FROM bgc;

-- Fully denormalised long view: sample context + one measurement per row.
CREATE VIEW IF NOT EXISTS measurement_full AS
    SELECT o.glider_id,
           o.timestamp,
           o.pressure,
           o.latitude,
           o.longitude,
           o.phase,
           o.phase_number,
           m.family,
           m.variable_name,
           m.value,
           m.qc_flag,
           m.value_adjusted,
           m.adjusted_qc_flag
      FROM observation o
      JOIN measurement m ON m.observation_id = o.observation_id;

-- Per-variable QC breakdown for a deployment.
CREATE VIEW IF NOT EXISTS qc_summary AS
    SELECT o.glider_id,
           m.family,
           m.variable_name,
           COUNT(*)                                          AS n_total,
           SUM(m.qc_flag = 1)                                AS n_good,
           SUM(m.qc_flag = 2)                                AS n_probably_good,
           SUM(m.qc_flag = 3)                                AS n_probably_bad,
           SUM(m.qc_flag = 4)                                AS n_bad,
           SUM(m.qc_flag = 9)                                AS n_missing,
           SUM(m.qc_flag = 0)                                AS n_no_qc,
           SUM(m.value_adjusted IS NOT NULL)                 AS n_adjusted,
           ROUND(100.0 * SUM(m.qc_flag IN (1,2)) / COUNT(*), 2) AS pct_good
      FROM observation o
      JOIN measurement m ON m.observation_id = o.observation_id
     GROUP BY o.glider_id, m.family, m.variable_name;
