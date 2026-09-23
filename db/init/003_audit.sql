CREATE SCHEMA IF NOT EXISTS audit;

CREATE TABLE IF NOT EXISTS audit.access_log (
    id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    occurred_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    user_name     TEXT,
    roles         TEXT,
    method        TEXT NOT NULL,
    path          TEXT NOT NULL,
    query_string  TEXT,
    resource_type TEXT,
    resource_id   TEXT,
    status_code   INT NOT NULL,
    client_ip     TEXT,
    duration_ms   INT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_access_log_time ON audit.access_log (occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_access_log_user ON audit.access_log (user_name);

CREATE OR REPLACE FUNCTION audit.prevent_modification()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'audit.access_log is append-only';
END;
$$;

DROP TRIGGER IF EXISTS trg_access_log_no_update_delete ON audit.access_log;
CREATE TRIGGER trg_access_log_no_update_delete
    BEFORE UPDATE OR DELETE ON audit.access_log
    FOR EACH ROW EXECUTE FUNCTION audit.prevent_modification();

DROP TRIGGER IF EXISTS trg_access_log_no_truncate ON audit.access_log;
CREATE TRIGGER trg_access_log_no_truncate
    BEFORE TRUNCATE ON audit.access_log
    FOR EACH STATEMENT EXECUTE FUNCTION audit.prevent_modification();
