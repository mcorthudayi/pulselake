CREATE SCHEMA IF NOT EXISTS raw;

CREATE TABLE IF NOT EXISTS raw.ingestion_runs (
    run_id              UUID PRIMARY KEY,
    started_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    finished_at         TIMESTAMPTZ,
    status              TEXT NOT NULL DEFAULT 'running'
                        CHECK (status IN ('running', 'succeeded', 'partial', 'failed')),
    files_total         INT NOT NULL DEFAULT 0,
    files_failed        INT NOT NULL DEFAULT 0,
    resources_inserted  INT NOT NULL DEFAULT 0,
    resources_updated   INT NOT NULL DEFAULT 0,
    resources_unchanged INT NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS raw.fhir_resources (
    resource_type   TEXT NOT NULL,
    resource_id     TEXT NOT NULL,
    resource        JSONB NOT NULL,
    content_hash    TEXT NOT NULL,
    source_file     TEXT NOT NULL,
    run_id          UUID NOT NULL REFERENCES raw.ingestion_runs (run_id),
    first_loaded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_loaded_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (resource_type, resource_id)
);

CREATE INDEX IF NOT EXISTS idx_fhir_resources_type
    ON raw.fhir_resources (resource_type);

CREATE INDEX IF NOT EXISTS idx_fhir_resources_json
    ON raw.fhir_resources USING GIN (resource jsonb_path_ops);
