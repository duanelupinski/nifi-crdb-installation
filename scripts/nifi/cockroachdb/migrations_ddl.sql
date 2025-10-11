-- Put in the target database for the migration.
CREATE SCHEMA IF NOT EXISTS _migrations;

-- ===== ENUM TYPES =====
CREATE TYPE IF NOT EXISTS _migrations.migration_status AS ENUM (
  'pending','running','succeeded','failed','canceled','partial'
);

CREATE TYPE IF NOT EXISTS _migrations.statement_phase AS ENUM (
  'ensure_db','drop','create_table','alter_table','index','constraint','family','other'
);

CREATE TYPE IF NOT EXISTS _migrations.task_status AS ENUM (
  'pending','running','succeeded','failed','paused'
);

-- ===== RUNS =====
CREATE TABLE IF NOT EXISTS _migrations.migration_run (
  -- Random primary key avoids hotspots.
  run_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Correlators
  flowfile_uuid UUID,                       -- NiFi FlowFile UUID (if available)
  migration_id STRING NOT NULL,             -- payload's "migrationId" (human-readable)

  -- Target & mode
  target_db STRING NOT NULL,
  target_schema STRING NOT NULL,
  ddl_mode STRING NOT NULL,                 -- e.g., generate_only, drop_and_apply, etc.

  -- Artifacts
  payload JSON,                             -- raw incoming payload
  schema_mapping JSON,                      -- generated mapping doc (JSON)

  -- Status & timings
  status _migrations.migration_status NOT NULL DEFAULT 'pending',
  started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  finished_at TIMESTAMPTZ,

  -- Error + misc
  error_text STRING,
  error_code STRING,
  metrics JSON,                             -- aggregate counters

  -- Fast lookups & uniqueness
  UNIQUE (flowfile_uuid),

  -- Families: keep hot/skinny fields separate from large text/JSON
  FAMILY f_meta (run_id, migration_id, flowfile_uuid, status, ddl_mode,
                 target_db, target_schema, started_at, finished_at),
  FAMILY f_docs (payload, schema_mapping, metrics, error_text, error_code)
);

CREATE INDEX IF NOT EXISTS idx_migration_run_status_started
  ON _migrations.migration_run (status, started_at DESC)
  STORING (target_db, target_schema, ddl_mode);

CREATE INDEX IF NOT EXISTS idx_migration_run_finished
  ON _migrations.migration_run (finished_at DESC)
  WHERE finished_at IS NOT NULL;

-- ===== DDL STATEMENTS EXECUTED =====
CREATE TABLE IF NOT EXISTS _migrations.ddl_statement (
  stmt_id INT8 PRIMARY KEY DEFAULT unordered_unique_rowid(),

  run_id UUID NOT NULL
    REFERENCES _migrations.migration_run (run_id) ON DELETE CASCADE,

  ordinal INT4 NOT NULL,                    -- execution order within the run
  phase _migrations.statement_phase NOT NULL,
  statement STRING NOT NULL,                -- the exact SQL we attempted/applied

  applied BOOL NOT NULL DEFAULT false,
  applied_at TIMESTAMPTZ,
  retries INT4 NOT NULL DEFAULT 0,
  duration_ms INT8,                         -- measured duration per attempt (latest)

  error_text STRING,
  error_code STRING,

  UNIQUE (run_id, ordinal),

  FAMILY f_small (stmt_id, run_id, ordinal, phase, applied,
                  applied_at, retries, duration_ms),
  FAMILY f_text  (statement, error_text, error_code)
);

CREATE INDEX IF NOT EXISTS idx_stmt_run_phase
  ON _migrations.ddl_statement (run_id, phase, applied, ordinal);

CREATE INDEX IF NOT EXISTS idx_stmt_errors
  ON _migrations.ddl_statement (run_id, applied, ordinal)
  STORING (error_text, error_code)
  WHERE error_text IS NOT NULL;

-- ===== OBJECT STATE TRACKER =====
CREATE TABLE IF NOT EXISTS _migrations.object_state (
  id INT8 PRIMARY KEY DEFAULT unordered_unique_rowid(),

  run_id UUID NOT NULL
    REFERENCES _migrations.migration_run (run_id) ON DELETE CASCADE,

  object_type STRING NOT NULL,              -- 'table' | 'index' | 'constraint' | ...
  object_name STRING NOT NULL,
  before JSON,                              -- information_schema snapshot before apply
  after JSON,                               -- information_schema snapshot after apply
  noted_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  FAMILY f_meta (id, run_id, object_type, object_name, noted_at),
  FAMILY f_docs (before, after)
);

CREATE INDEX IF NOT EXISTS idx_obj_run_name
  ON _migrations.object_state (run_id, object_type, object_name);

-- ===== SNAPSHOT PROGRESS =====
CREATE TABLE IF NOT EXISTS _migrations.snapshot_progress (
  id INT8 PRIMARY KEY DEFAULT unordered_unique_rowid(),

  run_id UUID NOT NULL
    REFERENCES _migrations.migration_run (run_id) ON DELETE CASCADE,

  table_name STRING NOT NULL,
  started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  finished_at TIMESTAMPTZ,

  status _migrations.task_status NOT NULL DEFAULT 'pending',
  rows_copied INT8 NOT NULL DEFAULT 0,
  last_key STRING,                          -- or JSON if composite key
  error_text STRING,

  FAMILY f_hot (id, run_id, table_name, status, rows_copied,
                started_at, finished_at, last_key),
  FAMILY f_err (error_text)
);

CREATE INDEX IF NOT EXISTS idx_snapshot_run_table
  ON _migrations.snapshot_progress (run_id, table_name);

CREATE INDEX IF NOT EXISTS idx_snapshot_active
  ON _migrations.snapshot_progress (status)
  STORING (run_id, table_name, started_at, rows_copied)
  WHERE status IN ('pending','running');

-- ===== CDC PROGRESS =====
CREATE TABLE IF NOT EXISTS _migrations.cdc_progress (
  id INT8 PRIMARY KEY DEFAULT unordered_unique_rowid(),

  run_id UUID NOT NULL
    REFERENCES _migrations.migration_run (run_id) ON DELETE CASCADE,

  table_name STRING NOT NULL,
  stream_name STRING,                       -- identifier/job name if you create one
  status _migrations.task_status NOT NULL DEFAULT 'pending',

  started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  paused_at TIMESTAMPTZ,
  stopped_at TIMESTAMPTZ,

  resume_token STRING,                      -- e.g., Mongo resume token or CRDB job id
  high_watermark TIMESTAMPTZ,
  events_applied INT8 DEFAULT 0,
  bytes_processed INT8 DEFAULT 0,
  error_text STRING,

  FAMILY f_hot (id, run_id, table_name, stream_name, status,
                started_at, paused_at, stopped_at,
                resume_token, high_watermark,
                events_applied, bytes_processed),
  FAMILY f_err (error_text)
);

CREATE INDEX IF NOT EXISTS idx_cdc_run_table
  ON _migrations.cdc_progress (run_id, table_name);

CREATE INDEX IF NOT EXISTS idx_cdc_active
  ON _migrations.cdc_progress (status)
  STORING (run_id, table_name, started_at, resume_token, high_watermark)
  WHERE status IN ('pending','running');

-- ===== EVENT LOG (quick breadcrumbs and human-readable context) =====
CREATE TABLE IF NOT EXISTS _migrations.event_log (
  id INT8 PRIMARY KEY DEFAULT unordered_unique_rowid(),

  run_id UUID NOT NULL
    REFERENCES _migrations.migration_run (run_id) ON DELETE CASCADE,

  ts TIMESTAMPTZ NOT NULL DEFAULT now(),
  component STRING NOT NULL,                -- 'nifi'|'schema_gen'|'ddl_apply'|'snapshot'|'cdc'|...
  level STRING NOT NULL DEFAULT 'INFO',     -- INFO|WARN|ERROR
  message STRING NOT NULL,
  details JSON,

  FAMILY f_hot (id, run_id, ts, component, level, message),
  FAMILY f_docs (details)
);

CREATE INDEX IF NOT EXISTS idx_event_run_ts
  ON _migrations.event_log (run_id, ts DESC)
  STORING (component, level, message);

CREATE INDEX IF NOT EXISTS idx_event_errors
  ON _migrations.event_log (run_id, level, ts DESC)
  STORING (message)
  WHERE level IN ('WARN','ERROR');