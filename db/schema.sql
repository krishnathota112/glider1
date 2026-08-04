-- ============================================================
--  glider_rtqc — SQLite schema
--
--  Four tables, ARGO-style long format:
--
--    meta         one row per deployment (glider_id)
--    observation  one row per (glider_id, timestamp) sample
--    core         one row per (observation_id, variable_name), physical vars
--    bgc          one row per (observation_id, variable_name), biogeochemical
--
--  `core` and `bgc` are keyed on a variable_name string rather than having a
--  column per variable, so a glider with a sensor suite this pipeline has
--  never seen adds new rows, never new columns. No ALTER TABLE, ever.
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
    glider_id         TEXT    PRIMARY KEY,
    deployment_name   TEXT,
    deployment_start  TEXT,              -- ISO 8601 UTC
    deployment_end    TEXT,              -- ISO 8601 UTC
    max_depth_dbar    REAL,
    n_profiles_l0     INTEGER,
    n_profiles_l1     INTEGER,
    pipeline_version  TEXT,
    processed_at      TEXT,              -- ISO 8601 UTC, when ingested
    -- provenance: which files this row was built from
    l0_path           TEXT,
    l1_path           TEXT,
    n_observations    INTEGER
);


-- ------------------------------------------------------------
--  observation — one row per (glider_id, timestamp)
--
--  Holds everything that describes *where and how* the sample was taken.
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
    depth_m               REAL,
    pressure              REAL,
    latitude              REAL,
    longitude             REAL,
    profile_id            REAL,

    -- navigation / engineering channels present in the L0 timeseries.
    -- Loaded so nothing in the NetCDF is silently dropped; all nullable,
    -- since not every glider reports every channel.
    profile_direction     REAL,
    heading               REAL,
    pitch                 REAL,
    roll                  REAL,
    waypoint_latitude     REAL,
    waypoint_longitude    REAL,
    distance_over_ground  REAL
);


-- ------------------------------------------------------------
--  core — physical / CTD-derived variables
--
--  value            raw L0 value
--  qc_flag          L1 <var>_QC        (ARGO ref table 2)
--  value_adjusted   L1 corrected value (despiked / smoothed / lag-corrected),
--                   NULL when the pipeline computed no correction
--  adjusted_qc_flag QC flag on the adjusted value, NULL when none exists
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS core (
    observation_id    INTEGER NOT NULL
                          REFERENCES observation(observation_id) ON DELETE CASCADE,
    variable_name     TEXT    NOT NULL,   -- ARGO short name, e.g. TEMP, PSAL
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
    variable_name     TEXT    NOT NULL,   -- ARGO short name, e.g. DOXY, CHLA
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
CREATE INDEX IF NOT EXISTS idx_observation_glider_profile
    ON observation (glider_id, profile_id);

-- Depth-binned queries.
CREATE INDEX IF NOT EXISTS idx_observation_depth
    ON observation (depth_m);

-- "give me all TEMP" without scanning the whole table. The (observation_id,
-- variable_name) PK can't serve this — variable_name is its second column.
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
-- Useful when you don't care which family a variable belongs to.
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
           o.depth_m,
           o.pressure,
           o.latitude,
           o.longitude,
           o.profile_id,
           m.family,
           m.variable_name,
           m.value,
           m.qc_flag,
           m.value_adjusted,
           m.adjusted_qc_flag
      FROM observation o
      JOIN measurement m ON m.observation_id = o.observation_id;

-- Per-variable QC breakdown for a deployment — the query the summary report
-- answers, but straight from SQL.
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
           SUM(m.value_adjusted IS NOT NULL)                 AS n_adjusted,
           ROUND(100.0 * SUM(m.qc_flag = 1) / COUNT(*), 2)   AS pct_good
      FROM observation o
      JOIN measurement m ON m.observation_id = o.observation_id
     GROUP BY o.glider_id, m.family, m.variable_name;

-- NOTE: load_deployment.py additionally creates two pivoted wide views,
-- `wide_core` and `wide_bgc`, with one column set per variable
-- (TEMP, TEMP_ADJUSTED, TEMP_QC, ...). Those are generated after load
-- because their column list depends on which variables the deployment
-- actually contains — they give you single-table raw-vs-adjusted
-- comparison without a join, off the same long storage.
